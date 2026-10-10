import Foundation
import Crypto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct OAuthCredentials: Codable, Equatable, Sendable {
    public var refresh: String
    public var access: String
    /// Unix milliseconds.
    public var expires: Int64
    public var extra: [String: JSONValue]?
    public init(refresh: String, access: String, expires: Int64, extra: [String: JSONValue]? = nil) { self.refresh = refresh; self.access = access; self.expires = expires; self.extra = extra }
}

public struct OAuthAuthInfo: Codable, Equatable, Sendable { public var url: String; public var instructions: String; public init(url: String, instructions: String) { self.url = url; self.instructions = instructions } }
public struct OAuthPrompt: Codable, Equatable, Sendable { public var message: String; public var placeholder: String; public var allowEmpty: Bool; public init(message: String, placeholder: String = "", allowEmpty: Bool = false) { self.message = message; self.placeholder = placeholder; self.allowEmpty = allowEmpty } }

public struct OAuthLoginOptions: Sendable {
    public var agentName: String?
    public init(agentName: String? = nil) { self.agentName = agentName }
}

public struct OAuthLoginCallbacks: Sendable {
    public var onAuth: (@Sendable (OAuthAuthInfo) async -> Void)?
    public var onPrompt: (@Sendable (OAuthPrompt) async throws -> String)?
    public var onProgress: (@Sendable (String) async -> Void)?
    public var onAuthPrompt: (@Sendable (AuthPrompt) async throws -> String)?
    public init(onAuth: (@Sendable (OAuthAuthInfo) async -> Void)? = nil, onPrompt: (@Sendable (OAuthPrompt) async throws -> String)? = nil, onProgress: (@Sendable (String) async -> Void)? = nil, onAuthPrompt: (@Sendable (AuthPrompt) async throws -> String)? = nil) { self.onAuth = onAuth; self.onPrompt = onPrompt; self.onProgress = onProgress; self.onAuthPrompt = onAuthPrompt }
}

public protocol OAuthProvider: Sendable {
    var id: String { get }
    var name: String { get }
    func login(callbacks: OAuthLoginCallbacks) async throws -> OAuthCredentials
    func login(callbacks: OAuthLoginCallbacks, options: OAuthLoginOptions) async throws -> OAuthCredentials
    func refreshToken(credentials: OAuthCredentials) async throws -> OAuthCredentials
    func refreshToken(credentials: OAuthCredentials, cancellation: OAuthCancellation) async throws -> OAuthCredentials
    func apiKey(credentials: OAuthCredentials) -> String
    func modifyModels(_ models: [Model], credentials: OAuthCredentials) -> [Model]
}

public struct OAuthCancellation: Sendable {
    public init() {}
    public func check() throws { try Task.checkCancellation() }
}

public extension OAuthProvider {
    func login(callbacks: OAuthLoginCallbacks, options: OAuthLoginOptions) async throws -> OAuthCredentials { try await login(callbacks: callbacks) }
    func refreshToken(credentials: OAuthCredentials, cancellation: OAuthCancellation) async throws -> OAuthCredentials {
        try cancellation.check()
        let refreshed = try await refreshToken(credentials: credentials)
        try cancellation.check()
        return refreshed
    }
}

public actor OAuthRegistry {
    public static let shared = OAuthRegistry()
    private var providers: [String: any OAuthProvider] = [:]

    public func register(_ provider: any OAuthProvider) { providers[provider.id] = provider }
    public func provider(id: String) -> (any OAuthProvider)? { providers[id] }
    public func listProviders() -> [any OAuthProvider] { providers.values.sorted { $0.id < $1.id } }
    public func clear() { providers.removeAll() }

    public func login(id: String, callbacks: OAuthLoginCallbacks = OAuthLoginCallbacks(), options: OAuthLoginOptions = OAuthLoginOptions()) async throws -> OAuthCredentials {
        guard let provider = providers[id] else { throw ModelsError("OAuth provider \(id) not registered") }
        do { return try await provider.login(callbacks: callbacks, options: options) }
        catch { throw ModelsError("OAuth login failed for \(id)", cause: error) }
    }

    public func refreshToken(id: String, credentials: OAuthCredentials, cancellation: OAuthCancellation = OAuthCancellation()) async throws -> OAuthCredentials {
        guard let provider = providers[id] else { throw ModelsError("OAuth provider \(id) not registered") }
        do { try cancellation.check(); return try await provider.refreshToken(credentials: credentials, cancellation: cancellation) }
        catch is CancellationError { throw CancellationError() }
        catch { throw ModelsError("OAuth refresh failed for \(id)", cause: error) }
    }

    public func apiKey(id: String, credentials: OAuthCredentials) throws -> (OAuthCredentials, String) {
        guard let provider = providers[id] else { throw ModelsError("OAuth provider \(id) not registered") }
        return (credentials, provider.apiKey(credentials: credentials))
    }

    public func resolveAPIKey(id: String, credentials: OAuthCredentials, minimumValiditySeconds: Int? = nil, now: Date = Date()) async throws -> (OAuthCredentials, String) {
        guard let provider = providers[id] else { throw ModelsError("OAuth provider \(id) not registered") }
        var resolved = credentials
        let effectiveMinimumSeconds = max(300, minimumValiditySeconds ?? 300)
        let minValidityMs = Int64(effectiveMinimumSeconds) * 1000
        let nowMs = Int64(now.timeIntervalSince1970 * 1000)
        let cancellation = OAuthCancellation()
        if resolved.expires - nowMs <= minValidityMs {
            do { try cancellation.check(); resolved = try await provider.refreshToken(credentials: credentials, cancellation: cancellation) }
            catch is CancellationError { throw CancellationError() }
            catch { throw ModelsError("OAuth refresh failed for \(id)", cause: error) }
        }
        if let explicit = minimumValiditySeconds, explicit > 300, resolved.expires - nowMs < Int64(explicit) * 1000 {
            throw ModelsError("OAuth refresh for \(id) did not satisfy minimum validity of \(explicit)s", cause: AIError.provider("refreshed token expires too soon"))
        }
        return (resolved, provider.apiKey(credentials: resolved))
    }
}

public struct PKCEPair: Equatable, Sendable { public var verifier: String; public var challenge: String }

public enum OAuthUtilities {
    public static func generatePKCE() throws -> PKCEPair {
        let bytes = (0..<32).map { _ in UInt8.random(in: UInt8.min...UInt8.max) }
        let verifier = base64URLEncode(Data(bytes))
        let digest = SHA256.hash(data: Data(verifier.utf8))
        let challenge = base64URLEncode(Data(digest))
        return PKCEPair(verifier: verifier, challenge: challenge)
    }

    public static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    public static func normalizeDomain(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        return URL(string: candidate)?.host
    }
}

public enum OAuthDeviceCodePollStatus<Value: Sendable>: Sendable {
    case pending
    case slowDown
    case complete(Value)
}

public enum OAuthDeviceCodePoller {
    public static func poll<Value: Sendable>(intervalSeconds: Int, expiresInSeconds: Int, poll: @escaping @Sendable () async throws -> OAuthDeviceCodePollStatus<Value>) async throws -> Value {
        let deadline = Date().addingTimeInterval(TimeInterval(expiresInSeconds))
        var interval = max(1, intervalSeconds)
        var sawSlowDown = false
        while Date() < deadline {
            try Task.checkCancellation()
            switch try await poll() {
            case .complete(let value): return value
            case .pending: break
            case .slowDown: interval += 5; sawSlowDown = true
            }
            let now = Date()
            if now.addingTimeInterval(TimeInterval(interval)) >= deadline {
                break
            }
            do { try await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000) }
            catch is CancellationError { throw AIError.provider("Login cancelled") }
        }
        throw AIError.provider(sawSlowDown ? "Device flow timed out after one or more slow_down responses" : "device flow timed out")
    }
}

public struct OAuthCallbackDecision: Equatable, Sendable {
    public var status: Int
    public var title: String
    public var detail: String?
    public var code: String?
    public var shouldComplete: Bool
    public init(status: Int, title: String, detail: String? = nil, code: String? = nil, shouldComplete: Bool = false) { self.status = status; self.title = title; self.detail = detail; self.code = code; self.shouldComplete = shouldComplete }
}

public enum OAuthCallbackUtilities {
    public static func redirectURI(host: String, port: Int, path: String, redirectHost: String? = nil) -> String {
        let outHost = redirectHost ?? host
        let bracketed = outHost.contains(":") ? "[\(outHost)]" : outHost
        return "http://\(bracketed):\(port)\(path)"
    }

    public static func handle(method: String, rawURL: String, path: String, providerName: String, expectedState: String?, claimed: Bool = false, settled: Bool = false) -> OAuthCallbackDecision {
        guard method == "GET", let url = URL(string: rawURL, relativeTo: URL(string: "http://localhost")), url.path == path else {
            return OAuthCallbackDecision(status: 404, title: "Callback route not found.")
        }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: true)?.queryItems ?? []
        func query(_ name: String) -> String? { items.first { $0.name == name }?.value }
        if let expectedState, query("state") != expectedState { return OAuthCallbackDecision(status: 400, title: "State mismatch.") }
        if claimed || settled { return OAuthCallbackDecision(status: 409, title: "This sign-in has already been handled.") }
        if let error = query("error") {
            let description = query("error_description") ?? error
            return OAuthCallbackDecision(status: 400, title: "\(providerName) authorization failed.", detail: description)
        }
        guard let code = query("code"), !code.isEmpty else { return OAuthCallbackDecision(status: 400, title: "Missing authorization code.") }
        return OAuthCallbackDecision(status: 200, title: "Signed in to \(providerName). You may now close this page.", code: code, shouldComplete: true)
    }
}

public enum OpenAIChatGPTOAuthUtilities {
    public static let dynamicClientID = "dynamic_agent_client"
    public static let agentNameHint = "Pi"
    public static let authorizeURL = "https://auth.openai.com/api/accounts/authorize"
    public static let tokenURL = "https://auth.openai.com/api/accounts/oauth/token"
    public static let resource = "https://api.openai.com/v1"
    public static let redirectURI = "http://127.0.0.1:1455/auth/callback"
    public static let directTokenScope = "chatgpt.tokens.use.direct"
    public static let scope = "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct"
    public static let expiryMarginMs: Int64 = 3 * 60 * 1000

    public static func agentHostID(deviceID: String?) throws -> String {
        guard let deviceID, deviceID.range(of: #"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"#, options: .regularExpression) != nil else {
            throw AIError.provider("Sign in with ChatGPT requires a device ID (UUID) for this installation")
        }
        return "urn:uuid:\(deviceID.lowercased())"
    }

    public static func authorizationURL(deviceID: String, state: String, nonce: String, challenge: String, agentName: String? = nil) throws -> String {
        var components = URLComponents(string: authorizeURL)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: dynamicClientID),
            URLQueryItem(name: "agent_name_hint", value: agentName ?? agentNameHint),
            URLQueryItem(name: "ext_agent_host_id", value: try agentHostID(deviceID: deviceID)),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "resource", value: resource),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "nonce", value: nonce),
        ]
        return components.url!.absoluteString
    }

    public static func authorizationResult(callbackURL: String, expectedState: String) throws -> (code: String, clientID: String) {
        guard let url = URL(string: callbackURL) else { throw AIError.provider("Paste the full callback URL from the browser") }
        let expected = URL(string: redirectURI)!
        guard url.scheme == expected.scheme, url.host == expected.host, url.port == expected.port, url.path == expected.path else { throw AIError.provider("The pasted callback URL must start with \(redirectURI)") }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func query(_ name: String) -> String? { items.first { $0.name == name }?.value }
        if let error = query("error") { throw AIError.provider("ChatGPT authorization failed: \(error)") }
        guard let code = query("code"), !code.isEmpty else { throw AIError.provider("Missing authorization code") }
        guard query("state") == expectedState else { throw AIError.provider("OAuth state mismatch") }
        guard let clientID = query("client_id")?.trimmingCharacters(in: .whitespacesAndNewlines), !clientID.isEmpty else { throw AIError.provider("OpenAI OAuth registration callback did not contain an issued client ID") }
        return (code, clientID)
    }

    public static func exchangeBody(code: String, verifier: String, clientID: String) -> [String: String] {
        ["grant_type": "authorization_code", "client_id": clientID, "code": code, "code_verifier": verifier, "redirect_uri": redirectURI, "resource": resource]
    }

    public static func refreshBody(refreshToken: String, clientID: String) -> [String: String] {
        ["grant_type": "refresh_token", "client_id": clientID, "refresh_token": refreshToken, "resource": resource]
    }

    public static func credential(token: [String: JSONValue], clientID: String, nowMs: Int64) throws -> OAuthCredentials {
        func string(_ key: String) throws -> String {
            guard let value = token[key]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { throw AIError.provider("OpenAI OAuth token response has invalid \(key)") }
            return value
        }
        let access = try string("access_token")
        let refresh = try string("refresh_token")
        let scopeString = try string("scope")
        guard let expiresIn = token["expires_in"]?.doubleValue, expiresIn.isFinite, expiresIn > 0 else { throw AIError.provider("OpenAI OAuth token response has invalid expires_in") }
        let scopes = scopeString.split(whereSeparator: \.isWhitespace).map(String.init)
        guard scopes.contains(directTokenScope) else { throw AIError.provider("OpenAI OAuth grant did not include \(directTokenScope)") }
        var extra: [String: JSONValue] = ["clientId": .string(clientID), "scopes": .array(scopes.map { .string($0) })]
        if let idToken = token["id_token"]?.stringValue, !idToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { extra["idToken"] = .string(idToken) }
        return OAuthCredentials(refresh: refresh, access: access, expires: nowMs + Int64(expiresIn * 1000) - expiryMarginMs, extra: extra)
    }
}

public struct DeviceFlowResponse: Decodable, Sendable {
    public var deviceCode: String
    public var userCode: String
    public var verificationURI: String
    public var interval: Int
    public var expiresIn: Int
    public init(deviceCode: String, userCode: String, verificationURI: String, interval: Int, expiresIn: Int) { self.deviceCode = deviceCode; self.userCode = userCode; self.verificationURI = verificationURI; self.interval = interval; self.expiresIn = expiresIn }
    enum CodingKeys: String, CodingKey { case deviceCode = "device_code"; case userCode = "user_code"; case verificationURI = "verification_uri"; case interval; case expiresIn = "expires_in" }
}
