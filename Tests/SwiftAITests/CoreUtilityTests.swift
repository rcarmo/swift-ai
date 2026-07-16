import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import SwiftAI

final class CoreUtilityTests: XCTestCase {
    func testLaxMessageContentDecodingAndTransform() throws {
        let data = #"""
        [
          {"role":"user","content":null,"timestamp":1},
          {"role":"assistant","content":null,"api":"openai-completions","provider":"openai","model":"test-model","stopReason":"stop","timestamp":2},
          {"role":"toolResult","toolCallId":"call_1","toolName":"web_search","timestamp":3}
        ]
        """#.data(using: .utf8)!
        let messages = try JSONDecoder().decode([Message].self, from: data)
        let model = Model(id: "test-model", name: "Test Model", api: .openAICompletions, provider: .openAI, input: ["text"])
        let transformed = AIUtilities.transformMessages(messages, for: model)
        XCTAssertEqual(transformed.count, 3)
        XCTAssertTrue(transformed.allSatisfy { $0.content.isEmpty })
    }

    func testV0806ContextEstimateIgnoresStaleAssistantUsage() {
        func assistant(timestamp: Int64, totalTokens: Int) -> Message {
            var msg = Message(role: .assistant, content: [.text("kept")], timestamp: timestamp)
            var usage = Usage(); usage.input = totalTokens; usage.totalTokens = totalTokens
            msg.api = .openAIResponses; msg.provider = .openAI; msg.model = "test-model"; msg.usage = usage; msg.stopReason = .stop
            return msg
        }
        let staleContext = AIContext(systemPrompt: "system", messages: [
            Message(role: .user, content: [.text("summary")], timestamp: 200),
            assistant(timestamp: 100, totalTokens: 9_500),
            Message(role: .user, content: [.text(String(repeating: "x", count: 4_000))], timestamp: 300),
        ])
        let staleEstimate = AIUtilities.estimateContextTokens(staleContext)
        XCTAssertEqual(staleEstimate.tokens, 1005)
        XCTAssertEqual(staleEstimate.usageTokens, 0)
        XCTAssertEqual(staleEstimate.trailingTokens, 1005)
        XCTAssertNil(staleEstimate.lastUsageIndex)
        let model = Model(id: "test-model", name: "Test Model", api: .openAIResponses, provider: .openAI, contextWindow: 10_000, maxTokens: 8_000)
        XCTAssertEqual(AIUtilities.effectiveMaxTokens(model: model, context: staleContext, options: nil, defaultToModel: true), 4899)

        let freshContext = AIContext(messages: [
            Message(role: .user, content: [.text("summary")], timestamp: 200),
            assistant(timestamp: 100, totalTokens: 9_500),
            Message(role: .user, content: [.text("new prompt")], timestamp: 300),
            assistant(timestamp: 400, totalTokens: 2_000),
            Message(role: .user, content: [.text("tail")], timestamp: 500),
        ])
        let freshEstimate = AIUtilities.estimateContextTokens(freshContext)
        XCTAssertEqual(freshEstimate.tokens, 2001)
        XCTAssertEqual(freshEstimate.usageTokens, 2000)
        XCTAssertEqual(freshEstimate.trailingTokens, 1)
        XCTAssertEqual(freshEstimate.lastUsageIndex, 3)
    }

    func testV0806MaxThinkingLevelOptInAndClamp() {
        let ordinary = Model(id: "ordinary-reasoning", name: "Ordinary", api: .openAICompletions, provider: .faux, reasoning: true)
        XCTAssertEqual(AIUtilities.supportedThinkingLevels(model: ordinary), [.off, .minimal, .low, .medium, .high])
        XCTAssertEqual(AIUtilities.clampThinkingLevel(model: ordinary, level: .max), .high)
        let highAndMax = Model(id: "high-and-max", name: "High and Max", api: .openAICompletions, provider: .faux, reasoning: true, thinkingLevelMap: [.xhigh: nil, .max: "max"])
        XCTAssertEqual(AIUtilities.supportedThinkingLevels(model: highAndMax), [.off, .minimal, .low, .medium, .high, .max])
        XCTAssertEqual(AIUtilities.clampThinkingLevel(model: highAndMax, level: .xhigh), .max)
        XCTAssertEqual(AIUtilities.mapThinkingLevel(model: highAndMax, level: .max), "max")
    }

    func testV0803EstimateClampErrorAndRetryUtilities() {
        XCTAssertEqual(AIUtilities.estimateTextTokens("12345678"), 2)
        XCTAssertEqual(AIUtilities.estimateTextTokens("123456789"), 3)
        XCTAssertEqual(AIUtilities.estimateTextTokens(""), 0)
        XCTAssertEqual(AIUtilities.estimateTextTokens("hello"), 2)
        XCTAssertEqual(AIUtilities.estimateTextAndImageContentTokens([.text("abcd"), .image(data: "x", mimeType: "image/png")]), 1201)
        var assistant = Message(role: .assistant, content: [.text("answer")])
        var usage = Usage(); usage.input = 100; usage.output = 20; usage.cacheRead = 3; usage.cacheWrite = 2; usage.totalTokens = 125
        assistant.usage = usage; assistant.stopReason = .stop
        let context = AIContext(systemPrompt: "sys", messages: [.user("hello"), assistant, .user("tail")], tools: [Tool(name: "lookup", description: "Lookup", parameters: .object(["type": .string("object")]))])
        let estimate = AIUtilities.estimateContextTokens(context)
        XCTAssertEqual(estimate.usageTokens, 125)
        XCTAssertEqual(estimate.trailingTokens, 1)
        XCTAssertEqual(estimate.tokens, 126)
        let boundary = AIContext(messages: [.user("hello")])
        let model = Model(id: "m", name: "M", api: .openAICompletions, provider: .openAI, contextWindow: 5000, maxTokens: 2000)
        XCTAssertEqual(AIUtilities.clampMaxTokensToContext(model: model, context: boundary, maxTokens: 2000), 902)
        XCTAssertEqual(AIUtilities.clampMaxTokensToContext(model: Model(id: "m", name: "M", api: .openAICompletions, provider: .openAI, contextWindow: 0), context: boundary, maxTokens: -4), 1)

        let long = String(repeating: "x", count: 4005)
        XCTAssertEqual(AIUtilities.truncateErrorText(long).count, 4023)
        let normalized = AIUtilities.normalizeProviderError(["status": 403, "error": ["message": "denied"], "message": "403 status code (no body)"] as [String: Any])
        XCTAssertEqual(normalized.status, 403)
        XCTAssertEqual(normalized.body, #"{"message":"denied"}"#)
        XCTAssertEqual(AIUtilities.formatProviderError(normalized, prefix: "OpenAI API error"), #"OpenAI API error (403): {"message":"denied"}"#)
        XCTAssertEqual(AIUtilities.formatProviderError(status: 403, body: #"{"error":"forbidden"}"#), #"403: {"error":"forbidden"}"#)
        XCTAssertEqual(AIUtilities.formatProviderError(status: 429, body: "rate limited", prefix: "OpenAI API error"), "OpenAI API error (429): rate limited")
        XCTAssertEqual(AIUtilities.formatProviderError(status: 500, body: "boom", prefix: "Azure OpenAI API error"), "Azure OpenAI API error (500): boom")
        XCTAssertEqual(AIUtilities.formatProviderError(status: 503, body: "   spaced   "), "503: spaced")
        XCTAssertEqual(AIUtilities.formatProviderError(status: 503, body: "   "), "503")
        XCTAssertEqual(AIUtilities.formatProviderError(status: 503, body: "", prefix: "OpenAI API error"), "OpenAI API error (503)")
        XCTAssertEqual(AIUtilities.formatProviderError(status: 400, body: String(repeating: "x", count: 4025)), "400: \(String(repeating: "x", count: 4000))... [truncated 25 chars]")
        XCTAssertEqual(AIUtilities.safeJsonStringify(["b": 2, "a": 1]), #"{"a":1,"b":2}"#)

        let anthropicBody = AnthropicMessagesProvider.buildRequestBody(model: Model(id: "claude", name: "Claude", api: .anthropicMessages, provider: .anthropic, contextWindow: 5000, maxTokens: 2000), context: boundary, options: nil)
        XCTAssertEqual(anthropicBody["max_tokens"], .number(902))
        let bedrockBody = BedrockProvider.buildConverseRequest(model: Model(id: "claude", name: "Claude", api: .bedrockConverseStream, provider: .amazonBedrock, contextWindow: 5000, maxTokens: 2000), context: boundary, options: nil)
        XCTAssertEqual(bedrockBody["inferenceConfig"], .object(["maxTokens": .number(902)]))
        var explicitOptions = StreamOptions(); explicitOptions.maxTokens = 2000
        let completionsBody = OpenAICompletionsProvider.buildRequestBody(model: model, context: boundary, options: explicitOptions)
        XCTAssertEqual(completionsBody["max_completion_tokens"], .number(902))
        XCTAssertEqual(OpenAIResponsesProvider.buildRequestBody(model: Model(id: "gpt", name: "GPT", api: .openAIResponses, provider: .openAI, contextWindow: 5000, maxTokens: 2000), context: boundary, options: explicitOptions)["max_output_tokens"], .number(902))
        guard case .object(let googleGen)? = GoogleGenerativeAIProvider.buildRequestBody(model: Model(id: "gemini", name: "Gemini", api: .googleGenerativeAI, provider: .google, contextWindow: 5000, maxTokens: 2000), context: boundary, options: explicitOptions)["generationConfig"] else { return XCTFail("missing google generation config") }
        XCTAssertEqual(googleGen["maxOutputTokens"], .number(902))
        XCTAssertEqual(MistralConversationsProvider.buildRequestBody(model: Model(id: "mistral", name: "Mistral", api: .mistralConversations, provider: .mistral, contextWindow: 5000, maxTokens: 2000), context: boundary, options: explicitOptions)["max_tokens"], .number(902))
        let defaultClampModel = Model(id: "gpt", name: "GPT", api: .openAICompletions, provider: .openAI, contextWindow: 10000, maxTokens: 8000)
        let longContext = AIContext(messages: [.user(String(repeating: "x", count: 8000))])
        XCTAssertEqual(OpenAICompletionsProvider.buildRequestBody(model: defaultClampModel, context: longContext, options: nil)["max_completion_tokens"], .number(3904))
        XCTAssertEqual(try OpenAIResponsesProvider.normalizeAzureBaseURL("https://foundry.ai.azure.com"), "https://foundry.ai.azure.com/openai/v1")
        XCTAssertEqual(try OpenAIResponsesProvider.normalizeAzureBaseURL("https://foundry.services.ai.azure.com/openai/v1/responses"), "https://foundry.services.ai.azure.com/openai/v1")
        let sonnet5 = Model(id: "anthropic.claude-sonnet-5", name: "Claude Sonnet 5", api: .bedrockConverseStream, provider: .amazonBedrock, reasoning: true)
        var reasoningOptions = StreamOptions(); reasoningOptions.reasoning = .high
        guard let sonnetFields = BedrockProvider.additionalModelRequestFields(model: sonnet5, options: reasoningOptions), case .object(let sonnetThinking)? = sonnetFields["thinking"] else { return XCTFail("missing sonnet 5 thinking") }
        XCTAssertEqual(sonnetThinking["type"], .string("adaptive"))
        XCTAssertEqual(sonnetThinking["display"], .string("summarized"))
        XCTAssertEqual(sonnetFields["output_config"], .object(["effort": .string("high")]))

        let sse = """
        event: message_start
        data: {"message":{"id":"m","usage":{"input_tokens":10,"cache_read_input_tokens":3,"cache_creation_input_tokens":2}}}

        event: message_delta
        data: {"delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":5,"output_tokens_details":{"thinking_tokens":4}}}

        event: message_stop
        data: {}

        """
        guard case .done(_, let anthropicMessage)? = AnthropicMessagesProvider.processSSEText(sse, model: Model(id: "claude", name: "Claude", api: .anthropicMessages, provider: .anthropic)).last else { return XCTFail("missing anthropic done") }
        XCTAssertEqual(anthropicMessage.usage?.reasoning, 4)
        XCTAssertEqual(anthropicMessage.usage?.totalTokens, 20)

        let openAIUsageSSE = """
        data: {"choices":[],"usage":{"prompt_tokens":10,"completion_tokens":20,"completion_tokens_details":{"reasoning_tokens":30}}}

        data: [DONE]

        """
        guard case .done(_, let openAIMessage)? = OpenAICompletionsProvider.processSSEText(openAIUsageSSE, model: model).last else { return XCTFail("missing openai done") }
        XCTAssertEqual(openAIMessage.usage?.reasoning, 30)
        let responsesUsageSSE = """
        event: response.completed
        data: {"response":{"id":"r","status":"completed","usage":{"input_tokens":10,"output_tokens":20,"input_tokens_details":{"cached_tokens":3,"cache_write_tokens":4},"output_tokens_details":{"reasoning_tokens":12}}}}

        """
        guard case .done(_, let responsesMessage)? = OpenAIResponsesProvider.processSSEText(responsesUsageSSE, model: Model(id: "gpt", name: "GPT", api: .openAIResponses, provider: .openAI)).last else { return XCTFail("missing responses done") }
        XCTAssertEqual(responsesMessage.usage?.input, 7)
        XCTAssertEqual(responsesMessage.usage?.cacheRead, 3)
        XCTAssertEqual(responsesMessage.usage?.cacheWrite, 4)
        XCTAssertEqual(responsesMessage.usage?.reasoning, 12)
        let googleUsageSSE = """
        data: {"usageMetadata":{"promptTokenCount":10,"candidatesTokenCount":20,"thoughtsTokenCount":7,"totalTokenCount":37}}

        """
        guard case .done(_, let googleMessage)? = GoogleGenerativeAIProvider.processSSEText(googleUsageSSE, model: Model(id: "gemini", name: "Gemini", api: .googleGenerativeAI, provider: .google)).last else { return XCTFail("missing google done") }
        XCTAssertEqual(googleMessage.usage?.reasoning, 7)

        var retryable = Message(role: .assistant, content: [])
        retryable.stopReason = .error; retryable.errorMessage = "Provider returned error: 503 service unavailable, please retry your request"
        XCTAssertTrue(AssistantErrorRetryClassifier.isRetryableAssistantError(retryable))
        for text in ["524", "socket connection was closed", "ResourceExhausted"] {
            retryable.errorMessage = text
            XCTAssertTrue(AssistantErrorRetryClassifier.isRetryableAssistantError(retryable), text)
        }
        retryable.errorMessage = "insufficient_quota billing limit reached after 429"
        XCTAssertFalse(AssistantErrorRetryClassifier.isRetryableAssistantError(retryable))
        retryable.stopReason = .stop
        XCTAssertFalse(AssistantErrorRetryClassifier.isRetryableAssistantError(retryable))
    }

    func testUsageTotalTokensComponentInvariant() {
        var usage = Usage()
        usage.input = 10
        usage.output = 5
        usage.cacheRead = 3
        usage.cacheWrite = 2
        usage.totalTokens = usage.input + usage.output + usage.cacheRead + usage.cacheWrite
        XCTAssertEqual(usage.totalTokens, 20)
        let model = Model(id: "m", name: "M", api: .openAICompletions, provider: .openAI, cost: ModelCost(input: 1, output: 2, cacheRead: 0.5, cacheWrite: 1.5))
        AIUtilities.applyCost(model: model, usage: &usage)
        XCTAssertEqual(usage.cost.total, usage.cost.input + usage.cost.output + usage.cost.cacheRead + usage.cost.cacheWrite, accuracy: 0.0000001)
    }

    func testHTTPProxyResolution() throws {
        XCTAssertNil(try HTTPProxyResolver.resolveProxyURL(forTarget: "https://bedrock-runtime.us-east-1.amazonaws.com", env: ["HTTPS_PROXY": "http://proxy.example:8080", "NO_PROXY": "bedrock-runtime.us-east-1.amazonaws.com"]))
        XCTAssertEqual(try HTTPProxyResolver.resolveProxyURL(forTarget: "https://bedrock-runtime.us-east-1.amazonaws.com", env: ["HTTPS_PROXY": "http://proxy.example:8080"])?.absoluteString, "http://proxy.example:8080")
        XCTAssertEqual(try HTTPProxyResolver.resolveProxyURL(forTarget: "https://bedrock-runtime.us-east-1.amazonaws.com", env: ["HTTPS_PROXY": "http://scoped-proxy.example:8080", "https_proxy": "http://process-proxy.example:8080"])?.absoluteString, "http://scoped-proxy.example:8080")
        XCTAssertThrowsError(try HTTPProxyResolver.resolveProxyURL(forTarget: "https://bedrock-runtime.us-east-1.amazonaws.com", env: ["HTTPS_PROXY": "socks5://proxy.example:1080"])) { error in
            XCTAssertTrue(String(describing: error).contains(HTTPProxyResolver.unsupportedProxyProtocolMessage))
        }
    }

    func testCompleteErrorEventWithoutMessage() async throws {
        await AIRegistry.shared.clearProviders()
        await AIRegistry.shared.register(APIProvider(api: .faux, stream: { _, _, _ in
            AsyncStream { continuation in
                continuation.yield(.error(reason: .error, message: nil, error: AIError.provider("boom")))
                continuation.finish()
            }
        }))
        let model = Model(id: "m", name: "M", api: .faux, provider: .faux)
        do {
            _ = try await SwiftAI.complete(model: model)
            XCTFail("expected error")
        } catch {
            XCTAssertTrue(String(describing: error).contains("boom"))
        }
        await SwiftAI.bootstrap()
    }

    func testModelsRuntimeRegistryOperationsAndUnknownProvider() async throws {
        await AIRegistry.shared.clearProviders()
        await AIRegistry.shared.clearModels()
        await AIRegistry.shared.register(APIProvider(api: .openAICompletions, stream: { model, _, _ in
            AsyncStream { continuation in
                var output = Message(role: .assistant, content: [.text("ok")])
                output.api = model.api; output.provider = model.provider; output.model = model.id; output.stopReason = .stop; output.usage = Usage()
                continuation.yield(.start(partial: output)); continuation.yield(.done(reason: .stop, message: output)); continuation.finish()
            }
        }))
        let registeredProvider = await AIRegistry.shared.apiProvider(for: .openAICompletions)
        XCTAssertNotNil(registeredProvider)
        await AIRegistry.shared.unregister(api: .openAICompletions)
        let unregisteredProvider = await AIRegistry.shared.apiProvider(for: .openAICompletions)
        XCTAssertNil(unregisteredProvider)
        await AIRegistry.shared.register(Model(id: "m1", name: "M1", api: .openAICompletions, provider: .openAI))
        await AIRegistry.shared.register(Model(id: "m2", name: "M2", api: .openAIResponses, provider: .openAI))
        await AIRegistry.shared.register(Model(id: "m3", name: "M3", api: .anthropicMessages, provider: .anthropic))
        let openAIModelIDs = await AIRegistry.shared.listModels(provider: .openAI).map(\.id)
        let anthropicModel = await AIRegistry.shared.model(provider: .anthropic, id: "m3")
        let providers = await AIRegistry.shared.listProviders()
        XCTAssertEqual(openAIModelIDs, ["m1", "m2"])
        XCTAssertEqual(anthropicModel?.id, "m3")
        XCTAssertEqual(providers, [.anthropic, .openAI])
        let ghost = Model(id: "ghost", name: "Ghost", api: .mistralConversations, provider: .mistral)
        let events = await SwiftAI.stream(model: ghost, context: AIContext(), options: nil)
        var sawError = false
        for await event in events { if case .error(_, _, let error) = event { sawError = true; XCTAssertTrue(String(describing: error).contains("No provider registered") || String(describing: error).contains("noProvider")) } }
        XCTAssertTrue(sawError)
        await SwiftAI.bootstrap()
    }

    func testModelRuntimeStoreRefreshDedupeReplacementAndRemoval() async throws {
        let store = InMemoryProviderModelsStore()
        let runtime = ModelRuntime(store: store)
        final class Counter: @unchecked Sendable { var count = 0 }
        let counter = Counter()
        let fallback = [Model(id: "fallback", name: "Fallback", api: .openAIResponses, provider: .faux)]
        let dynamic = [Model(id: "dynamic", name: "Dynamic", api: .openAIResponses, provider: .faux)]
        await AIRegistry.shared.register(fallback[0])
        await runtime.register(RuntimeProvider(id: .faux, name: "Faux", fallbackModels: fallback, refresh: { context in
            counter.count += 1
            XCTAssertEqual(context.providerId, "faux")
            XCTAssertTrue(context.allowNetwork)
            try await Task.sleep(nanoseconds: 10_000_000)
            return dynamic
        }))
        let fallbackIDs = await runtime.listModels(provider: .faux).map(\.id)
        XCTAssertEqual(fallbackIDs, ["fallback"])
        async let first = runtime.refresh(provider: .faux, apiKey: "k")
        async let second = runtime.refresh(provider: .faux, apiKey: "k")
        let results = await [first, second]
        XCTAssertTrue(results.allSatisfy { $0.errors.isEmpty })
        XCTAssertEqual(counter.count, 1)
        let dynamicModel = await runtime.model(provider: .faux, id: "dynamic")
        let staleFallback = await AIRegistry.shared.model(provider: .faux, id: "fallback")
        let registeredDynamic = await AIRegistry.shared.model(provider: .faux, id: "dynamic")
        XCTAssertEqual(dynamicModel?.id, "dynamic")
        XCTAssertNil(staleFallback)
        XCTAssertEqual(registeredDynamic?.id, "dynamic")
        await runtime.replaceModels(provider: .faux, models: [Model(id: "replacement", name: "Replacement", api: .openAIResponses, provider: .faux)])
        let replacementIDs = await runtime.listModels(provider: .faux).map(\.id)
        let staleDynamic = await AIRegistry.shared.model(provider: .faux, id: "dynamic")
        let registeredReplacement = await AIRegistry.shared.model(provider: .faux, id: "replacement")
        XCTAssertEqual(replacementIDs, ["replacement"])
        XCTAssertNil(staleDynamic)
        XCTAssertEqual(registeredReplacement?.id, "replacement")
        await runtime.removeModel(provider: .faux, id: "replacement")
        let emptyModels = await runtime.listModels(provider: .faux)
        let removedReplacement = await AIRegistry.shared.model(provider: .faux, id: "replacement")
        XCTAssertEqual(emptyModels, [])
        XCTAssertNil(removedReplacement)
        try await store.write(providerId: "faux", entry: StoredModelsEntry(models: [Model(id: "cached", name: "Cached", api: .openAIResponses, provider: .faux)]))
        await runtime.register(RuntimeProvider(id: .faux, name: "Faux", fallbackModels: fallback, refresh: { _ in throw AIError.provider("network down") }))
        let failed = await runtime.refresh(provider: .faux, allowNetwork: true, force: true)
        XCTAssertEqual(failed.errors.keys.sorted(), ["faux"])
        let cachedIDs = await runtime.listModels(provider: .faux).map(\.id)
        XCTAssertEqual(cachedIDs, ["cached"])
    }

    func testRadiusRuntimeProviderRefreshUsesConfigAndCacheFallback() async throws {
        let store = InMemoryProviderModelsStore()
        let runtime = ModelRuntime(store: store)
        final class RadiusMock: @unchecked Sendable { var fail = false; var auth: String? }
        let mock = RadiusMock()
        RadiusOAuthProvider.requestTransport = { request in
            mock.auth = request.value(forHTTPHeaderField: "Authorization")
            if mock.fail { return (#"{"error":"temporary"}"#.data(using: .utf8)!, HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!) }
            let json = #"{"baseUrl":"https://radius.test/v1","models":[{"id":"radius-auto","name":"Radius Auto","reasoning":true,"input":["text"],"cost":{"input":1,"output":2,"cacheRead":0,"cacheWrite":0},"contextWindow":128000,"maxTokens":16384}]}"#
            return (json.data(using: .utf8)!, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        defer { RadiusOAuthProvider.requestTransport = nil }
        let fallback = [Model(id: "radius-fallback", name: "Radius Fallback", api: .piMessages, provider: .radius)]
        await AIRegistry.shared.register(fallback[0])
        await runtime.register(RadiusRuntimeProviderFactory.provider(fallbackModels: fallback))
        let refreshed = await runtime.refresh(provider: .radius, apiKey: "radius-key", force: true)
        XCTAssertTrue(refreshed.errors.isEmpty)
        XCTAssertEqual(mock.auth, "Bearer radius-key")
        let refreshedIDs = await runtime.listModels(provider: .radius).map(\.id)
        let staleRadiusFallback = await AIRegistry.shared.model(provider: .radius, id: "radius-fallback")
        let registeredRadiusAuto = await AIRegistry.shared.model(provider: .radius, id: "radius-auto")
        XCTAssertEqual(refreshedIDs, ["radius-auto"])
        XCTAssertNil(staleRadiusFallback)
        XCTAssertEqual(registeredRadiusAuto?.baseUrl, "https://radius.test/v1")
        mock.fail = true
        let failed = await runtime.refresh(provider: .radius, apiKey: "radius-key", force: true)
        XCTAssertEqual(failed.errors.keys.sorted(), ["radius"])
        let cachedAfterFailure = await runtime.listModels(provider: .radius).map(\.id)
        XCTAssertEqual(cachedAfterFailure, ["radius-auto"])
        await runtime.register(RadiusRuntimeProviderFactory.provider(fallbackModels: fallback))
        let offline = await runtime.refresh(provider: .radius, allowNetwork: false)
        XCTAssertTrue(offline.errors.isEmpty)
        let offlineIDs = await runtime.listModels(provider: .radius).map(\.id)
        XCTAssertEqual(offlineIDs, ["radius-auto"])
    }

    func testBootstrapRegistersXAIOAuthAndGrokFallback() async throws {
        await SwiftAI.bootstrap()
        let oauth = await OAuthRegistry.shared.provider(id: "xai")
        let runtimeModel = await ModelRuntime.shared.model(provider: .xai, id: "grok-4.5")
        let registryModel = await AIRegistry.shared.model(provider: .xai, id: "grok-4.5")
        XCTAssertNotNil(oauth)
        XCTAssertNotNil(runtimeModel)
        XCTAssertEqual(registryModel?.api, .openAIResponses)
    }

    func testCompatLegacyAPIRegistryDispatchPreservesRequestAPIKey() async throws {
        await AIRegistry.shared.clearProviders()
        final class Box: @unchecked Sendable { var apiKey: String? }
        let box = Box()
        await AIRegistry.shared.register(APIProvider(api: .openAIResponses, stream: { model, _, options in
            box.apiKey = options?.apiKey
            return AsyncStream { continuation in
                var output = Message(role: .assistant, content: [.text("ok")])
                output.api = model.api
                output.provider = model.provider
                output.model = model.id
                output.usage = Usage()
                output.stopReason = .stop
                continuation.yield(.start(partial: output))
                continuation.yield(.done(reason: .stop, message: output))
                continuation.finish()
            }
        }))
        var options = StreamOptions()
        options.apiKey = "request-key"
        let model = Model(id: "test-model", name: "Test Model", api: .openAIResponses, provider: .openCode, baseUrl: "https://example.test/v1", input: ["text"], contextWindow: 128000, maxTokens: 4096)
        let result = try await SwiftAI.complete(model: model, context: AIContext(messages: [.user("hi")]), options: options)
        XCTAssertEqual(result.content, [.text("ok")])
        XCTAssertEqual(box.apiKey, "request-key")
        await SwiftAI.bootstrap()
    }

    func testUserMessageAndContextJSON() throws {
        let message = Message.user("hello")
        XCTAssertEqual(message.role, .user)
        XCTAssertEqual(message.content, [.text("hello")])
        let context = AIContext(systemPrompt: "sys", messages: [message])
        let data = try JSONEncoder().encode(context)
        let decoded = try JSONDecoder().decode(AIContext.self, from: data)
        XCTAssertEqual(decoded, context)
    }

    func testModelsAreEqual() {
        let a = Model(id: "m", name: "M", api: .openAICompletions, provider: .openAI)
        let b = Model(id: "m", name: "Other", api: .openAIResponses, provider: .openAI)
        let c = Model(id: "m2", name: "M2", api: .openAICompletions, provider: .openAI)
        XCTAssertTrue(AIUtilities.modelsAreEqual(a, b))
        XCTAssertFalse(AIUtilities.modelsAreEqual(a, c))
        XCTAssertFalse(AIUtilities.modelsAreEqual(a, nil))
    }

    func testHarnessCloneNilAndSaveLoadContext() throws {
        XCTAssertNil(Harness.cloneContext(nil))
        let context = AIContext(systemPrompt: "sys", messages: [.user("hello")], tools: [Tool(name: "echo", description: "Echo", parameters: .object(["type": .string("object")]))])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("swift-ai-context-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Harness.saveContext(context, to: url)
        let loaded = try Harness.loadContext(from: url)
        XCTAssertEqual(loaded, context)
    }

    func testTransformInsertsSyntheticToolResultBeforeFollowUpUser() {
        let model = Model(id: "gpt-4o-mini", name: "GPT", api: .openAICompletions, provider: .openAI)
        var assistant = Message(role: .assistant, content: [.toolCall(id: "calculate_1", name: "calculate", arguments: ["expression": .string("25 * 18")])])
        assistant.api = model.api; assistant.provider = model.provider; assistant.model = model.id; assistant.stopReason = .toolUse
        let transformed = AIUtilities.transformMessages([.user("Please calculate 25 * 18"), assistant, .user("Never mind, what is 2+2?")], for: model)
        XCTAssertEqual(transformed.map(\.role), [.user, .assistant, .toolResult, .user])
        XCTAssertEqual(transformed[2].toolCallId, "calculate_1")
        XCTAssertEqual(transformed[2].toolName, "calculate")
        XCTAssertEqual(transformed[2].isError, true)
        XCTAssertEqual(transformed[2].content, [.text("No result provided")])
    }

    func testTransformMessagesCopilotOpenAIToAnthropic() {
        let model = Model(id: "claude-sonnet-4.6", name: "Claude", api: .anthropicMessages, provider: .githubCopilot, input: ["text", "image"])
        var assistant = Message(role: .assistant, content: [.thinking("Let me think about this..."), .text("Hi there!")])
        assistant.api = .openAICompletions; assistant.provider = .githubCopilot; assistant.model = "gpt-4o"; assistant.stopReason = .stop
        assistant.content[0].thinkingSignature = "reasoning_content"
        let transformed = AIUtilities.transformMessages([.user("hello"), assistant], for: model)
        guard let convertedAssistant = transformed.first(where: { $0.role == .assistant }) else { return XCTFail("missing assistant") }
        XCTAssertEqual(convertedAssistant.content.filter { $0.type == "thinking" }.count, 0)
        XCTAssertGreaterThanOrEqual(convertedAssistant.content.filter { $0.type == "text" }.count, 2)

        var toolAssistant = Message(role: .assistant, content: [.toolCall(id: "call_123", name: "bash", arguments: ["command": .string("ls")])])
        toolAssistant.api = .openAIResponses; toolAssistant.provider = .githubCopilot; toolAssistant.model = "gpt-5"; toolAssistant.stopReason = .toolUse
        toolAssistant.content[0].thoughtSignature = "{\"type\":\"reasoning.encrypted\"}"
        var result = Message(role: .toolResult, content: [.text("output")]); result.toolCallId = "call_123"; result.toolName = "bash"
        let stripped = AIUtilities.transformMessages([.user("run"), toolAssistant, result], for: model)
        let strippedCall = stripped.first(where: { $0.role == .assistant })?.content.first(where: { $0.type == "toolCall" })
        XCTAssertNil(strippedCall?.thoughtSignature)

        var orphan = Message(role: .assistant, content: [.toolCall(id: "call_123|fc_123", name: "read", arguments: ["path": .string("README.md")])])
        orphan.api = .openAIResponses; orphan.provider = .githubCopilot; orphan.model = "gpt-5"; orphan.stopReason = .toolUse
        let orphaned = AIUtilities.transformMessages([.user("read"), orphan], for: model)
        XCTAssertEqual(orphaned.last?.role, .toolResult)
        XCTAssertEqual(orphaned.last?.toolCallId, "call_123_fc_123")
        XCTAssertEqual(orphaned.last?.toolName, "read")
        XCTAssertEqual(orphaned.last?.isError, true)
        XCTAssertEqual(orphaned.last?.content, [.text("No result provided")])
    }

    func testEmptyAndWhitespaceMessagesSerializeGracefully() {
        let emptyUser = Message(role: .user, content: [])
        let emptyString = Message.user("")
        let whitespace = Message.user("   \n\t  ")
        let model = Model(id: "gpt", name: "GPT", api: .openAICompletions, provider: .openAI)
        let body = OpenAICompletionsProvider.buildRequestBody(model: model, context: AIContext(messages: [emptyUser, emptyString, whitespace]), options: nil)
        guard case .array(let messages)? = body["messages"] else { return XCTFail("missing messages") }
        XCTAssertEqual(messages.count, 3)
        for message in messages {
            guard case .object(let object) = message else { return XCTFail("message not object") }
            XCTAssertEqual(object["role"], .string("user"))
            XCTAssertNotNil(object["content"])
        }
        var assistant = Message(role: .assistant, content: [])
        assistant.api = model.api; assistant.provider = model.provider; assistant.model = model.id; assistant.stopReason = .stop
        let transformed = AIUtilities.transformMessages([.user("Hello"), assistant, .user("Please respond")], for: model)
        XCTAssertEqual(transformed.map(\.role), [.user, .assistant, .user])
    }

    func testTransformPreservesImagesForVisionModelsAndDowngradesTextModels() {
        let image = ContentBlock.image(data: "abc", mimeType: "image/png")
        let messages = [Message(role: .user, content: [.text("see"), image])]
        let vision = Model(id: "vision", name: "Vision", api: .openAICompletions, provider: .openAI, input: ["text", "image"])
        let textOnly = Model(id: "text", name: "Text", api: .openAICompletions, provider: .openAI, input: ["text"])
        XCTAssertEqual(AIUtilities.transformMessages(messages, for: vision).first?.content.last?.type, "image")
        let downgraded = AIUtilities.transformMessages(messages, for: textOnly)
        XCTAssertEqual(downgraded.first?.content.map(\.type), ["text", "text"])
        XCTAssertEqual(downgraded.first?.content.last?.text, "(image omitted: model does not support images)")
    }

    func testTransformSkipsErroredAssistantMessagesAndInsertsSyntheticToolResults() {
        var errored = Message(role: .assistant, content: [.text("bad")])
        errored.stopReason = .error
        let toolCall = ContentBlock.toolCall(id: "call", name: "lookup", arguments: [:])
        var assistant = Message(role: .assistant, content: [toolCall])
        assistant.stopReason = .toolUse
        let model = Model(id: "m", name: "M", api: .openAICompletions, provider: .openAI)
        let transformed = AIUtilities.transformMessages([errored, assistant], for: model)
        XCTAssertFalse(transformed.contains { $0.errorMessage == "bad" || $0.content.first?.text == "bad" })
        XCTAssertTrue(transformed.contains { $0.role == .toolResult && $0.toolCallId == "call" && $0.isError == true })
    }
}
