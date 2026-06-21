import Foundation

public enum API: String, Codable, Sendable {
    case openAICompletions = "openai-completions"
    case openAIResponses = "openai-responses"
    case azureOpenAIResponses = "azure-openai-responses"
    case openAICodexResponses = "openai-codex-responses"
    case anthropicMessages = "anthropic-messages"
    case bedrockConverseStream = "bedrock-converse-stream"
    case googleGenerativeAI = "google-generative-ai"
    case googleGeminiCLI = "google-gemini-cli"
    case googleVertex = "google-vertex"
    case mistralConversations = "mistral-conversations"
    case faux = "faux"
}

public enum Provider: String, Codable, Hashable, Sendable {
    case openAI = "openai"
    case anthropic = "anthropic"
    case google = "google"
    case googleGeminiCLI = "google-gemini-cli"
    case googleAntigravity = "google-antigravity"
    case googleVertex = "google-vertex"
    case azureOpenAI = "azure-openai-responses"
    case openAICodex = "openai-codex"
    case githubCopilot = "github-copilot"
    case amazonBedrock = "amazon-bedrock"
    case mistral = "mistral"
    case xai = "xai"
    case groq = "groq"
    case cerebras = "cerebras"
    case openRouter = "openrouter"
    case vercelAIGateway = "vercel-ai-gateway"
    case zai = "zai"
    case miniMax = "minimax"
    case miniMaxCN = "minimax-cn"
    case huggingFace = "huggingface"
    case fireworks = "fireworks"
    case openCode = "opencode"
    case together = "together"
    case openCodeGo = "opencode-go"
    case kimiCoding = "kimi-coding"
    case deepSeek = "deepseek"
    case cloudflareWorkersAI = "cloudflare-workers-ai"
    case cloudflareAIGateway = "cloudflare-ai-gateway"
    case moonshotAI = "moonshotai"
    case moonshotAICN = "moonshotai-cn"
    case xiaomi = "xiaomi"
    case xiaomiTokenPlanCN = "xiaomi-token-plan-cn"
    case xiaomiTokenPlanAMS = "xiaomi-token-plan-ams"
    case xiaomiTokenPlanSGP = "xiaomi-token-plan-sgp"
    case antLing = "ant-ling"
    case nvidia = "nvidia"
    case zaiCodingCN = "zai-coding-cn"
    case faux = "faux"
}

public enum ThinkingLevel: String, Codable, Sendable { case minimal, low, medium, high, xhigh }
public enum ModelThinkingLevel: String, Codable, Hashable, Sendable { case off, minimal, low, medium, high, xhigh }
public enum Role: String, Codable, Sendable { case user, assistant, toolResult }
public enum StopReason: String, Codable, Sendable { case stop, length, toolUse, error, aborted }
public enum CacheRetention: String, Codable, Sendable { case none, short, long }
public enum Transport: String, Codable, Sendable { case sse, websocket, webSocketCached = "websocket-cached", auto }

public enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public var stringValue: String? { if case .string(let value) = self { return value }; return nil }
    public var doubleValue: Double? { if case .number(let value) = self { return value }; return nil }
    public var boolValue: Bool? { if case .bool(let value) = self { return value }; return nil }
    public var arrayValue: [JSONValue]? { if case .array(let value) = self { return value }; return nil }
    public var objectValue: [String: JSONValue]? { if case .object(let value) = self { return value }; return nil }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let v = try? container.decode(Bool.self) { self = .bool(v) }
        else if let v = try? container.decode(Double.self) { self = .number(v) }
        else if let v = try? container.decode(String.self) { self = .string(v) }
        else if let v = try? container.decode([JSONValue].self) { self = .array(v) }
        else { self = .object(try container.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let v): try container.encode(v)
        case .number(let v): try container.encode(v)
        case .string(let v): try container.encode(v)
        case .array(let v): try container.encode(v)
        case .object(let v): try container.encode(v)
        }
    }
}

public struct ContentBlock: Codable, Equatable, Sendable {
    public var type: String
    public var text: String?
    public var textSignature: String?
    public var thinking: String?
    public var thinkingSignature: String?
    public var redacted: Bool?
    public var data: String?
    public var mimeType: String?
    public var id: String?
    public var name: String?
    public var arguments: [String: JSONValue]?
    public var thoughtSignature: String?

    public init(type: String, text: String? = nil, textSignature: String? = nil, thinking: String? = nil, thinkingSignature: String? = nil, redacted: Bool? = nil, data: String? = nil, mimeType: String? = nil, id: String? = nil, name: String? = nil, arguments: [String: JSONValue]? = nil, thoughtSignature: String? = nil) {
        self.type = type; self.text = text; self.textSignature = textSignature; self.thinking = thinking; self.thinkingSignature = thinkingSignature; self.redacted = redacted; self.data = data; self.mimeType = mimeType; self.id = id; self.name = name; self.arguments = arguments; self.thoughtSignature = thoughtSignature
    }

    public static func text(_ text: String, signature: String? = nil) -> ContentBlock { ContentBlock(type: "text", text: text, textSignature: signature) }
    public static func thinking(_ text: String, signature: String? = nil, redacted: Bool? = nil) -> ContentBlock { ContentBlock(type: "thinking", thinking: text, thinkingSignature: signature, redacted: redacted) }
    public static func image(data: String, mimeType: String) -> ContentBlock { ContentBlock(type: "image", data: data, mimeType: mimeType) }
    public static func toolCall(id: String, name: String, arguments: [String: JSONValue]) -> ContentBlock { ContentBlock(type: "toolCall", id: id, name: name, arguments: arguments) }
}

public struct CostBreakdown: Codable, Equatable, Sendable { public var input = 0.0; public var output = 0.0; public var cacheRead = 0.0; public var cacheWrite = 0.0; public var total = 0.0; public init() {} }
public struct Usage: Codable, Equatable, Sendable { public var input = 0; public var output = 0; public var cacheRead = 0; public var cacheWrite = 0; public var cacheWrite1h: Int?; public var totalTokens = 0; public var cost = CostBreakdown(); public init() {} }

public struct DiagnosticError: Codable, Equatable, Sendable { public var name: String?; public var message: String; public var stack: String?; public var code: JSONValue?; public init(message: String, name: String? = nil, stack: String? = nil, code: JSONValue? = nil) { self.message = message; self.name = name; self.stack = stack; self.code = code } }
public struct AssistantMessageDiagnostic: Codable, Equatable, Sendable { public var type: String; public var timestamp: Int64; public var error: DiagnosticError; public var details: [String: JSONValue]?; public init(type: String, timestamp: Int64, error: DiagnosticError, details: [String: JSONValue]? = nil) { self.type = type; self.timestamp = timestamp; self.error = error; self.details = details } }

public struct Message: Codable, Equatable, Sendable {
    public var role: Role
    public var content: [ContentBlock]
    public var timestamp: Int64
    public var api: API?
    public var provider: Provider?
    public var model: String?
    public var responseId: String?
    public var responseModel: String?
    public var diagnostics: [AssistantMessageDiagnostic]?
    public var usage: Usage?
    public var stopReason: StopReason?
    public var errorMessage: String?
    public var toolCallId: String?
    public var toolName: String?
    public var isError: Bool?
    public var details: JSONValue?

    public init(role: Role, content: [ContentBlock], timestamp: Int64 = 0) { self.role = role; self.content = content; self.timestamp = timestamp }
    public static func user(_ text: String) -> Message { Message(role: .user, content: [.text(text)]) }
}

public struct Tool: Codable, Equatable, Sendable { public var name: String; public var description: String; public var parameters: JSONValue; public init(name: String, description: String, parameters: JSONValue) { self.name = name; self.description = description; self.parameters = parameters } }
public struct AIContext: Codable, Equatable, Sendable { public var systemPrompt: String?; public var messages: [Message]; public var tools: [Tool]?; public init(systemPrompt: String? = nil, messages: [Message] = [], tools: [Tool]? = nil) { self.systemPrompt = systemPrompt; self.messages = messages; self.tools = tools } }

public struct ModelCost: Codable, Equatable, Sendable { public var input = 0.0; public var output = 0.0; public var cacheRead = 0.0; public var cacheWrite = 0.0; public init(input: Double = 0, output: Double = 0, cacheRead: Double = 0, cacheWrite: Double = 0) { self.input = input; self.output = output; self.cacheRead = cacheRead; self.cacheWrite = cacheWrite } }

public struct Model: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var api: API
    public var provider: Provider
    public var baseUrl: String
    public var reasoning: Bool
    public var thinkingLevelMap: [ModelThinkingLevel: String?]?
    public var input: [String]
    public var cost: ModelCost
    public var contextWindow: Int
    public var maxTokens: Int
    public var headers: [String: String]?
    public var completionsCompat: OpenAICompletionsCompat?
    public var responsesCompat: OpenAIResponsesCompat?
    public var anthropicCompat: AnthropicMessagesCompat?

    public init(id: String, name: String, api: API, provider: Provider, baseUrl: String = "", reasoning: Bool = false, thinkingLevelMap: [ModelThinkingLevel: String?]? = nil, input: [String] = ["text"], cost: ModelCost = ModelCost(), contextWindow: Int = 0, maxTokens: Int = 0, headers: [String: String]? = nil, completionsCompat: OpenAICompletionsCompat? = nil, responsesCompat: OpenAIResponsesCompat? = nil, anthropicCompat: AnthropicMessagesCompat? = nil) {
        self.id = id; self.name = name; self.api = api; self.provider = provider; self.baseUrl = baseUrl; self.reasoning = reasoning; self.thinkingLevelMap = thinkingLevelMap; self.input = input; self.cost = cost; self.contextWindow = contextWindow; self.maxTokens = maxTokens; self.headers = headers; self.completionsCompat = completionsCompat; self.responsesCompat = responsesCompat; self.anthropicCompat = anthropicCompat
    }
}

public struct ThinkingBudgets: Codable, Equatable, Sendable { public var minimal: Int?; public var low: Int?; public var medium: Int?; public var high: Int?; public init(minimal: Int? = nil, low: Int? = nil, medium: Int? = nil, high: Int? = nil) { self.minimal = minimal; self.low = low; self.medium = medium; self.high = high } }
public typealias ProviderEnv = [String: String]

public struct RetryConfig: Codable, Equatable, Sendable { public var maxRetries: Int?; public var maxDelayMs: Int?; public init(maxRetries: Int? = nil, maxDelayMs: Int? = nil) { self.maxRetries = maxRetries; self.maxDelayMs = maxDelayMs } }

public struct StreamOptions: Codable, Equatable, Sendable {
    public var temperature: Double?
    public var maxTokens: Int?
    public var apiKey: String?
    public var transport: Transport?
    public var cacheRetention: CacheRetention?
    public var sessionId: String?
    public var headers: [String: String]?
    public var maxRetryDelayMs: Int?
    public var metadata: [String: JSONValue]?
    public var env: ProviderEnv?
    public var region: String?
    public var profile: String?
    public var bearerToken: String?
    public var requestMetadata: [String: String]?
    public var project: String?
    public var location: String?
    public var textVerbosity: String?
    public var azureApiVersion: String?
    public var azureResourceName: String?
    public var azureBaseUrl: String?
    public var azureDeploymentName: String?
    public var timeoutMs: Int?
    public var webSocketConnectTimeoutMs: Int?
    public var maxRetries: Int?
    public var reasoning: ThinkingLevel?
    public var thinkingBudgets: ThinkingBudgets?
    public var reasoningSummary: String?
    public var serviceTier: String?

    public init() {}
}
