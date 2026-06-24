import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct OpenAICodexOAuthProvider: OAuthProvider {
    public let id = "openai-codex"
    public let name = "OpenAI Codex"

    public static let deviceUserCodeURL = "https://auth.openai.com/api/accounts/deviceauth/usercode"
    public static let deviceTokenURL = "https://auth.openai.com/api/accounts/deviceauth/token"
    public static let accessTokenURL = "https://auth.openai.com/oauth/token"
    public static let codexDeviceVerificationURI = "https://auth.openai.com/codex/device"
    public static let codexRedirectURI = "https://auth.openai.com/deviceauth/callback"
    public static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    private let legacyDeviceCodeURL = "https://auth0.openai.com/oauth/device/code"
    private let legacyAccessTokenURL = "https://auth0.openai.com/oauth/token"
    private let legacyClientID = "DRivsnm2Mu42T3KOpqdtwB3NYviHYzwD"
    private let audience = "https://api.openai.com/v1"
    private let scope = "openid profile email offline_access"

    public init() {}

    public func login(callbacks: OAuthLoginCallbacks) async throws -> OAuthCredentials {
        let device = try await startDeviceFlow()
        if let onAuth = callbacks.onAuth { await onAuth(OAuthAuthInfo(url: device.verificationURI, instructions: "Enter code: \(device.userCode)")) }
        return try await pollForToken(deviceCode: device.deviceCode, interval: device.interval, expiresIn: device.expiresIn)
    }

    public func refreshToken(credentials: OAuthCredentials) async throws -> OAuthCredentials { try await refreshCodexToken(refreshToken: credentials.refresh) }
    public func apiKey(credentials: OAuthCredentials) -> String { credentials.access }
    public func modifyModels(_ models: [Model], credentials: OAuthCredentials) -> [Model] { models }

    public static func deviceUserCodeBody() -> [String: JSONValue] { ["client_id": .string(clientID)] }
    public static func deviceTokenBody(deviceAuthID: String, userCode: String) -> [String: JSONValue] { ["device_auth_id": .string(deviceAuthID), "user_code": .string(userCode)] }
    public static func authorizationCodeFields(code: String, verifier: String) -> [String: String] { ["grant_type": "authorization_code", "client_id": clientID, "code": code, "redirect_uri": codexRedirectURI, "code_verifier": verifier] }
    public static func refreshFailureMessage(status: Int, body: String) -> String {
        let data = body.data(using: .utf8) ?? Data()
        let raw = (try? JSONDecoder().decode([String: JSONValue].self, from: data)) ?? [:]
        let nested = raw["error"]?.objectValue
        let message = nested?["message"]?.stringValue ?? raw["error_description"]?.stringValue ?? raw["error"]?.stringValue ?? body
        return "OpenAI Codex token refresh failed (\(status)): \(message)"
    }

    public static func extractAccountID(from accessToken: String) throws -> String {
        let parts = accessToken.split(separator: ".")
        guard parts.count >= 2 else { throw AIError.provider("no chatgpt_account_id in token") }
        var payload = String(parts[1])
        while payload.count % 4 != 0 { payload += "=" }
        payload = payload.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        guard let data = Data(base64Encoded: payload), let object = try? JSONDecoder().decode([String: JSONValue].self, from: data), let auth = object["https://api.openai.com/auth"]?.objectValue, let account = auth["chatgpt_account_id"]?.stringValue, !account.isEmpty else { throw AIError.provider("no chatgpt_account_id in token") }
        return account
    }

    private func startDeviceFlow() async throws -> DeviceFlowResponse {
        var request = URLRequest(url: URL(string: legacyDeviceCodeURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form(["client_id": legacyClientID, "scope": scope, "audience": audience])
        let (data, response) = try await HTTPRetry.data(for: request, policy: RetryPolicy(maxRetries: 1))
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw AIError.apiError(status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: String(data: data, encoding: .utf8) ?? "") }
        return try JSONDecoder().decode(CodexDeviceResponse.self, from: data).asDeviceFlowResponse
    }

    private func pollForToken(deviceCode: String, interval: Int, expiresIn: Int) async throws -> OAuthCredentials {
        let deadline = Date().addingTimeInterval(TimeInterval(expiresIn))
        var interval = max(1, interval)
        while Date() < deadline {
            try await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
            var request = URLRequest(url: URL(string: legacyAccessTokenURL)!)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.httpBody = form(["grant_type": "urn:ietf:params:oauth:grant-type:device_code", "device_code": deviceCode, "client_id": legacyClientID])
            let (data, _) = try await URLSession.shared.data(for: request)
            let raw = (try? JSONDecoder().decode([String: JSONValue].self, from: data)) ?? [:]
            if let token = raw["access_token"]?.stringValue {
                let refresh = raw["refresh_token"]?.stringValue ?? ""
                let expires = Int64(Date().addingTimeInterval((raw["expires_in"]?.doubleValue ?? 0) - 300).timeIntervalSince1970 * 1000)
                return OAuthCredentials(refresh: refresh, access: token, expires: expires)
            }
            switch raw["error"]?.stringValue {
            case "authorization_pending": continue
            case "slow_down": interval = Int(Double(interval) * 1.4); continue
            default: throw AIError.provider("device flow: \(raw["error_description"]?.stringValue ?? raw["error"]?.stringValue ?? "unknown")")
            }
        }
        throw AIError.provider("device flow timed out")
    }

    private func refreshCodexToken(refreshToken: String) async throws -> OAuthCredentials {
        var request = URLRequest(url: URL(string: legacyAccessTokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = form(["grant_type": "refresh_token", "client_id": legacyClientID, "refresh_token": refreshToken])
        let (data, response) = try await HTTPRetry.data(for: request, policy: RetryPolicy(maxRetries: 1))
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { let status = (response as? HTTPURLResponse)?.statusCode ?? 0; throw AIError.provider(Self.refreshFailureMessage(status: status, body: String(data: data, encoding: .utf8) ?? "")) }
        let raw = try JSONDecoder().decode([String: JSONValue].self, from: data)
        let access = raw["access_token"]?.stringValue ?? ""
        let refresh = raw["refresh_token"]?.stringValue ?? refreshToken
        let expires = Int64(Date().addingTimeInterval((raw["expires_in"]?.doubleValue ?? 0) - 300).timeIntervalSince1970 * 1000)
        return OAuthCredentials(refresh: refresh, access: access, expires: expires)
    }

    private func form(_ fields: [String: String]) -> Data? {
        fields.map { key, value in "\(escape(key))=\(escape(value))" }.joined(separator: "&").data(using: .utf8)
    }

    private func escape(_ value: String) -> String { value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value }
}

private struct CodexDeviceResponse: Decodable {
    var deviceCode: String
    var userCode: String
    var verificationURIComplete: String?
    var verificationURI: String?
    var interval: Int
    var expiresIn: Int
    enum CodingKeys: String, CodingKey { case deviceCode = "device_code"; case userCode = "user_code"; case verificationURIComplete = "verification_uri_complete"; case verificationURI = "verification_uri"; case interval; case expiresIn = "expires_in" }
    var asDeviceFlowResponse: DeviceFlowResponse { DeviceFlowResponse(deviceCode: deviceCode, userCode: userCode, verificationURI: verificationURIComplete ?? verificationURI ?? "", interval: interval, expiresIn: expiresIn) }
}

