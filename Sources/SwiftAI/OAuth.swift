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

public struct OAuthLoginCallbacks: Sendable {
    public var onAuth: (@Sendable (OAuthAuthInfo) async -> Void)?
    public var onPrompt: (@Sendable (OAuthPrompt) async throws -> String)?
    public var onProgress: (@Sendable (String) async -> Void)?
    public init(onAuth: (@Sendable (OAuthAuthInfo) async -> Void)? = nil, onPrompt: (@Sendable (OAuthPrompt) async throws -> String)? = nil, onProgress: (@Sendable (String) async -> Void)? = nil) { self.onAuth = onAuth; self.onPrompt = onPrompt; self.onProgress = onProgress }
}

public protocol OAuthProvider: Sendable {
    var id: String { get }
    var name: String { get }
    func login(callbacks: OAuthLoginCallbacks) async throws -> OAuthCredentials
    func refreshToken(credentials: OAuthCredentials) async throws -> OAuthCredentials
    func apiKey(credentials: OAuthCredentials) -> String
    func modifyModels(_ models: [Model], credentials: OAuthCredentials) -> [Model]
}

public actor OAuthRegistry {
    public static let shared = OAuthRegistry()
    private var providers: [String: any OAuthProvider] = [:]

    public func register(_ provider: any OAuthProvider) { providers[provider.id] = provider }
    public func provider(id: String) -> (any OAuthProvider)? { providers[id] }
    public func listProviders() -> [any OAuthProvider] { providers.values.sorted { $0.id < $1.id } }
    public func clear() { providers.removeAll() }

    public func apiKey(id: String, credentials: OAuthCredentials) throws -> (OAuthCredentials, String) {
        guard let provider = providers[id] else { throw AIError.provider("OAuth provider \(id) not registered") }
        return (credentials, provider.apiKey(credentials: credentials))
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

public struct DeviceFlowResponse: Decodable, Sendable {
    public var deviceCode: String
    public var userCode: String
    public var verificationURI: String
    public var interval: Int
    public var expiresIn: Int
    public init(deviceCode: String, userCode: String, verificationURI: String, interval: Int, expiresIn: Int) { self.deviceCode = deviceCode; self.userCode = userCode; self.verificationURI = verificationURI; self.interval = interval; self.expiresIn = expiresIn }
    enum CodingKeys: String, CodingKey { case deviceCode = "device_code"; case userCode = "user_code"; case verificationURI = "verification_uri"; case interval; case expiresIn = "expires_in" }
}
