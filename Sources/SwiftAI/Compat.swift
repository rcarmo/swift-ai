import Foundation

public struct ChatTemplateKwargValue: Codable, Equatable, Sendable {
    public var value: JSONValue?
    public var variable: String?
    public var omitWhenOff: Bool?

    enum CodingKeys: String, CodingKey { case value; case variable = "$var"; case omitWhenOff }
    public init(value: JSONValue? = nil, variable: String? = nil, omitWhenOff: Bool? = nil) { self.value = value; self.variable = variable; self.omitWhenOff = omitWhenOff }
}

public struct OpenAICompletionsCompat: Codable, Equatable, Sendable {
    public var supportsStore: Bool?
    public var supportsDeveloperRole: Bool?
    public var supportsReasoningEffort: Bool?
    public var supportsUsageInStreaming: Bool?
    public var maxTokensField: String?
    public var requiresToolResultName: Bool?
    public var requiresAssistantAfterToolResult: Bool?
    public var requiresThinkingAsText: Bool?
    public var requiresReasoningContentOnAssistantMessages: Bool?
    public var thinkingFormat: String?
    public var chatTemplateKwargs: [String: ChatTemplateKwargValue]?
    public var openRouterRouting: [String: JSONValue]?
    public var vercelGatewayRouting: [String: JSONValue]?
    public var zaiToolStream: Bool?
    public var supportsStrictMode: Bool?
    public var cacheControlFormat: String?
    public var sendSessionAffinityHeaders: Bool?
    public var supportsLongCacheRetention: Bool?
    public var allowEmptySignature: Bool?
    public var sendSessionIdHeader: Bool?
    public var supportsEagerToolInputStreaming: Bool?
    public init() {}
}

public struct OpenAIResponsesCompat: Codable, Equatable, Sendable {
    public var promptCacheKey: Bool?
    public var sendSessionIdHeader: Bool?
    public var supportsLongCacheRetention: Bool?
    public init(promptCacheKey: Bool? = nil, sendSessionIdHeader: Bool? = nil, supportsLongCacheRetention: Bool? = nil) { self.promptCacheKey = promptCacheKey; self.sendSessionIdHeader = sendSessionIdHeader; self.supportsLongCacheRetention = supportsLongCacheRetention }
}
public struct AnthropicMessagesCompat: Codable, Equatable, Sendable {
    public var supportsEagerToolInputStreaming: Bool?
    public var supportsLongCacheRetention: Bool?
    public var allowEmptySignature: Bool?
    public var supportsTemperature: Bool?
    public var forceAdaptiveThinking: Bool?
    public init(supportsEagerToolInputStreaming: Bool? = nil, supportsLongCacheRetention: Bool? = nil, allowEmptySignature: Bool? = nil, supportsTemperature: Bool? = nil, forceAdaptiveThinking: Bool? = nil) {
        self.supportsEagerToolInputStreaming = supportsEagerToolInputStreaming
        self.supportsLongCacheRetention = supportsLongCacheRetention
        self.allowEmptySignature = allowEmptySignature
        self.supportsTemperature = supportsTemperature
        self.forceAdaptiveThinking = forceAdaptiveThinking
    }
}

public enum Compat {
    public static func detect(baseUrl: String) -> OpenAICompletionsCompat { detect(provider: nil, modelId: nil, baseUrl: baseUrl) }

    public static func detect(for model: Model) -> OpenAICompletionsCompat {
        var detected = detect(provider: model.provider, modelId: model.id, baseUrl: model.baseUrl)
        guard let override = model.completionsCompat else { return detected }
        if override.supportsStore != nil { detected.supportsStore = override.supportsStore }
        if override.supportsDeveloperRole != nil { detected.supportsDeveloperRole = override.supportsDeveloperRole }
        if override.supportsReasoningEffort != nil { detected.supportsReasoningEffort = override.supportsReasoningEffort }
        if override.supportsUsageInStreaming != nil { detected.supportsUsageInStreaming = override.supportsUsageInStreaming }
        if override.maxTokensField != nil { detected.maxTokensField = override.maxTokensField }
        if override.requiresToolResultName != nil { detected.requiresToolResultName = override.requiresToolResultName }
        if override.requiresAssistantAfterToolResult != nil { detected.requiresAssistantAfterToolResult = override.requiresAssistantAfterToolResult }
        if override.requiresThinkingAsText != nil { detected.requiresThinkingAsText = override.requiresThinkingAsText }
        if override.requiresReasoningContentOnAssistantMessages != nil { detected.requiresReasoningContentOnAssistantMessages = override.requiresReasoningContentOnAssistantMessages }
        if override.thinkingFormat != nil { detected.thinkingFormat = override.thinkingFormat }
        if override.chatTemplateKwargs != nil { detected.chatTemplateKwargs = override.chatTemplateKwargs }
        if override.openRouterRouting != nil { detected.openRouterRouting = override.openRouterRouting }
        if override.vercelGatewayRouting != nil { detected.vercelGatewayRouting = override.vercelGatewayRouting }
        if override.zaiToolStream != nil { detected.zaiToolStream = override.zaiToolStream }
        if override.supportsStrictMode != nil { detected.supportsStrictMode = override.supportsStrictMode }
        if override.cacheControlFormat != nil { detected.cacheControlFormat = override.cacheControlFormat }
        if override.sendSessionAffinityHeaders != nil { detected.sendSessionAffinityHeaders = override.sendSessionAffinityHeaders }
        if override.supportsLongCacheRetention != nil { detected.supportsLongCacheRetention = override.supportsLongCacheRetention }
        if override.allowEmptySignature != nil { detected.allowEmptySignature = override.allowEmptySignature }
        if override.sendSessionIdHeader != nil { detected.sendSessionIdHeader = override.sendSessionIdHeader }
        if override.supportsEagerToolInputStreaming != nil { detected.supportsEagerToolInputStreaming = override.supportsEagerToolInputStreaming }
        return detected
    }

    private static func detect(provider: Provider?, modelId: String?, baseUrl: String) -> OpenAICompletionsCompat {
        let lower = baseUrl.lowercased()
        var c = OpenAICompletionsCompat()
        c.supportsStore = true
        c.supportsDeveloperRole = true
        c.supportsReasoningEffort = false
        c.supportsUsageInStreaming = true
        c.maxTokensField = "max_tokens"
        c.thinkingFormat = "openai"
        c.openRouterRouting = [:]
        c.vercelGatewayRouting = [:]
        c.chatTemplateKwargs = [:]
        c.zaiToolStream = false
        c.supportsStrictMode = true

        if provider == .openRouter || lower.contains("openrouter.ai") {
            c.supportsStore = false; c.thinkingFormat = "openrouter"; c.openRouterRouting = [:]
        }
        if provider == .groq || lower.contains("api.groq.com") { c.supportsStore = false; c.supportsDeveloperRole = false }
        if provider == .deepSeek || lower.contains("deepseek.com") { c.supportsStore = false; c.thinkingFormat = "deepseek"; c.supportsReasoningEffort = true }
        if provider == .zai || lower.contains("api.z.ai") { c.supportsStore = false; c.thinkingFormat = "zai"; c.zaiToolStream = true }
        if provider == .together || lower.contains("api.together.xyz") { c.supportsStore = false; c.thinkingFormat = "together"; c.supportsStrictMode = false }
        if provider == .moonshotAI || provider == .moonshotAICN || lower.contains("moonshot") { c.supportsStore = false; c.supportsStrictMode = false }
        if lower.contains("ollama") || lower.contains("localhost") || lower.contains("127.0.0.1") { c.supportsStore = false; c.supportsUsageInStreaming = false; c.supportsStrictMode = false }
        if provider == .nvidia { c.supportsStrictMode = false }
        if modelId?.lowercased().contains("qwen") == true { c.thinkingFormat = "qwen-chat-template" }
        return c
    }
}
