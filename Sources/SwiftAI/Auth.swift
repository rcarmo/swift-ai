import Foundation

public struct ModelAuth: Codable, Equatable, Sendable {
    public var apiKey: String?
    public var headers: [String: String]?
    public var baseUrl: String?
    public init(apiKey: String? = nil, headers: [String: String]? = nil, baseUrl: String? = nil) { self.apiKey = apiKey; self.headers = headers; self.baseUrl = baseUrl }
}

public enum Credential: Codable, Equatable, Sendable {
    case apiKey(key: String?, env: ProviderEnv?)
    case oauth(OAuthCredentials)

    enum CodingKeys: String, CodingKey { case type, key, env, refresh, access, expires, extra }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "api_key":
            self = .apiKey(key: try c.decodeIfPresent(String.self, forKey: .key), env: try c.decodeIfPresent(ProviderEnv.self, forKey: .env))
        case "oauth":
            self = .oauth(OAuthCredentials(refresh: try c.decode(String.self, forKey: .refresh), access: try c.decode(String.self, forKey: .access), expires: try c.decode(Int64.self, forKey: .expires), extra: try c.decodeIfPresent([String: JSONValue].self, forKey: .extra)))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "unknown credential type: \(type)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .apiKey(let key, let env):
            try c.encode("api_key", forKey: .type)
            try c.encodeIfPresent(key, forKey: .key)
            try c.encodeIfPresent(env, forKey: .env)
        case .oauth(let credentials):
            try c.encode("oauth", forKey: .type)
            try c.encode(credentials.refresh, forKey: .refresh)
            try c.encode(credentials.access, forKey: .access)
            try c.encode(credentials.expires, forKey: .expires)
            try c.encodeIfPresent(credentials.extra, forKey: .extra)
        }
    }
}

public protocol CredentialStore: Sendable {
    func read(providerId: String) async throws -> Credential?
    func modify(providerId: String, _ fn: @Sendable (Credential?) async throws -> Credential?) async throws -> Credential?
    func delete(providerId: String) async throws
}

public actor InMemoryCredentialStore: CredentialStore {
    private var values: [String: Credential] = [:]
    public init(initial: [String: Credential] = [:]) { values = initial }
    public func read(providerId: String) async throws -> Credential? { values[providerId] }
    public func modify(providerId: String, _ fn: @Sendable (Credential?) async throws -> Credential?) async throws -> Credential? {
        let next = try await fn(values[providerId])
        if let next { values[providerId] = next }
        return values[providerId]
    }
    public func delete(providerId: String) async throws { values.removeValue(forKey: providerId) }
}

public protocol AuthContext: Sendable {
    func env(_ name: String) async -> String?
    func fileExists(_ path: String) async -> Bool
}

public struct ProcessAuthContext: AuthContext {
    public init() {}
    public func env(_ name: String) async -> String? { ProcessInfo.processInfo.environment[name] }
    public func fileExists(_ path: String) async -> Bool {
        let resolved: String
        if path.hasPrefix("~/") { resolved = FileManager.default.homeDirectoryForCurrentUser.path + String(path.dropFirst()) }
        else { resolved = path }
        return FileManager.default.fileExists(atPath: resolved)
    }
}

public struct AuthResult: Codable, Equatable, Sendable {
    public var auth: ModelAuth
    public var env: ProviderEnv?
    public var source: String?
    public init(auth: ModelAuth, env: ProviderEnv? = nil, source: String? = nil) { self.auth = auth; self.env = env; self.source = source }
}

public enum AuthPrompt: Equatable, Sendable {
    case text(message: String, placeholder: String? = nil)
    case secret(message: String, placeholder: String? = nil)
    case select(message: String, options: [SelectOption])
    case manualCode(message: String, placeholder: String? = nil)

    public struct SelectOption: Codable, Equatable, Sendable { public var id: String; public var label: String; public var description: String?; public init(id: String, label: String, description: String? = nil) { self.id = id; self.label = label; self.description = description } }
}

public enum AuthEvent: Equatable, Sendable {
    case authURL(url: String, instructions: String? = nil)
    case deviceCode(userCode: String, verificationURI: String, intervalSeconds: Int? = nil, expiresInSeconds: Int? = nil)
    case progress(message: String)
}

public struct AuthLoginCallbacks: Sendable {
    public var prompt: @Sendable (AuthPrompt) async throws -> String
    public var notify: @Sendable (AuthEvent) async -> Void
    public init(prompt: @escaping @Sendable (AuthPrompt) async throws -> String, notify: @escaping @Sendable (AuthEvent) async -> Void = { _ in }) { self.prompt = prompt; self.notify = notify }
}
