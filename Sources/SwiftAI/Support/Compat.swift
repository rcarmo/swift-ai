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
    public var chatTemplateArgs: [String: ChatTemplateKwargValue]?
    public var openRouterRouting: [String: JSONValue]?
    public var vercelGatewayRouting: [String: JSONValue]?
    public var zaiToolStream: Bool?
    public var supportsStrictMode: Bool?
    public var supportsOpenAIGrammarTools: Bool?
    public var supportsThinkingTokenBudget: Bool?
    public var cacheControlFormat: String?
    public var sendSessionAffinityHeaders: Bool?
    public var supportsLongCacheRetention: Bool?
    public var allowEmptySignature: Bool?
    public var sendSessionIdHeader: Bool?
    public var supportsEagerToolInputStreaming: Bool?
    public var deferredToolsMode: String?
    public var vllmPriority: Int?
    public var supportsMidConvoSystemMessages: Bool?
    public var supportsMidConvoToolAdditions: Bool?
    public init() {}

    enum CodingKeys: String, CodingKey { case supportsStore, supportsDeveloperRole, supportsReasoningEffort, supportsUsageInStreaming, maxTokensField, requiresToolResultName, requiresAssistantAfterToolResult, requiresThinkingAsText, requiresReasoningContentOnAssistantMessages, thinkingFormat, chatTemplateKwargs, chatTemplateArgs, openRouterRouting, vercelGatewayRouting, zaiToolStream, supportsStrictMode, supportsOpenAIGrammarTools, supportsOpenaiGrammarTools, supportsThinkingTokenBudget, cacheControlFormat, sendSessionAffinityHeaders, supportsLongCacheRetention, allowEmptySignature, sendSessionIdHeader, supportsEagerToolInputStreaming, deferredToolsMode, vllmPriority, supportsMidConvoSystemMessages, supportsMidConvoToolAdditions }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        supportsStore = try c.decodeIfPresent(Bool.self, forKey: .supportsStore)
        supportsDeveloperRole = try c.decodeIfPresent(Bool.self, forKey: .supportsDeveloperRole)
        supportsReasoningEffort = try c.decodeIfPresent(Bool.self, forKey: .supportsReasoningEffort)
        supportsUsageInStreaming = try c.decodeIfPresent(Bool.self, forKey: .supportsUsageInStreaming)
        maxTokensField = try c.decodeIfPresent(String.self, forKey: .maxTokensField)
        requiresToolResultName = try c.decodeIfPresent(Bool.self, forKey: .requiresToolResultName)
        requiresAssistantAfterToolResult = try c.decodeIfPresent(Bool.self, forKey: .requiresAssistantAfterToolResult)
        requiresThinkingAsText = try c.decodeIfPresent(Bool.self, forKey: .requiresThinkingAsText)
        requiresReasoningContentOnAssistantMessages = try c.decodeIfPresent(Bool.self, forKey: .requiresReasoningContentOnAssistantMessages)
        thinkingFormat = try c.decodeIfPresent(String.self, forKey: .thinkingFormat)
        chatTemplateKwargs = try c.decodeIfPresent([String: ChatTemplateKwargValue].self, forKey: .chatTemplateKwargs)
        chatTemplateArgs = try c.decodeIfPresent([String: ChatTemplateKwargValue].self, forKey: .chatTemplateArgs)
        openRouterRouting = try c.decodeIfPresent([String: JSONValue].self, forKey: .openRouterRouting)
        vercelGatewayRouting = try c.decodeIfPresent([String: JSONValue].self, forKey: .vercelGatewayRouting)
        zaiToolStream = try c.decodeIfPresent(Bool.self, forKey: .zaiToolStream)
        supportsStrictMode = try c.decodeIfPresent(Bool.self, forKey: .supportsStrictMode)
        supportsOpenAIGrammarTools = try c.decodeIfPresent(Bool.self, forKey: .supportsOpenAIGrammarTools) ?? c.decodeIfPresent(Bool.self, forKey: .supportsOpenaiGrammarTools)
        supportsThinkingTokenBudget = try c.decodeIfPresent(Bool.self, forKey: .supportsThinkingTokenBudget)
        cacheControlFormat = try c.decodeIfPresent(String.self, forKey: .cacheControlFormat)
        sendSessionAffinityHeaders = try c.decodeIfPresent(Bool.self, forKey: .sendSessionAffinityHeaders)
        supportsLongCacheRetention = try c.decodeIfPresent(Bool.self, forKey: .supportsLongCacheRetention)
        allowEmptySignature = try c.decodeIfPresent(Bool.self, forKey: .allowEmptySignature)
        sendSessionIdHeader = try c.decodeIfPresent(Bool.self, forKey: .sendSessionIdHeader)
        supportsEagerToolInputStreaming = try c.decodeIfPresent(Bool.self, forKey: .supportsEagerToolInputStreaming)
        deferredToolsMode = try c.decodeIfPresent(String.self, forKey: .deferredToolsMode)
        vllmPriority = try c.decodeIfPresent(Int.self, forKey: .vllmPriority)
        supportsMidConvoSystemMessages = try c.decodeIfPresent(Bool.self, forKey: .supportsMidConvoSystemMessages)
        supportsMidConvoToolAdditions = try c.decodeIfPresent(Bool.self, forKey: .supportsMidConvoToolAdditions)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(supportsStore, forKey: .supportsStore)
        try c.encodeIfPresent(supportsDeveloperRole, forKey: .supportsDeveloperRole)
        try c.encodeIfPresent(supportsReasoningEffort, forKey: .supportsReasoningEffort)
        try c.encodeIfPresent(supportsUsageInStreaming, forKey: .supportsUsageInStreaming)
        try c.encodeIfPresent(maxTokensField, forKey: .maxTokensField)
        try c.encodeIfPresent(requiresToolResultName, forKey: .requiresToolResultName)
        try c.encodeIfPresent(requiresAssistantAfterToolResult, forKey: .requiresAssistantAfterToolResult)
        try c.encodeIfPresent(requiresThinkingAsText, forKey: .requiresThinkingAsText)
        try c.encodeIfPresent(requiresReasoningContentOnAssistantMessages, forKey: .requiresReasoningContentOnAssistantMessages)
        try c.encodeIfPresent(thinkingFormat, forKey: .thinkingFormat)
        try c.encodeIfPresent(chatTemplateKwargs, forKey: .chatTemplateKwargs)
        try c.encodeIfPresent(chatTemplateArgs, forKey: .chatTemplateArgs)
        try c.encodeIfPresent(openRouterRouting, forKey: .openRouterRouting)
        try c.encodeIfPresent(vercelGatewayRouting, forKey: .vercelGatewayRouting)
        try c.encodeIfPresent(zaiToolStream, forKey: .zaiToolStream)
        try c.encodeIfPresent(supportsStrictMode, forKey: .supportsStrictMode)
        try c.encodeIfPresent(supportsOpenAIGrammarTools, forKey: .supportsOpenAIGrammarTools)
        try c.encodeIfPresent(supportsThinkingTokenBudget, forKey: .supportsThinkingTokenBudget)
        try c.encodeIfPresent(cacheControlFormat, forKey: .cacheControlFormat)
        try c.encodeIfPresent(sendSessionAffinityHeaders, forKey: .sendSessionAffinityHeaders)
        try c.encodeIfPresent(supportsLongCacheRetention, forKey: .supportsLongCacheRetention)
        try c.encodeIfPresent(allowEmptySignature, forKey: .allowEmptySignature)
        try c.encodeIfPresent(sendSessionIdHeader, forKey: .sendSessionIdHeader)
        try c.encodeIfPresent(supportsEagerToolInputStreaming, forKey: .supportsEagerToolInputStreaming)
        try c.encodeIfPresent(deferredToolsMode, forKey: .deferredToolsMode)
        try c.encodeIfPresent(vllmPriority, forKey: .vllmPriority)
        try c.encodeIfPresent(supportsMidConvoSystemMessages, forKey: .supportsMidConvoSystemMessages)
        try c.encodeIfPresent(supportsMidConvoToolAdditions, forKey: .supportsMidConvoToolAdditions)
    }
}

public struct OpenAIResponsesCompat: Codable, Equatable, Sendable {
    public var promptCacheKey: Bool?
    public var sendSessionIdHeader: Bool?
    public var supportsLongCacheRetention: Bool?
    public var supportsToolSearch: Bool?
    public var supportsStrictMode: Bool?
    public var supportsOpenAIGrammarTools: Bool?
    public var supportsAdditionalTools: Bool?
    public var supportsExplicitPromptCacheMode: Bool?
    public var sessionAffinityFormat: String?
    public var supportsMaxOutputTokens: Bool?
    public var supportsReasoningEffort: Bool?
    public var supportsMidConvoSystemMessages: Bool?
    public init(promptCacheKey: Bool? = nil, sendSessionIdHeader: Bool? = nil, supportsLongCacheRetention: Bool? = nil, supportsToolSearch: Bool? = nil, supportsStrictMode: Bool? = nil, supportsOpenAIGrammarTools: Bool? = nil, supportsAdditionalTools: Bool? = nil, supportsExplicitPromptCacheMode: Bool? = nil, sessionAffinityFormat: String? = nil, supportsMaxOutputTokens: Bool? = nil, supportsReasoningEffort: Bool? = nil, supportsMidConvoSystemMessages: Bool? = nil) { self.promptCacheKey = promptCacheKey; self.sendSessionIdHeader = sendSessionIdHeader; self.supportsLongCacheRetention = supportsLongCacheRetention; self.supportsToolSearch = supportsToolSearch; self.supportsStrictMode = supportsStrictMode; self.supportsOpenAIGrammarTools = supportsOpenAIGrammarTools; self.supportsAdditionalTools = supportsAdditionalTools; self.supportsExplicitPromptCacheMode = supportsExplicitPromptCacheMode; self.sessionAffinityFormat = sessionAffinityFormat; self.supportsMaxOutputTokens = supportsMaxOutputTokens; self.supportsReasoningEffort = supportsReasoningEffort; self.supportsMidConvoSystemMessages = supportsMidConvoSystemMessages }

    enum CodingKeys: String, CodingKey { case promptCacheKey, sendSessionIdHeader, supportsLongCacheRetention, supportsToolSearch, supportsStrictMode, supportsOpenAIGrammarTools, supportsOpenaiGrammarTools, supportsAdditionalTools, supportsExplicitPromptCacheMode, sessionAffinityFormat, supportsMaxOutputTokens, supportsReasoningEffort, supportsMidConvoSystemMessages }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        promptCacheKey = try c.decodeIfPresent(Bool.self, forKey: .promptCacheKey)
        sendSessionIdHeader = try c.decodeIfPresent(Bool.self, forKey: .sendSessionIdHeader)
        supportsLongCacheRetention = try c.decodeIfPresent(Bool.self, forKey: .supportsLongCacheRetention)
        supportsToolSearch = try c.decodeIfPresent(Bool.self, forKey: .supportsToolSearch)
        supportsStrictMode = try c.decodeIfPresent(Bool.self, forKey: .supportsStrictMode)
        supportsOpenAIGrammarTools = try c.decodeIfPresent(Bool.self, forKey: .supportsOpenAIGrammarTools) ?? c.decodeIfPresent(Bool.self, forKey: .supportsOpenaiGrammarTools)
        supportsAdditionalTools = try c.decodeIfPresent(Bool.self, forKey: .supportsAdditionalTools)
        supportsExplicitPromptCacheMode = try c.decodeIfPresent(Bool.self, forKey: .supportsExplicitPromptCacheMode)
        sessionAffinityFormat = try c.decodeIfPresent(String.self, forKey: .sessionAffinityFormat)
        supportsMaxOutputTokens = try c.decodeIfPresent(Bool.self, forKey: .supportsMaxOutputTokens)
        supportsReasoningEffort = try c.decodeIfPresent(Bool.self, forKey: .supportsReasoningEffort)
        supportsMidConvoSystemMessages = try c.decodeIfPresent(Bool.self, forKey: .supportsMidConvoSystemMessages)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(promptCacheKey, forKey: .promptCacheKey)
        try c.encodeIfPresent(sendSessionIdHeader, forKey: .sendSessionIdHeader)
        try c.encodeIfPresent(supportsLongCacheRetention, forKey: .supportsLongCacheRetention)
        try c.encodeIfPresent(supportsToolSearch, forKey: .supportsToolSearch)
        try c.encodeIfPresent(supportsStrictMode, forKey: .supportsStrictMode)
        try c.encodeIfPresent(supportsOpenAIGrammarTools, forKey: .supportsOpenAIGrammarTools)
        try c.encodeIfPresent(supportsAdditionalTools, forKey: .supportsAdditionalTools)
        try c.encodeIfPresent(supportsExplicitPromptCacheMode, forKey: .supportsExplicitPromptCacheMode)
        try c.encodeIfPresent(sessionAffinityFormat, forKey: .sessionAffinityFormat)
        try c.encodeIfPresent(supportsMaxOutputTokens, forKey: .supportsMaxOutputTokens)
        try c.encodeIfPresent(supportsReasoningEffort, forKey: .supportsReasoningEffort)
        try c.encodeIfPresent(supportsMidConvoSystemMessages, forKey: .supportsMidConvoSystemMessages)
    }
}
public struct AnthropicFallbackModel: Codable, Equatable, Sendable { public var provider: String?; public var model: String; public var cost: ModelCost?; public init(provider: String? = nil, model: String, cost: ModelCost? = nil) { self.provider = provider; self.model = model; self.cost = cost } }

public struct AnthropicMessagesCompat: Codable, Equatable, Sendable {
    public var supportsEagerToolInputStreaming: Bool?
    public var supportsLongCacheRetention: Bool?
    public var sendSessionAffinityHeaders: Bool?
    public var supportsCacheControlOnTools: Bool?
    public var allowEmptySignature: Bool?
    public var supportsTemperature: Bool?
    public var forceAdaptiveThinking: Bool?
    public var supportsToolReferences: Bool?
    public var supportsStrictTools: Bool?
    public var allowedFallbackModels: [AnthropicFallbackModel]?
    public var supportsMidConvoEffort: Bool?
    public var supportsMidConvoSystemMessages: Bool?
    public var supportsMidConvoToolChanges: Bool?
    public init(supportsEagerToolInputStreaming: Bool? = nil, supportsLongCacheRetention: Bool? = nil, sendSessionAffinityHeaders: Bool? = nil, supportsCacheControlOnTools: Bool? = nil, allowEmptySignature: Bool? = nil, supportsTemperature: Bool? = nil, forceAdaptiveThinking: Bool? = nil, supportsToolReferences: Bool? = nil, supportsStrictTools: Bool? = nil, allowedFallbackModels: [AnthropicFallbackModel]? = nil, supportsMidConvoEffort: Bool? = nil, supportsMidConvoSystemMessages: Bool? = nil, supportsMidConvoToolChanges: Bool? = nil) {
        self.supportsEagerToolInputStreaming = supportsEagerToolInputStreaming
        self.supportsLongCacheRetention = supportsLongCacheRetention
        self.sendSessionAffinityHeaders = sendSessionAffinityHeaders
        self.supportsCacheControlOnTools = supportsCacheControlOnTools
        self.allowEmptySignature = allowEmptySignature
        self.supportsTemperature = supportsTemperature
        self.forceAdaptiveThinking = forceAdaptiveThinking
        self.supportsToolReferences = supportsToolReferences
        self.supportsStrictTools = supportsStrictTools
        self.allowedFallbackModels = allowedFallbackModels
        self.supportsMidConvoEffort = supportsMidConvoEffort
        self.supportsMidConvoSystemMessages = supportsMidConvoSystemMessages
        self.supportsMidConvoToolChanges = supportsMidConvoToolChanges
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
        if override.chatTemplateArgs != nil { detected.chatTemplateArgs = override.chatTemplateArgs }
        if override.openRouterRouting != nil { detected.openRouterRouting = override.openRouterRouting }
        if override.vercelGatewayRouting != nil { detected.vercelGatewayRouting = override.vercelGatewayRouting }
        if override.zaiToolStream != nil { detected.zaiToolStream = override.zaiToolStream }
        if override.supportsStrictMode != nil { detected.supportsStrictMode = override.supportsStrictMode }
        if override.supportsOpenAIGrammarTools != nil { detected.supportsOpenAIGrammarTools = override.supportsOpenAIGrammarTools }
        if override.supportsThinkingTokenBudget != nil { detected.supportsThinkingTokenBudget = override.supportsThinkingTokenBudget }
        if override.cacheControlFormat != nil { detected.cacheControlFormat = override.cacheControlFormat }
        if override.sendSessionAffinityHeaders != nil { detected.sendSessionAffinityHeaders = override.sendSessionAffinityHeaders }
        if override.supportsLongCacheRetention != nil { detected.supportsLongCacheRetention = override.supportsLongCacheRetention }
        if override.allowEmptySignature != nil { detected.allowEmptySignature = override.allowEmptySignature }
        if override.sendSessionIdHeader != nil { detected.sendSessionIdHeader = override.sendSessionIdHeader }
        if override.supportsEagerToolInputStreaming != nil { detected.supportsEagerToolInputStreaming = override.supportsEagerToolInputStreaming }
        if override.deferredToolsMode != nil { detected.deferredToolsMode = override.deferredToolsMode }
        if override.vllmPriority != nil { detected.vllmPriority = override.vllmPriority }
        return detected
    }

    private static func detect(provider: Provider?, modelId: String?, baseUrl: String) -> OpenAICompletionsCompat {
        let lower = baseUrl.lowercased()
        var c = OpenAICompletionsCompat()
        c.supportsStore = true
        c.supportsDeveloperRole = true
        c.supportsReasoningEffort = false
        c.supportsUsageInStreaming = true
        c.maxTokensField = (provider == .openAI || lower.contains("api.openai.com")) ? "max_completion_tokens" : "max_tokens"
        c.thinkingFormat = "openai"
        c.openRouterRouting = [:]
        c.vercelGatewayRouting = [:]
        c.chatTemplateKwargs = [:]
        c.zaiToolStream = false
        c.supportsStrictMode = true
        c.supportsOpenAIGrammarTools = false
        c.supportsThinkingTokenBudget = false

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
