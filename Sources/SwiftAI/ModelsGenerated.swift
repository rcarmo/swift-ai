import Foundation

public enum BuiltinModels {
    private static func compat(thinkingFormat: String) -> OpenAICompletionsCompat { var c = OpenAICompletionsCompat(); c.thinkingFormat = thinkingFormat; return c }

    public static let all: [Model] = [
        Model(id: "gpt-4.1", name: "GPT-4.1", api: .openAICompletions, provider: .openAI, baseUrl: "https://api.openai.com/v1", reasoning: false, input: ["text", "image"], cost: ModelCost(input: 2, output: 8, cacheRead: 0.5, cacheWrite: 0), contextWindow: 1_047_576, maxTokens: 32_768),
        Model(id: "gpt-4.1-mini", name: "GPT-4.1 mini", api: .openAICompletions, provider: .openAI, baseUrl: "https://api.openai.com/v1", reasoning: false, input: ["text", "image"], cost: ModelCost(input: 0.4, output: 1.6, cacheRead: 0.1, cacheWrite: 0), contextWindow: 1_047_576, maxTokens: 32_768),
        Model(id: "o4-mini", name: "o4-mini", api: .openAICompletions, provider: .openAI, baseUrl: "https://api.openai.com/v1", reasoning: true, thinkingLevelMap: [.minimal: "minimal", .low: "low", .medium: "medium", .high: "high"], input: ["text", "image"], cost: ModelCost(input: 1.1, output: 4.4, cacheRead: 0.275, cacheWrite: 0), contextWindow: 200_000, maxTokens: 100_000),
        Model(id: "claude-sonnet-4-20250514", name: "Claude Sonnet 4", api: .anthropicMessages, provider: .anthropic, baseUrl: "https://api.anthropic.com", reasoning: true, input: ["text", "image"], cost: ModelCost(input: 3, output: 15, cacheRead: 0.3, cacheWrite: 3.75), contextWindow: 200_000, maxTokens: 64_000),
        Model(id: "gemini-2.5-pro", name: "Gemini 2.5 Pro", api: .googleGenerativeAI, provider: .google, baseUrl: "https://generativelanguage.googleapis.com", reasoning: true, input: ["text", "image"], cost: ModelCost(input: 1.25, output: 10, cacheRead: 0.31, cacheWrite: 0), contextWindow: 1_048_576, maxTokens: 65_536),
        Model(id: "deepseek-chat", name: "DeepSeek Chat", api: .openAICompletions, provider: .deepSeek, baseUrl: "https://api.deepseek.com", reasoning: false, input: ["text"], cost: ModelCost(input: 0.27, output: 1.1, cacheRead: 0.07, cacheWrite: 0), contextWindow: 64_000, maxTokens: 8_000, completionsCompat: compat(thinkingFormat: "deepseek")),
        Model(id: "openrouter/auto", name: "OpenRouter Auto", api: .openAICompletions, provider: .openRouter, baseUrl: "https://openrouter.ai/api/v1", reasoning: false, input: ["text"], cost: ModelCost(), contextWindow: 0, maxTokens: 0)
    ]

    public static func registerAll() async { for model in all { await AIRegistry.shared.register(model) } }
}
