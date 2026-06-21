import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct AnthropicOAuthProvider: OAuthProvider {
    public let id = "anthropic"
    public let name = "Anthropic"

    private let authURL = "https://console.anthropic.com/oauth/authorize"
    private let tokenURL = "https://console.anthropic.com/oauth/token"
    private let clientID = "9d9e5f78-76ca-4484-be3c-e13fb3a3378c"
    private let redirectURI = "http://localhost:19139/callback"

    public init() {}

    public func login(callbacks: OAuthLoginCallbacks) async throws -> OAuthCredentials {
        let pkce = try OAuthUtilities.generatePKCE()
        let url = authorizationURL(challenge: pkce.challenge)
        await callbacks.onAuth?(OAuthAuthInfo(url: url, instructions: "Complete login in your browser and paste the returned code"))
        guard let code = try await callbacks.onPrompt?(OAuthPrompt(message: "Anthropic OAuth code", placeholder: "code", allowEmpty: false)), !code.isEmpty else {
            throw AIError.provider("Anthropic OAuth requires an authorization code")
        }
        return try await exchangeCode(code, verifier: pkce.verifier)
    }

    public func refreshToken(credentials: OAuthCredentials) async throws -> OAuthCredentials { try await refreshAnthropicToken(refreshToken: credentials.refresh) }
    public func apiKey(credentials: OAuthCredentials) -> String { credentials.access }
    public func modifyModels(_ models: [Model], credentials: OAuthCredentials) -> [Model] { models }

    public func authorizationURL(challenge: String) -> String {
        var components = URLComponents(string: authURL)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: "user:inference"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        return components.url?.absoluteString ?? authURL
    }

    public func exchangeCode(_ code: String, verifier: String) async throws -> OAuthCredentials {
        try await tokenRequest(fields: ["grant_type": "authorization_code", "client_id": clientID, "code": code, "redirect_uri": redirectURI, "code_verifier": verifier], fallbackRefresh: nil)
    }

    private func refreshAnthropicToken(refreshToken: String) async throws -> OAuthCredentials {
        try await tokenRequest(fields: ["grant_type": "refresh_token", "client_id": clientID, "refresh_token": refreshToken], fallbackRefresh: refreshToken)
    }

    private func tokenRequest(fields: [String: String], fallbackRefresh: String?) async throws -> OAuthCredentials {
        var request = URLRequest(url: URL(string: tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = form(fields)
        let (data, response) = try await HTTPRetry.data(for: request, policy: RetryPolicy(maxRetries: 1))
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw AIError.apiError(status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: String(data: data, encoding: .utf8) ?? "") }
        let raw = try JSONDecoder().decode([String: JSONValue].self, from: data)
        let access = raw["access_token"]?.stringValue ?? ""
        let refresh = raw["refresh_token"]?.stringValue ?? fallbackRefresh ?? ""
        let expires = Int64(Date().addingTimeInterval((raw["expires_in"]?.doubleValue ?? 0) - 300).timeIntervalSince1970 * 1000)
        return OAuthCredentials(refresh: refresh, access: access, expires: expires)
    }

    private func form(_ fields: [String: String]) -> Data? { fields.map { "\(escape($0.key))=\(escape($0.value))" }.joined(separator: "&").data(using: .utf8) }
    private func escape(_ value: String) -> String { value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value }
}

private extension JSONValue {
    var stringValue: String? { if case .string(let value) = self { return value }; return nil }
    var doubleValue: Double? { if case .number(let value) = self { return value }; return nil }
}
