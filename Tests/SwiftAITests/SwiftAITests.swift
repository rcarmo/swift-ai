import XCTest
@testable import SwiftAI

final class SwiftAITests: XCTestCase {
    func testUserMessageCodableShape() throws {
        let data = try JSONEncoder().encode(Message.user("hello"))
        let text = String(data: data, encoding: .utf8)!
        XCTAssertTrue(text.contains("\"role\":\"user\""))
        XCTAssertTrue(text.contains("\"type\":\"text\""))
        let decoded = try JSONDecoder().decode(Message.self, from: data)
        XCTAssertEqual(decoded.content.first?.text, "hello")
    }

    func testSSEParser() {
        let parser = SSEParser()
        let events = parser.parse("event: message\ndata: {\"x\":1}\nid: 7\n\n")
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].event, "message")
        XCTAssertEqual(events[0].data, "{\"x\":1}")
        XCTAssertEqual(events[0].id, "7")
    }

    func testCompatChatTemplateOverride() {
        var compat = OpenAICompletionsCompat()
        compat.thinkingFormat = "chat-template"
        compat.chatTemplateKwargs = ["enable_thinking": ChatTemplateKwargValue(variable: "thinking.enabled")]
        let model = Model(id: "x", name: "x", api: .openAICompletions, provider: .openAI, baseUrl: "https://example.com", reasoning: true, completionsCompat: compat)
        let detected = Compat.detect(for: model)
        XCTAssertEqual(detected.thinkingFormat, "chat-template")
        XCTAssertEqual(detected.chatTemplateKwargs?["enable_thinking"]?.variable, "thinking.enabled")
    }

    func testGeneratedModelRegistryMetadata() throws {
        XCTAssertEqual(BuiltinModels.upstreamVersion, "0.79.9")
        XCTAssertEqual(BuiltinModels.modelCount, 979)
        XCTAssertEqual(BuiltinModels.providerCount, 35)
        let models = try BuiltinModels.all()
        XCTAssertEqual(models.count, 979)
        XCTAssertTrue(models.contains { $0.provider == .openAI && $0.id == "gpt-4.1" })
        XCTAssertTrue(models.contains { $0.provider == .githubCopilot })
    }

    func testGeneratedImageModelRegistryMetadata() throws {
        XCTAssertEqual(BuiltinImageModels.upstreamVersion, "0.79.9")
        XCTAssertEqual(BuiltinImageModels.modelCount, 34)
        XCTAssertEqual(BuiltinImageModels.providerCount, 1)
        let models = try BuiltinImageModels.all()
        XCTAssertEqual(models.count, 34)
        XCTAssertTrue(models.contains { $0.provider == .openRouter && $0.api == .openRouterImages })
    }

    func testOpenRouterImagePayloadBuilder() throws {
        let model = ImagesModel(id: "image-model", name: "Image Model", api: .openRouterImages, provider: .openRouter, output: ["image", "text"])
        let payload = OpenRouterImagesProvider.buildImagesPayload(model: model, context: ImagesContext(input: [.text("draw"), .image(data: "abc", mimeType: "image/png")]))
        guard case .object(let object) = payload else { return XCTFail("expected object") }
        XCTAssertEqual(object["model"], .string("image-model"))
        XCTAssertEqual(object["stream"], .bool(false))
        guard case .array(let modalities)? = object["modalities"] else { return XCTFail("missing modalities") }
        XCTAssertEqual(modalities, [.string("image"), .string("text")])
    }

    func testDiagnosticsAndLogger() async throws {
        struct SampleError: Error {}
        XCTAssertEqual(Diagnostics.formatThrownValue("x"), "x")
        let diagnostic = Diagnostics.createAssistantMessageDiagnostic(type: "test", error: SampleError(), details: ["k": .string("v")])
        XCTAssertEqual(diagnostic.type, "test")
        XCTAssertEqual(diagnostic.details?["k"], .string("v"))
        var message = Message.user("hi")
        Diagnostics.appendAssistantMessageDiagnostic(diagnostic, to: &message)
        XCTAssertEqual(message.diagnostics?.count, 1)
        await LoggerRegistry.shared.setLogger(DiscardLogger())
        await LoggerRegistry.shared.info("ok", ["provider": "test"])
    }

    func testPromptCacheAndSessionResources() async throws {
        XCTAssertEqual(PromptCache.clampOpenAIKey(String(repeating: "x", count: 80)).count, 64)
        let registry = SessionResourceRegistry.shared
        let box = CleanupBox()
        let unregister = await registry.register { sessionId in await box.append(sessionId) }
        try await registry.cleanup(sessionId: "s1")
        XCTAssertEqual(await box.values(), ["s1"])
        await unregister()
        try await registry.cleanup(sessionId: "s2")
        XCTAssertEqual(await box.values(), ["s1"])
    }

    func testMessageTransform() {
        let textOnlyModel = Model(id: "target", name: "Target", api: .openAICompletions, provider: .openAI, input: ["text"])
        var assistant = Message(role: .assistant, content: [ContentBlock.thinking("private"), ContentBlock.toolCall(id: "call1", name: "tool", arguments: [:])])
        assistant.api = .anthropicMessages
        assistant.provider = .anthropic
        assistant.model = "other"
        let messages: [Message] = [
            Message(role: .user, content: [.image(data: "abc", mimeType: "image/png")]),
            assistant,
            Message.user("next")
        ]
        let transformed = AIUtilities.transformMessages(messages, for: textOnlyModel)
        XCTAssertEqual(transformed.first?.content.first?.text, "(image omitted: model does not support images)")
        XCTAssertTrue(transformed.contains { $0.role == .assistant && $0.content.first?.type == "text" && $0.content.first?.text == "private" })
        XCTAssertTrue(transformed.contains { $0.role == .toolResult && $0.toolCallId == "call1" && $0.isError == true })
    }

    func testCostCalculation() {
        let model = Model(id: "priced", name: "Priced", api: .openAICompletions, provider: .openAI, cost: ModelCost(input: 3, output: 15, cacheRead: 0.3, cacheWrite: 3.75))
        var usage = Usage()
        usage.input = 1000
        usage.output = 500
        usage.cacheRead = 200
        usage.cacheWrite = 100
        usage.cacheWrite1h = 25
        let cost = AIUtilities.calculateCost(model: model, usage: usage)
        XCTAssertEqual(cost.input, 0.003, accuracy: 0.0000001)
        XCTAssertEqual(cost.output, 0.0075, accuracy: 0.0000001)
        XCTAssertEqual(cost.cacheRead, 0.00006, accuracy: 0.0000001)
        XCTAssertEqual(cost.cacheWrite, ((75.0 * 3.75) + (25.0 * 6.0)) / 1_000_000.0, accuracy: 0.0000001)
        XCTAssertEqual(cost.total, cost.input + cost.output + cost.cacheRead + cost.cacheWrite, accuracy: 0.0000001)
    }

    func testFauxProviderHelpers() async throws {
        let registration = await FauxProvider.register()
        await registration.setResponses([.message(FauxProvider.textMessage("hello world"))])
        guard let model = await registration.model() else { return XCTFail("missing faux model") }
        let message = try await SwiftAI.complete(model: model, context: AIContext(messages: [.user("hi")]))
        XCTAssertEqual(message.content.first?.text, "hello world")
        XCTAssertEqual(await registration.pendingResponseCount(), 0)
    }

    func testOAuthPKCEAndCopilotHelpers() throws {
        let pair = try OAuthUtilities.generatePKCE()
        XCTAssertFalse(pair.verifier.isEmpty)
        XCTAssertFalse(pair.challenge.isEmpty)
        XCTAssertNotEqual(pair.verifier, pair.challenge)
        XCTAssertEqual(OAuthUtilities.normalizeDomain("https://company.ghe.com/"), "company.ghe.com")
        XCTAssertEqual(GitHubCopilotOAuthProvider.baseURL(token: "tid=abc;proxy-ep=proxy.individual.githubcopilot.com;sku=x"), "https://api.individual.githubcopilot.com")
        let provider = GitHubCopilotOAuthProvider()
        let models = [
            Model(id: "keep", name: "keep", api: .openAICompletions, provider: .githubCopilot),
            Model(id: "drop", name: "drop", api: .openAICompletions, provider: .githubCopilot),
            Model(id: "other", name: "other", api: .openAICompletions, provider: .openAI)
        ]
        let filtered = provider.modifyModels(models, credentials: OAuthCredentials(refresh: "r", access: "tok", expires: 0, extra: ["availableModelIds": .array([.string("keep")])]))
        XCTAssertEqual(filtered.map(\.id), ["keep", "other"])
    }

    func testRetryPolicy() {
        var options = StreamOptions()
        options.maxRetries = 3
        options.maxRetryDelayMs = 1_000
        let policy = RetryPolicy(options: options)
        XCTAssertEqual(policy.maxRetries, 3)
        XCTAssertEqual(policy.maxDelayMs, 1_000)
        XCTAssertEqual(policy.delayNanoseconds(attempt: 1), 250_000_000)
        XCTAssertEqual(policy.delayNanoseconds(attempt: 10), 1_000_000_000)
        XCTAssertTrue(HTTPRetry.shouldRetry(statusCode: 429))
        XCTAssertTrue(HTTPRetry.shouldRetry(statusCode: 500))
        XCTAssertFalse(HTTPRetry.shouldRetry(statusCode: 400))
    }

    func testOpenAIResponsesRequestAzureAndSSE() throws {
        let model = Model(id: "gpt-5", name: "GPT-5", api: .openAIResponses, provider: .openAI, baseUrl: "https://api.openai.com/v1", reasoning: true)
        var options = StreamOptions()
        options.reasoning = .high
        options.sessionId = "session"
        let body = OpenAIResponsesProvider.buildRequestBody(model: model, context: AIContext(systemPrompt: "sys", messages: [.user("hi")]), options: options)
        XCTAssertEqual(body["model"], .string("gpt-5"))
        XCTAssertEqual(body["stream"], .bool(true))
        XCTAssertNotNil(body["reasoning"])
        XCTAssertEqual(body["prompt_cache_key"], .string("session"))
        let azure = try OpenAIResponsesProvider.resolveAzureConfig(model: Model(id: "dep", name: "dep", api: .azureOpenAIResponses, provider: .azureOpenAI), options: { var o = StreamOptions(); o.azureResourceName = "res"; return o }())
        XCTAssertTrue(azure.baseURL.contains("res.openai.azure.com"))

        let sse = """
        event: response.created
        data: {"response":{"id":"resp_1"}}

        event: response.output_item.added
        data: {"item":{"type":"message"}}

        event: response.output_text.delta
        data: {"delta":"hi"}

        event: response.output_item.done
        data: {}

        event: response.completed
        data: {"response":{"id":"resp_1","usage":{"input_tokens":3,"output_tokens":2,"total_tokens":5}}}

        """
        let events = OpenAIResponsesProvider.processSSEText(sse, model: model)
        guard case .done(let reason, let message)? = events.last else { return XCTFail("missing done") }
        XCTAssertEqual(reason, .stop)
        XCTAssertEqual(message.responseId, "resp_1")
        XCTAssertEqual(message.content.first?.text, "hi")
        XCTAssertEqual(message.usage?.totalTokens, 5)
    }

    func testGoogleRequestURLAndSSEProcessing() throws {
        let model = Model(id: "gemini-2.5-pro", name: "Gemini", api: .googleGenerativeAI, provider: .google, baseUrl: "https://generativelanguage.googleapis.com/v1beta", reasoning: true)
        var options = StreamOptions()
        options.reasoning = .low
        let body = GoogleGenerativeAIProvider.buildRequestBody(model: model, context: AIContext(systemPrompt: "sys", messages: [.user("hi")]), options: options)
        XCTAssertNotNil(body["contents"])
        XCTAssertNotNil(body["generationConfig"])
        let url = try GoogleGenerativeAIProvider.buildStreamURL(model: model, apiKey: "key", options: nil)
        XCTAssertTrue(url.contains(":streamGenerateContent?alt=sse&key=key"))

        let sse = """
        data: {"responseId":"resp_1","candidates":[{"content":{"parts":[{"thought":true,"text":"why"}]}}]}

        data: {"candidates":[{"content":{"parts":[{"text":"ok"}]},"finishReason":"STOP"}],"usageMetadata":{"promptTokenCount":4,"candidatesTokenCount":2,"totalTokenCount":6,"cachedContentTokenCount":1}}

        """
        let events = GoogleGenerativeAIProvider.processSSEText(sse, model: model)
        guard case .done(let reason, let message)? = events.last else { return XCTFail("missing done") }
        XCTAssertEqual(reason, .stop)
        XCTAssertEqual(message.responseId, "resp_1")
        XCTAssertEqual(message.content.first?.type, "thinking")
        XCTAssertEqual(message.content.first?.thinking, "why")
        XCTAssertTrue(message.content.contains { $0.type == "text" && $0.text == "ok" })
        XCTAssertEqual(message.usage?.cacheRead, 1)
    }

    func testMistralRequestAndSSEProcessing() {
        let model = Model(id: "mistral-small-latest", name: "Mistral Small", api: .mistralConversations, provider: .mistral, baseUrl: "https://api.mistral.ai/v1", reasoning: true, thinkingLevelMap: [.low: "low"])
        var options = StreamOptions()
        options.reasoning = .low
        let body = MistralConversationsProvider.buildRequestBody(model: model, context: AIContext(systemPrompt: "sys", messages: [.user("hi")]), options: options)
        XCTAssertEqual(body["model"], .string("mistral-small-latest"))
        XCTAssertEqual(body["stream"], .bool(true))
        XCTAssertEqual(body["reasoning_effort"], .string("low"))

        let sse = """
        data: {"choices":[{"delta":{"reasoning_content":"think"}}]}

        data: {"choices":[{"delta":{"content":"ok"},"finish_reason":"stop"}],"usage":{"prompt_tokens":3,"completion_tokens":2,"total_tokens":5}}

        data: [DONE]

        """
        let events = MistralConversationsProvider.processSSEText(sse, model: model)
        guard case .done(let reason, let message)? = events.last else { return XCTFail("missing done") }
        XCTAssertEqual(reason, .stop)
        XCTAssertEqual(message.content.first?.type, "thinking")
        XCTAssertEqual(message.content.first?.thinking, "think")
        XCTAssertTrue(message.content.contains { $0.type == "text" && $0.text == "ok" })
        XCTAssertEqual(message.usage?.totalTokens, 5)
    }

    func testAnthropicRequestAndSSEProcessing() {
        let model = Model(id: "claude-test", name: "Claude Test", api: .anthropicMessages, provider: .anthropic, baseUrl: "https://api.anthropic.com", reasoning: true, maxTokens: 4096)
        var options = StreamOptions()
        options.reasoning = .low
        let body = AnthropicMessagesProvider.buildRequestBody(model: model, context: AIContext(systemPrompt: "sys", messages: [.user("hi")]), options: options)
        XCTAssertEqual(body["model"], .string("claude-test"))
        XCTAssertEqual(body["stream"], .bool(true))
        XCTAssertNotNil(body["thinking"])

        let sse = """
        event: message_start
        data: {"message":{"id":"msg_1","usage":{"input_tokens":5}}}

        event: content_block_start
        data: {"index":0,"content_block":{"type":"text"}}

        event: content_block_delta
        data: {"index":0,"delta":{"type":"text_delta","text":"hi"}}

        event: content_block_stop
        data: {"index":0}

        event: message_delta
        data: {"delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":2}}

        event: message_stop
        data: {}

        """
        let events = AnthropicMessagesProvider.processSSEText(sse, model: model)
        guard case .done(let reason, let message)? = events.last else { return XCTFail("missing done") }
        XCTAssertEqual(reason, .stop)
        XCTAssertEqual(message.responseId, "msg_1")
        XCTAssertEqual(message.content.first?.text, "hi")
        XCTAssertEqual(message.usage?.input, 5)
        XCTAssertEqual(message.usage?.output, 2)
    }

    func testOpenAISSEProcessing() {
        let model = Model(id: "gpt-test", name: "GPT Test", api: .openAICompletions, provider: .openAI, baseUrl: "https://example.com")
        let sse = """
        data: {"id":"chatcmpl_1","model":"actual","choices":[{"index":0,"delta":{"reasoning_content":"why"}}]}

        data: {"choices":[{"index":0,"delta":{"content":"hel"}}]}

        data: {"choices":[{"index":0,"delta":{"content":"lo","tool_calls":[{"index":0,"id":"call_1","function":{"name":"lookup","arguments":"{\\\"q\\\":"}}]}}]}

        data: {"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\\\"x\\\"}"}}]},"finish_reason":"tool_calls"}]}

        data: [DONE]

        """
        let events = OpenAICompletionsProvider.processSSEText(sse, model: model)
        guard case .done(let reason, let message)? = events.last else { return XCTFail("missing done") }
        XCTAssertEqual(reason, .toolUse)
        XCTAssertEqual(message.responseId, "chatcmpl_1")
        XCTAssertEqual(message.responseModel, "actual")
        XCTAssertEqual(message.content.first?.type, "thinking")
        XCTAssertEqual(message.content.first?.thinking, "why")
        XCTAssertTrue(message.content.contains { $0.type == "text" && $0.text == "hello" })
        XCTAssertTrue(message.content.contains { $0.type == "toolCall" && $0.name == "lookup" })
    }

    func testOpenAIStreamingRequestBuilder() {
        let model = Model(id: "x", name: "x", api: .openAICompletions, provider: .openAI, baseUrl: "https://example.com")
        let body = OpenAICompletionsProvider.buildRequestBody(model: model, context: AIContext(messages: [.user("hi")]), options: nil, stream: true)
        XCTAssertEqual(body["stream"], .bool(true))
        guard case .object(let streamOptions)? = body["stream_options"] else { return XCTFail("missing stream_options") }
        XCTAssertEqual(streamOptions["include_usage"], .bool(true))
    }

    func testOpenAIRequestBuilder() {
        var compat = OpenAICompletionsCompat()
        compat.thinkingFormat = "chat-template"
        compat.chatTemplateKwargs = [
            "enable_thinking": ChatTemplateKwargValue(variable: "thinking.enabled"),
            "effort": ChatTemplateKwargValue(variable: "thinking.effort", omitWhenOff: true)
        ]
        let model = Model(id: "x", name: "x", api: .openAICompletions, provider: .openAI, baseUrl: "https://example.com", reasoning: true, thinkingLevelMap: [.high: "high"], completionsCompat: compat)
        var options = StreamOptions()
        options.reasoning = .high
        let body = OpenAICompletionsProvider.buildRequestBody(model: model, context: AIContext(messages: [.user("hi")]), options: options)
        guard case .object(let kwargs)? = body["chat_template_kwargs"] else { return XCTFail("missing kwargs") }
        XCTAssertEqual(kwargs["enable_thinking"], .bool(true))
        XCTAssertEqual(kwargs["effort"], .string("high"))
    }
}

private actor CleanupBox {
    private var items: [String] = []
    func append(_ value: String) { items.append(value) }
    func values() -> [String] { items }
}
