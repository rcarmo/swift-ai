import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct RadiusOAuthProvider: OAuthProvider {
    public typealias RequestTransport = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    nonisolated(unsafe) public static var requestTransport: RequestTransport?

    public let id = "radius"
    public let name = "Radius"
    public static let defaultGateway = "https://radius.pi.dev"
    public static let callbackHost = "127.0.0.1"
    public static let callbackPort = 1456
    public static let callbackPath = "/oauth/callback"
    public static let redirectURI = "http://127.0.0.1:1456/oauth/callback"

    public var gateway: String
    public init(gateway: String = RadiusOAuthProvider.defaultGateway) { self.gateway = Self.normalizeGatewayURL(gateway) }

    public func login(callbacks: OAuthLoginCallbacks) async throws -> OAuthCredentials {
        let config = try await loadOAuthConfig(gateway: gateway)
        let method = try await callbacks.onPrompt?(OAuthPrompt(message: "Radius login method", placeholder: "browser or device-code", allowEmpty: true))
        if method?.trimmingCharacters(in: .whitespacesAndNewlines) == "device-code" {
            return try await loginDeviceCode(config: config, callbacks: callbacks)
        }
        let pkce = try OAuthUtilities.generatePKCE()
        let url = authorizationURL(config: config, challenge: pkce.challenge)
        if let onAuth = callbacks.onAuth { await onAuth(OAuthAuthInfo(url: url, instructions: "Complete Radius login in your browser and paste the returned code")) }
        guard let code = try await callbacks.onPrompt?(OAuthPrompt(message: "Radius OAuth code", placeholder: "code", allowEmpty: false)), !code.isEmpty else { throw RadiusOAuthError.cancelled }
        return try await exchangeCode(code, verifier: pkce.verifier, config: config)
    }

    public func refreshToken(credentials: OAuthCredentials) async throws -> OAuthCredentials {
        let config = try await loadOAuthConfig(gateway: gateway)
        return try await tokenRequest(url: config.tokenEndpoint, fields: Self.refreshTokenFields(clientID: config.clientId, refreshToken: credentials.refresh), fallbackRefresh: credentials.refresh, fallbackGatewayConfig: Self.gatewayConfig(from: credentials))
    }

    public func apiKey(credentials: OAuthCredentials) -> String { credentials.access }

    public func modifyModels(_ models: [Model], credentials: OAuthCredentials) -> [Model] {
        guard let config = Self.gatewayConfig(from: credentials) else { return models }
        let injected = config.models.map { gatewayModel in
            Model(id: gatewayModel.id, name: gatewayModel.name, api: .piMessages, provider: .radius, baseUrl: config.baseUrl, reasoning: gatewayModel.reasoning, thinkingLevelMap: gatewayModel.thinkingLevelMap, input: gatewayModel.input, cost: gatewayModel.cost, contextWindow: gatewayModel.contextWindow, maxTokens: gatewayModel.maxTokens)
        }
        return models.filter { $0.provider != .radius } + injected
    }

    public func authorizationURL(config: RadiusOAuthConfig, challenge: String) -> String {
        var components = URLComponents(string: config.authorizationEndpoint)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: config.clientId),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "scope", value: config.scope),
            URLQueryItem(name: "state", value: "handoff=url"),
            URLQueryItem(name: "handoff", value: "url"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        return components.url?.absoluteString ?? config.authorizationEndpoint
    }

    public func exchangeCode(_ code: String, verifier: String, config: RadiusOAuthConfig) async throws -> OAuthCredentials {
        try await tokenRequest(url: config.tokenEndpoint, fields: Self.authorizationCodeFields(clientID: config.clientId, code: code, verifier: verifier), fallbackRefresh: nil, fallbackGatewayConfig: nil)
    }

    public func loginDeviceCode(config: RadiusOAuthConfig, callbacks: OAuthLoginCallbacks) async throws -> OAuthCredentials {
        let device = try await startDeviceFlow(config: config)
        if let onAuth = callbacks.onAuth { await onAuth(OAuthAuthInfo(url: device.verificationURI, instructions: "Enter Radius code: \(device.userCode)")) }
        return try await OAuthDeviceCodePoller.poll(intervalSeconds: device.interval, expiresInSeconds: device.expiresIn) {
            try Task.checkCancellation()
            return try await pollDeviceToken(config: config, deviceCode: device.deviceCode)
        }
    }

    public func loadOAuthConfig(gateway: String) async throws -> RadiusOAuthConfig {
        let url = URL(string: Self.normalizeGatewayURL(gateway) + "/v1/oauth")!
        let (data, response) = try await Self.data(for: URLRequest(url: url))
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw RadiusOAuthError.http(status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: String(data: data, encoding: .utf8) ?? "") }
        return try JSONDecoder().decode(RadiusOAuthConfig.self, from: data)
    }

    public func loadGatewayConfig(gateway: String, apiKey: String?) async throws -> RadiusGatewayConfig {
        var request = URLRequest(url: URL(string: Self.normalizeGatewayURL(gateway) + "/v1/config")!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let apiKey, !apiKey.isEmpty { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await Self.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw RadiusOAuthError.http(status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: String(data: data, encoding: .utf8) ?? "") }
        return try JSONDecoder().decode(RadiusGatewayConfig.self, from: data)
    }

    public static func authorizationCodeFields(clientID: String, code: String, verifier: String) -> [String: String] { ["grant_type": "authorization_code", "client_id": clientID, "code": code, "redirect_uri": redirectURI, "code_verifier": verifier] }
    public static func refreshTokenFields(clientID: String, refreshToken: String) -> [String: String] { ["grant_type": "refresh_token", "client_id": clientID, "refresh_token": refreshToken] }
    public static func normalizeGatewayURL(_ value: String) -> String { (value.contains("://") ? value : "https://\(value)").trimmingCharacters(in: CharacterSet(charactersIn: "/")) }

    public static func credentials(refresh: String, access: String, expiresIn: Double, gatewayConfig: RadiusGatewayConfig?, now: Date = Date()) -> OAuthCredentials {
        var extra: [String: JSONValue] = [:]
        if let gatewayConfig { extra["gatewayConfig"] = (try? JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(gatewayConfig))) }
        return OAuthCredentials(refresh: refresh, access: access, expires: Int64(now.addingTimeInterval(expiresIn - 60).timeIntervalSince1970 * 1000), extra: extra.isEmpty ? nil : extra)
    }

    public static func gatewayConfig(from credentials: OAuthCredentials) -> RadiusGatewayConfig? {
        guard let value = credentials.extra?["gatewayConfig"], let data = try? JSONEncoder().encode(value) else { return nil }
        return try? JSONDecoder().decode(RadiusGatewayConfig.self, from: data)
    }

    private func tokenRequest(url: String, fields: [String: String], fallbackRefresh: String?, fallbackGatewayConfig: RadiusGatewayConfig?) async throws -> OAuthCredentials {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Self.form(fields)
        let (data, response) = try await Self.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw RadiusOAuthError.http(status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: String(data: data, encoding: .utf8) ?? "") }
        let raw = try JSONDecoder().decode([String: JSONValue].self, from: data)
        let access = raw["access_token"]?.stringValue ?? ""
        let refresh = raw["refresh_token"]?.stringValue ?? fallbackRefresh ?? ""
        let gatewayConfig: RadiusGatewayConfig
        do { gatewayConfig = try await loadGatewayConfig(gateway: gateway, apiKey: access) }
        catch { if let fallbackGatewayConfig { gatewayConfig = fallbackGatewayConfig } else { throw error } }
        return Self.credentials(refresh: refresh, access: access, expiresIn: raw["expires_in"]?.doubleValue ?? 3600, gatewayConfig: gatewayConfig)
    }

    private func startDeviceFlow(config: RadiusOAuthConfig) async throws -> DeviceFlowResponse {
        var request = URLRequest(url: URL(string: config.deviceAuthorizationEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.form(["client_id": config.clientId, "scope": config.scope])
        let (data, response) = try await Self.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw RadiusOAuthError.http(status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: String(data: data, encoding: .utf8) ?? "") }
        return try JSONDecoder().decode(RadiusDeviceResponse.self, from: data).asDeviceFlowResponse
    }

    private func pollDeviceToken(config: RadiusOAuthConfig, deviceCode: String) async throws -> OAuthDeviceCodePollStatus<OAuthCredentials> {
        var request = URLRequest(url: URL(string: config.tokenEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.form(["grant_type": config.deviceCodeGrantType, "client_id": config.clientId, "device_code": deviceCode])
        let (data, response) = try await Self.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIError.invalidResponse("missing HTTP response") }
        if http.statusCode == 200 {
            let raw = try JSONDecoder().decode([String: JSONValue].self, from: data)
            let access = raw["access_token"]?.stringValue ?? ""
            let refresh = raw["refresh_token"]?.stringValue ?? ""
            let gatewayConfig = try await loadGatewayConfig(gateway: gateway, apiKey: access)
            return .complete(Self.credentials(refresh: refresh, access: access, expiresIn: raw["expires_in"]?.doubleValue ?? 3600, gatewayConfig: gatewayConfig))
        }
        let raw = (try? JSONDecoder().decode([String: JSONValue].self, from: data)) ?? [:]
        switch raw["error"]?.stringValue {
        case "authorization_pending": return .pending
        case "slow_down": return .slowDown
        case "access_denied": throw RadiusOAuthError.denied
        case "expired_token": throw RadiusOAuthError.expired
        default: throw RadiusOAuthError.http(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
    }

    private static func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        if let transport = requestTransport { return try await transport(request) }
        return try await HTTPRetry.data(for: request, policy: RetryPolicy(maxRetries: 1))
    }

    private static func form(_ fields: [String: String]) -> Data? { fields.map { "\(escape($0.key))=\(escape($0.value))" }.joined(separator: "&").data(using: .utf8) }
    private static func escape(_ value: String) -> String { value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value }
}

public enum RadiusOAuthError: Error, Equatable, LocalizedError, Sendable {
    case cancelled
    case denied
    case expired
    case http(status: Int, body: String)
    case invalidGatewayConfig
    public var errorDescription: String? {
        switch self {
        case .cancelled: return "Radius login cancelled"
        case .denied: return "Radius login denied"
        case .expired: return "Radius device code expired"
        case .http(let status, let body): return "Radius OAuth HTTP error \(status): \(body)"
        case .invalidGatewayConfig: return "Invalid Radius gateway config"
        }
    }
}

public struct RadiusOAuthConfig: Codable, Equatable, Sendable {
    public var issuer: String
    public var authorizationEndpoint: String
    public var tokenEndpoint: String
    public var deviceAuthorizationEndpoint: String
    public var deviceAuthorizationEventsEndpoint: String
    public var verificationEndpoint: String
    public var clientId: String
    public var scope: String
    public var deviceCodeGrantType: String
    public init(issuer: String, authorizationEndpoint: String, tokenEndpoint: String, deviceAuthorizationEndpoint: String, deviceAuthorizationEventsEndpoint: String, verificationEndpoint: String, clientId: String, scope: String, deviceCodeGrantType: String) { self.issuer = issuer; self.authorizationEndpoint = authorizationEndpoint; self.tokenEndpoint = tokenEndpoint; self.deviceAuthorizationEndpoint = deviceAuthorizationEndpoint; self.deviceAuthorizationEventsEndpoint = deviceAuthorizationEventsEndpoint; self.verificationEndpoint = verificationEndpoint; self.clientId = clientId; self.scope = scope; self.deviceCodeGrantType = deviceCodeGrantType }
}

public struct RadiusGatewayConfig: Codable, Equatable, Sendable {
    public var baseUrl: String
    public var models: [RadiusGatewayModel]
    public init(baseUrl: String, models: [RadiusGatewayModel]) { self.baseUrl = baseUrl; self.models = models }
}

public struct RadiusGatewayModel: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var reasoning: Bool
    public var thinkingLevelMap: [ModelThinkingLevel: String?]?
    public var input: [String]
    public var cost: ModelCost
    public var contextWindow: Int
    public var maxTokens: Int
    public init(id: String, name: String, reasoning: Bool, thinkingLevelMap: [ModelThinkingLevel: String?]? = nil, input: [String], cost: ModelCost, contextWindow: Int, maxTokens: Int) { self.id = id; self.name = name; self.reasoning = reasoning; self.thinkingLevelMap = thinkingLevelMap; self.input = input; self.cost = cost; self.contextWindow = contextWindow; self.maxTokens = maxTokens }
}

private struct RadiusDeviceResponse: Decodable {
    var deviceCode: String
    var userCode: String
    var verificationURI: String?
    var verificationURIComplete: String?
    var interval: Int?
    var expiresIn: Int
    enum CodingKeys: String, CodingKey { case deviceCode = "device_code"; case userCode = "user_code"; case verificationURI = "verification_uri"; case verificationURIComplete = "verification_uri_complete"; case interval; case expiresIn = "expires_in" }
    var asDeviceFlowResponse: DeviceFlowResponse { DeviceFlowResponse(deviceCode: deviceCode, userCode: userCode, verificationURI: verificationURIComplete ?? verificationURI ?? "", interval: interval ?? 5, expiresIn: expiresIn) }
}
