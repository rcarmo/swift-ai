import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct GitHubCopilotOAuthProvider: OAuthProvider {
    public let id = "github-copilot"
    public let name = "GitHub Copilot"
    private let clientID = String(data: Data(base64Encoded: "SXYxLmI1MDdhMDhjODdlY2ZlOTg=") ?? Data(), encoding: .utf8) ?? ""
    private let apiVersion = "2026-06-01"

    public init() {}

    public func login(callbacks: OAuthLoginCallbacks) async throws -> OAuthCredentials {
        let domainInput = try await callbacks.onPrompt?(OAuthPrompt(message: "GitHub Enterprise URL/domain (blank for github.com)", placeholder: "company.ghe.com", allowEmpty: true)) ?? ""
        let enterpriseDomain = OAuthUtilities.normalizeDomain(domainInput) ?? ""
        let domain = enterpriseDomain.isEmpty ? "github.com" : enterpriseDomain
        let device = try await startDeviceFlow(domain: domain)
        if let onAuth = callbacks.onAuth { await onAuth(OAuthAuthInfo(url: device.verificationURI, instructions: "Enter code: \(device.userCode)")) }
        let githubToken = try await pollForAccessToken(domain: domain, device: device)
        var credentials = try await refreshGitHubCopilotAccessToken(refreshToken: githubToken, enterpriseDomain: enterpriseDomain)
        if let onProgress = callbacks.onProgress { await onProgress("Enabling models...") }
        await enableAllModels(token: credentials.access, enterpriseDomain: enterpriseDomain)
        let ids = try await fetchAvailableModelIDs(token: credentials.access, enterpriseDomain: enterpriseDomain)
        credentials.extra = (credentials.extra ?? [:]).merging(["availableModelIds": .array(ids.map(JSONValue.string))]) { _, new in new }
        return credentials
    }

    public func refreshToken(credentials: OAuthCredentials) async throws -> OAuthCredentials {
        let domain = credentials.extra?["enterpriseUrl"]?.stringValue ?? ""
        var refreshed = try await refreshGitHubCopilotAccessToken(refreshToken: credentials.refresh, enterpriseDomain: domain)
        let ids = try await fetchAvailableModelIDs(token: refreshed.access, enterpriseDomain: domain)
        refreshed.extra = (refreshed.extra ?? [:]).merging(["availableModelIds": .array(ids.map(JSONValue.string))]) { _, new in new }
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
        return try JSONDecoder().decode(DeviceFlowResponse.self, from: data)
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
            case "slow_down": interval = Int(Double(interval) * 1.4); continue
            default: throw AIError.provider("device flow failed: \(raw["error_description"]?.stringValue ?? raw["error"]?.stringValue ?? "unknown")")
            }
        }
        throw AIError.provider("device flow timed out")
    }

    private func refreshGitHubCopilotAccessToken(refreshToken: String, enterpriseDomain: String) async throws -> OAuthCredentials {
        let domain = enterpriseDomain.isEmpty ? "github.com" : enterpriseDomain
        var request = URLRequest(url: URL(string: "https://api.\(domain)/copilot_internal/v2/token")!)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(refreshToken)", forHTTPHeaderField: "Authorization")
        for (k, v) in copilotHeaders() { request.setValue(v, forHTTPHeaderField: k) }
        let (data, response) = try await HTTPRetry.data(for: request, policy: RetryPolicy(maxRetries: 1))
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw AIError.apiError(status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: String(data: data, encoding: .utf8) ?? "") }
        let raw = try JSONDecoder().decode(CopilotTokenResponse.self, from: data)
        return OAuthCredentials(refresh: refreshToken, access: raw.token, expires: raw.expiresAt * 1000 - 5 * 60 * 1000, extra: ["enterpriseUrl": .string(enterpriseDomain)])
    }

    public func fetchAvailableModelIDs(token: String, enterpriseDomain: String) async throws -> [String] {
        var request = URLRequest(url: URL(string: Self.baseURL(token: token, enterpriseDomain: enterpriseDomain) + "/models")!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(apiVersion, forHTTPHeaderField: "X-GitHub-Api-Version")
        for (k, v) in copilotHeaders() { request.setValue(v, forHTTPHeaderField: k) }
        let (data, response) = try await HTTPRetry.data(for: request, policy: RetryPolicy(maxRetries: 1))
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw AIError.apiError(status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: String(data: data, encoding: .utf8) ?? "") }
        let raw = try JSONDecoder().decode(CopilotModelsResponse.self, from: data)
        return raw.data.filter(\.isSelectable).map(\.id)
    }

    public func enableAllModels(token: String, enterpriseDomain: String) async {
        let models = (try? BuiltinModels.all()) ?? []
        await withTaskGroup(of: Void.self) { group in
            for model in models where model.provider == .githubCopilot {
                group.addTask { _ = await enableModel(token: token, modelID: model.id, enterpriseDomain: enterpriseDomain) }
            }
        }
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

    private func availableModelSet(credentials: OAuthCredentials) -> Set<String>? {
        guard case .array(let values)? = credentials.extra?["availableModelIds"] else { return nil }
        return Set(values.compactMap(\.stringValue))
    }
}

private struct CopilotTokenResponse: Decodable { var token: String; var expiresAt: Int64; enum CodingKeys: String, CodingKey { case token; case expiresAt = "expires_at" } }
private struct CopilotModelsResponse: Decodable { var data: [CopilotModel] }
private struct CopilotModel: Decodable { var id: String; var modelPickerEnabled: Bool?; var policy: Policy?; var capabilities: Capabilities?; var isSelectable: Bool { modelPickerEnabled == true && policy?.state != "disabled" && capabilities?.supports?.toolCalls != false }; enum CodingKeys: String, CodingKey { case id; case modelPickerEnabled = "model_picker_enabled"; case policy, capabilities }; struct Policy: Decodable { var state: String? }; struct Capabilities: Decodable { var supports: Supports? }; struct Supports: Decodable { var toolCalls: Bool?; enum CodingKeys: String, CodingKey { case toolCalls = "tool_calls" } } }

