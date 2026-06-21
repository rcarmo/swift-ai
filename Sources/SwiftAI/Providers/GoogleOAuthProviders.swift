import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct GoogleGeminiCLIOAuthProvider: OAuthProvider {
    public let id = "google-gemini-cli"
    public let name = "Google Gemini CLI"
    public init() {}

    public func login(callbacks: OAuthLoginCallbacks) async throws -> OAuthCredentials { try await GoogleOAuthFlow.login(callbacks: callbacks, providerName: name) }
    public func refreshToken(credentials: OAuthCredentials) async throws -> OAuthCredentials { try await GoogleOAuthFlow.refresh(credentials: credentials) }
    public func apiKey(credentials: OAuthCredentials) -> String { GoogleOAuthFlow.apiKey(credentials: credentials) }
    public func modifyModels(_ models: [Model], credentials: OAuthCredentials) -> [Model] { models }
}

public struct GoogleAntigravityOAuthProvider: OAuthProvider {
    public let id = "google-antigravity"
    public let name = "Antigravity (Google Cloud)"
    public init() {}

    public func login(callbacks: OAuthLoginCallbacks) async throws -> OAuthCredentials { try await GoogleOAuthFlow.login(callbacks: callbacks, providerName: name) }
    public func refreshToken(credentials: OAuthCredentials) async throws -> OAuthCredentials { try await GoogleOAuthFlow.refresh(credentials: credentials) }
    public func apiKey(credentials: OAuthCredentials) -> String { GoogleOAuthFlow.apiKey(credentials: credentials) }
    public func modifyModels(_ models: [Model], credentials: OAuthCredentials) -> [Model] { models }
}

public enum GoogleOAuthFlow {
    public static let authURL = "https://accounts.google.com/o/oauth2/v2/auth"
    public static let tokenURL = "https://oauth2.googleapis.com/token"
    public static let clientID = "962486aborv6v47vfgk7feun3q"
    public static let redirectURI = "http://localhost:19140/callback"
    public static let scopes = "openid https://www.googleapis.com/auth/cloud-platform https://www.googleapis.com/auth/generative-language"

    public static func login(callbacks: OAuthLoginCallbacks, providerName: String) async throws -> OAuthCredentials {
        let projectRaw = try await callbacks.onPrompt?(OAuthPrompt(message: "Google Cloud project ID", placeholder: "my-project-id", allowEmpty: false)) ?? ""
        let projectID = projectRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !projectID.isEmpty else { throw AIError.provider("project ID is required") }
        let pkce = try OAuthUtilities.generatePKCE()
        let url = authorizationURL(challenge: pkce.challenge)
        if let onAuth = callbacks.onAuth { await onAuth(OAuthAuthInfo(url: url, instructions: "Complete Google login for \(providerName) and paste the returned code")) }
        guard let code = try await callbacks.onPrompt?(OAuthPrompt(message: "Google OAuth code", placeholder: "code", allowEmpty: false)), !code.isEmpty else { throw AIError.provider("Google OAuth requires an authorization code") }
        var credentials = try await exchangeCode(code, verifier: pkce.verifier)
        credentials.extra = ["projectId": .string(projectID)]
        return credentials
    }

    public static func authorizationURL(challenge: String) -> String {
        var components = URLComponents(string: authURL)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]
        return components.url?.absoluteString ?? authURL
    }

    public static func exchangeCode(_ code: String, verifier: String) async throws -> OAuthCredentials {
        try await tokenRequest(fields: ["grant_type": "authorization_code", "client_id": clientID, "code": code, "redirect_uri": redirectURI, "code_verifier": verifier], fallbackRefresh: nil)
    }

    public static func refresh(credentials: OAuthCredentials) async throws -> OAuthCredentials {
        var refreshed = try await tokenRequest(fields: ["grant_type": "refresh_token", "client_id": clientID, "refresh_token": credentials.refresh], fallbackRefresh: credentials.refresh)
        refreshed.extra = credentials.extra
        return refreshed
    }

    public static func apiKey(credentials: OAuthCredentials) -> String {
        let projectID = credentials.extra?["projectId"]?.stringValue ?? ""
        let object: JSONValue = .object(["token": .string(credentials.access), "projectId": .string(projectID)])
        guard let data = try? JSONEncoder().encode(object) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private static func tokenRequest(fields: [String: String], fallbackRefresh: String?) async throws -> OAuthCredentials {
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

    private static func form(_ fields: [String: String]) -> Data? { fields.map { "\(escape($0.key))=\(escape($0.value))" }.joined(separator: "&").data(using: .utf8) }
    private static func escape(_ value: String) -> String { value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value }
}
