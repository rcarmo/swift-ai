import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct GitHubCopilotOAuthProvider: OAuthProvider {
    public let id = "github-copilot"
    public let name = "GitHub Copilot"
    private let clientID = String(data: Data(base64Encoded: "SXYxLmI1MDdhMDhjODdlY2ZlOTg=") ?? Data(), encoding: .utf8) ?? ""
    private let apiVersion = "2026-06-01"
    public typealias DataTransport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    nonisolated(unsafe) public static var dataTransport: DataTransport?

    public init() {}

    public func login(callbacks: OAuthLoginCallbacks) async throws -> OAuthCredentials {
        let domainInput = try await callbacks.onPrompt?(OAuthPrompt(message: "GitHub Enterprise URL/domain (blank for github.com)", placeholder: "company.ghe.com", allowEmpty: true)) ?? ""
        let enterpriseDomain = OAuthUtilities.normalizeDomain(domainInput) ?? ""
        let domain = enterpriseDomain.isEmpty ? "github.com" : enterpriseDomain
        let device = try await startDeviceFlow(domain: domain)
        if let onAuth = callbacks.onAuth { await onAuth(OAuthAuthInfo(url: device.verificationURI, instructions: "Enter code: \(device.userCode)")) }
        let githubToken = try await pollForAccessToken(domain: domain, device: device)
        var credentials = try await refreshGitHubCopilotAccessToken(refreshToken: githubToken, enterpriseDomain: enterpriseDomain)
        let catalog = try await fetchAvailableModelCatalog(token: credentials.access, enterpriseDomain: enterpriseDomain, maxRetries: 2, maxElapsedMs: 5_000)
        var ids = catalog.availableModelIds
        if !catalog.policyModelIds.isEmpty {
            if let onProgress = callbacks.onProgress { await onProgress("Enabling models...") }
            let enabled = await enableModels(token: credentials.access, modelIDs: catalog.policyModelIds, enterpriseDomain: enterpriseDomain)
            ids = Array(Set(ids).union(enabled)).sorted()
        }
        credentials.extra = (credentials.extra ?? [:]).merging(["availableModelIds": .array(ids.map { .string($0) })]) { _, new in new }
        return credentials
    }

    public func refreshToken(credentials: OAuthCredentials) async throws -> OAuthCredentials {
        let domain = credentials.extra?["enterpriseUrl"]?.stringValue ?? ""
        var refreshed = try await refreshGitHubCopilotAccessToken(refreshToken: credentials.refresh, enterpriseDomain: domain)
        let ids = try await fetchAvailableModelIDs(token: refreshed.access, enterpriseDomain: domain)
        refreshed.extra = (refreshed.extra ?? [:]).merging(["availableModelIds": .array(ids.map { .string($0) })]) { _, new in new }
        return refreshed
    }

    public func refreshToken(credentials: OAuthCredentials, cancellation: OAuthCancellation) async throws -> OAuthCredentials {
        try cancellation.check()
        let domain = credentials.extra?["enterpriseUrl"]?.stringValue ?? ""
        var refreshed = try await refreshGitHubCopilotAccessToken(refreshToken: credentials.refresh, enterpriseDomain: domain)
        try cancellation.check()
        let ids = try await fetchAvailableModelIDs(token: refreshed.access, enterpriseDomain: domain)
        try cancellation.check()
        refreshed.extra = (refreshed.extra ?? [:]).merging(["availableModelIds": .array(ids.map { .string($0) })]) { _, new in new }
        return refreshed
    }

    public func apiKey(credentials: OAuthCredentials) -> String { credentials.access }

    public func modifyModels(_ models: [Model], credentials: OAuthCredentials) -> [Model] {
        let domain = credentials.extra?["enterpriseUrl"]?.stringValue ?? ""
        let base = Self.baseURL(token: credentials.access, enterpriseDomain: domain)
        let available = availableModelSet(credentials: credentials)
        return models.compactMap { model in
            guard model.provider == .githubCopilot else { return model }
            if let available, !available.contains(model.id) { return nil }
            var copy = model
            copy.baseUrl = base
            return copy
        }
    }

    public static func baseURL(token: String, enterpriseDomain: String = "") -> String {
        if let range = token.range(of: "proxy-ep=([^;]+)", options: .regularExpression) {
            let match = String(token[range]).replacingOccurrences(of: "proxy-ep=", with: "")
            return "https://" + match.replacingOccurrences(of: "proxy.", with: "api.")
        }
        if !enterpriseDomain.isEmpty { return "https://copilot-api." + enterpriseDomain }
        return "https://api.individual.githubcopilot.com"
    }

    private func copilotHeaders() -> [String: String] { ["User-Agent": "GitHubCopilotChat/0.35.0", "Editor-Version": "vscode/1.107.0", "Editor-Plugin-Version": "copilot-chat/0.35.0", "Copilot-Integration-Id": "vscode-chat"] }

    private func startDeviceFlow(domain: String) async throws -> DeviceFlowResponse {
        var request = URLRequest(url: URL(string: "https://\(domain)/login/device/code")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("GitHubCopilotChat/0.35.0", forHTTPHeaderField: "User-Agent")
        request.httpBody = "client_id=\(clientID)&scope=read:user".data(using: .utf8)
        let (data, response) = try await HTTPRetry.data(for: request, policy: RetryPolicy())
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw AIError.apiError(status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: String(data: data, encoding: .utf8) ?? "") }
        var device = try JSONDecoder().decode(DeviceFlowResponse.self, from: data)
        device.verificationURI = try Self.normalizeVerificationURI(device.verificationURI)
        return device
    }

    public static func normalizeVerificationURI(_ raw: String) throws -> String {
        guard let components = URLComponents(string: raw), let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https", let url = components.url else {
            throw AIError.provider("Untrusted verification_uri: \(raw)")
        }
        return url.absoluteString
    }

    public static func nextDevicePollIntervalAfterSlowDown(current: Int, serverInterval: Double?) -> Int {
        if let serverInterval, serverInterval > 0 { return max(1, Int(serverInterval.rounded(.down))) }
        return max(1, current) + 5
    }

    private func pollForAccessToken(domain: String, device: DeviceFlowResponse) async throws -> String {
        let deadline = Date().addingTimeInterval(TimeInterval(device.expiresIn))
        var interval = max(1, device.interval)
        while Date() < deadline {
            try await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
            var request = URLRequest(url: URL(string: "https://\(domain)/login/oauth/access_token")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.setValue("GitHubCopilotChat/0.35.0", forHTTPHeaderField: "User-Agent")
            request.httpBody = "client_id=\(clientID)&device_code=\(device.deviceCode)&grant_type=urn:ietf:params:oauth:grant-type:device_code".data(using: .utf8)
            let (data, _) = try await URLSession.shared.data(for: request)
            let raw = (try? JSONDecoder().decode([String: JSONValue].self, from: data)) ?? [:]
            if let token = raw["access_token"]?.stringValue { return token }
            switch raw["error"]?.stringValue {
            case "authorization_pending": continue
            case "slow_down":
                interval = Self.nextDevicePollIntervalAfterSlowDown(current: interval, serverInterval: raw["interval"]?.doubleValue)
                continue
            default: throw AIError.provider("device flow failed: \(raw["error_description"]?.stringValue ?? raw["error"]?.stringValue ?? "unknown")")
            }
        }
        throw AIError.provider("device flow timed out")
    }

    private func refreshGitHubCopilotAccessToken(refreshToken: String, enterpriseDomain: String) async throws -> OAuthCredentials {
        try Task.checkCancellation()
        let domain = enterpriseDomain.isEmpty ? "github.com" : enterpriseDomain
        var request = URLRequest(url: URL(string: "https://api.\(domain)/copilot_internal/v2/token")!)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(refreshToken)", forHTTPHeaderField: "Authorization")
        for (k, v) in copilotHeaders() { request.setValue(v, forHTTPHeaderField: k) }
        let (data, response) = try await HTTPRetry.data(for: request, policy: RetryPolicy(maxRetries: 1))
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw AIError.apiError(status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: String(data: data, encoding: .utf8) ?? "") }
        let raw = try JSONDecoder().decode(CopilotTokenResponse.self, from: data)
        return OAuthCredentials(refresh: refreshToken, access: raw.token, expires: raw.expiresAt * 1000 - 5 * 60 * 1000, extra: ["enterpriseUrl": .string(enterpriseDomain)])
    }

    public func fetchAvailableModelIDs(token: String, enterpriseDomain: String) async throws -> [String] {
        try await fetchAvailableModelCatalog(token: token, enterpriseDomain: enterpriseDomain).availableModelIds
    }

    public func fetchAvailableModelCatalog(token: String, enterpriseDomain: String, maxRetries: Int = 0, maxElapsedMs: Int = 0) async throws -> CopilotModelCatalog {
        try Task.checkCancellation()
        var request = URLRequest(url: URL(string: Self.baseURL(token: token, enterpriseDomain: enterpriseDomain) + "/models")!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(apiVersion, forHTTPHeaderField: "X-GitHub-Api-Version")
        for (k, v) in copilotHeaders() { request.setValue(v, forHTTPHeaderField: k) }
        let (data, response) = try await Self.fetchWithRateLimitRetry(request: request, maxRetries: maxRetries, maxElapsedMs: maxElapsedMs)
        try Task.checkCancellation()
        guard response.statusCode == 200 else { throw AIError.apiError(status: response.statusCode, body: String(data: data, encoding: .utf8) ?? "") }
        let raw = try JSONDecoder().decode(CopilotModelsResponse.self, from: data)
        return Self.parseModelCatalog(raw.data, allowPolicyFallback: Self.baseURL(token: token, enterpriseDomain: enterpriseDomain) == "https://api.individual.githubcopilot.com")
    }


    public func enableAllModels(token: String, enterpriseDomain: String) async {
        let ids = (try? await fetchAvailableModelCatalog(token: token, enterpriseDomain: enterpriseDomain, maxRetries: 2, maxElapsedMs: 5_000).policyModelIds) ?? []
        _ = await enableModels(token: token, modelIDs: ids, enterpriseDomain: enterpriseDomain)
    }

    @discardableResult public func enableModels(token: String, modelIDs: [String], enterpriseDomain: String, maxConcurrent: Int = 4, operation: (@Sendable (String) async -> Bool)? = nil) async -> [String] {
        let limit = max(1, maxConcurrent)
        var iterator = modelIDs.makeIterator()
        var enabled: [String] = []
        await withTaskGroup(of: (String, Bool).self) { group in
            var inFlight = 0
            func submit(_ modelID: String) {
                inFlight += 1
                group.addTask {
                    let ok: Bool
                    if let operation { ok = await operation(modelID) }
                    else { ok = await enableModel(token: token, modelID: modelID, enterpriseDomain: enterpriseDomain) }
                    return (modelID, ok)
                }
            }
            while inFlight < limit, let next = iterator.next(), !Task.isCancelled { submit(next) }
            while inFlight > 0 {
                if let result = await group.next(), result.1 { enabled.append(result.0) }
                inFlight -= 1
                if Task.isCancelled { continue }
                if let next = iterator.next() { submit(next) }
            }
        }
        return enabled
    }

    public func enableModel(token: String, modelID: String, enterpriseDomain: String) async -> Bool {
        var request = URLRequest(url: URL(string: Self.baseURL(token: token, enterpriseDomain: enterpriseDomain) + "/models/\(modelID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? modelID)/policy")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("chat-policy", forHTTPHeaderField: "openai-intent")
        request.setValue("chat-policy", forHTTPHeaderField: "x-interaction-type")
        for (k, v) in copilotHeaders() { request.setValue(v, forHTTPHeaderField: k) }
        request.httpBody = try? JSONEncoder().encode(JSONValue.object(["state": .string("enabled")]))
        guard let (_, response) = try? await URLSession.shared.data(for: request), let http = response as? HTTPURLResponse else { return false }
        return (200..<300).contains(http.statusCode)
    }

    public static func parseModelCatalog(_ models: [CopilotModel], allowPolicyFallback: Bool) -> CopilotModelCatalog {
        let account = models.filter { $0.capabilities?.supports?.toolCalls != false }
        let picker = account.filter { $0.modelPickerEnabled == true && $0.policy?.state != "disabled" }.map(\.id)
        let available = (!picker.isEmpty || !allowPolicyFallback) ? picker : account.filter { $0.policy?.state == "enabled" }.map(\.id)
        let useFallback = allowPolicyFallback && picker.isEmpty
        let policy = account.filter { $0.policy?.state == "unconfigured" && ($0.modelPickerEnabled == true || useFallback) }.map(\.id)
        return CopilotModelCatalog(availableModelIds: Array(Set(available)).sorted(), policyModelIds: Array(Set(policy)).sorted())
    }

    private static func performData(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if let dataTransport { return try await dataTransport(request) }
        let (data, response) = try await HTTPRetry.data(for: request, policy: .noRetry())
        guard let http = response as? HTTPURLResponse else { throw AIError.invalidResponse("non-HTTP response") }
        return (data, http)
    }

    private static func fetchWithRateLimitRetry(request: URLRequest, maxRetries: Int, maxElapsedMs: Int) async throws -> (Data, HTTPURLResponse) {
        let deadline = maxElapsedMs > 0 ? Date().addingTimeInterval(Double(maxElapsedMs) / 1000.0) : nil
        var attempt = 0
        while true {
            let (data, response) = try await performData(request)
            guard response.statusCode == 429, attempt < maxRetries else { return (data, response) }
            let retryAfter = retryAfterMilliseconds(response: response) ?? 500
            if let deadline, Date().addingTimeInterval(Double(retryAfter) / 1000.0) > deadline { return (data, response) }
            try await Task.sleep(nanoseconds: UInt64(max(0, retryAfter)) * 1_000_000)
            attempt += 1
        }
    }

    private static func retryAfterMilliseconds(response: HTTPURLResponse) -> Int? {
        let headers = response.allHeaderFields.reduce(into: [String: String]()) { $0[String(describing: $1.key).lowercased()] = String(describing: $1.value) }
        if let ms = headers["retry-after-ms"], let value = Double(ms) { return Int(value) }
        if let seconds = headers["retry-after"], let value = Double(seconds) { return Int(value * 1000) }
        if let date = headers["retry-after"] {
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            if let parsed = formatter.date(from: date) { return max(0, Int(parsed.timeIntervalSinceNow * 1000)) }
        }
        return nil
    }

    private func availableModelSet(credentials: OAuthCredentials) -> Set<String>? {
        guard case .array(let values)? = credentials.extra?["availableModelIds"] else { return nil }
        return Set(values.compactMap(\.stringValue))
    }
}

public struct CopilotModelCatalog: Equatable, Sendable { public var availableModelIds: [String]; public var policyModelIds: [String]; public init(availableModelIds: [String], policyModelIds: [String]) { self.availableModelIds = availableModelIds; self.policyModelIds = policyModelIds } }
private struct CopilotTokenResponse: Decodable { var token: String; var expiresAt: Int64; enum CodingKeys: String, CodingKey { case token; case expiresAt = "expires_at" } }
private struct CopilotModelsResponse: Decodable { var data: [CopilotModel] }
public struct CopilotModel: Decodable, Sendable { public var id: String; public var modelPickerEnabled: Bool?; public var policy: Policy?; public var capabilities: Capabilities?; public init(id: String, modelPickerEnabled: Bool? = nil, policy: Policy? = nil, capabilities: Capabilities? = nil) { self.id = id; self.modelPickerEnabled = modelPickerEnabled; self.policy = policy; self.capabilities = capabilities }; enum CodingKeys: String, CodingKey { case id; case modelPickerEnabled = "model_picker_enabled"; case policy, capabilities }; public struct Policy: Decodable, Sendable { public var state: String?; public init(state: String? = nil) { self.state = state } }; public struct Capabilities: Decodable, Sendable { public var supports: Supports?; public init(supports: Supports? = nil) { self.supports = supports } }; public struct Supports: Decodable, Sendable { public var toolCalls: Bool?; public init(toolCalls: Bool? = nil) { self.toolCalls = toolCalls }; enum CodingKeys: String, CodingKey { case toolCalls = "tool_calls" } } }

