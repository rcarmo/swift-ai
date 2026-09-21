import Foundation

public enum SwiftAIStatus {
    public static let upstreamPackage = "@earendil-works/pi-ai"
    public static let upstreamVersion = "0.87.0"
    public static let referenceImplementation = "pi-ai v0.87.0"

    public static let textModelCount = 1445
    public static let textProviderCount = 41
    public static let textAPICount = 10
    public static let imageModelCount = 54
    public static let imageProviderCount = 1
    public static let imageAPICount = 1

    public static let bundledRuntimeAPIs: [API] = [
        .openAICompletions,
        .openAIResponses,
        .azureOpenAIResponses,
        .openAICodexResponses,
        .anthropicMessages,
        .googleGenerativeAI,
        .googleVertex,
        .googleGeminiCLI,
        .mistralConversations,
        .faux
    ]

    public static let bundledImageRuntimeAPIs: [ImagesAPI] = [.openRouterImages]

    public static let oauthProviderIDs = [
        "github-copilot",
        "openai-codex",
        "anthropic",
        "google-gemini-cli",
        "google-antigravity"
    ]

    public static let pluggableTransports = [
        "bedrock-converse-stream": "BedrockTransport",
        "openai-codex-responses": "CodexTransport"
    ]
}
