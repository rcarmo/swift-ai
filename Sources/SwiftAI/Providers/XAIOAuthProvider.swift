import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct XAIOAuthProvider: OAuthProvider {
    public typealias RequestTransport = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    nonisolated(unsafe) public static var requestTransport: RequestTransport?

    public let id = "xai"
    public let name = "xAI (Grok/X subscription)"
    public static let clientID = "b1a00492-073a-47ea-816f-4c329264a828"
    public static let scope = "openid profile email offline_access grok-cli:access api:access"
    public static let deviceCodeURL = "https://auth.x.ai/oauth2/device/code"
    public static let tokenURL = "https://auth.x.ai/oauth2/token"
    public static let refreshSkewSeconds: Double = 5 * 60
    public init() {}

    public func login(callbacks: OAuthLoginCallbacks) async throws -> OAuthCredentials {
        let device = try await requestDeviceCode()
        if let onAuth = callbacks.onAuth { await onAuth(OAuthAuthInfo(url: device.verificationURI, instructions: "Enter xAI code: \(device.userCode)")) }
        return try await OAuthDeviceCodePoller.poll(intervalSeconds: device.interval, expiresInSeconds: device.expiresIn) {
            try Task.checkCancellation()
            return try await pollDeviceToken(deviceCode: device.deviceCode)
        }
    }

    public func refreshToken(credentials: OAuthCredentials) async throws -> OAuthCredentials { try await refreshXAIToken(refreshToken: credentials.refresh) }
    public func apiKey(credentials: OAuthCredentials) -> String { credentials.access }
    public func modifyModels(_ models: [Model], credentials: OAuthCredentials) -> [Model] { models }

    public func requestDeviceCode() async throws -> DeviceFlowResponse {
        var request = URLRequest(url: URL(string: Self.deviceCodeURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.form(["client_id": Self.clientID, "scope": Self.scope, "referrer": "pi"])
        let body = try await Self.jsonResponse(request: request, action: "device authorization")
        let baseVerificationURI = try Self.validateVerificationURI(Self.requiredString(body, "verification_uri"))
        let completeVerificationURI = try body["verification_uri_complete"]?.stringValue.map(Self.validateVerificationURI)
        let verificationURI = completeVerificationURI ?? baseVerificationURI
        let interval = Self.positiveInt(body, "interval") ?? 5
        return DeviceFlowResponse(deviceCode: try Self.requiredString(body, "device_code"), userCode: try Self.requiredString(body, "user_code"), verificationURI: verificationURI, interval: interval, expiresIn: try Self.requiredPositiveInt(body, "expires_in"))
    }

    public func pollDeviceToken(deviceCode: String) async throws -> OAuthDeviceCodePollStatus<OAuthCredentials> {
        var request = URLRequest(url: URL(string: Self.tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.form(["grant_type": "urn:ietf:params:oauth:grant-type:device_code", "client_id": Self.clientID, "device_code": deviceCode])
        let (data, response) = try await Self.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIError.invalidResponse("missing HTTP response") }
        let body = try Self.decodeJSON(data: data, status: http.statusCode)
        if (200..<300).contains(http.statusCode) { return .complete(try Self.credentials(from: body)) }
        switch body["error"]?.stringValue {
        case "authorization_pending": return .pending
        case "slow_down": return .slowDown
        case "access_denied", "authorization_denied": throw XAIOAuthError.denied
        case "expired_token": throw XAIOAuthError.expired
        default: throw XAIOAuthError.http(action: "device token polling", status: http.statusCode, body: body)
        }
    }

    public func refreshXAIToken(refreshToken: String) async throws -> OAuthCredentials {
        var request = URLRequest(url: URL(string: Self.tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.form(["grant_type": "refresh_token", "client_id": Self.clientID, "refresh_token": refreshToken])
        let body = try await Self.jsonResponse(request: request, action: "token refresh")
        return try Self.credentials(from: body, previousRefreshToken: refreshToken)
    }

    private static func jsonResponse(request: URLRequest, action: String) async throws -> [String: JSONValue] {
        let (data, response) = try await data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIError.invalidResponse("missing HTTP response") }
        let body = try decodeJSON(data: data, status: http.statusCode)
        guard (200..<300).contains(http.statusCode) else { throw XAIOAuthError.http(action: action, status: http.statusCode, body: body) }
        return body
    }

    private static func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        if let transport = requestTransport { return try await transport(request) }
        do { return try await HTTPRetry.data(for: request, policy: RetryPolicy(maxRetries: 1)) }
        catch is CancellationError { throw XAIOAuthError.cancelled }
    }

    private static func decodeJSON(data: Data, status: Int) throws -> [String: JSONValue] {
        guard let raw = try? JSONDecoder().decode([String: JSONValue].self, from: data) else { throw XAIOAuthError.invalidJSON(status: status) }
        return raw
    }

    private static func credentials(from body: [String: JSONValue], previousRefreshToken: String? = nil, now: Date = Date()) throws -> OAuthCredentials {
        let access = try requiredString(body, "access_token")
        let refresh = body["refresh_token"]?.stringValue ?? previousRefreshToken ?? ""
        guard !refresh.isEmpty else { throw XAIOAuthError.invalidField("refresh_token") }
        let expiresIn = body["expires_in"]?.doubleValue ?? 3600
        return OAuthCredentials(refresh: refresh, access: access, expires: Int64(now.addingTimeInterval(expiresIn - refreshSkewSeconds).timeIntervalSince1970 * 1000))
    }

    private static func validateVerificationURI(_ raw: String) throws -> String {
        guard let url = URL(string: raw), url.scheme == "https" else { throw XAIOAuthError.untrustedVerificationURI }
        return url.absoluteString
    }

    private static func requiredString(_ body: [String: JSONValue], _ field: String) throws -> String {
        guard let value = body[field]?.stringValue, !value.isEmpty else { throw XAIOAuthError.invalidField(field) }
        return value
    }

    private static func positiveInt(_ body: [String: JSONValue], _ field: String) -> Int? {
        guard let value = body[field]?.doubleValue, value > 0 else { return nil }
        return Int(value)
    }

    private static func requiredPositiveInt(_ body: [String: JSONValue], _ field: String) throws -> Int {
        guard let value = positiveInt(body, field) else { throw XAIOAuthError.invalidField(field) }
        return value
    }

    private static func form(_ fields: [String: String]) -> Data? { fields.map { "\(escape($0.key))=\(escape($0.value))" }.joined(separator: "&").data(using: .utf8) }
    private static func escape(_ value: String) -> String { value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value }
}

public enum XAIOAuthError: Error, Equatable, LocalizedError, Sendable {
    case cancelled
    case denied
    case expired
    case http(action: String, status: Int, body: [String: JSONValue])
    case invalidField(String)
    case invalidJSON(status: Int)
    case untrustedVerificationURI
    public var errorDescription: String? {
        switch self {
        case .cancelled: return "Login cancelled"
        case .denied: return "xAI device authorization was denied"
        case .expired: return "xAI device code expired"
        case .http(let action, let status, let body): return "xAI OAuth \(action) failed (HTTP \(status)): \(body["error"]?.stringValue ?? "unknown")"
        case .invalidField(let field): return "Invalid xAI OAuth response field: \(field)"
        case .invalidJSON(let status): return "xAI OAuth returned invalid JSON (HTTP \(status))"
        case .untrustedVerificationURI: return "Untrusted verification URI in xAI OAuth response"
        }
    }
}
