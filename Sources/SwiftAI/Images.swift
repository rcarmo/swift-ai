import Foundation

public enum ImagesAPI: String, Codable, Sendable { case openRouterImages = "openrouter-images" }
public enum ImagesProvider: String, Codable, Hashable, Sendable { case openRouter = "openrouter" }

public struct ImageInput: Codable, Equatable, Sendable {
    public var type: String
    public var text: String?
    public var data: String?
    public var mimeType: String?
    public init(type: String, text: String? = nil, data: String? = nil, mimeType: String? = nil) { self.type = type; self.text = text; self.data = data; self.mimeType = mimeType }
    public static func text(_ text: String) -> ImageInput { ImageInput(type: "text", text: text) }
    public static func image(data: String, mimeType: String) -> ImageInput { ImageInput(type: "image", data: data, mimeType: mimeType) }
}

public struct ImagesContext: Codable, Equatable, Sendable { public var input: [ImageInput]; public init(input: [ImageInput]) { self.input = input } }

public struct ImageOutput: Codable, Equatable, Sendable {
    public var type: String
    public var text: String?
    public var data: String?
    public var mimeType: String?
    public init(type: String, text: String? = nil, data: String? = nil, mimeType: String? = nil) { self.type = type; self.text = text; self.data = data; self.mimeType = mimeType }
}

public struct ImagesModel: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var api: ImagesAPI
    public var provider: ImagesProvider
    public var baseUrl: String?
    public var headers: [String: String]?
    public var input: [String]?
    public var output: [String]?
    public var cost: ModelCost
    public init(id: String, name: String, api: ImagesAPI, provider: ImagesProvider, baseUrl: String? = nil, headers: [String: String]? = nil, input: [String]? = nil, output: [String]? = nil, cost: ModelCost = ModelCost()) { self.id = id; self.name = name; self.api = api; self.provider = provider; self.baseUrl = baseUrl; self.headers = headers; self.input = input; self.output = output; self.cost = cost }
}

public struct AssistantImages: Codable, Equatable, Sendable {
    public var api: ImagesAPI?
    public var provider: ImagesProvider?
    public var model: String?
    public var output: [ImageOutput]
    public var stopReason: StopReason
    public var timestamp: Int64
    public var responseId: String?
    public var usage: Usage?
    public var errorMessage: String?
    public init(api: ImagesAPI? = nil, provider: ImagesProvider? = nil, model: String? = nil, output: [ImageOutput] = [], stopReason: StopReason, timestamp: Int64 = 0, responseId: String? = nil, usage: Usage? = nil, errorMessage: String? = nil) { self.api = api; self.provider = provider; self.model = model; self.output = output; self.stopReason = stopReason; self.timestamp = timestamp; self.responseId = responseId; self.usage = usage; self.errorMessage = errorMessage }
}

public struct ImagesResponseMetadata: Codable, Equatable, Sendable { public var status: Int; public var headers: [String: String]; public init(status: Int, headers: [String: String]) { self.status = status; self.headers = headers } }

public struct ImagesOptions: Codable, Equatable, Sendable {
    public var headers: [String: String]?
    public var timeoutMs: Int?
    public var maxRetries: Int?
    public var maxRetryDelayMs: Int?
    public var metadata: [String: JSONValue]?
    public var env: ProviderEnv?
    public init() {}
}

public typealias ImagesFunction = @Sendable (ImagesModel, ImagesContext, ImagesOptions?) async -> AssistantImages

public struct ImagesAPIProvider: Sendable {
    public var api: ImagesAPI
    public var generateImages: ImagesFunction
    public init(api: ImagesAPI, generateImages: @escaping ImagesFunction) { self.api = api; self.generateImages = generateImages }
}

public actor ImagesRegistry {
    public static let shared = ImagesRegistry()
    private var providers: [ImagesAPI: ImagesAPIProvider] = [:]
    private var models: [String: ImagesModel] = [:]

    public func register(_ provider: ImagesAPIProvider) { providers[provider.api] = provider }
    public func apiProvider(for api: ImagesAPI) -> ImagesAPIProvider? { providers[api] }
    public func clearProviders() { providers.removeAll() }
    public func register(_ model: ImagesModel) { models["\(model.provider.rawValue)/\(model.id)"] = model }
    public func clearModels() { models.removeAll() }
    public func model(provider: ImagesProvider, id: String) -> ImagesModel? { models["\(provider.rawValue)/\(id)"] }
    public func listModels(provider: ImagesProvider? = nil) -> [ImagesModel] { models.values.filter { provider == nil || $0.provider == provider! }.sorted { $0.id < $1.id } }
    public func listProviders() -> [ImagesProvider] { Array(Set(models.values.map(\.provider))).sorted { $0.rawValue < $1.rawValue } }
}

public extension SwiftAI {
    static func generateImages(model: ImagesModel?, context: ImagesContext, options: ImagesOptions? = nil) async -> AssistantImages {
        guard let model else { return AssistantImages(stopReason: .error, errorMessage: "nil model") }
        guard let provider = await ImagesRegistry.shared.apiProvider(for: model.api) else { return AssistantImages(api: model.api, provider: model.provider, model: model.id, stopReason: .error, errorMessage: "no image provider registered") }
        return await provider.generateImages(model, context, options)
    }
}
