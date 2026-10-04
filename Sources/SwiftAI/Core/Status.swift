import Foundation

public enum SwiftAIStatus {
    public static let upstreamPackage = "@earendil-works/pi-ai"
    public static let upstreamVersion = "1.0.1"
    public static let referenceImplementation = "pi-ai v1.0.1"

    public static let textModelCount = 1536
    public static let textProviderCount = 41
    public static let textAPICount = 10
    public static let imageModelCount = 59
    public static let imageProviderCount = 1
    public static let imageAPICount = 1
    public static let classifierModelCount = 20
    public static let classifierProviderCount = 5
    public static let classifierAPICount = 2

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
        .piMessages,
        .faux
    ]

    public static let bundledImageRuntimeAPIs: [ImagesAPI] = [.openRouterImages]
    public static let bundledClassifierRuntimeAPIs: [ClassifierAPI] = [.typeSafeSystemOne, .cloudflareWorkersAISystemOne]

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
