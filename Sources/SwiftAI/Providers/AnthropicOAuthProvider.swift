import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct AnthropicOAuthProvider: OAuthProvider {
    public typealias RequestTransport = @Sendable (URLRequest, RetryPolicy) async throws -> (Data, URLResponse)

    public let id = "anthropic"
    public let name = "Anthropic"

    public static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    public static let authorizeURL = "https://claude.ai/oauth/authorize"
    public static let tokenURL = "https://platform.claude.com/v1/oauth/token"
    public static let redirectURI = "http://localhost:53692/callback"
    public static let copyCodeRedirectURI = "https://platform.claude.com/oauth/code/callback"
    public static let scopes = "org:create_api_key user:profile user:inference user:sessions:claude_code user:mcp_servers user:file_upload"
    public static let browserLoginMethod = "browser"
    public static let copyCodeLoginMethod = "copy_code"

    private let requestTransport: RequestTransport?

    public init(requestTransport: RequestTransport? = nil) { self.requestTransport = requestTransport }

    public func login(callbacks: OAuthLoginCallbacks) async throws -> OAuthCredentials {
        try Task.checkCancellation()
        let method = try await loginMethod(callbacks: callbacks)
        try Task.checkCancellation()
        switch method {
        case Self.browserLoginMethod:
            return try await loginBrowser(callbacks: callbacks)
        case Self.copyCodeLoginMethod:
            return try await loginCopyCode(callbacks: callbacks)
        default:
            throw AIError.provider("Unknown Anthropic login method")
        }
    }

    public func refreshToken(credentials: OAuthCredentials) async throws -> OAuthCredentials { try await refreshAnthropicToken(refreshToken: credentials.refresh) }
    public func refreshToken(credentials: OAuthCredentials, cancellation: OAuthCancellation) async throws -> OAuthCredentials { try cancellation.check(); let refreshed = try await refreshAnthropicToken(refreshToken: credentials.refresh); try cancellation.check(); return refreshed }
    public func apiKey(credentials: OAuthCredentials) -> String { credentials.access }
    public func modifyModels(_ models: [Model], credentials: OAuthCredentials) -> [Model] { models }

    public func authorizationURL(challenge: String) -> String { authorizationURL(challenge: challenge, state: nil, redirectURI: Self.redirectURI) }

    public func authorizationURL(challenge: String, state: String?, redirectURI: String) -> String {
        var components = URLComponents(string: Self.authorizeURL)!
        components.queryItems = [
            URLQueryItem(name: "code", value: "true"),
            URLQueryItem(name: "client_id", value: Self.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: Self.scopes),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state)
        ].compactMap { $0.value == nil ? nil : $0 }
        return components.url?.absoluteString ?? Self.authorizeURL
    }

    public func exchangeCode(_ code: String, verifier: String) async throws -> OAuthCredentials {
        try await exchangeCode(code, state: verifier, verifier: verifier, redirectURI: Self.redirectURI)
    }

    public func exchangeCode(_ code: String, state: String, verifier: String, redirectURI: String) async throws -> OAuthCredentials {
        let trimmedCode = try Self.requireAuthorizationCode(code)
        try Task.checkCancellation()
        return try await tokenRequest(fields: Self.authorizationCodeFields(clientID: Self.clientID, code: trimmedCode, state: state, verifier: verifier, redirectURI: redirectURI), fallbackRefresh: nil, redactedFields: ["code": trimmedCode, "state": state, "code_verifier": verifier])
    }

    public static func authorizationCodeFields(clientID: String, code: String, verifier: String) -> [String: String] {
        authorizationCodeFields(clientID: clientID, code: code, state: verifier, verifier: verifier, redirectURI: redirectURI)
    }

    public static func authorizationCodeFields(clientID: String, code: String, state: String, verifier: String, redirectURI: String) -> [String: String] {
        ["grant_type": "authorization_code", "client_id": clientID, "code": code, "state": state, "redirect_uri": redirectURI, "code_verifier": verifier]
    }

    public static func refreshTokenFields(clientID: String, refreshToken: String) -> [String: String] {
        ["grant_type": "refresh_token", "client_id": clientID, "refresh_token": refreshToken]
    }

    public static func parseAuthorizationInput(_ input: String) -> (code: String?, state: String?) {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return (nil, nil) }
        if let url = URL(string: value), url.scheme != nil {
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            func query(_ name: String) -> String? { items.first { $0.name == name }?.value }
            return (query("code"), query("state"))
        }
        if value.contains("#") {
            let parts = value.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
            return (String(parts.first ?? ""), parts.count > 1 ? String(parts[1]) : nil)
        }
        if value.contains("code=") {
            var components = URLComponents()
            components.query = value.hasPrefix("?") ? String(value.dropFirst()) : value
            func query(_ name: String) -> String? { components.queryItems?.first { $0.name == name }?.value }
            return (query("code"), query("state"))
        }
        return (value, nil)
    }

    private static func requireAuthorizationCode(_ raw: String?) throws -> String {
        let code = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !code.isEmpty else { throw AIError.provider("Missing authorization code") }
        return code
    }

    private func loginMethod(callbacks: OAuthLoginCallbacks) async throws -> String {
        if let prompt = callbacks.onAuthPrompt {
            return try await prompt(.select(message: "Select Anthropic login method:", options: [
                .init(id: Self.browserLoginMethod, label: "Browser login (default)"),
                .init(id: Self.copyCodeLoginMethod, label: "Copy code login (headless)")
            ]))
        }
        return Self.browserLoginMethod
    }

    private func promptForAuthorizationInput(callbacks: OAuthLoginCallbacks, message: String, placeholder: String) async throws -> String {
        if let prompt = callbacks.onAuthPrompt { return try await prompt(.manualCode(message: message, placeholder: placeholder)) }
        if let legacy = callbacks.onPrompt { return try await legacy(OAuthPrompt(message: message, placeholder: placeholder, allowEmpty: false)) }
        throw AIError.provider("Anthropic OAuth requires an authorization code")
    }

    private func loginBrowser(callbacks: OAuthLoginCallbacks) async throws -> OAuthCredentials {
        try Task.checkCancellation()
        let pkce = try OAuthUtilities.generatePKCE()
        let url = authorizationURL(challenge: pkce.challenge, state: pkce.verifier, redirectURI: Self.redirectURI)
        try Task.checkCancellation()
        await callbacks.onAuth?(OAuthAuthInfo(url: url, instructions: "Complete login in your browser. If the browser is on another machine, paste the final redirect URL here."))
        try Task.checkCancellation()
        let input = try await promptForAuthorizationInput(callbacks: callbacks, message: "Complete login in your browser, or paste the authorization code / redirect URL here:", placeholder: Self.redirectURI)
        try Task.checkCancellation()
        let parsed = Self.parseAuthorizationInput(input)
        let code = try Self.requireAuthorizationCode(parsed.code)
        if let state = parsed.state, state != pkce.verifier { throw AIError.provider("OAuth state mismatch") }
        await callbacks.onProgress?("Exchanging authorization code for tokens...")
        try Task.checkCancellation()
        return try await exchangeCode(code, state: parsed.state ?? pkce.verifier, verifier: pkce.verifier, redirectURI: Self.redirectURI)
    }

    private func loginCopyCode(callbacks: OAuthLoginCallbacks) async throws -> OAuthCredentials {
        try Task.checkCancellation()
        let pkce = try OAuthUtilities.generatePKCE()
        let url = authorizationURL(challenge: pkce.challenge, state: pkce.verifier, redirectURI: Self.copyCodeRedirectURI)
        try Task.checkCancellation()
        await callbacks.onAuth?(OAuthAuthInfo(url: url, instructions: "Complete login in your browser, then copy the code Anthropic shows and paste it here."))
        try Task.checkCancellation()
        let input = try await promptForAuthorizationInput(callbacks: callbacks, message: "Paste the code Anthropic shows after you sign in:", placeholder: "code#state")
        try Task.checkCancellation()
        let parsed = Self.parseAuthorizationInput(input)
        let code = try Self.requireAuthorizationCode(parsed.code)
        if let state = parsed.state, state != pkce.verifier { throw AIError.provider("OAuth state mismatch") }
        await callbacks.onProgress?("Exchanging authorization code for tokens...")
        try Task.checkCancellation()
        return try await exchangeCode(code, state: parsed.state ?? pkce.verifier, verifier: pkce.verifier, redirectURI: Self.copyCodeRedirectURI)
    }

    private func refreshAnthropicToken(refreshToken: String) async throws -> OAuthCredentials {
        try await tokenRequest(fields: Self.refreshTokenFields(clientID: Self.clientID, refreshToken: refreshToken), fallbackRefresh: refreshToken, redactedFields: ["refresh_token": refreshToken])
    }

    private func tokenRequest(fields: [String: String], fallbackRefresh: String?, redactedFields: [String: String]) async throws -> OAuthCredentials {
        try Task.checkCancellation()
        var request = URLRequest(url: URL(string: Self.tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(fields)
        let data: Data
        let response: URLResponse
        do {
            if let requestTransport { (data, response) = try await requestTransport(request, RetryPolicy(maxRetries: 1)) }
            else { (data, response) = try await HTTPRetry.data(for: request, policy: RetryPolicy(maxRetries: 1)) }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw AIError.provider("Token exchange request failed. url=\(Self.tokenURL); redirect_uri=\(fields["redirect_uri"] ?? ""); response_type=authorization_code")
        }
        try Task.checkCancellation()
        let responseBody = String(data: data, encoding: .utf8) ?? ""
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw AIError.apiError(status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: "Token exchange failed. url=\(Self.tokenURL)") }
        let raw: [String: JSONValue]
        do { raw = try JSONDecoder().decode([String: JSONValue].self, from: data) }
        catch { throw AIError.provider(redact("Token exchange returned invalid JSON. url=\(Self.tokenURL); details=\(String(describing: error))", requestSecrets: redactedFields, responseBody: responseBody)) }
        let access = raw["access_token"]?.stringValue ?? ""
        let refresh = raw["refresh_token"]?.stringValue ?? fallbackRefresh ?? ""
        let expires = Int64(Date().addingTimeInterval((raw["expires_in"]?.doubleValue ?? 0) - 300).timeIntervalSince1970 * 1000)
        return OAuthCredentials(refresh: refresh, access: access, expires: expires)
    }

    private func redact(_ text: String, requestSecrets: [String: String], responseBody: String?) -> String {
        var out = text
        for value in requestSecrets.values where !value.isEmpty { out = out.replacingOccurrences(of: value, with: "[redacted]") }
        if let data = responseBody?.data(using: .utf8), let object = try? JSONDecoder().decode([String: JSONValue].self, from: data) {
            for key in ["access_token", "refresh_token", "id_token"] {
                if let value = object[key]?.stringValue, !value.isEmpty { out = out.replacingOccurrences(of: value, with: "[redacted]") }
            }
        }
        return out
    }
}
