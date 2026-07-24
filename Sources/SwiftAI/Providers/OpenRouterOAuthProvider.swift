import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct OpenRouterOAuthProvider: OAuthProvider {
    public typealias RequestTransport = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    nonisolated(unsafe) public static var requestTransport: RequestTransport?

    public let id = "openrouter"
    public let name = "OpenRouter OAuth"
    public init() {}

    private static let authorizeURL = "https://openrouter.ai/auth"
    private static let tokenURL = "https://openrouter.ai/api/v1/auth/keys"

    public func login(callbacks: OAuthLoginCallbacks) async throws -> OAuthCredentials {
        let pkce = try OAuthUtilities.generatePKCE()
        let callbackURL = "http://127.0.0.1/oauth/callback"
        var components = URLComponents(string: Self.authorizeURL)!
        components.queryItems = [
            URLQueryItem(name: "callback_url", value: callbackURL),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        await callbacks.onAuth?(OAuthAuthInfo(url: components.url!.absoluteString, instructions: "Complete OpenRouter sign-in in your browser and paste the returned authorization code."))
        guard let code = try await callbacks.onPrompt?(OAuthPrompt(message: "OpenRouter authorization code", placeholder: "code")), !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AIError.provider("OpenRouter OAuth requires an authorization code") }
        return try await Self.exchangeAuthorizationCode(code.trimmingCharacters(in: .whitespacesAndNewlines), verifier: pkce.verifier)
    }

    public func refreshToken(credentials: OAuthCredentials) async throws -> OAuthCredentials { credentials }
    public func apiKey(credentials: OAuthCredentials) -> String { credentials.access }
    public func modifyModels(_ models: [Model], credentials: OAuthCredentials) -> [Model] { models }

    public static func exchangeAuthorizationCode(_ code: String, verifier: String) async throws -> OAuthCredentials {
        var request = URLRequest(url: URL(string: tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(JSONValue.object(["code": .string(code), "code_verifier": .string(verifier), "code_challenge_method": .string("S256")]))
        let (data, response) = try await data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIError.invalidResponse("missing HTTP response") }
        let raw = (try? JSONDecoder().decode([String: JSONValue].self, from: data)) ?? [:]
        guard (200..<300).contains(http.statusCode) else {
            let detail = raw["error_description"]?.stringValue ?? raw["message"]?.stringValue ?? raw["error"]?.stringValue
            throw AIError.provider("OpenRouter OAuth key exchange failed (HTTP \(http.statusCode))\(detail.map { ": \($0)" } ?? "")")
        }
        guard let key = raw["key"]?.stringValue, !key.isEmpty else { throw AIError.provider("OpenRouter OAuth response carries no \"key\"") }
        return OAuthCredentials(refresh: "", access: key, expires: Int64.max)
    }

    private static func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        if let transport = requestTransport { return try await transport(request) }
        return try await HTTPRetry.data(for: request, policy: RetryPolicy(maxRetries: 1))
    }
}
