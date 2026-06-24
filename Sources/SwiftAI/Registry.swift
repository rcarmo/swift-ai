import Foundation

public typealias ProviderStream = @Sendable (Model, AIContext, StreamOptions?) -> AsyncStream<AIEvent>

public struct APIProvider: Sendable {
    public var api: API
    public var stream: ProviderStream
    public var streamSimple: ProviderStream?
    public init(api: API, stream: @escaping ProviderStream, streamSimple: ProviderStream? = nil) { self.api = api; self.stream = stream; self.streamSimple = streamSimple }
}

public actor AIRegistry {
    public static let shared = AIRegistry()
    private var providers: [API: APIProvider] = [:]
    private var models: [String: Model] = [:]

    public func register(_ provider: APIProvider) { providers[provider.api] = provider }
    public func unregister(api: API) { providers.removeValue(forKey: api) }
    public func clearProviders() { providers.removeAll() }
    public func apiProvider(for api: API) -> APIProvider? { providers[api] }

    public func register(_ model: Model) { models["\(model.provider.rawValue)/\(model.id)"] = model }
    public func clearModels() { models.removeAll() }
    public func model(provider: Provider, id: String) -> Model? { models["\(provider.rawValue)/\(id)"] }
    public func listModels(provider: Provider? = nil) -> [Model] { models.values.filter { provider == nil || $0.provider == provider! }.sorted { $0.id < $1.id } }
    public func listProviders() -> [Provider] { Array(Set(models.values.map(\.provider))).sorted { $0.rawValue < $1.rawValue } }
}

public enum SwiftAI {
    public static func bootstrap() async {
        await BuiltinModels.registerAll()
        await BuiltinImageModels.registerAll()
        await AIRegistry.shared.register(APIProvider(api: .openAICompletions, stream: { model, context, options in OpenAICompletionsProvider.stream(model: model, context: context, options: options) }))
        await AIRegistry.shared.register(APIProvider(api: .openAIResponses, stream: { model, context, options in OpenAIResponsesProvider.stream(model: model, context: context, options: options) }))
        await AIRegistry.shared.register(APIProvider(api: .azureOpenAIResponses, stream: { model, context, options in OpenAIResponsesProvider.stream(model: model, context: context, options: options) }))
        await AIRegistry.shared.register(APIProvider(api: .openAICodexResponses, stream: { model, context, options in OpenAIResponsesProvider.stream(model: model, context: context, options: options) }))
        await AIRegistry.shared.register(APIProvider(api: .anthropicMessages, stream: { model, context, options in AnthropicMessagesProvider.stream(model: model, context: context, options: options) }))
        await AIRegistry.shared.register(APIProvider(api: .mistralConversations, stream: { model, context, options in MistralConversationsProvider.stream(model: model, context: context, options: options) }))
        await AIRegistry.shared.register(APIProvider(api: .googleGenerativeAI, stream: { model, context, options in GoogleGenerativeAIProvider.stream(model: model, context: context, options: options) }))
        await AIRegistry.shared.register(APIProvider(api: .googleVertex, stream: { model, context, options in GoogleGenerativeAIProvider.stream(model: model, context: context, options: options) }))
        await AIRegistry.shared.register(APIProvider(api: .googleGeminiCLI, stream: { model, context, options in GoogleGeminiCLIProvider.stream(model: model, context: context, options: options) }))
        await AIRegistry.shared.register(APIProvider(api: .bedrockConverseStream, stream: { model, context, options in BedrockProvider.stream(model: model, context: context, options: options) }))
        await ImagesRegistry.shared.register(ImagesAPIProvider(api: .openRouterImages, generateImages: { model, context, options in await OpenRouterImagesProvider.generateImages(model: model, context: context, options: options) }))
        await OAuthRegistry.shared.register(GitHubCopilotOAuthProvider())
        await OAuthRegistry.shared.register(OpenAICodexOAuthProvider())
        await OAuthRegistry.shared.register(AnthropicOAuthProvider())
        await OAuthRegistry.shared.register(GoogleGeminiCLIOAuthProvider())
        await OAuthRegistry.shared.register(GoogleAntigravityOAuthProvider())
    }

    public static func stream(model: Model?, context: AIContext = AIContext(), options: StreamOptions? = nil) async -> AsyncStream<AIEvent> {
        guard let model else { return AsyncStream { continuation in continuation.yield(.error(reason: .error, message: nil, error: AIError.nilModel)); continuation.finish() } }
        if options?.reasoning == .xhigh && !AIUtilities.supportsXHigh(model: model) {
            return AsyncStream { continuation in
                var msg = Message(role: .assistant, content: [])
                msg.api = model.api; msg.provider = model.provider; msg.model = model.id; msg.stopReason = .error; msg.errorMessage = "xhigh reasoning is not supported by \(model.id)"
                continuation.yield(.error(reason: .error, message: msg, error: AIError.provider(msg.errorMessage ?? "xhigh unsupported")))
                continuation.finish()
            }
        }
        guard let provider = await AIRegistry.shared.apiProvider(for: model.api) else {
            return AsyncStream { continuation in continuation.yield(.error(reason: .error, message: nil, error: AIError.noProvider(model.api))); continuation.finish() }
        }
        if options?.reasoning != nil, let simple = provider.streamSimple { return simple(model, context, options) }
        return provider.stream(model, context, options)
    }

    public static func complete(model: Model?, context: AIContext = AIContext(), options: StreamOptions? = nil) async throws -> Message {
        let events = await stream(model: model, context: context, options: options)
        var result: Message?
        var resultError: Error?
        for await event in events {
            switch event {
            case .done(_, let message): result = message
            case .error(_, let message, let error): result = message; resultError = error ?? AIError.provider(message?.errorMessage ?? "LLM error")
            default: break
            }
        }
        if let resultError { throw resultError }
        if let result { return result }
        throw AIError.invalidResponse("stream ended without a done event")
    }
}
