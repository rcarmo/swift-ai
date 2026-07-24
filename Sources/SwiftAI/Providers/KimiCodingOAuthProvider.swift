import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct KimiCodingOAuthProvider: OAuthProvider {
    public typealias RequestTransport = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    nonisolated(unsafe) public static var requestTransport: RequestTransport?

    public let id = "kimi-coding"
    public let name = "Kimi Code (subscription)"
    public init() {}

    private static let clientID = "17e5f671-d194-4dfb-9706-5516cb48c098"
    private static let defaultOAuthHost = "https://auth.kimi.com"
    private static let defaultInterval = 5
    private static let defaultExpires = 15 * 60

    public func login(callbacks: OAuthLoginCallbacks) async throws -> OAuthCredentials {
        let device = try await Self.startDeviceAuthorization(oauthHost: Self.oauthHost())
        await callbacks.onAuth?(OAuthAuthInfo(url: device.verificationURIComplete, instructions: "Open this URL to sign in to Kimi Code."))
        await callbacks.onProgress?("Kimi Code user code: \(device.userCode)")
        return try await OAuthDeviceCodePoller.poll(intervalSeconds: device.interval, expiresInSeconds: device.expiresIn) {
            try await Self.pollForToken(oauthHost: Self.oauthHost(), deviceCode: device.deviceCode)
        }
    }

    public func refreshToken(credentials: OAuthCredentials) async throws -> OAuthCredentials { try await Self.refresh(oauthHost: Self.oauthHost(), refreshToken: credentials.refresh) }
    public func apiKey(credentials: OAuthCredentials) -> String { credentials.access }
    public func modifyModels(_ models: [Model], credentials: OAuthCredentials) -> [Model] { models }

    public static func oauthHost(env: ProviderEnv? = nil) -> String {
        (ProviderEnvironment.value("KIMI_CODE_OAUTH_HOST", env: env) ?? ProviderEnvironment.value("KIMI_OAUTH_HOST", env: env) ?? defaultOAuthHost).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    public struct DeviceAuthorization: Equatable, Sendable { public var deviceCode: String; public var userCode: String; public var verificationURI: String; public var verificationURIComplete: String; public var interval: Int; public var expiresIn: Int }

    public static func startDeviceAuthorization(oauthHost: String) async throws -> DeviceAuthorization {
        var request = URLRequest(url: URL(string: oauthHost + "/api/oauth/device_authorization")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = "client_id=\(clientID)".data(using: .utf8)
        let body = try await jsonResponse(request, action: "Kimi Code device authorization")
        let verificationURI = try trustedHTTPURL(requiredString(body, "verification_uri"))
        let complete = try trustedHTTPURL(requiredString(body, "verification_uri_complete"))
        return DeviceAuthorization(deviceCode: try requiredString(body, "device_code"), userCode: try requiredString(body, "user_code"), verificationURI: verificationURI, verificationURIComplete: complete, interval: positiveInt(body, "interval") ?? defaultInterval, expiresIn: positiveInt(body, "expires_in") ?? defaultExpires)
    }

    public static func pollForToken(oauthHost: String, deviceCode: String) async throws -> OAuthDeviceCodePollStatus<OAuthCredentials> {
        var request = URLRequest(url: URL(string: oauthHost + "/api/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = "client_id=\(clientID)&device_code=\(deviceCode)&grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Adevice_code".data(using: .utf8)
        let (data, response) = try await data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIError.invalidResponse("missing HTTP response") }
        let body = (try? JSONDecoder().decode([String: JSONValue].self, from: data)) ?? [:]
        if (200..<300).contains(http.statusCode), body["access_token"]?.stringValue != nil { return .complete(try parseToken(body)) }
        switch body["error"]?.stringValue {
        case "authorization_pending": return .pending
        case "slow_down": return .slowDown
        case "expired_token": throw AIError.provider("Kimi Code device authorization expired. Please restart login.")
        case "access_denied": throw AIError.provider("Kimi Code login was denied.")
        default: throw AIError.provider("Kimi Code device token request failed (status \(http.statusCode))")
        }
    }

    public static func refresh(oauthHost: String, refreshToken: String) async throws -> OAuthCredentials {
        var lastError: Error?
        for attempt in 0...3 {
            if attempt > 0 { try await Task.sleep(nanoseconds: UInt64(1_000 * Int(pow(2.0, Double(attempt - 1)))) * 1_000_000) }
            var request = URLRequest(url: URL(string: oauthHost + "/api/oauth/token")!)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.httpBody = "client_id=\(clientID)&grant_type=refresh_token&refresh_token=\(refreshToken)".data(using: .utf8)
            do {
                let (data, response) = try await data(for: request)
                guard let http = response as? HTTPURLResponse else { throw AIError.invalidResponse("missing HTTP response") }
                let body = (try? JSONDecoder().decode([String: JSONValue].self, from: data)) ?? [:]
                if (200..<300).contains(http.statusCode) { return try parseToken(body) }
                if http.statusCode == 401 || http.statusCode == 403 || body["error"]?.stringValue == "invalid_grant" { throw AIError.provider("Kimi Code token refresh unauthorized (status \(http.statusCode))") }
                if (http.statusCode == 429 || http.statusCode >= 500), attempt < 3 { lastError = AIError.provider("Kimi Code token refresh failed with status \(http.statusCode)"); continue }
                throw AIError.provider("Kimi Code token refresh failed with status \(http.statusCode)")
            } catch { lastError = error; if attempt == 3 { throw error } }
        }
        throw lastError ?? AIError.provider("Kimi Code token refresh failed")
    }

    private static func jsonResponse(_ request: URLRequest, action: String) async throws -> [String: JSONValue] {
        let (data, response) = try await data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIError.invalidResponse("missing HTTP response") }
        let body = (try? JSONDecoder().decode([String: JSONValue].self, from: data)) ?? [:]
        guard (200..<300).contains(http.statusCode) else { throw AIError.provider("\(action) failed with status \(http.statusCode)") }
        return body
    }

    private static func parseToken(_ body: [String: JSONValue]) throws -> OAuthCredentials {
        let access = try requiredString(body, "access_token")
        let refresh = try requiredString(body, "refresh_token")
        let expiresIn = body["expires_in"]?.doubleValue ?? 3600
        return OAuthCredentials(refresh: refresh, access: access, expires: Int64(Date().addingTimeInterval(expiresIn).timeIntervalSince1970 * 1000))
    }

    private static func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        if let transport = requestTransport { return try await transport(request) }
        return try await HTTPRetry.data(for: request, policy: RetryPolicy(maxRetries: 1))
    }
    private static func requiredString(_ body: [String: JSONValue], _ field: String) throws -> String { guard let value = body[field]?.stringValue, !value.isEmpty else { throw AIError.provider("Kimi Code response missing \(field)") }; return value }
    private static func positiveInt(_ body: [String: JSONValue], _ field: String) -> Int? { guard let value = body[field]?.doubleValue, value > 0 else { return nil }; return Int(value) }
    private static func trustedHTTPURL(_ raw: String) throws -> String { guard let url = URL(string: raw), url.scheme == "https" || url.scheme == "http" else { throw AIError.provider("untrusted Kimi Code verification URI") }; return url.absoluteString }
}
