import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum ClassifierAPI: String, Codable, Sendable {
    case typeSafeSystemOne = "typesafe-system-one"
    case cloudflareWorkersAISystemOne = "cloudflare-workers-ai-system-one"
}

public enum ClassifierProvider: String, Codable, Hashable, Sendable {
    case typesafe = "typesafe"
    case cloudflareWorkersAI = "cloudflare-workers-ai"
    case openRouter = "openrouter"
    case vercelAIGateway = "vercel-ai-gateway"
    case openCode = "opencode"
}

public struct ClassifierModel: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var api: ClassifierAPI
    public var provider: ClassifierProvider
    public var baseUrl: String
    public var input: [String]
    public var cost: ModelCost
    public var contextWindow: Int
    public var maxTokens: Int
    public var headers: ProviderHeaders?
    public var type: String?

    public init(id: String, name: String, api: ClassifierAPI, provider: ClassifierProvider, baseUrl: String = "", input: [String] = ["text"], cost: ModelCost = ModelCost(), contextWindow: Int = 0, maxTokens: Int = 0, headers: ProviderHeaders? = nil, type: String? = nil) {
        self.id = id
        self.name = name
        self.api = api
        self.provider = provider
        self.baseUrl = baseUrl
        self.input = input
        self.cost = cost
        self.contextWindow = contextWindow
        self.maxTokens = maxTokens
        self.headers = headers
        self.type = type
    }

    enum CodingKeys: String, CodingKey { case id, name, api, provider, baseUrl, input, cost, contextWindow, maxTokens, headers, type }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        api = try c.decode(ClassifierAPI.self, forKey: .api)
        provider = try c.decode(ClassifierProvider.self, forKey: .provider)
        baseUrl = try c.decodeIfPresent(String.self, forKey: .baseUrl) ?? ""
        input = try c.decodeIfPresent([String].self, forKey: .input) ?? ["text"]
        cost = try c.decodeIfPresent(ModelCost.self, forKey: .cost) ?? ModelCost()
        contextWindow = try c.decodeIfPresent(Int.self, forKey: .contextWindow) ?? 0
        maxTokens = try c.decodeIfPresent(Int.self, forKey: .maxTokens) ?? 0
        headers = try c.decodeIfPresent(ProviderHeaders.self, forKey: .headers)
        type = try c.decodeIfPresent(String.self, forKey: .type)
    }
}

public struct ClassifierQuestion: Codable, Equatable, Sendable {
    public var type: String
    public var instructions: String
    public var criteria: JSONValue
    public init(type: String, instructions: String, criteria: JSONValue) { self.type = type; self.instructions = instructions; self.criteria = criteria }
    public static func choice(instructions: String, criteria: [String: String]) -> ClassifierQuestion { ClassifierQuestion(type: "choice", instructions: instructions, criteria: .object(criteria.mapValues { .string($0) })) }
    public static func score(instructions: String, criteria: [String]) -> ClassifierQuestion { ClassifierQuestion(type: "score", instructions: instructions, criteria: .array(criteria.map { .string($0) })) }
    public static func bool(instructions: String, trueCriteria: String? = nil, falseCriteria: String? = nil) -> ClassifierQuestion {
        var object: [String: JSONValue] = [:]
        if let trueCriteria { object["true"] = .string(trueCriteria) }
        if let falseCriteria { object["false"] = .string(falseCriteria) }
        return ClassifierQuestion(type: "bool", instructions: instructions, criteria: .object(object))
    }
}

public struct ClassificationContext: Codable, Equatable, Sendable {
    public var state: JSONValue
    public var questions: [String: ClassifierQuestion]
    public init(state: JSONValue, questions: [String: ClassifierQuestion]) { self.state = state; self.questions = questions }
    public init(stateObject: [String: JSONValue], questions: [String: ClassifierQuestion]) { self.state = .object(stateObject); self.questions = questions }
    public init(input: String, questions: [String: ClassifierQuestion]) { self.state = .string(input); self.questions = questions }
}

public struct ClassificationAnswer: Codable, Equatable, Sendable {
    public var type: String
    public var choice: String?
    public var probabilities: [String: Double]?
    public var confidence: Double?
    public var score: Double?
    public var probability: Double?
    public init(type: String, choice: String? = nil, probabilities: [String: Double]? = nil, confidence: Double? = nil, score: Double? = nil, probability: Double? = nil) { self.type = type; self.choice = choice; self.probabilities = probabilities; self.confidence = confidence; self.score = score; self.probability = probability }
}

public struct ClassificationResult: Codable, Equatable, Sendable {
    public var api: ClassifierAPI?
    public var provider: ClassifierProvider?
    public var model: String?
    public var answers: [String: ClassificationAnswer]
    public var stopReason: StopReason
    public var timestamp: Int64
    public var responseId: String?
    public var usage: Usage?
    public var errorMessage: String?
    public init(api: ClassifierAPI? = nil, provider: ClassifierProvider? = nil, model: String? = nil, answers: [String: ClassificationAnswer] = [:], stopReason: StopReason, timestamp: Int64 = 0, responseId: String? = nil, usage: Usage? = nil, errorMessage: String? = nil) {
        self.api = api
        self.provider = provider
        self.model = model
        self.answers = answers
        self.stopReason = stopReason
        self.timestamp = timestamp
        self.responseId = responseId
        self.usage = usage
        self.errorMessage = errorMessage
    }
}

public struct ClassifierResponseMetadata: Codable, Equatable, Sendable { public var status: Int; public var headers: [String: String]; public init(status: Int, headers: [String: String]) { self.status = status; self.headers = headers } }

public struct ClassifierOptions: Sendable {
    public typealias RequestTransport = @Sendable (URLRequest, RetryPolicy) async throws -> (Data, URLResponse)
    public var apiKey: String?
    public var headers: ProviderHeaders?
    public var timeoutMs: Int?
    public var maxRetries: Int?
    public var maxRetryDelayMs: Int?
    public var metadata: [String: JSONValue]?
    public var env: ProviderEnv?
    public var telemetryContext: TelemetryContext?
    public var requestTransport: RequestTransport?
    public var onPayload: (@Sendable ([String: JSONValue], ClassifierModel) async throws -> [String: JSONValue])?
    public var onResponse: (@Sendable (ClassifierResponseMetadata, ClassifierModel) async -> Void)?
    public init() {}
}

public typealias ClassifierFunction = @Sendable (ClassifierModel, ClassificationContext, ClassifierOptions?) async -> ClassificationResult

public struct ClassifierAPIProvider: Sendable {
    public var api: ClassifierAPI
    public var classify: ClassifierFunction
    public init(api: ClassifierAPI, classify: @escaping ClassifierFunction) { self.api = api; self.classify = classify }
}

public actor ClassifierRegistry {
    public static let shared = ClassifierRegistry()
    private var providers: [ClassifierAPI: ClassifierAPIProvider] = [:]
    private var models: [String: ClassifierModel] = [:]

    public func register(_ provider: ClassifierAPIProvider) { providers[provider.api] = provider }
    public func apiProvider(for api: ClassifierAPI) -> ClassifierAPIProvider? { providers[api] }
    public func clearProviders() { providers.removeAll() }
    public func register(_ model: ClassifierModel) { models["\(model.provider.rawValue)/\(model.id)"] = model }
    public func clearModels() { models.removeAll() }
    public func model(provider: ClassifierProvider, id: String) -> ClassifierModel? { models["\(provider.rawValue)/\(id)"] }
    public func listModels(provider: ClassifierProvider? = nil) -> [ClassifierModel] { models.values.filter { provider == nil || $0.provider == provider! }.sorted { $0.id < $1.id } }
    public func listProviders() -> [ClassifierProvider] { Array(Set(models.values.map(\.provider))).sorted { $0.rawValue < $1.rawValue } }
}

public extension SwiftAI {
    static func classify(model: ClassifierModel?, context: ClassificationContext, options: ClassifierOptions? = nil) async -> ClassificationResult {
        guard let model else { return ClassificationResult(stopReason: .error, errorMessage: "nil model") }
        guard let provider = await ClassifierRegistry.shared.apiProvider(for: model.api) else { return ClassificationResult(api: model.api, provider: model.provider, model: model.id, stopReason: .error, errorMessage: "no classifier provider registered") }
        return await provider.classify(model, context, options)
    }
}
