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

    func testSSEParserMultilineStickyIDAndRetry() {
        let parser = SSEParser()
        let events = parser.parse("id: 7\nretry: 2500\nevent: chunk\ndata: a\ndata: b\n\ndata: c\n\n")
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0], SSEEvent(event: "chunk", data: "a\nb", id: "7", retry: 2500))
        XCTAssertEqual(events[1], SSEEvent(event: nil, data: "c", id: "7", retry: 2500))
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

    func testModelCompatCodableShape() throws {
        let anthropicJSON = """
        {"id":"a","name":"A","api":"anthropic-messages","provider":"anthropic","reasoning":false,"input":["text"],"cost":{"input":0,"output":0,"cacheRead":0,"cacheWrite":0},"contextWindow":1,"maxTokens":1,"anthropicCompat":{"sendSessionAffinityHeaders":true,"supportsCacheControlOnTools":false}}
        """.data(using: .utf8)!
        let anthropic = try JSONDecoder().decode(Model.self, from: anthropicJSON)
        XCTAssertEqual(anthropic.anthropicCompat?.sendSessionAffinityHeaders, true)
        XCTAssertEqual(anthropic.anthropicCompat?.supportsCacheControlOnTools, false)
    }

    func testModelThinkingLevelMapCodableShape() throws {
        let json = """
        {"id":"m","name":"M","api":"openai-completions","provider":"openai","baseUrl":"","reasoning":true,"thinkingLevelMap":{"off":"none","xhigh":null},"input":["text"],"cost":{"input":0,"output":0,"cacheRead":0,"cacheWrite":0},"contextWindow":1,"maxTokens":1}
        """.data(using: .utf8)!
        let model = try JSONDecoder().decode(Model.self, from: json)
        guard let thinkingMap = model.thinkingLevelMap else { return XCTFail("missing thinking map") }
        XCTAssertEqual(thinkingMap[.off]!, Optional("none"))
        XCTAssertTrue(thinkingMap.keys.contains(.xhigh))
        XCTAssertNil(thinkingMap[.xhigh]!)
        let encoded = try JSONEncoder().encode(model)
        let decoded = try JSONDecoder().decode(Model.self, from: encoded)
        XCTAssertTrue(decoded.thinkingLevelMap?.keys.contains(.xhigh) == true)
    }

    func testAuthCredentialStoreAndCodable() async throws {
        let store = InMemoryCredentialStore()
        try await store.modify(providerId: "openai") { _ in .apiKey(key: "k", env: ["A": "B"]) }
        let storedCredential = try await store.read(providerId: "openai")
        XCTAssertEqual(storedCredential, .apiKey(key: "k", env: ["A": "B"]))
        try await store.delete(providerId: "openai")
        let deletedCredential = try await store.read(providerId: "openai")
        XCTAssertNil(deletedCredential)
        let oauth = Credential.oauth(OAuthCredentials(refresh: "r", access: "a", expires: 1, extra: ["x": .string("y")]))
        let data = try JSONEncoder().encode(oauth)
        XCTAssertEqual(try JSONDecoder().decode(Credential.self, from: data), oauth)
        let ctx = ProcessAuthContext()
        let missingFileExists = await ctx.fileExists("/definitely/missing/swift-ai-file")
        XCTAssertFalse(missingFileExists)
        let callbacks = AuthLoginCallbacks(prompt: { prompt in
            if case .manualCode = prompt { return "code" }
            return "value"
        })
        let promptResult = try await callbacks.prompt(.manualCode(message: "code"))
        XCTAssertEqual(promptResult, "code")
    }

    func testCompleteNilModelDoesNotPanic() async {
        do {
            _ = try await SwiftAI.complete(model: nil)
            XCTFail("expected nil model error")
        } catch {
            XCTAssertTrue(String(describing: error).contains("nilModel") || String(describing: error).contains("nil model"))
        }
    }

    func testCloneContextDeepCopiesNestedFieldsAndToolCalls() throws {
        var assistant = Message(role: .assistant, content: [.toolCall(id: "c", name: "tool", arguments: ["nested": .object(["x": .string("y")])])])
        var usage = Usage(); usage.input = 1; assistant.usage = usage
        let context = AIContext(systemPrompt: "sys", messages: [assistant], tools: [Tool(name: "tool", description: "desc", parameters: .object(["type": .string("object")]))])
        var clone = try XCTUnwrap(Harness.cloneContext(context))
        clone.messages[0].content[0].arguments?["nested"] = .object(["x": .string("changed")])
        XCTAssertEqual(context.messages[0].content[0].arguments?["nested"], .object(["x": .string("y")]))
        var calls = Harness.toolCalls(in: context.messages[0])
        calls[0].arguments?["nested"] = .object(["x": .string("changed")])
        XCTAssertEqual(context.messages[0].content[0].arguments?["nested"], .object(["x": .string("y")]))
    }

    func testStreamNilModelAndNoProvider() async {
        let nilEvents = await SwiftAI.stream(model: nil)
        var sawNilError = false
        for await event in nilEvents { if case .error(_, _, let error) = event { sawNilError = String(describing: error).contains("nilModel") || String(describing: error).contains("nil model") } }
        XCTAssertTrue(sawNilError)

        let missing = Model(id: "missing", name: "Missing", api: .faux, provider: .faux)
        await AIRegistry.shared.unregister(api: .faux)
        let events = await SwiftAI.stream(model: missing)
        var sawProviderError = false
        for await event in events { if case .error(_, _, let error) = event { sawProviderError = String(describing: error).contains("noProvider") || String(describing: error).contains("no provider") } }
        XCTAssertTrue(sawProviderError)
        await SwiftAI.bootstrap()
    }

    func testSwiftAIStatusConstants() {
        XCTAssertEqual(SwiftAIStatus.upstreamVersion, "0.80.3")
        XCTAssertEqual(SwiftAIStatus.textModelCount, 1029)
        XCTAssertEqual(SwiftAIStatus.imageModelCount, 35)
        XCTAssertTrue(SwiftAIStatus.bundledRuntimeAPIs.contains(.openAICompletions))
        XCTAssertEqual(SwiftAIStatus.pluggableTransports["bedrock-converse-stream"], "BedrockTransport")
    }

    func testGeneratedModelRegistryMetadata() throws {
        XCTAssertEqual(BuiltinModels.upstreamVersion, "0.80.3")
        XCTAssertEqual(BuiltinModels.modelCount, 1029)
        XCTAssertEqual(BuiltinModels.providerCount, 35)
        let models = try BuiltinModels.all()
        XCTAssertEqual(models.count, 1029)
        XCTAssertTrue(models.contains { $0.provider == .openAI && $0.id == "gpt-4.1" })
        XCTAssertTrue(models.contains { $0.provider == .githubCopilot })
    }

    func testXiaomiMiMoModelPlacement() throws {
        let models = try BuiltinModels.all()
        XCTAssertNotNil(models.first { $0.provider == .xiaomi && $0.id == "mimo-v2-flash" })
        for provider in [Provider.xiaomiTokenPlanCN, .xiaomiTokenPlanAMS, .xiaomiTokenPlanSGP] {
            XCTAssertFalse(models.contains { $0.provider == provider && $0.id == "mimo-v2-flash" }, provider.rawValue)
        }
    }

    func testGeneratedImageModelRegistryMetadata() throws {
        XCTAssertEqual(BuiltinImageModels.upstreamVersion, "0.80.3")
        XCTAssertEqual(BuiltinImageModels.modelCount, 35)
        XCTAssertEqual(BuiltinImageModels.providerCount, 1)
        let models = try BuiltinImageModels.all()
        XCTAssertEqual(models.count, 35)
        XCTAssertTrue(models.contains { $0.provider == .openRouter && $0.api == .openRouterImages })
    }

    func testOpenRouterImageResponseParser() throws {
        let model = ImagesModel(id: "image-model", name: "Image Model", api: .openRouterImages, provider: .openRouter, cost: ModelCost(input: 1, output: 1))
        let json = """
        {"id":"r","choices":[{"message":{"content":"caption","images":[{"image_url":{"url":"data:image/png;base64,abc"}},{"image_url":"data:image/jpeg;base64,def"}]}}],"usage":{"prompt_tokens":1000,"completion_tokens":1000,"total_tokens":2000}}
        """.data(using: .utf8)!
        let result = try OpenRouterImagesProvider.parseResponseData(json, model: model)
        XCTAssertEqual(result.responseId, "r")
        XCTAssertEqual(result.stopReason, .stop)
        XCTAssertEqual(result.output.count, 3)
        XCTAssertEqual(result.output[0], ImageOutput(type: "text", text: "caption"))
        XCTAssertEqual(result.output[1], ImageOutput(type: "image", data: "abc", mimeType: "image/png"))
        XCTAssertEqual(result.output[2].mimeType, "image/jpeg")
        XCTAssertEqual(result.usage?.cost.total ?? -1, 0.002, accuracy: 0.0000001)
    }

    func testOpenRouterImagePayloadBuilder() throws {
        let model = ImagesModel(id: "image-model", name: "Image Model", api: .openRouterImages, provider: .openRouter, output: ["image", "text"])
        let payload = OpenRouterImagesProvider.buildImagesPayload(model: model, context: ImagesContext(input: [.text("draw"), .image(data: "abc", mimeType: "image/png")]))
        guard case .object(let object) = payload else { return XCTFail("expected object") }
        XCTAssertEqual(object["model"], .string("image-model"))
        XCTAssertEqual(object["stream"], .bool(false))
        guard case .array(let modalities)? = object["modalities"] else { return XCTFail("missing modalities") }
        XCTAssertEqual(modalities, [.string("image"), .string("text")])
        guard case .array(let messages)? = object["messages"], case .object(let message) = messages[0], case .array(let content)? = message["content"] else { return XCTFail("missing message content") }
        XCTAssertEqual(message["role"], .string("user"))
        XCTAssertEqual(content.first, .object(["type": .string("text"), "text": .string("draw")]))
    }

    func testCloudflareBaseURLHelpers() {
        let model = Model(id: "cf", name: "CF", api: .openAICompletions, provider: .cloudflareWorkersAI, baseUrl: "https://api.cloudflare.com/client/v4/accounts/{CLOUDFLARE_ACCOUNT_ID}/ai/v1")
        XCTAssertTrue(AIUtilities.isCloudflareProvider(.cloudflareWorkersAI))
        XCTAssertEqual(AIUtilities.resolveCloudflareBaseURL(model: model, env: ["CLOUDFLARE_ACCOUNT_ID": "acct"]), "https://api.cloudflare.com/client/v4/accounts/acct/ai/v1")
    }

    func testHashAndSanitizeUtilities() {
        XCTAssertEqual(AIUtilities.shortHash("abc"), AIUtilities.shortHash("abc"))
        XCTAssertEqual(AIUtilities.shortHash("abc").count, 16)
        let emojiText = "Mario Zechner wann? Wo? Bin grad äußersr eventuninformiert 🙈 こんにちは 你好 ∑∫∂√"
        XCTAssertEqual(AIUtilities.sanitizeSurrogates(emojiText), emojiText)
        XCTAssertEqual(AIUtilities.sanitizeSurrogates("ok\u{FFFD}"), "ok")
        var toolResult = Message(role: .toolResult, content: [.text(emojiText + "\u{FFFD}")])
        toolResult.toolCallId = "call_1"
        toolResult.toolName = "test_tool"
        let model = Model(id: "gpt", name: "GPT", api: .openAICompletions, provider: .openAI)
        let body = OpenAICompletionsProvider.buildRequestBody(model: model, context: AIContext(messages: [toolResult]), options: nil)
        guard case .array(let messages)? = body["messages"], case .object(let message) = messages[0] else { return XCTFail("missing message") }
        XCTAssertEqual(message["content"], .string(emojiText))
    }

    func testAuthHeaderAndMergeHelpers() {
        XCTAssertTrue(AIUtilities.hasOpenAIAuthHeader(["Authorization": "Bearer token"]))
        XCTAssertTrue(AIUtilities.hasOpenAIAuthHeader(["cf-aig-authorization": "Bearer token"]))
        XCTAssertFalse(AIUtilities.hasOpenAIAuthHeader(["Authorization": "  "]))
        XCTAssertTrue(AIUtilities.hasAnthropicAuthHeader(["X-Api-Key": "key"]))
        XCTAssertTrue(AIUtilities.hasAnthropicAuthHeader(["authorization": "Bearer key"]))
        XCTAssertFalse(AIUtilities.hasAnthropicAuthHeader(["X-Api-Key": ""] ))
        let merged = AIUtilities.mergeHeaders(defaults: ["a": "default", "b": "default", "empty": "default"], provider: ["b": "provider"], explicit: ["b": "explicit", "empty": ""])
        XCTAssertEqual(merged["a"], "default")
        XCTAssertEqual(merged["b"], "explicit")
        XCTAssertEqual(merged["empty"], "")
    }

    func testCopilotAndSessionHeaders() {
        XCTAssertEqual(AIUtilities.inferCopilotInitiator([.user("hi")]), "user")
        var assistant = Message(role: .assistant, content: [.text("ok")])
        XCTAssertEqual(AIUtilities.inferCopilotInitiator([assistant]), "agent")
        XCTAssertEqual(AIUtilities.buildCopilotDynamicHeaders([Message(role: .user, content: [.image(data: "x", mimeType: "image/png")])])["Copilot-Vision-Request"], "true")
        XCTAssertEqual(AIUtilities.copilotHeaders(intent: "chat")["openai-intent"], "chat")
        XCTAssertEqual(AIUtilities.azureSessionHeaders("s")["x-ms-client-request-id"], "s")
    }

    func testPartialJSONParser() {
        XCTAssertEqual(PartialJSONParser.closeJSON("{\"a\": [1"), "{\"a\": [1]}")
        XCTAssertEqual(PartialJSONParser.parseObject("{\"q\": \"hel")?["q"], .string("hel"))
        XCTAssertEqual(PartialJSONParser.parseObject("{\"n\": 1}")?["n"], .number(1))
        XCTAssertNil(PartialJSONParser.parseObject(""))
    }

    func testProviderEnvironmentResolution() {
        XCTAssertEqual(ProviderEnvironment.apiKey(for: .anthropic, env: ["ANTHROPIC_OAUTH_TOKEN": "oauth", "ANTHROPIC_API_KEY": "api"]), "oauth")
        XCTAssertEqual(ProviderEnvironment.apiKey(for: .openRouter, env: ["OPENROUTER_API_KEY": "router"]), "router")
        XCTAssertEqual(ProviderEnvironment.apiKey(for: .amazonBedrock, env: ["AWS_PROFILE": "default"]), "<authenticated>")
        XCTAssertEqual(ProviderEnvironment.envFallbackName(.zaiCodingCN), "ZAI_CODING_CN_API_KEY")
        var options = StreamOptions()
        options.apiKey = "explicit"
        let model = Model(id: "x", name: "x", api: .openAICompletions, provider: .openAI)
        XCTAssertEqual(ProviderEnvironment.resolveAPIKey(model: model, options: options), "explicit")
        XCTAssertEqual(ProviderEnvironment.resolveCacheRetention(nil, env: ["PI_CACHE_RETENTION": "long"]), .long)
    }

    func testThinkingAndCostNilSafety() {
        XCTAssertEqual(AIUtilities.mapThinkingLevel(model: nil, level: .off), "none")
        XCTAssertEqual(AIUtilities.calculateCost(model: nil, usage: Usage()).total, 0)
        let adjusted = AIUtilities.adjustMaxTokensForThinking(baseMaxTokens: 0, modelMaxTokens: 512, level: .high)
        XCTAssertEqual(adjusted.maxTokens, 512)
        XCTAssertEqual(adjusted.thinkingBudget, 0)
    }

    func testUpstreamSupportedThinkingLevels() throws {
        let models = try BuiltinModels.all()
        func model(_ provider: Provider, _ id: String) throws -> Model {
            try XCTUnwrap(models.first { $0.provider == provider && $0.id == id }, "missing \(provider.rawValue)/\(id)")
        }
        XCTAssertTrue(AIUtilities.supportedThinkingLevels(model: try model(.anthropic, "claude-opus-4-6")).contains(.xhigh))
        XCTAssertTrue(AIUtilities.supportedThinkingLevels(model: try model(.anthropic, "claude-opus-4-8")).contains(.xhigh))
        let fable = AIUtilities.supportedThinkingLevels(model: try model(.anthropic, "claude-fable-5"))
        XCTAssertTrue(fable.contains(.xhigh))
        XCTAssertTrue(AIUtilities.supportedThinkingLevels(model: try model(.openAI, "gpt-5.5-pro")).contains(.xhigh))
        XCTAssertTrue(AIUtilities.supportedThinkingLevels(model: try model(.openRouter, "openai/gpt-5.5-pro")).contains(.xhigh))
        XCTAssertTrue(AIUtilities.supportedThinkingLevels(model: try model(.deepSeek, "deepseek-v4-flash")).contains(.xhigh))
        XCTAssertTrue(AIUtilities.supportedThinkingLevels(model: try model(.openCodeGo, "deepseek-v4-flash")).contains(.xhigh))
        XCTAssertFalse(AIUtilities.supportedThinkingLevels(model: try model(.openCodeGo, "kimi-k2.6")).contains(.xhigh))
        XCTAssertFalse(AIUtilities.supportedThinkingLevels(model: try model(.moonshotAI, "kimi-k2.7-code")).isEmpty)
        XCTAssertFalse(AIUtilities.supportedThinkingLevels(model: try model(.moonshotAICN, "kimi-k2.7-code")).isEmpty)
        XCTAssertFalse(AIUtilities.supportedThinkingLevels(model: try model(.openCode, "grok-build-0.1")).isEmpty)
        XCTAssertTrue(AIUtilities.supportedThinkingLevels(model: try model(.openRouter, "deepseek/deepseek-v4-flash")).contains(.xhigh))
        XCTAssertTrue(AIUtilities.supportedThinkingLevels(model: try model(.openRouter, "anthropic/claude-opus-4.6")).contains(.xhigh))
        let bedrockFable = AIUtilities.supportedThinkingLevels(model: try model(.amazonBedrock, "global.anthropic.claude-fable-5"))
        XCTAssertTrue(bedrockFable.contains(.xhigh))
    }

    func testThinkingHelpers() {
        let low = "low"
        let high = "high"
        let model = Model(id: "reasoner", name: "Reasoner", api: .openAICompletions, provider: .openAI, reasoning: true, thinkingLevelMap: [.low: low, .high: high, .xhigh: nil])
        XCTAssertEqual(AIUtilities.supportedThinkingLevels(model: nil), [.off])
        XCTAssertEqual(AIUtilities.clampReasoning(.xhigh), .high)
        XCTAssertEqual(AIUtilities.clampThinkingLevel(model: model, level: .minimal), .low)
        XCTAssertEqual(AIUtilities.mapThinkingLevel(model: model, level: .low), "low")
        XCTAssertFalse(AIUtilities.supportsXHigh(model: model))
        let adjusted = AIUtilities.adjustMaxTokensForThinking(baseMaxTokens: 1000, modelMaxTokens: 2500, level: .low)
        XCTAssertEqual(adjusted.maxTokens, 2500)
        XCTAssertEqual(adjusted.thinkingBudget, 2048)
    }

    func testContextOverflowDiagnosticsNilSafety() {
        XCTAssertFalse(ContextUtilities.isContextOverflow(nil, contextWindow: 0))
        var message = Message(role: .assistant, content: [])
        message.stopReason = .error
        message.diagnostics = [AssistantMessageDiagnostic(type: "error", timestamp: 0, error: DiagnosticError(message: "model_context_window_exceeded", code: .string("context_length_exceeded")))]
        XCTAssertTrue(ContextUtilities.isContextOverflow(message, contextWindow: 0))
    }

    func testToolValidationCoercionParity() throws {
        func tool(_ schema: JSONValue, _ value: JSONValue) -> (Tool, [String: JSONValue]) {
            (Tool(name: "echo", description: "Echo", parameters: .object(["type": .string("object"), "properties": .object(["value": schema]), "required": .array([.string("value")])])), ["value": value])
        }
        let passing: [(JSONValue, JSONValue, JSONValue)] = [
            (.object(["type": .string("number")]), .string("42"), .number(42)),
            (.object(["type": .string("number")]), .bool(true), .number(1)),
            (.object(["type": .string("number")]), .null, .number(0)),
            (.object(["type": .string("integer")]), .string("42"), .number(42)),
            (.object(["type": .string("boolean")]), .string("true"), .bool(true)),
            (.object(["type": .string("boolean")]), .string("false"), .bool(false)),
            (.object(["type": .string("boolean")]), .number(1), .bool(true)),
            (.object(["type": .string("boolean")]), .number(0), .bool(false)),
            (.object(["type": .string("string")]), .null, .string("")),
            (.object(["type": .string("string")]), .bool(true), .string("true")),
            (.object(["type": .string("null")]), .string(""), .null),
            (.object(["type": .string("null")]), .number(0), .null),
            (.object(["type": .string("null")]), .bool(false), .null),
            (.object(["type": .array([.string("number"), .string("string")])]), .string("1"), .string("1")),
            (.object(["type": .array([.string("boolean"), .string("number")])]), .string("1"), .number(1))
        ]
        for (schema, input, expected) in passing {
            let (t, args) = tool(schema, input)
            XCTAssertEqual(try ContextUtilities.validateToolArguments(tool: t, arguments: args), ["value": expected])
        }
        for (schema, input) in [
            (JSONValue.object(["type": .string("boolean")]), JSONValue.string("1")),
            (.object(["type": .string("boolean")]), .string("0")),
            (.object(["type": .string("null")]), .string("null")),
            (.object(["type": .string("integer")]), .string("42.1"))
        ] {
            let (t, args) = tool(schema, input)
            XCTAssertThrowsError(try ContextUtilities.validateToolArguments(tool: t, arguments: args))
        }
    }

    func testContextOverflowAndToolValidation() throws {
        var overflow = Message(role: .assistant, content: [])
        overflow.stopReason = .error
        overflow.errorMessage = "input token count exceeds the maximum"
        XCTAssertTrue(ContextUtilities.isContextOverflow(overflow, contextWindow: 0))
        overflow.errorMessage = "rate limit: too many requests"
        XCTAssertFalse(ContextUtilities.isContextOverflow(overflow, contextWindow: 0))
        var usage = Usage()
        usage.input = 100
        usage.cacheRead = 1
        var stop = Message(role: .assistant, content: [])
        stop.stopReason = .stop
        stop.usage = usage
        XCTAssertTrue(ContextUtilities.isContextOverflow(stop, contextWindow: 50))

        let schema: JSONValue = .object([
            "type": .string("object"),
            "required": .array([.string("q")]),
            "properties": .object([
                "q": .object(["type": .string("string"), "enum": .array([.string("ok")])]),
                "n": .object(["type": .string("integer")])
            ])
        ])
        let tool = Tool(name: "lookup", description: "lookup", parameters: schema)
        XCTAssertNoThrow(try ContextUtilities.validateToolArguments(tool: tool, arguments: ["q": .string("ok"), "n": .number(1)]))
        XCTAssertThrowsError(try ContextUtilities.validateToolArguments(tool: tool, arguments: ["n": .number(1)]))
        XCTAssertThrowsError(try ContextUtilities.validateToolArguments(tool: tool, arguments: ["q": .string("bad")]))
        XCTAssertThrowsError(try ContextUtilities.validateToolArguments(tool: tool, arguments: ["q": .string("ok"), "n": .number(1.5)]))
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

    func testRegistryClearAndUnregister() async {
        await AIRegistry.shared.clearModels()
        await AIRegistry.shared.clearProviders()
        let initialModels = await AIRegistry.shared.listModels()
        let initialProviders = await AIRegistry.shared.listProviders()
        XCTAssertTrue(initialModels.isEmpty)
        XCTAssertTrue(initialProviders.isEmpty)
        let model = Model(id: "m", name: "M", api: .faux, provider: .faux)
        await AIRegistry.shared.register(model)
        let foundModel = await AIRegistry.shared.model(provider: .faux, id: "m")
        let fauxCount = await AIRegistry.shared.listModels(provider: .faux).count
        XCTAssertEqual(foundModel, model)
        XCTAssertEqual(fauxCount, 1)
        await AIRegistry.shared.register(APIProvider(api: .faux, stream: { _, _, _ in AsyncStream { $0.finish() } }))
        let provider = await AIRegistry.shared.apiProvider(for: .faux)
        XCTAssertNotNil(provider)
        await AIRegistry.shared.unregister(api: .faux)
        let removedProvider = await AIRegistry.shared.apiProvider(for: .faux)
        XCTAssertNil(removedProvider)
        await AIRegistry.shared.clearModels()
        let removedModel = await AIRegistry.shared.model(provider: .faux, id: "m")
        XCTAssertNil(removedModel)
        await SwiftAI.bootstrap()
    }

    func testLoggerRegistrySetAndReset() async {
        await LoggerRegistry.shared.setLogger(nil)
        let defaultLogger = await LoggerRegistry.shared.current()
        XCTAssertTrue(defaultLogger is DiscardLogger)
        defaultLogger.info("discarded", [:])
        await LoggerRegistry.shared.setLogger(DiscardLogger())
        let logger = await LoggerRegistry.shared.current()
        logger.info("ok", [:])
        await LoggerRegistry.shared.setLogger(nil)
        let reset = await LoggerRegistry.shared.current()
        XCTAssertTrue(reset is DiscardLogger)
        reset.warn("ok", [:])
        let defaultStderr = StderrLogger()
        XCTAssertEqual(defaultStderr.level, .info)
        let warnLogger = StderrLogger(level: .warn)
        XCTAssertFalse(warnLogger.shouldEmit(.debug))
        XCTAssertFalse(warnLogger.shouldEmit(.info))
        XCTAssertTrue(warnLogger.shouldEmit(.warn))
        XCTAssertTrue(warnLogger.shouldEmit(.error))
        XCTAssertFalse(StderrLogger(level: .off).shouldEmit(.error))
    }

    func testAppendAssistantMessageAndGetTextContent() {
        var context = AIContext(messages: [])
        let assistant = Message(role: .assistant, content: [.text("hello"), .text(" world")])
        Harness.appendAssistantMessage(assistant, to: &context)
        XCTAssertEqual(context.messages.count, 1)
        XCTAssertEqual(Harness.textContent(in: context.messages[0]), "hello world")
    }

    func testAppendAssistantMessageNilSafe() {
        var context = AIContext(messages: [])
        Harness.appendAssistantMessage(nil, to: &context)
        XCTAssertTrue(context.messages.isEmpty)
    }

    func testHarnessHelpers() throws {
        var context = AIContext(systemPrompt: "system", messages: [.user("one"), .user("two")], tools: [Tool(name: "t", description: "d", parameters: .object(["type": .string("object")]))])
        let clone = Harness.cloneContext(context)
        XCTAssertEqual(clone, context)
        XCTAssertGreaterThan(Harness.estimateTokens(context), 0)
        let model = Model(id: "small", name: "Small", api: .openAICompletions, provider: .openAI, contextWindow: 1)
        XCTAssertFalse(Harness.fitsInContextWindow(context, model: model).fits)
        XCTAssertEqual(Harness.compactContext(context, model: model, keepRecent: 1)?.messages.count, 1)
        Harness.appendUserMessage("three", to: &context)
        XCTAssertEqual(context.messages.last?.content.first?.text, "three")
        Harness.appendToolResult(toolCallId: "c", toolName: "tool", text: "result", isError: false, to: &context)
        XCTAssertEqual(context.messages.last?.role, .toolResult)
        var assistant = Message(role: .assistant, content: [.toolCall(id: "c", name: "tool", arguments: [:])])
        assistant.stopReason = .toolUse
        XCTAssertTrue(Harness.needsToolExecution(assistant))
        XCTAssertEqual(Harness.toolCalls(in: assistant).count, 1)
    }

    func testStreamAndImageOptionHooks() async throws {
        let model = Model(id: "m", name: "M", api: .openAICompletions, provider: .openAI)
        var options = StreamOptions()
        options.onPayload = { payload, receivedModel in
            XCTAssertEqual(receivedModel.id, model.id)
            var next = payload
            next["hooked"] = .bool(true)
            return next
        }
        options.onResponse = { response, receivedModel in
            XCTAssertEqual(response.status, 200)
            XCTAssertEqual(receivedModel.id, model.id)
        }
        let payload = try await XCTUnwrap(options.onPayload)(["x": .number(1)], model)
        XCTAssertEqual(payload["hooked"], .bool(true))
        if let onResponse = options.onResponse { await onResponse(HTTPResponseMetadata(status: 200, headers: ["h": "v"]), model) }

        let imageModel = ImagesModel(id: "img", name: "Image", api: .openRouterImages, provider: .openRouter)
        var imageOptions = ImagesOptions()
        imageOptions.onPayload = { payload, receivedModel in
            XCTAssertEqual(receivedModel.id, imageModel.id)
            var next = payload
            next["imageHooked"] = .bool(true)
            return next
        }
        imageOptions.onResponse = { response, receivedModel in
            XCTAssertEqual(response.status, 201)
            XCTAssertEqual(receivedModel.id, imageModel.id)
        }
        let imagePayload = try await XCTUnwrap(imageOptions.onPayload)(["x": .string("y")], imageModel)
        XCTAssertEqual(imagePayload["imageHooked"], .bool(true))
        if let onResponse = imageOptions.onResponse { await onResponse(ImagesResponseMetadata(status: 201, headers: [:]), imageModel) }
    }

    func testOpenRouterImageAPIKeyResolution() {
        XCTAssertEqual(ProviderEnvironment.apiKey(for: .openRouter, env: ["OPENROUTER_API_KEY": "env-key"]), "env-key")
        var options = ImagesOptions()
        options.apiKey = "explicit"
        XCTAssertEqual(options.apiKey, "explicit")
    }

    func testOpenAICompletionsAnthropicCacheControlFormat() {
        var compat = OpenAICompletionsCompat(); compat.cacheControlFormat = "anthropic"
        let model = Model(id: "custom-qwen", name: "Custom Qwen", api: .openAICompletions, provider: .openRouter, baseUrl: "https://example.com/v1", completionsCompat: compat)
        let tool = Tool(name: "read", description: "Read", parameters: .object(["type": .string("object")]))
        let body = OpenAICompletionsProvider.buildRequestBody(model: model, context: AIContext(systemPrompt: "System prompt", messages: [.user("Hello")], tools: [tool]), options: nil)
        guard case .array(let messages)? = body["messages"], case .object(let system) = messages[0], case .array(let systemContent)? = system["content"], case .object(let systemPart) = systemContent[0], case .array(let tools)? = body["tools"], case .object(let toolObj) = tools[0], case .object(let lastUser) = messages.last, case .array(let userContent)? = lastUser["content"], case .object(let userPart) = userContent[0] else { return XCTFail("missing cache markers") }
        XCTAssertEqual(systemPart["cache_control"], .object(["type": .string("ephemeral")]))
        XCTAssertEqual(toolObj["cache_control"], .object(["type": .string("ephemeral")]))
        XCTAssertEqual(userPart["cache_control"], .object(["type": .string("ephemeral")]))
        var options = StreamOptions(); options.cacheRetention = CacheRetention.none
        let none = OpenAICompletionsProvider.buildRequestBody(model: model, context: AIContext(systemPrompt: "System prompt", messages: [.user("Hello")], tools: [tool]), options: options)
        guard case .array(let noneMessages)? = none["messages"], case .object(let noneSystem) = noneMessages[0] else { return XCTFail("missing none system") }
        XCTAssertEqual(noneSystem["content"], .string("System prompt"))
    }

    func testOpenAICompletionsPromptCacheParity() {
        var options = StreamOptions(); options.sessionId = "session-123"
        var openAICompat = OpenAICompletionsCompat(); openAICompat.supportsLongCacheRetention = true
        let openAI = Model(id: "gpt", name: "GPT", api: .openAICompletions, provider: .openAI, baseUrl: "https://api.openai.com/v1", completionsCompat: openAICompat)
        let direct = OpenAICompletionsProvider.buildRequestBody(model: openAI, context: AIContext(messages: [.user("hi")]), options: options)
        XCTAssertEqual(direct["prompt_cache_key"], .string("session-123"))
        XCTAssertNil(direct["prompt_cache_retention"])
        options.cacheRetention = .long
        let long = OpenAICompletionsProvider.buildRequestBody(model: openAI, context: AIContext(messages: [.user("hi")]), options: options)
        XCTAssertEqual(long["prompt_cache_key"], .string("session-123"))
        XCTAssertEqual(long["prompt_cache_retention"], .string("24h"))
        options.cacheRetention = CacheRetention.none
        let none = OpenAICompletionsProvider.buildRequestBody(model: openAI, context: AIContext(messages: [.user("hi")]), options: options)
        XCTAssertNil(none["prompt_cache_key"])
        XCTAssertNil(none["prompt_cache_retention"])
        var proxyCompat = OpenAICompletionsCompat(); proxyCompat.supportsLongCacheRetention = false
        options.cacheRetention = .long
        let proxy = Model(id: "proxy", name: "Proxy", api: .openAICompletions, provider: .openRouter, baseUrl: "https://proxy.example.com/v1", completionsCompat: proxyCompat)
        let proxyBody = OpenAICompletionsProvider.buildRequestBody(model: proxy, context: AIContext(messages: [.user("hi")]), options: options)
        XCTAssertNil(proxyBody["prompt_cache_key"])
        XCTAssertNil(proxyBody["prompt_cache_retention"])
    }

    func testEnvDrivenPromptCacheRetention() {
        var options = StreamOptions()
        options.sessionId = String(repeating: "s", count: 80)
        options.env = ["PI_CACHE_RETENTION": "long"]
        var compat = OpenAICompletionsCompat()
        compat.supportsLongCacheRetention = true
        let chatModel = Model(id: "chat", name: "Chat", api: .openAICompletions, provider: .openAI, completionsCompat: compat)
        let chatBody = OpenAICompletionsProvider.buildRequestBody(model: chatModel, context: AIContext(messages: [.user("hi")]), options: options)
        XCTAssertEqual((chatBody["prompt_cache_key"]?.stringValue ?? "").count, 64)
        XCTAssertEqual(chatBody["prompt_cache_retention"], .string("24h"))
        let responsesModel = Model(id: "resp", name: "Resp", api: .openAIResponses, provider: .openAI)
        let responsesBody = OpenAIResponsesProvider.buildRequestBody(model: responsesModel, context: AIContext(messages: [.user("hi")]), options: options)
        XCTAssertEqual(responsesBody["prompt_cache_retention"], .string("24h"))
        let cloudflare = Model(id: "cf", name: "CF", api: .openAIResponses, provider: .cloudflareAIGateway)
        let cloudflareBody = OpenAIResponsesProvider.buildRequestBody(model: cloudflare, context: AIContext(messages: [.user("hi")]), options: options)
        XCTAssertNil(cloudflareBody["prompt_cache_retention"])
    }

    func testPromptCacheAndSessionResources() async throws {
        XCTAssertEqual(PromptCache.clampOpenAIKey(String(repeating: "x", count: 80)).count, 64)
        let registry = SessionResourceRegistry.shared
        let box = CleanupBox()
        let unregister = await registry.register { sessionId in await box.append(sessionId) }
        try await registry.cleanup(sessionId: "s1")
        let firstCleanupValues = await box.values()
        XCTAssertEqual(firstCleanupValues, ["s1"])
        await unregister()
        try await registry.cleanup(sessionId: "s2")
        let secondCleanupValues = await box.values()
        XCTAssertEqual(secondCleanupValues, ["s1"])
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
        let imageModel = ImagesModel(id: "img", name: "Image", api: .openRouterImages, provider: .openRouter, cost: ModelCost(input: 2, output: 4))
        var imageUsage = Usage(); imageUsage.input = 1000; imageUsage.output = 1000
        XCTAssertEqual(AIUtilities.calculateCost(imageModel: imageModel, usage: imageUsage).total, 0.006, accuracy: 0.0000001)
    }

    func testFauxProviderHelpers() async throws {
        let text = FauxProvider.textMessage("hello world")
        XCTAssertEqual(text.content.first?.text, "hello world")
        let thinking = FauxProvider.thinkingMessage(thinking: "why", text: "answer")
        XCTAssertEqual(thinking.content.first?.type, "thinking")
        let tool = FauxProvider.toolCallMessage(name: "lookup", arguments: ["q": .string("x")])
        XCTAssertEqual(tool.stopReason, .toolUse)
        XCTAssertTrue(Harness.hasToolCalls(tool))

        let registration = await FauxProvider.register()
        await registration.setResponses([.message(text)])
        guard let model = await registration.model() else { return XCTFail("missing faux model") }
        let message = try await SwiftAI.complete(model: model, context: AIContext(messages: [.user("hi")]))
        XCTAssertEqual(message.content.first?.text, "hello world")
        let pendingAfterFauxMessage = await registration.pendingResponseCount()
        XCTAssertEqual(pendingAfterFauxMessage, 0)
    }

    func testFauxProviderMultipleModelsAndQueueExhaustion() async throws {
        let registration = await FauxProvider.register(options: FauxOptions(models: [
            FauxModelDef(id: "faux-fast", name: "Faux Fast", reasoning: false),
            FauxModelDef(id: "faux-thinker", name: "Faux Thinker", reasoning: true)
        ]))
        await registration.setResponses([
            .factory { _, _, state in FauxProvider.textMessage("fast:\(state.callCount)") },
            .factory { _, _, state in FauxProvider.textMessage("thinker:\(state.callCount)") }
        ])
        XCTAssertEqual(registration.models.map(\.id), ["faux-fast", "faux-thinker"])
        let defaultFaux = await registration.model()
        let fastFaux = await registration.model(id: "faux-fast")
        let thinkerFaux = await registration.model(id: "faux-thinker")
        XCTAssertEqual(defaultFaux?.id, "faux-fast")
        XCTAssertEqual(fastFaux?.reasoning, false)
        XCTAssertEqual(thinkerFaux?.reasoning, true)
        let fast = try await SwiftAI.complete(model: registration.models[0], context: AIContext(messages: [.user("hi")]))
        let thinker = try await SwiftAI.complete(model: registration.models[1], context: AIContext(messages: [.user("hi")]))
        XCTAssertEqual(fast.content, [.text("fast:1")])
        XCTAssertEqual(thinker.content, [.text("thinker:2")])
        do {
            _ = try await SwiftAI.complete(model: registration.models[0], context: AIContext(messages: [.user("hi")]))
            XCTFail("expected exhausted faux queue error")
        } catch {
            XCTAssertTrue(String(describing: error).contains("No more faux responses queued"))
        }
        let exhaustedPending = await registration.pendingResponseCount()
        let exhaustedState = await registration.state
        XCTAssertEqual(exhaustedPending, 0)
        XCTAssertEqual(exhaustedState.callCount, 3)
    }

    func testFauxThinkingToolFactoryMultipleAndError() async throws {
        let registration = await FauxProvider.register()
        await registration.setResponses([
            .message(FauxProvider.thinkingMessage(thinking: "why", text: "answer")),
            .message(FauxProvider.toolCallMessage(name: "lookup", arguments: ["q": .string("x")])),
            .factory { _, _, state in FauxProvider.textMessage("call #\(state.callCount)") },
            .message(FauxProvider.errorMessage("boom"))
        ])
        guard let model = await registration.model() else { return XCTFail("missing faux model") }
        let first = try await SwiftAI.complete(model: model, context: AIContext())
        XCTAssertEqual(first.content.first?.thinking, "why")
        let second = try await SwiftAI.complete(model: model, context: AIContext())
        XCTAssertEqual(second.stopReason, .toolUse)
        XCTAssertTrue(Harness.needsToolExecution(second))
        let third = try await SwiftAI.complete(model: model, context: AIContext())
        XCTAssertEqual(third.content.first?.text, "call #3")
        do {
            _ = try await SwiftAI.complete(model: model, context: AIContext())
            XCTFail("expected faux error")
        } catch {
            XCTAssertTrue(String(describing: error).contains("boom"))
        }
        let pendingAfterError = await registration.pendingResponseCount()
        XCTAssertEqual(pendingAfterError, 0)
    }

    func testFauxProviderTokenCacheAndToolDeltas() async throws {
        let registration = await FauxProvider.register()
        await registration.setResponses([
            .message(FauxProvider.textMessage("first")),
            .message(FauxProvider.textMessage("second")),
            .message(FauxProvider.textMessage("third")),
            .message(FauxProvider.toolCallMessage(name: "echo", arguments: ["text": .string("abcdefghijklmnopqrstuvwxyz"), "count": .number(12)]))
        ])
        guard let model = await registration.model() else { return XCTFail("missing faux model") }
        var context = AIContext(systemPrompt: "Be concise.", messages: [.user("hello")])
        var options = StreamOptions(); options.sessionId = "session-1"; options.cacheRetention = .short
        let first = try await SwiftAI.complete(model: model, context: context, options: options)
        XCTAssertGreaterThan(first.usage?.input ?? 0, 0)
        XCTAssertGreaterThan(first.usage?.output ?? 0, 0)
        XCTAssertEqual(first.usage?.cacheRead, 0)
        XCTAssertGreaterThan(first.usage?.cacheWrite ?? 0, 0)
        context.messages.append(first)
        context.messages.append(.user("follow up"))
        let second = try await SwiftAI.complete(model: model, context: context, options: options)
        XCTAssertGreaterThan(second.usage?.cacheRead ?? 0, 0)
        options.sessionId = "session-2"
        let third = try await SwiftAI.complete(model: model, context: context, options: options)
        XCTAssertEqual(third.usage?.cacheRead, 0)
        XCTAssertGreaterThan(third.usage?.cacheWrite ?? 0, 0)

        var deltas: [String] = []
        var eventTypes: [String] = []
        for await event in await SwiftAI.stream(model: model, context: AIContext(messages: [.user("tool")])) {
            switch event {
            case .start: eventTypes.append("start")
            case .toolCallStart: eventTypes.append("toolcall_start")
            case .toolCallDelta(_, let delta, _): eventTypes.append("toolcall_delta"); deltas.append(delta)
            case .toolCallEnd: eventTypes.append("toolcall_end")
            case .done: eventTypes.append("done")
            default: break
            }
        }
        XCTAssertTrue(eventTypes.contains("toolcall_start"))
        XCTAssertTrue(eventTypes.contains("toolcall_delta"))
        XCTAssertTrue(eventTypes.contains("toolcall_end"))
        XCTAssertGreaterThan(deltas.count, 1)
        XCTAssertTrue(deltas.joined().contains("abcdefghijklmnopqrstuvwxyz"))
    }

    func testGoogleOAuthProviderShape() {
        let gemini = GoogleGeminiCLIOAuthProvider()
        let anti = GoogleAntigravityOAuthProvider()
        XCTAssertEqual(gemini.id, "google-gemini-cli")
        XCTAssertEqual(anti.id, "google-antigravity")
        let url = GoogleOAuthFlow.authorizationURL(challenge: "challenge")
        XCTAssertTrue(url.contains("code_challenge=challenge"))
        XCTAssertTrue(url.contains("access_type=offline"))
        let key = gemini.apiKey(credentials: OAuthCredentials(refresh: "r", access: "tok", expires: 0, extra: ["projectId": .string("project")]))
        XCTAssertTrue(key.contains("tok"))
        XCTAssertTrue(key.contains("project"))
    }

    func testAnthropicOAuthProviderShape() {
        let provider = AnthropicOAuthProvider()
        let url = provider.authorizationURL(challenge: "challenge")
        XCTAssertEqual(provider.id, "anthropic")
        XCTAssertTrue(url.contains("code_challenge=challenge"))
        XCTAssertTrue(url.contains("client_id="))
        XCTAssertTrue(url.contains("redirect_uri=http://localhost:53692/callback") || url.contains("redirect_uri=http%3A//localhost%3A53692/callback") || url.contains("redirect_uri=http%3A%2F%2Flocalhost%3A53692%2Fcallback"))
        let authFields = AnthropicOAuthProvider.authorizationCodeFields(clientID: "client", code: "manual-code", verifier: "verifier")
        XCTAssertEqual(authFields["redirect_uri"], AnthropicOAuthProvider.redirectURI)
        let refreshFields = AnthropicOAuthProvider.refreshTokenFields(clientID: "client", refreshToken: "refresh-token")
        XCTAssertEqual(refreshFields["grant_type"], "refresh_token")
        XCTAssertEqual(refreshFields["refresh_token"], "refresh-token")
        XCTAssertNil(refreshFields["scope"])
        XCTAssertEqual(provider.apiKey(credentials: OAuthCredentials(refresh: "r", access: "a", expires: 0)), "a")
    }

    func testOpenAICodexTokenRefreshFailureDoesNotWriteToStderr() {
        let body = #"{"error":{"message":"Could not validate your token. Please try signing in again.","type":"invalid_request_error"}}"#
        let message = OpenAICodexOAuthProvider.refreshFailureMessage(status: 401, body: body)
        XCTAssertTrue(message.contains("OpenAI Codex token refresh failed (401)"))
        XCTAssertTrue(message.contains("Could not validate your token"))
    }

    func testOpenAICodexOAuthDeviceCodeHelpers() throws {
        XCTAssertEqual(OpenAICodexOAuthProvider.deviceUserCodeURL, "https://auth.openai.com/api/accounts/deviceauth/usercode")
        XCTAssertEqual(OpenAICodexOAuthProvider.deviceTokenURL, "https://auth.openai.com/api/accounts/deviceauth/token")
        XCTAssertEqual(OpenAICodexOAuthProvider.accessTokenURL, "https://auth.openai.com/oauth/token")
        XCTAssertEqual(OpenAICodexOAuthProvider.codexDeviceVerificationURI, "https://auth.openai.com/codex/device")
        XCTAssertEqual(OpenAICodexOAuthProvider.deviceUserCodeBody(), ["client_id": .string("app_EMoamEEZ73f0CkXaXp7hrann")])
        XCTAssertEqual(OpenAICodexOAuthProvider.deviceTokenBody(deviceAuthID: "device-auth-id", userCode: "ABCD-1234"), ["device_auth_id": .string("device-auth-id"), "user_code": .string("ABCD-1234")])
        let fields = OpenAICodexOAuthProvider.authorizationCodeFields(code: "oauth-code", verifier: "device-code-verifier")
        XCTAssertEqual(fields["grant_type"], "authorization_code")
        XCTAssertEqual(fields["client_id"], "app_EMoamEEZ73f0CkXaXp7hrann")
        XCTAssertEqual(fields["code"], "oauth-code")
        XCTAssertEqual(fields["redirect_uri"], "https://auth.openai.com/deviceauth/callback")
        XCTAssertEqual(fields["code_verifier"], "device-code-verifier")
        let payload = #"{"https://api.openai.com/auth":{"chatgpt_account_id":"account-123"}}"#.data(using: .utf8)!.base64EncodedString()
        XCTAssertEqual(try OpenAICodexOAuthProvider.extractAccountID(from: "header.\(payload).signature"), "account-123")
    }

    func testCodexOAuthProviderShape() {
        let provider = OpenAICodexOAuthProvider()
        let creds = OAuthCredentials(refresh: "r", access: "a", expires: 0)
        XCTAssertEqual(provider.id, "openai-codex")
        XCTAssertEqual(provider.name, "OpenAI Codex")
        XCTAssertEqual(provider.apiKey(credentials: creds), "a")
        let models = [Model(id: "codex", name: "Codex", api: .openAICodexResponses, provider: .openAICodex)]
        XCTAssertEqual(provider.modifyModels(models, credentials: creds).count, 1)
    }

    func testOAuthDeviceCodePollingImmediateAndCancellation() async throws {
        final class Box: @unchecked Sendable { var polls = 0 }
        let box = Box()
        let token = try await OAuthDeviceCodePoller.poll(intervalSeconds: 30, expiresInSeconds: 60) {
            box.polls += 1
            return box.polls == 1 ? .complete("token") : .pending
        }
        XCTAssertEqual(token, "token")
        XCTAssertEqual(box.polls, 1)

        let task = Task {
            try await OAuthDeviceCodePoller.poll(intervalSeconds: 30, expiresInSeconds: 60) { OAuthDeviceCodePollStatus<String>.pending }
        }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("expected cancellation")
        } catch {
            XCTAssertTrue(String(describing: error).contains("Login cancelled") || error is CancellationError)
        }
    }

    func testOAuthPKCEAndCopilotHelpers() throws {
        let pair = try OAuthUtilities.generatePKCE()
        XCTAssertFalse(pair.verifier.isEmpty)
        XCTAssertFalse(pair.challenge.isEmpty)
        XCTAssertNotEqual(pair.verifier, pair.challenge)
        XCTAssertEqual(OAuthUtilities.normalizeDomain("https://company.ghe.com/"), "company.ghe.com")
        XCTAssertEqual(GitHubCopilotOAuthProvider.baseURL(token: "tid=abc;proxy-ep=proxy.individual.githubcopilot.com;sku=x"), "https://api.individual.githubcopilot.com")
        XCTAssertEqual(GitHubCopilotOAuthProvider.baseURL(token: "tid=abc;proxy-ep=proxy.enterprise.example;rest"), "https://api.enterprise.example")
        XCTAssertEqual(GitHubCopilotOAuthProvider.baseURL(token: "no-proxy-ep", enterpriseDomain: "company.ghe.com"), "https://copilot-api.company.ghe.com")
        XCTAssertEqual(GitHubCopilotOAuthProvider.baseURL(token: "no-proxy-ep"), "https://api.individual.githubcopilot.com")
        let provider = GitHubCopilotOAuthProvider()
        let models = [
            Model(id: "keep", name: "keep", api: .openAICompletions, provider: .githubCopilot),
            Model(id: "drop", name: "drop", api: .openAICompletions, provider: .githubCopilot),
            Model(id: "other", name: "other", api: .openAICompletions, provider: .openAI)
        ]
        let filtered = provider.modifyModels(models, credentials: OAuthCredentials(refresh: "r", access: "tid=abc;proxy-ep=proxy.business.githubcopilot.com;rest", expires: 0, extra: ["availableModelIds": .array([.string("keep")])]))
        XCTAssertEqual(filtered.map(\.id), ["keep", "other"])
        XCTAssertEqual(filtered.first?.baseUrl, "https://api.business.githubcopilot.com")
    }

    func testOAuthRegistryRoundTrip() async throws {
        await OAuthRegistry.shared.clear()
        let provider = OpenAICodexOAuthProvider()
        await OAuthRegistry.shared.register(provider)
        let registeredOAuthProvider = await OAuthRegistry.shared.provider(id: "openai-codex")
        let oauthProviderIDs = await OAuthRegistry.shared.listProviders().map(\.id)
        XCTAssertEqual(registeredOAuthProvider?.id, "openai-codex")
        XCTAssertEqual(oauthProviderIDs, ["openai-codex"])
        let creds = OAuthCredentials(refresh: "r", access: "access-token", expires: 0)
        let (_, key) = try await OAuthRegistry.shared.apiKey(id: "openai-codex", credentials: creds)
        XCTAssertEqual(key, "access-token")
        await OAuthRegistry.shared.clear()
        await SwiftAI.bootstrap()
    }

    func testRetryRunnerSuccessExhaustionAndCallback() async throws {
        final class Box: @unchecked Sendable { var attempts: [Int] = []; var callbacks: [Int] = [] }
        let box = Box()
        let result = try await RetryRunner.run(policy: RetryPolicy(maxRetries: 2, baseDelayMs: 0, jitterFraction: 0), sleep: { _ in }, onRetry: { attempt, _ in box.callbacks.append(attempt) }) { attempt in
            box.attempts.append(attempt)
            if attempt < 1 { throw AIError.provider("temporary") }
            return "ok"
        }
        XCTAssertEqual(result, "ok")
        XCTAssertEqual(box.attempts, [0, 1])
        XCTAssertEqual(box.callbacks, [1])

        let exhausted = Box()
        do {
            _ = try await RetryRunner.run(policy: RetryPolicy(maxRetries: 2, baseDelayMs: 0, jitterFraction: 0), sleep: { _ in }) { attempt -> String in
                exhausted.attempts.append(attempt)
                throw AIError.provider("still failing")
            }
            XCTFail("expected retry exhaustion")
        } catch {
            XCTAssertTrue(String(describing: error).contains("still failing"))
        }
        XCTAssertEqual(exhausted.attempts, [0, 1, 2])
    }

    func testRetryPolicy() throws {
        XCTAssertEqual(RetryPolicy(options: Optional<StreamOptions>.none).maxRetries, 0)
        var explicit = StreamOptions()
        explicit.maxRetries = 2
        let explicitPolicy = RetryPolicy(options: explicit)
        XCTAssertEqual(explicitPolicy.maxRetries, 2)
        XCTAssertEqual(RetryPolicy(maxRetries: -5).maxRetries, 0)
        var options = StreamOptions()
        options.maxRetryDelayMs = 1_000
        let policy = RetryPolicy(options: options)
        XCTAssertEqual(policy.maxRetries, 3)
        XCTAssertEqual(policy.maxRetryDelayMs, 1_000)
        XCTAssertGreaterThan(try policy.delayNanoseconds(attempt: 1), 0)
        XCTAssertThrowsError(try policy.delayMilliseconds(attempt: 1, retryAfterMs: 2_000))
        XCTAssertEqual(try RetryPolicy(maxRetries: 1, maxDelayMs: 10_000, baseDelayMs: 250, backoffMultiplier: 1, jitterFraction: 0).delayMilliseconds(attempt: 3), 250)
        XCTAssertEqual(HTTPRetry.retryAfterMs(headers: ["Retry-After": "2"]), 2_000)
        XCTAssertEqual(HTTPRetry.parseDurationMilliseconds("250ms"), 250)
        XCTAssertEqual(HTTPRetry.parseDurationMilliseconds("1.5s"), 1500)
        XCTAssertEqual(HTTPRetry.parseDurationMilliseconds("2m"), 120_000)
        XCTAssertEqual(HTTPRetry.parseDurationMilliseconds("1h"), 3_600_000)
        XCTAssertNil(HTTPRetry.parseDurationMilliseconds("bad"))
        XCTAssertTrue(HTTPRetry.shouldRetry(statusCode: 429, policy: policy))
        XCTAssertTrue(HTTPRetry.shouldRetry(statusCode: 500, policy: policy))
        XCTAssertTrue(HTTPRetry.shouldRetry(statusCode: 502, policy: policy))
        XCTAssertTrue(HTTPRetry.shouldRetry(statusCode: 503, policy: policy))
        XCTAssertTrue(HTTPRetry.shouldRetry(statusCode: 504, policy: policy))
        XCTAssertTrue(HTTPRetry.shouldRetry(statusCode: 429, policy: RetryPolicy(retryableStatuses: [429])))
        XCTAssertFalse(HTTPRetry.shouldRetry(statusCode: 501, policy: RetryPolicy(retryableStatuses: [429])))
        XCTAssertFalse(HTTPRetry.shouldRetry(statusCode: 400, policy: policy))
    }

    func testAzureReasoningEventNormalization() throws {
        let passthrough: [String: JSONValue] = ["type": .string("response.output_text.delta"), "delta": .string("hello")]
        XCTAssertEqual(AzureHelpers.normalizeReasoningEvent(passthrough), passthrough)
        let event: [String: JSONValue] = ["type": .string("response.reasoning_text.delta"), "delta": .string("why")]
        XCTAssertEqual(AzureHelpers.normalizeReasoningEvent(event)["type"], .string("response.reasoning_summary_text.delta"))
        let done: [String: JSONValue] = ["type": .string("response.reasoning_text.done"), "text": .string("done why")]
        let normalizedDone = AzureHelpers.normalizeReasoningEvent(done)
        XCTAssertEqual(normalizedDone["type"], .string("response.reasoning_summary_part.done"))
        XCTAssertEqual(normalizedDone["part"], .object(["type": .string("summary_text"), "text": .string("done why")]))
        let reasoningDone: [String: JSONValue] = ["type": .string("response.output_item.done"), "item": .object(["id": .string("r"), "type": .string("reasoning"), "content": .array([.object(["type": .string("reasoning_text"), "text": .string("reason")])])])]
        guard case .object(let reasoningItem)? = AzureHelpers.normalizeReasoningEvent(reasoningDone)["item"] else { return XCTFail("missing reasoning item") }
        XCTAssertEqual(reasoningItem["summary"], .array([.object(["type": .string("summary_text"), "text": .string("reason")])]))
        let commentary: [String: JSONValue] = ["type": .string("response.output_item.done"), "item": .object(["id": .string("i"), "type": .string("message"), "phase": .string("commentary"), "content": .array([.object(["type": .string("output_text"), "text": .string("reason")])])])]
        guard case .object(let item)? = AzureHelpers.normalizeReasoningEvent(commentary)["item"] else { return XCTFail("missing item") }
        XCTAssertEqual(item["type"], .string("reasoning"))
        let model = Model(id: "az", name: "Azure", api: .azureOpenAIResponses, provider: .azureOpenAI)
        let sse = """
        event: response.output_item.added
        data: {"type":"response.output_item.added","item":{"id":"i","type":"message","phase":"commentary"}}

        event: response.reasoning_text.delta
        data: {"type":"response.reasoning_text.delta","delta":"why"}

        event: response.output_item.done
        data: {"type":"response.output_item.done","item":{"id":"i","type":"message","phase":"commentary","content":[{"type":"output_text","text":"why"}]}}

        event: response.completed
        data: {"type":"response.completed","response":{"id":"r","status":"completed"}}

        """
        let events = OpenAIResponsesProvider.processSSEText(sse, model: model)
        guard case .done(_, let message)? = events.last else { return XCTFail("missing done") }
        XCTAssertEqual(message.content.first?.type, "thinking")
        XCTAssertEqual(message.content.first?.thinking, "why")
    }

    func testAzureToolCallLimit() {
        let messages: [JSONValue] = [
            .object(["type": .string("function_call"), "name": .string("old"), "call_id": .string("1")]),
            .object(["type": .string("function_call_output"), "call_id": .string("1"), "output": .string("older output")]),
            .object(["type": .string("function_call"), "name": .string("new"), "call_id": .string("2")]),
            .object(["type": .string("function_call_output"), "call_id": .string("2"), "output": .string("newer output")])
        ]
        let result = AzureHelpers.applyToolCallLimit(messages, config: ToolCallLimitConfig(limit: 1, summaryMax: 100, outputChars: 20))
        XCTAssertEqual(result.toolCallTotal, 2)
        XCTAssertEqual(result.toolCallRemoved, 1)
        XCTAssertTrue(result.summaryText.contains("old"))
        XCTAssertEqual(result.messages.count, 3)

        var budgetMessages: [JSONValue] = []
        for i in 0..<5 {
            budgetMessages.append(.object(["type": .string("function_call"), "name": .string("search"), "call_id": .string("\(i)")]))
            budgetMessages.append(.object(["type": .string("function_call_output"), "call_id": .string("\(i)"), "output": .string("this is a fairly long tool output that should count toward the token budget")]))
        }
        let budget = AzureHelpers.applyToolCallLimit(budgetMessages, config: ToolCallLimitConfig(limit: 10, summaryMax: 2000, outputChars: 30, maxEstimatedTokens: 40))
        XCTAssertGreaterThan(budget.toolCallBudgetRemoved, 0)
        XCTAssertLessThanOrEqual(budget.estimatedTokensAfter, budget.estimatedTokensBefore)
        XCTAssertFalse(budget.summaryText.isEmpty)
    }

    func testAzureResponsesHelpers() throws {
        XCTAssertEqual(OpenAIResponsesProvider.parseAzureDeploymentNameMap("gpt-5=prod, other = dep2")["other"], "dep2")
        XCTAssertEqual(try OpenAIResponsesProvider.normalizeAzureBaseURL("https://res.openai.azure.com"), "https://res.openai.azure.com/openai/v1")
        XCTAssertEqual(try OpenAIResponsesProvider.normalizeAzureBaseURL("https://res.openai.azure.com/openai"), "https://res.openai.azure.com/openai/v1")
        var options = StreamOptions()
        options.env = ["AZURE_OPENAI_BASE_URL": "https://res.openai.azure.com", "AZURE_OPENAI_DEPLOYMENT_NAME_MAP": "model=dep"]
        let cfg = try OpenAIResponsesProvider.resolveAzureConfig(model: Model(id: "model", name: "M", api: .azureOpenAIResponses, provider: .azureOpenAI), options: options)
        XCTAssertTrue(cfg.baseURL.contains("/openai/v1/deployments/dep"))
    }

    func testCodexResponsesHelpers() throws {
        XCTAssertEqual(OpenAIResponsesProvider.resolveCodexURL(""), "https://api.openai.com/v1/codex/responses")
        XCTAssertEqual(OpenAIResponsesProvider.resolveCodexURL("https://api.openai.com/v1"), "https://api.openai.com/v1/codex/responses")
        let payload: JSONValue = .object(["https://api.openai.com/auth": .object(["chatgpt_account_id": .string("acct")])])
        let payloadData = try JSONEncoder().encode(payload)
        let payloadPart = payloadData.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        XCTAssertEqual(try OpenAIResponsesProvider.extractCodexAccountID("h.\(payloadPart).s"), "acct")
    }

    func testOpenAIResponsesPartialJSONCleanup() {
        let model = Model(id: "gpt-5-mini", name: "GPT", api: .openAIResponses, provider: .openAI)
        let sse = """
        event: response.output_item.added
        data: {"item":{"type":"function_call","id":"fc_test","call_id":"call_test","name":"edit"}}

        event: response.function_call_arguments.delta
        data: {"delta":"{\\\"path\\\":\\\"README.md\\\""}

        event: response.function_call_arguments.delta
        data: {"delta":",\\\"content\\\":\\\"draft\\\"}"}

        event: response.function_call_arguments.done
        data: {"arguments":"{\\\"path\\\":\\\"README.md\\\",\\\"content\\\":\\\"updated\\\"}"}

        event: response.output_item.done
        data: {"item":{"type":"function_call","id":"fc_test","call_id":"call_test","name":"edit","arguments":"{\\\"path\\\":\\\"README.md\\\",\\\"content\\\":\\\"updated\\\"}"}}

        event: response.completed
        data: {"response":{"id":"resp_test","status":"completed"}}

        """
        let events = OpenAIResponsesProvider.processSSEText(sse, model: model)
        guard case .done(_, let message)? = events.last else { return XCTFail("missing done") }
        XCTAssertEqual(message.content.count, 1)
        XCTAssertEqual(message.content[0].type, "toolCall")
        XCTAssertEqual(message.content[0].arguments, ["path": .string("README.md"), "content": .string("updated")])
        let endEvents = events.filter { if case .toolCallEnd = $0 { return true }; return false }
        XCTAssertEqual(endEvents.count, 1)
    }

    func testOpenAIResponsesFailedEventEmitsError() {
        let model = Model(id: "gpt", name: "GPT", api: .openAIResponses, provider: .openAI)
        let failed = """
        event: response.failed
        data: {"response":{"error":{"message":"bad"}}}

        """
        let events = OpenAIResponsesProvider.processSSEText(failed, model: model)
        XCTAssertTrue(events.contains { if case .error = $0 { return true }; return false })
        let apiError = """
        event: error
        data: {"code":"bad_request","message":"bad"}

        """
        let apiEvents = OpenAIResponsesProvider.processSSEText(apiError, model: model)
        XCTAssertTrue(apiEvents.contains { if case .error = $0 { return true }; return false })
    }

    func testOpenAIResponsesTerminalEvents() {
        let model = Model(id: "gpt-5-mini", name: "GPT", api: .openAIResponses, provider: .openAI)
        let early = """
        event: response.created
        data: {"response":{"id":"resp_early_eof"}}

        event: response.output_item.added
        data: {"item":{"type":"reasoning","id":"rs_early_eof","summary":[]}}

        event: response.reasoning_text.delta
        data: {"type":"response.reasoning_text.delta","delta":"partial reasoning before the stream ends"}

        """
        let earlyEvents = OpenAIResponsesProvider.processSSEText(early, model: model)
        XCTAssertTrue(earlyEvents.contains { if case .error(_, let message, _) = $0 { return message?.errorMessage == "OpenAI Responses stream ended before a terminal response event" }; return false })

        let completed = """
        event: response.completed
        data: {"response":{"id":"resp_completed","status":"completed","usage":{"input_tokens":20,"output_tokens":7,"total_tokens":27,"input_tokens_details":{"cached_tokens":2}}}}

        """
        guard case .done(let doneReason, let doneMessage)? = OpenAIResponsesProvider.processSSEText(completed, model: model).last else { return XCTFail("missing completed") }
        XCTAssertEqual(doneReason, .stop)
        XCTAssertEqual(doneMessage.responseId, "resp_completed")
        XCTAssertEqual(doneMessage.usage?.input, 18)
        XCTAssertEqual(doneMessage.usage?.cacheRead, 2)

        let incomplete = """
        event: response.incomplete
        data: {"response":{"id":"resp_incomplete","status":"incomplete","usage":{"input_tokens":30,"output_tokens":12,"total_tokens":42,"input_tokens_details":{"cached_tokens":5}}}}

        """
        guard case .done(let incompleteReason, let incompleteMessage)? = OpenAIResponsesProvider.processSSEText(incomplete, model: model).last else { return XCTFail("missing incomplete") }
        XCTAssertEqual(incompleteReason, .length)
        XCTAssertEqual(incompleteMessage.responseId, "resp_incomplete")
        XCTAssertEqual(incompleteMessage.usage?.input, 25)
        XCTAssertEqual(incompleteMessage.usage?.cacheRead, 5)

        let failed = """
        event: response.failed
        data: {"response":{"id":"resp_failed","status":"failed","error":{"code":"server_error","message":"boom"}}}

        """
        let failedEvents = OpenAIResponsesProvider.processSSEText(failed, model: model)
        XCTAssertTrue(failedEvents.contains { if case .error(_, let message, _) = $0 { return message?.errorMessage == "server_error: boom" }; return false })
    }

    func testOpenAIResponsesStatusMapping() {
        let model = Model(id: "gpt", name: "GPT", api: .openAIResponses, provider: .openAI)
        let incomplete = """
        event: response.completed
        data: {"response":{"id":"r","status":"incomplete"}}

        """
        guard case .done(let reason, _)? = OpenAIResponsesProvider.processSSEText(incomplete, model: model).last else { return XCTFail("missing done") }
        XCTAssertEqual(reason, .length)
        let toolUse = """
        event: response.output_item.added
        data: {"item":{"type":"function_call","call_id":"c","name":"lookup"}}

        event: response.completed
        data: {"response":{"id":"r","status":"completed"}}

        """
        guard case .done(let toolReason, _)? = OpenAIResponsesProvider.processSSEText(toolUse, model: model).last else { return XCTFail("missing tool done") }
        XCTAssertEqual(toolReason, .toolUse)
    }

    func testAnthropicRawSSEParsingRepairsMalformedToolJSON() {
        let model = Model(id: "claude-haiku-4-5", name: "Claude", api: .anthropicMessages, provider: .anthropic)
        let malformed = #"{"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\"path\":\"A\H\",\"text\":\"col1"# + "\u{9}" + #"col2\"}"}}"#
        let sse = """
        event: message_start
        data: {"type":"message_start","message":{"id":"msg_test","usage":{"input_tokens":12,"output_tokens":0,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}

        event: content_block_start
        data: {"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_test","name":"edit","input":{}}}

        event: content_block_delta
        data: \(malformed)

        event: content_block_stop
        data: {"type":"content_block_stop","index":0}

        event: message_delta
        data: {"type":"message_delta","delta":{"stop_reason":"tool_use"},"usage":{"input_tokens":12,"output_tokens":5,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}

        event: message_stop
        data: {"type":"message_stop"}

        """
        let events = AnthropicMessagesProvider.processSSEText(sse, model: model)
        guard case .done(let reason, let message)? = events.last else { return XCTFail("missing done") }
        XCTAssertEqual(reason, .toolUse)
        let toolCall = message.content.first { $0.type == "toolCall" }
        XCTAssertEqual(toolCall?.arguments?["path"], .string("A\\H"))
        XCTAssertEqual(toolCall?.arguments?["text"], .string("col1\tcol2"))
    }

    func testAnthropicRawSSEParsingRefusalAndPostStopUnknownEvents() {
        let model = Model(id: "claude-haiku-4-5", name: "Claude", api: .anthropicMessages, provider: .anthropic)
        let explanation = "This request triggered restrictions on violative cyber content."
        let refusal = """
        event: message_start
        data: {"type":"message_start","message":{"id":"msg_refusal","usage":{"input_tokens":412,"output_tokens":0,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}

        event: message_delta
        data: {"type":"message_delta","delta":{"stop_reason":"refusal","stop_details":{"type":"refusal","category":"cyber","explanation":"\(explanation)"}},"usage":{"input_tokens":412,"output_tokens":0,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}

        event: message_stop
        data: {"type":"message_stop"}

        """
        guard case .done(let refusalReason, let refusalMessage)? = AnthropicMessagesProvider.processSSEText(refusal, model: model).last else { return XCTFail("missing refusal") }
        XCTAssertEqual(refusalReason, .error)
        XCTAssertEqual(refusalMessage.errorMessage, explanation)

        let minimal = """
        event: message_start
        data: {"type":"message_start","message":{"id":"msg_test","usage":{"input_tokens":12,"output_tokens":0,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}

        event: content_block_start
        data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

        event: content_block_delta
        data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}

        event: content_block_stop
        data: {"type":"content_block_stop","index":0}

        event: message_delta
        data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"input_tokens":12,"output_tokens":5,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}

        event: message_stop
        data: {"type":"message_stop"}

        event: done
        data: [DONE]

        event: proxy.stats
        data: not json

        """
        guard case .done(let reason, let message)? = AnthropicMessagesProvider.processSSEText(minimal, model: model).last else { return XCTFail("missing done") }
        XCTAssertEqual(reason, .stop)
        XCTAssertNil(message.errorMessage)
        XCTAssertEqual(message.content, [.text("Hello")])
    }

    func testOpenAIResponsesServiceTierCostMultipliers() {
        func usage(modelID: String, tier: String) -> Usage? {
            let model = Model(id: modelID, name: modelID, api: .openAIResponses, provider: .openAI, cost: ModelCost(input: 1, output: 2))
            let sse = """
            event: response.completed
            data: {"type":"response.completed","response":{"id":"r","status":"completed","service_tier":"\(tier)","usage":{"input_tokens":1000000,"output_tokens":1000000,"total_tokens":2000000,"input_tokens_details":{"cached_tokens":0}}}}

            """
            guard case .done(_, let message)? = OpenAIResponsesProvider.processSSEText(sse, model: model).last else { return nil }
            return message.usage
        }
        XCTAssertEqual(usage(modelID: "gpt-5.4", tier: "priority")?.cost.input, 2)
        XCTAssertEqual(usage(modelID: "gpt-5.4", tier: "priority")?.cost.output, 4)
        XCTAssertEqual(usage(modelID: "gpt-5.5", tier: "priority")?.cost.input, 2.5)
        XCTAssertEqual(usage(modelID: "gpt-5.5", tier: "priority")?.cost.output, 5)
        XCTAssertEqual(usage(modelID: "gpt-5.5", tier: "flex")?.cost.input, 0.5)
        XCTAssertEqual(usage(modelID: "gpt-5.5", tier: "flex")?.cost.output, 1)
    }

    func testAzureOpenAIResponsesBaseURLNormalization() throws {
        let cases = [
            ("https://marc-quicktests-resource.cognitiveservices.azure.com", "https://marc-quicktests-resource.cognitiveservices.azure.com/openai/v1"),
            ("https://my-resource.openai.azure.com", "https://my-resource.openai.azure.com/openai/v1"),
            ("https://my-resource.cognitiveservices.azure.com/openai", "https://my-resource.cognitiveservices.azure.com/openai/v1"),
            ("https://my-resource.cognitiveservices.azure.com/openai/v1", "https://my-resource.cognitiveservices.azure.com/openai/v1"),
            ("https://my-proxy.example.com/v1", "https://my-proxy.example.com/v1"),
            ("https://my-resource.openai.azure.com/openai?api-version=2024-12-01", "https://my-resource.openai.azure.com/openai/v1"),
            ("https://my-proxy.example.com/v1?custom=true", "https://my-proxy.example.com/v1?custom=true"),
        ]
        for (input, expected) in cases { XCTAssertEqual(try OpenAIResponsesProvider.normalizeAzureBaseURL(input), expected, input) }
        XCTAssertThrowsError(try OpenAIResponsesProvider.normalizeAzureBaseURL("not-a-url")) { error in
            XCTAssertTrue(String(describing: error).contains("Invalid Azure OpenAI base URL"))
        }
    }

    func testAzureOpenAIResponsesConfigAndPayloadDefaults() throws {
        let model = Model(id: "gpt-4o-mini", name: "GPT", api: .azureOpenAIResponses, provider: .azureOpenAI)
        var options = StreamOptions()
        options.azureBaseUrl = "https://my-resource.openai.azure.com"
        options.azureApiVersion = "2024-12-01"
        options.sessionId = String(repeating: "x", count: 67)
        let cfg = try OpenAIResponsesProvider.resolveAzureConfig(model: model, options: options)
        XCTAssertEqual(cfg.baseURL, "https://my-resource.openai.azure.com/openai/v1/deployments/gpt-4o-mini")
        XCTAssertEqual(cfg.apiVersion, "2024-12-01")
        let body = OpenAIResponsesProvider.buildRequestBody(model: model, context: AIContext(messages: [.user("hello")]), options: options)
        XCTAssertEqual(body["store"], JSONValue.bool(false))
        XCTAssertEqual(body["prompt_cache_key"], JSONValue.string(String(repeating: "x", count: 64)))

        var envOptions = StreamOptions()
        envOptions.env = ["AZURE_OPENAI_RESOURCE_NAME": "my-resource"]
        let envCfg = try OpenAIResponsesProvider.resolveAzureConfig(model: model, options: envOptions)
        XCTAssertEqual(envCfg.baseURL, "https://my-resource.openai.azure.com/openai/v1/deployments/gpt-4o-mini")
    }

    func testOpenAIResponsesProviderDefaultReasoningMatrix() throws {
        let models = try BuiltinModels.all()
        for id in ["gpt-5.1", "gpt-5.2", "gpt-5.3-codex", "gpt-5.4", "gpt-5.4-mini", "gpt-5.4-nano", "gpt-5.5"] {
            let model = try XCTUnwrap(models.first { $0.provider == .openAI && $0.id == id })
            let body = OpenAIResponsesProvider.buildRequestBody(model: model, context: AIContext(messages: [.user("hi")]), options: nil)
            XCTAssertEqual(body["reasoning"], .object(["effort": .string("none"), "summary": .string("auto")]), id)
        }
        for id in ["gpt-5", "gpt-5-mini", "gpt-5-nano", "gpt-5-pro", "gpt-5.2-pro", "gpt-5.4-pro", "gpt-5.5-pro"] {
            let model = try XCTUnwrap(models.first { $0.provider == .openAI && $0.id == id })
            let body = OpenAIResponsesProvider.buildRequestBody(model: model, context: AIContext(messages: [.user("hi")]), options: nil)
            XCTAssertNil(body["reasoning"], id)
        }
    }

    func testOpenAIResponsesDefaultReasoning() {
        let model = Model(id: "gpt-5", name: "GPT-5", api: .openAIResponses, provider: .openAI, reasoning: true)
        let body = OpenAIResponsesProvider.buildRequestBody(model: model, context: AIContext(messages: [.user("hi")]), options: nil)
        guard case .object(let reasoning)? = body["reasoning"] else { return XCTFail("missing reasoning") }
        XCTAssertEqual(reasoning["effort"], .string("medium"))
        XCTAssertEqual(body["include"], .array([.string("reasoning.encrypted_content")]))
        let copilot = Model(id: "gpt-5", name: "GPT-5", api: .openAIResponses, provider: .githubCopilot, reasoning: true)
        let copilotBody = OpenAIResponsesProvider.buildRequestBody(model: copilot, context: AIContext(messages: [.user("hi")]), options: nil)
        XCTAssertNil(copilotBody["reasoning"])
    }

    func testOpenAIResponsesToolResultImagesStayInFunctionCallOutput() {
        var toolResult = Message(role: .toolResult, content: [.text("A red circle with a diameter of 100 pixels."), .image(data: "abc", mimeType: "image/png")])
        toolResult.toolCallId = "call_1"
        toolResult.toolName = "get_circle_with_description"
        let model = Model(id: "gpt-5-mini", name: "GPT", api: .openAIResponses, provider: .openAI, input: ["text", "image"])
        let body = OpenAIResponsesProvider.buildRequestBody(model: model, context: AIContext(messages: [toolResult]), options: nil)
        guard case .array(let input)? = body["input"], case .object(let outputItem) = input[0], case .array(let output)? = outputItem["output"] else { return XCTFail("missing function_call_output array") }
        XCTAssertEqual(outputItem["type"], .string("function_call_output"))
        XCTAssertTrue(output.contains { if case .object(let obj) = $0 { return obj["type"] == .string("input_text") && obj["text"]?.stringValue?.contains("red circle") == true }; return false })
        XCTAssertTrue(output.contains { if case .object(let obj) = $0 { return obj["type"] == .string("input_image") && obj["image_url"]?.stringValue?.hasPrefix("data:image/png;base64,") == true }; return false })
        XCTAssertFalse(input.dropFirst().contains { if case .object(let obj) = $0 { return obj["role"] == .string("user") }; return false })
    }

    func testCodexResponsesRequestHeadersAndErrors() throws {
        let model = Model(id: "gpt-5.5", name: "Codex", api: .openAICodexResponses, provider: .openAICodex)
        var options = StreamOptions(); options.sessionId = String(repeating: "x", count: 67); options.reasoning = .high
        let body = OpenAIResponsesProvider.buildRequestBody(model: model, context: AIContext(messages: [.user("hi")]), options: options)
        XCTAssertEqual(body["model"], JSONValue.string("gpt-5.5"))
        XCTAssertEqual(body["stream"], JSONValue.bool(true))
        XCTAssertEqual(body["store"], JSONValue.bool(false))
        XCTAssertEqual(body["prompt_cache_key"], JSONValue.string(String(repeating: "x", count: 64)))
        let payload = #"{"https://api.openai.com/auth":{"chatgpt_account_id":"account-123"}}"#.data(using: .utf8)!.base64EncodedString()
        let token = "header.\(payload).signature"
        let headers = try OpenAIResponsesProvider.codexHeaders(apiKey: token)
        XCTAssertEqual(headers["chatgpt-account-id"], "account-123")
        XCTAssertEqual(headers["originator"], "pi")
        XCTAssertEqual(headers["OpenAI-Beta"], "responses=experimental")
        XCTAssertEqual(OpenAIResponsesProvider.extractCodexEventError(.object(["event": .object(["error": .object(["message": .string("nested boom")])])])), "nested boom")
    }

    func testOpenAIResponsesAssistantItemsAllowEmptyThinkingSignature() {
        let model = Model(id: "gpt", name: "GPT", api: .openAIResponses, provider: .openAI)
        var assistant = Message(role: .assistant, content: [.thinking("private", signature: "")])
        assistant.api = model.api; assistant.provider = model.provider; assistant.model = model.id; assistant.stopReason = .stop
        let body = OpenAIResponsesProvider.buildRequestBody(model: model, context: AIContext(messages: [assistant]), options: nil)
        guard case .array(let input)? = body["input"], case .object(let item) = input.first else { return XCTFail("missing input") }
        XCTAssertEqual(item["type"], .string("reasoning"))
        XCTAssertNotNil(item["id"])
    }

    func testOpenAIResponsesForeignToolCallIDNormalization() {
        let rawID = "call_4VnzVawQXPB9MgYib7CiQFEY|I9b95oN1wD/cHXKTw3PpRkL6KkCtzTJhUxMouMWYwHeTo2j3htzfSk7YPx2vifiIM4g3A8XXyOj8q4Bt6SLUG7gqY1E3ELkrkVQNHglRfUmWj84lqxJY+Puieb3VKyX0FB+83TUzn91cDMF/4gzt990IzqVrc+nIb9RRscRD070Du16q1glydVjWR0SBJsE6TbY/esOjFpqplogQqrajm1eI++f3eLi73R6q7hVusY0QbeFySVxABCjhN0lXB04caBe1rzHjYzul6MAXj7uq+0r17VLq+yrtyYhN12wkmFqHeqTyEei6EFPbMy24Nc+IbJlkP0OCg02W+gOnyBFcbi2ctvJFSOhSjt1CqBdqCnnhwUqXjbWiT0wh3DmLScRgTHmGkaI+oAcQQjfic65nxj+TnEkReA=="
        var assistant = Message(role: .assistant, content: [.toolCall(id: rawID, name: "edit", arguments: ["path": .string("src/styles/app.css")])])
        assistant.api = .openAIResponses; assistant.provider = .githubCopilot; assistant.model = "gpt-5.5"; assistant.stopReason = .toolUse
        var toolResult = Message(role: .toolResult, content: [.text("ok")])
        toolResult.toolCallId = rawID; toolResult.toolName = "edit"
        let model = Model(id: "gpt-5.5", name: "Codex", api: .openAICodexResponses, provider: .openAICodex)
        let body = OpenAIResponsesProvider.buildRequestBody(model: model, context: AIContext(systemPrompt: "You are concise.", messages: [.user("Use the tool."), assistant, toolResult]), options: nil)
        guard case .array(let input)? = body["input"], let functionCall = input.compactMap({ item -> [String: JSONValue]? in if case .object(let obj) = item, obj["type"] == .string("function_call") { return obj }; return nil }).first else { return XCTFail("missing function call") }
        let itemPart = rawID.split(separator: "|", maxSplits: 1).map(String.init)[1]
        let expected = "fc_" + AIUtilities.shortHash(itemPart)
        XCTAssertEqual(functionCall["id"], .string(expected))
        XCTAssertLessThanOrEqual(expected.count, 64)
    }

    func testOpenAIResponsesFallbackMessageIDs() throws {
        var assistant = Message(role: .assistant, content: [ContentBlock.thinking("private reasoning"), .text("visible answer")])
        assistant.api = .anthropicMessages
        assistant.provider = .anthropic
        assistant.model = "claude-opus-4-8"
        assistant.stopReason = .stop
        let model = Model(id: "gpt-5.5", name: "Codex", api: .openAICodexResponses, provider: .openAICodex)
        let body = OpenAIResponsesProvider.buildRequestBody(model: model, context: AIContext(systemPrompt: "You are concise.", messages: [.user("hello"), assistant]), options: nil)
        guard case .array(let input)? = body["input"] else { return XCTFail("missing input") }
        let messageIds = input.compactMap { item -> String? in
            if case .object(let obj) = item, obj["type"] == .string("message") { return obj["id"]?.stringValue }
            return nil
        }
        XCTAssertEqual(messageIds, ["msg_pi_1", "msg_pi_1_1"])
        XCTAssertEqual(Set(messageIds).count, messageIds.count)
    }

    func testOpenAIResponsesAssistantReplayItems() throws {
        let reasoningSig = "{\"type\":\"reasoning\",\"summary\":[]}"
        let textSig = "{\"id\":\"msg_1\",\"phase\":\"final\"}"
        var assistant = Message(role: .assistant, content: [ContentBlock.thinking("why", signature: reasoningSig), ContentBlock.text("answer", signature: textSig), ContentBlock.toolCall(id: "call|item", name: "lookup", arguments: ["q": .string("x")])])
        assistant.api = .openAIResponses
        assistant.provider = .openAI
        assistant.model = "gpt"
        let model = Model(id: "gpt", name: "GPT", api: .openAIResponses, provider: .openAI)
        let body = OpenAIResponsesProvider.buildRequestBody(model: model, context: AIContext(messages: [assistant]), options: nil)
        guard case .array(let input)? = body["input"] else { return XCTFail("missing input") }
        XCTAssertTrue(input.contains { if case .object(let obj) = $0 { return obj["type"] == .string("reasoning") }; return false })
        XCTAssertTrue(input.contains { if case .object(let obj) = $0 { return obj["id"] == .string("msg_1") && obj["phase"] == .string("final") }; return false })
        XCTAssertTrue(input.contains { if case .object(let obj) = $0 { return obj["type"] == .string("function_call") && obj["call_id"] == .string("call") }; return false })
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
        XCTAssertEqual(body["prompt_cache_key"], JSONValue.string("session"))
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
        data: {"response":{"id":"resp_1","usage":{"input_tokens":3,"output_tokens":2,"total_tokens":5,"input_tokens_details":{"cached_tokens":1}}}}

        """
        let events = OpenAIResponsesProvider.processSSEText(sse, model: model)
        guard case .done(let reason, let message)? = events.last else { return XCTFail("missing done") }
        XCTAssertEqual(reason, .stop)
        XCTAssertEqual(message.responseId, "resp_1")
        XCTAssertEqual(message.content.first?.text, "hi")
        XCTAssertEqual(message.usage?.input, 2)
        XCTAssertEqual(message.usage?.cacheRead, 1)
        XCTAssertEqual(message.usage?.totalTokens, 5)
    }

    func testCodexPluggableTransport() async throws {
        await CodexTransportRegistry.shared.setTransport(FakeCodexTransport())
        defer { Task { await CodexTransportRegistry.shared.setTransport(nil) } }
        let model = Model(id: "codex", name: "Codex", api: .openAICodexResponses, provider: .openAICodex)
        let message = try await SwiftAI.complete(model: model, context: AIContext(messages: [.user("hi")]))
        XCTAssertEqual(message.content.first?.text, "codex ok")
    }

    func testBedrockPluggableTransport() async throws {
        await BedrockTransportRegistry.shared.setTransport(FakeBedrockTransport())
        defer { Task { await BedrockTransportRegistry.shared.setTransport(nil) } }
        let model = Model(id: "bedrock", name: "Bedrock", api: .bedrockConverseStream, provider: .amazonBedrock)
        let message = try await SwiftAI.complete(model: model, context: AIContext(messages: [.user("hi")]))
        XCTAssertEqual(message.content.first?.text, "bedrock ok")
    }

    func testBedrockRequestAndRegionHelpers() {
        XCTAssertEqual(BedrockProvider.arnRegion("arn:aws:bedrock:us-west-2:123:foundation-model/x"), "us-west-2")
        XCTAssertEqual(BedrockProvider.arnRegion("arn:aws-us-gov:bedrock:us-gov-west-1:123456789012:application-inference-profile/abc123"), "us-gov-west-1")
        XCTAssertEqual(BedrockProvider.standardEndpointRegion("https://bedrock-runtime.eu-central-1.amazonaws.com"), "eu-central-1")
        XCTAssertEqual(BedrockProvider.standardEndpointRegion("https://bedrock-runtime.cn-north-1.amazonaws.com.cn"), "cn-north-1")
        XCTAssertNil(BedrockProvider.standardEndpointRegion("https://bedrock-vpc.example.com"))
        let model = Model(id: "anthropic.claude", name: "Claude", api: .bedrockConverseStream, provider: .amazonBedrock, baseUrl: "https://bedrock-runtime.eu-central-1.amazonaws.com")
        XCTAssertEqual(BedrockProvider.configuredRegion(model: model, options: nil), "eu-central-1")
        var regionOptions = StreamOptions(); regionOptions.env = ["AWS_REGION": "us-east-2"]
        XCTAssertEqual(BedrockProvider.configuredRegion(model: model, options: regionOptions), "us-east-2")
        regionOptions = StreamOptions(); regionOptions.env = ["AWS_DEFAULT_REGION": "us-west-1"]
        XCTAssertEqual(BedrockProvider.configuredRegion(model: model, options: regionOptions), "us-west-1")
        let arnModel = Model(id: "arn:aws:bedrock:us-west-2:123456789012:application-inference-profile/abc123", name: "Claude", api: .bedrockConverseStream, provider: .amazonBedrock, baseUrl: "https://bedrock-runtime.eu-central-1.amazonaws.com")
        regionOptions = StreamOptions(); regionOptions.env = ["AWS_REGION": "us-east-1"]
        XCTAssertEqual(BedrockProvider.configuredRegion(model: arnModel, options: regionOptions), "us-west-2")
        XCTAssertFalse(BedrockProvider.shouldUseExplicitEndpoint(baseURL: "https://bedrock-runtime.eu-central-1.amazonaws.com", configuredRegion: "us-east-2", hasAmbientConfiguredProfile: false))
        XCTAssertFalse(BedrockProvider.shouldUseExplicitEndpoint(baseURL: "https://bedrock-runtime.eu-central-1.amazonaws.com", configuredRegion: nil, hasAmbientConfiguredProfile: true))
        XCTAssertTrue(BedrockProvider.shouldUseExplicitEndpoint(baseURL: "https://bedrock-vpc.example.com", configuredRegion: "us-west-2", hasAmbientConfiguredProfile: true))
        let body = BedrockProvider.buildConverseRequest(model: model, context: AIContext(systemPrompt: "sys", messages: [.user("hi")], tools: [Tool(name: "lookup", description: "lookup", parameters: .object(["type": .string("object")]))]), options: nil)
        XCTAssertEqual(body["modelId"], .string("anthropic.claude"))
        XCTAssertNotNil(body["messages"])
        XCTAssertNotNil(body["system"])
        XCTAssertNotNil(body["toolConfig"])
    }

    func testBedrockConvertMessagesSkipsUnknownAndBlankContent() {
        let model = Model(id: "anthropic.claude", name: "Claude", api: .bedrockConverseStream, provider: .amazonBedrock)
        func messages(_ context: AIContext) -> [JSONValue] {
            guard case .array(let values)? = BedrockProvider.buildConverseRequest(model: model, context: context, options: nil)["messages"] else { XCTFail("missing messages"); return [] }
            return values
        }
        var values = messages(AIContext(messages: [Message(role: .user, content: [.text("hello"), ContentBlock(type: "unknown", data: "foo")])]))
        XCTAssertEqual(values, [.object(["role": .string("user"), "content": .array([.object(["text": .string("hello")])])])])
        values = messages(AIContext(messages: [Message(role: .user, content: [ContentBlock(type: "unknown", data: "foo")])]))
        XCTAssertEqual(values, [.object(["role": .string("user"), "content": .array([.object(["text": .string("<empty>")])])])])
        values = messages(AIContext(messages: [.user("   ")]))
        XCTAssertEqual(values, [.object(["role": .string("user"), "content": .array([.object(["text": .string("<empty>")])])])])
        values = messages(AIContext(messages: [Message(role: .user, content: [.text(""), .text("hello")])]))
        XCTAssertEqual(values, [.object(["role": .string("user"), "content": .array([.object(["text": .string("hello")])])])])
        values = messages(AIContext(messages: [.user("\u{FFFD}")]))
        XCTAssertEqual(values, [.object(["role": .string("user"), "content": .array([.object(["text": .string("<empty>")])])])])
        var assistant = Message(role: .assistant, content: [.text("\u{FFFD}")])
        assistant.api = model.api; assistant.provider = model.provider; assistant.model = model.id; assistant.stopReason = .stop
        XCTAssertEqual(messages(AIContext(messages: [assistant])), [])
        assistant.content = [ContentBlock(type: "unknown", data: "foo")]
        XCTAssertEqual(messages(AIContext(messages: [assistant])), [])
        var tool = Message(role: .toolResult, content: [.text(" ")])
        tool.toolCallId = "tool-1"; tool.toolName = "tool"; tool.isError = false
        values = messages(AIContext(messages: [tool]))
        XCTAssertEqual(values, [.object(["role": .string("user"), "content": .array([.object(["toolResult": .object(["toolUseId": .string("tool-1"), "content": .array([.object(["text": .string("<empty>")])]), "status": .string("success")])])])])])
    }

    func testBedrockCustomHeaderFiltering() {
        var headers = ["authorization": "real-auth", "x-amz-date": "real-date", "host": "real-host"]
        BedrockProvider.applyCustomHeaders(["authorization": "evil", "Authorization": "evil2", "x-amz-date": "evil", "X-Amz-Date": "evil2", "HOST": "evil3", "x-allowed": "ok"], to: &headers)
        XCTAssertEqual(headers["authorization"], "real-auth")
        XCTAssertEqual(headers["x-amz-date"], "real-date")
        XCTAssertEqual(headers["host"], "real-host")
        XCTAssertEqual(headers["x-allowed"], "ok")
        XCTAssertNil(headers["Authorization"])
        XCTAssertNil(headers["X-Amz-Date"])
        XCTAssertNil(headers["HOST"])
    }

    func testBedrockThinkingPayloadParity() {
        func fields(_ model: Model, reasoning: ThinkingLevel = .high, region: String? = nil) -> [String: JSONValue] {
            var options = StreamOptions(); options.reasoning = reasoning; options.region = region
            return BedrockProvider.additionalModelRequestFields(model: model, options: options) ?? [:]
        }
        let opus48 = Model(id: "global.anthropic.claude-opus-4-8-v1", name: "Claude Opus 4.8", api: .bedrockConverseStream, provider: .amazonBedrock, reasoning: true)
        var payload = fields(opus48)
        XCTAssertEqual(payload["thinking"], .object(["type": .string("adaptive"), "display": .string("summarized")]))
        XCTAssertEqual(payload["output_config"], .object(["effort": .string("high")]))
        XCTAssertNil(payload["anthropic_beta"])
        payload = fields(opus48, reasoning: .xhigh)
        XCTAssertEqual(payload["output_config"], .object(["effort": .string("xhigh")]))
        payload = fields(opus48, region: "us-gov-west-1")
        XCTAssertEqual(payload["thinking"], .object(["type": .string("adaptive")]))
        let fable = Model(id: "global.anthropic.claude-fable-5", name: "Claude Fable 5", api: .bedrockConverseStream, provider: .amazonBedrock, reasoning: true)
        XCTAssertEqual(fields(fable, reasoning: .xhigh)["output_config"], .object(["effort": .string("xhigh")]))
        let sonnet45 = Model(id: "us-gov.anthropic.claude-sonnet-4-5-20250929-v1:0", name: "Claude Sonnet 4.5", api: .bedrockConverseStream, provider: .amazonBedrock, reasoning: true)
        payload = fields(sonnet45)
        XCTAssertEqual(payload["thinking"], .object(["type": .string("enabled"), "budget_tokens": .number(16384)]))
        XCTAssertEqual(payload["anthropic_beta"], .array([.string("interleaved-thinking-2025-05-14")]))
        let arnProfile = Model(id: "arn:aws:bedrock:us-east-1:123456789012:application-inference-profile/my-profile", name: "Claude Opus 4.6", api: .bedrockConverseStream, provider: .amazonBedrock, reasoning: true)
        XCTAssertEqual(fields(arnProfile)["thinking"], .object(["type": .string("adaptive"), "display": .string("summarized")]))
    }

    func testGeminiCLIRequestAndSSEProcessing() {
        let model = Model(id: "gemini-cli", name: "Gemini CLI", api: .googleGeminiCLI, provider: .googleGeminiCLI, reasoning: true)
        var options = StreamOptions()
        options.reasoning = .low
        options.sessionId = "sess"
        let body = GoogleGeminiCLIProvider.buildRequestBody(model: model, context: AIContext(systemPrompt: "sys", messages: [.user("hi")]), projectId: "proj", options: options)
        XCTAssertEqual(body["project"], .string("proj"))
        XCTAssertEqual(body["model"], .string("gemini-cli"))
        guard case .object(let request)? = body["request"] else { return XCTFail("missing request") }
        XCTAssertEqual(request["sessionId"], .string("sess"))
        let sse = """
        data: {"response":{"responseId":"r1","candidates":[{"content":{"parts":[{"text":"ok"}]},"finishReason":"STOP"}],"usageMetadata":{"promptTokenCount":1,"candidatesTokenCount":1,"totalTokenCount":2}}}

        """
        let events = GoogleGeminiCLIProvider.processSSEText(sse, model: model)
        guard case .done(let reason, let message)? = events.last else { return XCTFail("missing done") }
        XCTAssertEqual(reason, .stop)
        XCTAssertEqual(message.responseId, "r1")
        XCTAssertEqual(message.content.first?.text, "ok")
    }

    func testGoogleGemini3UnsignedToolCalls() {
        func makeModel(id: String = "gemini-3-pro-preview", api: API = .googleGenerativeAI, provider: Provider = .google) -> Model {
            Model(id: id, name: "Gemini", api: api, provider: provider, reasoning: true)
        }
        func makeAssistant(model: Model, signature: String? = nil) -> Message {
            var first = ContentBlock.toolCall(id: "call_1", name: "bash", arguments: ["command": .string("echo hi")])
            first.thoughtSignature = signature
            var assistant = Message(role: .assistant, content: [first, .toolCall(id: "call_2", name: "bash", arguments: ["command": .string("ls -la")])])
            assistant.api = model.api; assistant.provider = model.provider; assistant.model = model.id; assistant.stopReason = .toolUse
            return assistant
        }
        let genAI = makeModel()
        let unsigned = GoogleGenerativeAIProvider.buildRequestBody(model: genAI, context: AIContext(messages: [.user("Hi"), makeAssistant(model: makeModel(id: "other-model"))]), options: nil)
        guard case .array(let contents)? = unsigned["contents"], case .object(let modelTurn) = contents.first(where: { if case .object(let obj) = $0 { return obj["role"] == .string("model") }; return false }), case .array(let parts)? = modelTurn["parts"] else { return XCTFail("missing model turn") }
        let functionParts = parts.compactMap { part -> [String: JSONValue]? in if case .object(let obj) = part, obj["functionCall"] != nil { return obj }; return nil }
        XCTAssertEqual(functionParts.count, 2)
        XCTAssertNil(functionParts[0]["thoughtSignature"])
        XCTAssertNil(functionParts[1]["thoughtSignature"])
        XCTAssertFalse(String(describing: modelTurn).contains("skip_thought_signature_validator"))

        let vertex = makeModel(api: .googleVertex, provider: .googleVertex)
        let vertexBody = GoogleGenerativeAIProvider.buildRequestBody(model: vertex, context: AIContext(messages: [makeAssistant(model: vertex)]), options: nil)
        guard case .array(let vertexContents)? = vertexBody["contents"], case .object(let vertexTurn) = vertexContents[0], case .array(let vertexParts)? = vertexTurn["parts"] else { return XCTFail("missing vertex") }
        XCTAssertFalse(String(describing: vertexParts).contains("skip_thought_signature_validator"))

        let signed = GoogleGenerativeAIProvider.buildRequestBody(model: genAI, context: AIContext(messages: [makeAssistant(model: genAI, signature: "AAAAAAAAAAAAAAAAAAAAAA==")]), options: nil)
        guard case .array(let signedContents)? = signed["contents"], case .object(let signedTurn) = signedContents[0], case .array(let signedParts)? = signedTurn["parts"], case .object(let signedFirst) = signedParts[0] else { return XCTFail("missing signed") }
        XCTAssertEqual(signedFirst["thoughtSignature"], .string("AAAAAAAAAAAAAAAAAAAAAA=="))

        let nonGemini3 = makeModel(id: "gemini-2.5-flash")
        let nonGeminiBody = GoogleGenerativeAIProvider.buildRequestBody(model: nonGemini3, context: AIContext(messages: [makeAssistant(model: makeModel(id: "other-model"))]), options: nil)
        guard case .array(let nonContents)? = nonGeminiBody["contents"], case .object(let nonTurn) = nonContents[0], case .array(let nonParts)? = nonTurn["parts"], case .object(let nonFirst) = nonParts[0] else { return XCTFail("missing non-gemini") }
        XCTAssertNil(nonFirst["thoughtSignature"])
    }

    func testGoogleToolResultSerialization() {
        var result = Message(role: .toolResult, content: [.text("ok")])
        result.toolName = "lookup"
        result.toolCallId = "call.1"
        let model = Model(id: "gemini", name: "Gemini", api: .googleGenerativeAI, provider: .google)
        let body = GoogleGenerativeAIProvider.buildRequestBody(model: model, context: AIContext(messages: [result]), options: nil)
        guard case .array(let contents)? = body["contents"], case .object(let first) = contents[0], case .array(let parts)? = first["parts"], case .object(let part) = parts[0], case .object(let response)? = part["functionResponse"] else { return XCTFail("missing functionResponse") }
        XCTAssertEqual(response["name"], .string("lookup"))
        XCTAssertNotNil(response["response"])
        let cliBody = GoogleGeminiCLIProvider.buildRequestBody(model: Model(id: "gemini", name: "Gemini", api: .googleGeminiCLI, provider: .googleGeminiCLI), context: AIContext(messages: [result]), projectId: "p", options: nil)
        guard case .object(let request)? = cliBody["request"], case .array(let cliContents)? = request["contents"], case .object(let cliFirst) = cliContents[0], case .array(let cliParts)? = cliFirst["parts"], case .object(let cliPart) = cliParts[0] else { return XCTFail("missing cli functionResponse") }
        XCTAssertNotNil(cliPart["functionResponse"])
    }

    func testGoogleMultimodalToolResultSerialization() {
        var result = Message(role: .toolResult, content: [.image(data: "abc", mimeType: "image/png")])
        result.toolName = "lookup"
        result.toolCallId = "call.1"
        let model = Model(id: "gemini-3-pro", name: "Gemini 3", api: .googleGenerativeAI, provider: .google, input: ["image"])
        let body = GoogleGenerativeAIProvider.buildRequestBody(model: model, context: AIContext(messages: [result]), options: nil)
        guard case .array(let contents)? = body["contents"], case .object(let first) = contents[0], case .array(let parts)? = first["parts"], case .object(let part) = parts[0], case .object(let response)? = part["functionResponse"], case .array(let responseParts)? = response["parts"] else { return XCTFail("missing multimodal functionResponse parts") }
        XCTAssertEqual(responseParts.count, 1)
    }

    func testGoogleSameModelSignatureReplay() {
        let sig = "QUJDRA=="
        let model = Model(id: "gemini", name: "Gemini", api: .googleGenerativeAI, provider: .google)
        var assistant = Message(role: .assistant, content: [ContentBlock(type: "thinking", thinking: "why", thinkingSignature: sig), ContentBlock.toolCall(id: "call", name: "lookup", arguments: [:])])
        assistant.api = model.api
        assistant.provider = model.provider
        assistant.model = model.id
        assistant.content[1].thoughtSignature = sig
        let body = GoogleGenerativeAIProvider.buildRequestBody(model: model, context: AIContext(messages: [assistant]), options: nil)
        guard case .array(let contents)? = body["contents"], case .object(let first) = contents[0], case .array(let parts)? = first["parts"], case .object(let thinking) = parts[0], case .object(let tool) = parts[1] else { return XCTFail("missing parts") }
        XCTAssertEqual(thinking["thoughtSignature"], .string(sig))
        XCTAssertEqual(tool["thoughtSignature"], .string(sig))
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

    func testMistralErrorFinishEmitsError() {
        let model = Model(id: "mistral", name: "Mistral", api: .mistralConversations, provider: .mistral)
        let sse = """
        data: {"choices":[{"delta":{"content":"bad"},"finish_reason":"error"}]}

        """
        let events = MistralConversationsProvider.processSSEText(sse, model: model)
        XCTAssertTrue(events.contains { if case .error = $0 { return true }; return false })
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
        data: {"id":"resp_1","model":"actual-model","choices":[{"delta":{"reasoning_content":"think"}}]}

        data: {"choices":[{"delta":{"content":"ok"},"finish_reason":"stop"}],"usage":{"prompt_tokens":3,"completion_tokens":2,"total_tokens":5}}

        data: [DONE]

        """
        let events = MistralConversationsProvider.processSSEText(sse, model: model)
        guard case .done(let reason, let message)? = events.last else { return XCTFail("missing done") }
        XCTAssertEqual(reason, .stop)
        XCTAssertEqual(message.responseId, "resp_1")
        XCTAssertEqual(message.responseModel, "actual-model")
        XCTAssertEqual(message.content.first?.type, "thinking")
        XCTAssertEqual(message.content.first?.thinking, "think")
        XCTAssertTrue(message.content.contains { $0.type == "text" && $0.text == "ok" })
        XCTAssertEqual(message.usage?.totalTokens, 5)
    }

    func testAnthropicTruncatedStreamEmitsError() {
        let model = Model(id: "claude", name: "Claude", api: .anthropicMessages, provider: .anthropic)
        let sse = """
        event: message_start
        data: {"message":{"id":"m","usage":{"input_tokens":1}}}

        """
        let events = AnthropicMessagesProvider.processSSEText(sse, model: model)
        XCTAssertTrue(events.contains { if case .error = $0 { return true }; return false })
    }

    func testAnthropicEmptyThinkingSignatureCompat() {
        var assistant = Message(role: .assistant, content: [ContentBlock.thinking("internal reasoning", signature: "")])
        assistant.api = .anthropicMessages
        assistant.provider = .xiaomiTokenPlanAMS
        assistant.model = "mimo-v2.5-pro"
        let defaultModel = Model(id: "mimo-v2.5-pro", name: "MiMo", api: .anthropicMessages, provider: .xiaomiTokenPlanAMS, reasoning: true)
        let defaultBody = AnthropicMessagesProvider.buildRequestBody(model: defaultModel, context: AIContext(messages: [.user("first"), assistant, .user("second")]), options: nil)
        guard case .array(let defaultMessages)? = defaultBody["messages"], case .object(let defaultAssistant) = defaultMessages[1], case .array(let defaultContent)? = defaultAssistant["content"], case .object(let defaultBlock) = defaultContent[0] else { return XCTFail("missing default assistant") }
        XCTAssertEqual(defaultBlock["type"], .string("text"))
        XCTAssertEqual(defaultBlock["text"], .string("internal reasoning"))

        assistant.content[0].thinkingSignature = " "
        let allowModel = Model(id: "mimo-v2.5-pro", name: "MiMo", api: .anthropicMessages, provider: .xiaomiTokenPlanAMS, reasoning: true, anthropicCompat: AnthropicMessagesCompat(allowEmptySignature: true))
        let allowBody = AnthropicMessagesProvider.buildRequestBody(model: allowModel, context: AIContext(messages: [.user("first"), assistant, .user("second")]), options: nil)
        guard case .array(let allowMessages)? = allowBody["messages"], case .object(let allowAssistant) = allowMessages[1], case .array(let allowContent)? = allowAssistant["content"], case .object(let allowBlock) = allowContent[0] else { return XCTFail("missing allow assistant") }
        XCTAssertEqual(allowBlock["type"], .string("thinking"))
        XCTAssertEqual(allowBlock["signature"], .string(""))
    }

    func testAnthropicToolUseAndResultRequest() {
        var assistant = Message(role: .assistant, content: [.toolCall(id: "call.1", name: "lookup", arguments: ["q": .string("x")])])
        assistant.stopReason = .toolUse
        var result = Message(role: .toolResult, content: [.text("ok")])
        result.toolCallId = "call.1"
        result.toolName = "lookup"
        let model = Model(id: "claude", name: "Claude", api: .anthropicMessages, provider: .anthropic)
        let body = AnthropicMessagesProvider.buildRequestBody(model: model, context: AIContext(messages: [assistant, result]), options: nil)
        guard case .array(let messages)? = body["messages"], case .object(let a) = messages[0], case .array(let ac)? = a["content"], case .object(let toolUse) = ac[0], case .object(let r) = messages[1], case .array(let rc)? = r["content"], case .object(let toolResult) = rc[0] else { return XCTFail("missing anthropic tool blocks") }
        XCTAssertEqual(toolUse["type"], .string("tool_use"))
        XCTAssertEqual(toolUse["id"], .string("call_1"))
        XCTAssertEqual(toolResult["type"], .string("tool_result"))
        XCTAssertEqual(toolResult["tool_use_id"], .string("call_1"))
    }

    func testAnthropicAdaptiveThinkingModelMetadata() throws {
        let models = try BuiltinModels.all()
        let flagged = models
            .filter { $0.api == .anthropicMessages && $0.anthropicCompat?.forceAdaptiveThinking == true }
            .map { "\($0.provider.rawValue)/\($0.id)" }
            .sorted()
        for expected in [
            "anthropic/claude-fable-5",
            "anthropic/claude-opus-4-8",
            "cloudflare-ai-gateway/claude-fable-5",
            "opencode/claude-opus-4-8",
            "vercel-ai-gateway/anthropic/claude-opus-4.8"
        ] {
            XCTAssertTrue(flagged.contains(expected), expected)
        }
        XCTAssertFalse(flagged.isEmpty)
    }

    func testAnthropicTemperatureCompat() throws {
        let opus47 = try XCTUnwrap(try BuiltinModels.all().first { $0.provider == .anthropic && $0.id == "claude-opus-4-7" })
        let opus48 = try XCTUnwrap(try BuiltinModels.all().first { $0.provider == .anthropic && $0.id == "claude-opus-4-8" })
        let opus46 = try XCTUnwrap(try BuiltinModels.all().first { $0.provider == .anthropic && $0.id == "claude-opus-4-6" })
        let sonnet46 = try XCTUnwrap(try BuiltinModels.all().first { $0.provider == .anthropic && $0.id == "claude-sonnet-4-6" })
        var options = StreamOptions(); options.temperature = 0
        XCTAssertNil(AnthropicMessagesProvider.buildRequestBody(model: opus47, context: AIContext(messages: [.user("Hello")]), options: options)["temperature"])
        XCTAssertNil(AnthropicMessagesProvider.buildRequestBody(model: opus48, context: AIContext(messages: [.user("Hello")]), options: options)["temperature"])
        XCTAssertEqual(AnthropicMessagesProvider.buildRequestBody(model: opus46, context: AIContext(messages: [.user("Hello")]), options: options)["temperature"], .number(0))
        XCTAssertEqual(AnthropicMessagesProvider.buildRequestBody(model: sonnet46, context: AIContext(messages: [.user("Hello")]), options: options)["temperature"], .number(0))
        let custom = Model(id: "vendor--claude-opus-4-7", name: "Vendor", api: .anthropicMessages, provider: .anthropic, anthropicCompat: AnthropicMessagesCompat(supportsTemperature: false))
        XCTAssertNil(AnthropicMessagesProvider.buildRequestBody(model: custom, context: AIContext(messages: [.user("Hello")]), options: options)["temperature"])
    }

    func testAnthropicCacheWrite1hCost() {
        let model = Model(id: "claude-opus-4-8", name: "Claude", api: .anthropicMessages, provider: .anthropic, cost: ModelCost(input: 5, output: 0, cacheRead: 0, cacheWrite: 6.25))
        let withBreakdown = """
        event: message_start
        data: {"message":{"id":"msg_test","usage":{"input_tokens":100,"cache_creation_input_tokens":1000000,"cache_creation":{"ephemeral_5m_input_tokens":600000,"ephemeral_1h_input_tokens":400000}}}}

        event: content_block_start
        data: {"index":0,"content_block":{"type":"text"}}

        event: content_block_delta
        data: {"index":0,"delta":{"type":"text_delta","text":"Hi"}}

        event: content_block_stop
        data: {"index":0}

        event: message_delta
        data: {"delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":5,"cache_creation_input_tokens":1000000,"cache_creation":{"ephemeral_1h_input_tokens":400000}}}

        event: message_stop
        data: {}

        """
        guard case .done(_, let message)? = AnthropicMessagesProvider.processSSEText(withBreakdown, model: model).last else { return XCTFail("missing done") }
        XCTAssertEqual(message.usage?.cacheWrite, 1_000_000)
        XCTAssertEqual(message.usage?.cacheWrite1h, 400_000)
        XCTAssertEqual(message.usage?.cost.cacheWrite ?? 0, 7.75, accuracy: 0.0000001)

        let withoutBreakdown = withBreakdown.replacingOccurrences(of: ",\"cache_creation\":{\"ephemeral_5m_input_tokens\":600000,\"ephemeral_1h_input_tokens\":400000}", with: "").replacingOccurrences(of: ",\"cache_creation\":{\"ephemeral_1h_input_tokens\":400000}", with: "")
        guard case .done(_, let noBreakdown)? = AnthropicMessagesProvider.processSSEText(withoutBreakdown, model: model).last else { return XCTFail("missing done") }
        XCTAssertEqual(noBreakdown.usage?.cacheWrite, 1_000_000)
        XCTAssertEqual(noBreakdown.usage?.cacheWrite1h ?? 0, 0)
        XCTAssertEqual(noBreakdown.usage?.cost.cacheWrite ?? 0, 6.25, accuracy: 0.0000001)
    }

    func testAnthropicThinkingDisablePayload() throws {
        for id in ["claude-sonnet-4-5", "claude-opus-4-6", "claude-opus-4-8"] {
            let model = try XCTUnwrap(try BuiltinModels.all().first { $0.provider == .anthropic && $0.id == id })
            let body = AnthropicMessagesProvider.buildRequestBody(model: model, context: AIContext(messages: [.user("Hello")]), options: nil)
            XCTAssertEqual(body["thinking"], .object(["type": .string("disabled")]), id)
            XCTAssertNil(body["output_config"], id)
        }
        let fable = try XCTUnwrap(try BuiltinModels.all().first { $0.provider == .anthropic && $0.id == "claude-fable-5" })
        let fableBody = AnthropicMessagesProvider.buildRequestBody(model: fable, context: AIContext(messages: [.user("Hello")]), options: nil)
        XCTAssertEqual(fableBody["thinking"], JSONValue.object(["type": .string("disabled")]))
        XCTAssertNil(fableBody["output_config"])
        var options = StreamOptions(); options.reasoning = .xhigh
        let opus48 = try XCTUnwrap(try BuiltinModels.all().first { $0.provider == .anthropic && $0.id == "claude-opus-4-8" })
        let enabled = AnthropicMessagesProvider.buildRequestBody(model: opus48, context: AIContext(messages: [.user("Hello")]), options: options)
        XCTAssertEqual(enabled["thinking"], .object(["type": .string("adaptive"), "display": .string("summarized")]))
        XCTAssertEqual(enabled["output_config"], .object(["effort": .string("xhigh")]))
    }

    func testAnthropicForceAdaptiveThinking() {
        var options = StreamOptions()
        options.reasoning = .medium
        let legacy = Model(id: "vendor--claude-opus-latest", name: "Vendor", api: .anthropicMessages, provider: .anthropic, reasoning: true)
        let legacyBody = AnthropicMessagesProvider.buildRequestBody(model: legacy, context: AIContext(messages: [.user("Hello")]), options: options)
        guard case .object(let legacyThinking)? = legacyBody["thinking"] else { return XCTFail("missing legacy thinking") }
        XCTAssertEqual(legacyThinking["type"], .string("enabled"))
        XCTAssertNil(legacyBody["output_config"])

        let adaptive = Model(id: "vendor--claude-opus-latest", name: "Vendor", api: .anthropicMessages, provider: .anthropic, reasoning: true, anthropicCompat: AnthropicMessagesCompat(forceAdaptiveThinking: true))
        let adaptiveBody = AnthropicMessagesProvider.buildRequestBody(model: adaptive, context: AIContext(messages: [.user("Hello")]), options: options)
        XCTAssertEqual(adaptiveBody["thinking"], .object(["type": .string("adaptive"), "display": .string("summarized")]))
        XCTAssertEqual(adaptiveBody["output_config"], .object(["effort": .string("medium")]))

        let offBody = AnthropicMessagesProvider.buildRequestBody(model: adaptive, context: AIContext(messages: [.user("Hello")]), options: nil)
        XCTAssertEqual(offBody["thinking"], .object(["type": .string("disabled")]))
        XCTAssertNil(offBody["output_config"])
    }

    func testAnthropicOAuthToolNameNormalization() {
        var options = StreamOptions(); options.apiKey = "sk-ant-oat-test"
        let model = Model(id: "claude", name: "Claude", api: .anthropicMessages, provider: .anthropic)
        let todo = Tool(name: "todowrite", description: "todo", parameters: .object(["type": .string("object")]))
        let read = Tool(name: "read", description: "read", parameters: .object(["type": .string("object")]))
        let find = Tool(name: "find", description: "find", parameters: .object(["type": .string("object")]))
        let body = AnthropicMessagesProvider.buildRequestBody(model: model, context: AIContext(messages: [.user("hi")], tools: [todo, read, find]), options: options)
        guard case .array(let tools)? = body["tools"], case .object(let t0) = tools[0], case .object(let t1) = tools[1], case .object(let t2) = tools[2] else { return XCTFail("missing tools") }
        XCTAssertEqual(t0["name"], .string("TodoWrite"))
        XCTAssertEqual(t1["name"], .string("Read"))
        XCTAssertEqual(t2["name"], .string("find"))
        var assistant = Message(role: .assistant, content: [.toolCall(id: "c", name: "todowrite", arguments: [:])])
        assistant.api = .anthropicMessages; assistant.provider = .anthropic; assistant.model = "claude"
        let replay = AnthropicMessagesProvider.buildRequestBody(model: model, context: AIContext(messages: [assistant]), options: options)
        guard case .array(let messages)? = replay["messages"], case .object(let msg) = messages[0], case .array(let content)? = msg["content"], case .object(let block) = content[0] else { return XCTFail("missing replay tool") }
        XCTAssertEqual(block["name"], .string("TodoWrite"))

        let sse = """
        event: message_start
        data: {"type":"message_start","message":{"id":"m","usage":{"input_tokens":1,"output_tokens":0}}}

        event: content_block_start
        data: {"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_1","name":"TodoWrite","input":{}}}

        event: content_block_delta
        data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\\\"task\\\":\\\"buy milk\\\"}"}}

        event: content_block_stop
        data: {"type":"content_block_stop","index":0}

        event: message_delta
        data: {"type":"message_delta","delta":{"stop_reason":"tool_use"},"usage":{"output_tokens":1}}

        event: message_stop
        data: {"type":"message_stop"}

        """
        let events = AnthropicMessagesProvider.processSSEText(sse, model: model, tools: [todo, read, find])
        guard case .done(_, let streamed)? = events.last else { return XCTFail("missing done") }
        XCTAssertEqual(streamed.content.first?.name, "todowrite")
        XCTAssertEqual(streamed.content.first?.arguments?["task"], .string("buy milk"))
    }

    func testAnthropicEagerToolInputCompat() {
        let tool = Tool(name: "lookup", description: "lookup", parameters: .object(["type": .string("object")]))
        let defaultModel = Model(id: "claude", name: "Claude", api: .anthropicMessages, provider: .anthropic)
        let defaultBody = AnthropicMessagesProvider.buildRequestBody(model: defaultModel, context: AIContext(messages: [.user("hi")], tools: [tool]), options: nil)
        guard case .array(let defaultTools)? = defaultBody["tools"], case .object(let defaultTool) = defaultTools[0] else { return XCTFail("missing default tool") }
        XCTAssertEqual(defaultTool["eager_input_streaming"], .bool(true))

        let disabledModel = Model(id: "claude", name: "Claude", api: .anthropicMessages, provider: .anthropic, anthropicCompat: AnthropicMessagesCompat(supportsEagerToolInputStreaming: false))
        let disabledBody = AnthropicMessagesProvider.buildRequestBody(model: disabledModel, context: AIContext(messages: [.user("hi")], tools: [tool]), options: nil)
        guard case .array(let disabledTools)? = disabledBody["tools"], case .object(let disabledTool) = disabledTools[0] else { return XCTFail("missing disabled tool") }
        XCTAssertNil(disabledTool["eager_input_streaming"])
        let noToolsBody = AnthropicMessagesProvider.buildRequestBody(model: disabledModel, context: AIContext(messages: [.user("hi")]), options: nil)
        XCTAssertNil(noToolsBody["tools"])
    }

    func testAnthropicLongCacheRetentionModelCoverage() throws {
        let models = try BuiltinModels.all().filter { $0.api == .anthropicMessages }
        XCTAssertFalse(models.isEmpty)
        let providers = Set(models.map(\.provider))
        XCTAssertTrue(providers.contains(.anthropic))
        XCTAssertTrue(providers.contains(.githubCopilot))
        var options = StreamOptions(); options.cacheRetention = .long
        let forced = models[0]
        let model = Model(id: forced.id, name: forced.name, api: forced.api, provider: forced.provider, baseUrl: forced.baseUrl, reasoning: forced.reasoning, thinkingLevelMap: forced.thinkingLevelMap, input: forced.input, cost: forced.cost, contextWindow: forced.contextWindow, maxTokens: forced.maxTokens, headers: forced.headers, anthropicCompat: AnthropicMessagesCompat(supportsLongCacheRetention: true))
        let body = AnthropicMessagesProvider.buildRequestBody(model: model, context: AIContext(systemPrompt: "sys", messages: [.user("hi")]), options: options)
        guard case .array(let system)? = body["system"], case .object(let systemBlock) = system[0], case .object(let cc)? = systemBlock["cache_control"] else { return XCTFail("missing long cache control") }
        XCTAssertEqual(cc["ttl"], .string("1h"))
    }

    func testAnthropicToolCacheControlCompat() {
        let model = Model(id: "claude", name: "Claude", api: .anthropicMessages, provider: .anthropic, anthropicCompat: AnthropicMessagesCompat(supportsCacheControlOnTools: false))
        var options = StreamOptions(); options.cacheRetention = .long
        let tool = Tool(name: "lookup", description: "lookup", parameters: .object(["type": .string("object")]))
        let body = AnthropicMessagesProvider.buildRequestBody(model: model, context: AIContext(messages: [.user("hi")], tools: [tool]), options: options)
        guard case .array(let tools)? = body["tools"], case .object(let toolObj) = tools[0] else { return XCTFail("missing tool") }
        XCTAssertNil(toolObj["cache_control"])
    }

    func testAnthropicCacheRetentionNoneAndLongCompat() {
        let model = Model(id: "claude", name: "Claude", api: .anthropicMessages, provider: .anthropic, anthropicCompat: AnthropicMessagesCompat(supportsLongCacheRetention: false))
        var options = StreamOptions(); options.cacheRetention = .long
        let longBody = AnthropicMessagesProvider.buildRequestBody(model: model, context: AIContext(systemPrompt: "sys", messages: [.user("hi")]), options: options)
        guard case .array(let system)? = longBody["system"], case .object(let sysBlock) = system[0], case .object(let cc)? = sysBlock["cache_control"] else { return XCTFail("missing cache control") }
        XCTAssertEqual(cc["type"], .string("ephemeral"))
        XCTAssertNil(cc["ttl"])
        options.cacheRetention = CacheRetention.none
        let noneBody = AnthropicMessagesProvider.buildRequestBody(model: model, context: AIContext(systemPrompt: "sys", messages: [.user("hi")]), options: options)
        guard case .array(let noneSystem)? = noneBody["system"], case .object(let noneBlock) = noneSystem[0] else { return XCTFail("missing system") }
        XCTAssertNil(noneBlock["cache_control"])
    }

    func testAnthropicCacheControlRequest() {
        let model = Model(id: "claude", name: "Claude", api: .anthropicMessages, provider: .anthropic, anthropicCompat: AnthropicMessagesCompat(supportsLongCacheRetention: true))
        var options = StreamOptions()
        options.cacheRetention = .long
        let tool = Tool(name: "lookup", description: "lookup", parameters: .object(["type": .string("object")]))
        let body = AnthropicMessagesProvider.buildRequestBody(model: model, context: AIContext(systemPrompt: "sys", messages: [.user("hi")], tools: [tool]), options: options)
        guard case .array(let messages)? = body["messages"], case .object(let msg) = messages[0], case .array(let content)? = msg["content"], case .object(let block) = content[0], case .object(let cc)? = block["cache_control"] else { return XCTFail("missing message cache_control") }
        XCTAssertEqual(cc["ttl"], .string("1h"))
        guard case .array(let tools)? = body["tools"], case .object(let toolObj) = tools[0], case .object(let toolCC)? = toolObj["cache_control"] else { return XCTFail("missing tool cache_control") }
        XCTAssertEqual(toolCC["type"], .string("ephemeral"))
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

    func testOpenAIReasoningDetailsStreamingAndReplay() {
        let detail: JSONValue = .object(["type": .string("reasoning.encrypted"), "id": .string("call_1"), "data": .string("encrypted-signature")])
        let model = Model(id: "google/gemini-test", name: "Gemini", api: .openAICompletions, provider: .openRouter, reasoning: true)
        let sse = """
        data: {"id":"chatcmpl-test","model":"google/gemini-test","choices":[{"index":0,"delta":{"reasoning_details":[{"type":"reasoning.encrypted","id":"call_1","data":"encrypted-signature"}]}}]}

        data: {"id":"chatcmpl-test","model":"google/gemini-test","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"read","arguments":"{\\\"path\\\":\\\"README.md\\\"}"}}]},"finish_reason":"tool_calls"}]}

        """
        guard case .done(_, let assistant)? = OpenAICompletionsProvider.processSSEText(sse, model: model).last else { return XCTFail("missing done") }
        let toolCall = try! XCTUnwrap(assistant.content.first { $0.type == "toolCall" })
        XCTAssertEqual(toolCall.id, "call_1")
        XCTAssertEqual(toolCall.name, "read")
        XCTAssertEqual(toolCall.arguments, ["path": .string("README.md")])
        let signatureData = try! XCTUnwrap(toolCall.thoughtSignature?.data(using: .utf8))
        XCTAssertEqual(try! JSONDecoder().decode(JSONValue.self, from: signatureData), detail)
        let replay = OpenAICompletionsProvider.buildRequestBody(model: model, context: AIContext(messages: [assistant], tools: [Tool(name: "read", description: "Read", parameters: .object(["type": .string("object")]))]), options: nil)
        guard case .array(let messages)? = replay["messages"], case .object(let replayAssistant) = messages[0], case .array(let details)? = replayAssistant["reasoning_details"] else { return XCTFail("missing replay reasoning details") }
        XCTAssertEqual(details, [detail])
    }

    func testOpenAIResponseModelEchoAndEmptyIgnored() {
        let model = Model(id: "openrouter/auto", name: "Auto", api: .openAICompletions, provider: .openRouter)
        let echo = """
        data: {"id":"chatcmpl-2","model":"openrouter/auto","choices":[{"index":0,"delta":{"content":"hi"}}]}

        data: {"id":"chatcmpl-2","model":"openrouter/auto","choices":[{"index":0,"delta":{},"finish_reason":"stop"}],"usage":{"prompt_tokens":1,"completion_tokens":1,"prompt_tokens_details":{"cached_tokens":0}}}

        """
        guard case .done(_, let echoMessage)? = OpenAICompletionsProvider.processSSEText(echo, model: model).last else { return XCTFail("missing echo done") }
        XCTAssertEqual(echoMessage.model, "openrouter/auto")
        XCTAssertNil(echoMessage.responseModel)

        let missing = """
        data: {"id":"chatcmpl-3","choices":[{"index":0,"delta":{"content":"hi"}}]}

        data: {"id":"chatcmpl-3","model":"","choices":[{"index":0,"delta":{"content":"!"}}]}

        data: {"id":"chatcmpl-3","choices":[{"index":0,"delta":{},"finish_reason":"stop"}],"usage":{"prompt_tokens":1,"completion_tokens":2,"prompt_tokens_details":{"cached_tokens":0}}}

        """
        guard case .done(_, let missingMessage)? = OpenAICompletionsProvider.processSSEText(missing, model: model).last else { return XCTFail("missing missing done") }
        XCTAssertEqual(missingMessage.model, "openrouter/auto")
        XCTAssertNil(missingMessage.responseModel)
    }

    func testOpenAISSEErrorFinishEmitsError() {
        let model = Model(id: "gpt", name: "GPT", api: .openAICompletions, provider: .openAI)
        let sse = """
        data: {"choices":[{"index":0,"delta":{"content":"bad"},"finish_reason":"content_filter"}]}

        data: [DONE]

        """
        let events = OpenAICompletionsProvider.processSSEText(sse, model: model)
        XCTAssertTrue(events.contains { if case .error = $0 { return true }; return false })
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

    func testOpenAICompletionsToolChoice() {
        let tool = Tool(name: "lookup", description: "lookup", parameters: .object(["type": .string("object")]))
        var options = StreamOptions()
        options.toolChoice = .string("required")
        let model = Model(id: "gpt", name: "GPT", api: .openAICompletions, provider: .openAI)
        let body = OpenAICompletionsProvider.buildRequestBody(model: model, context: AIContext(messages: [.user("hi")], tools: [tool]), options: options)
        XCTAssertEqual(body["tool_choice"], .string("required"))
        guard case .array(let tools)? = body["tools"] else { return XCTFail("missing tools") }
        XCTAssertGreaterThan(tools.count, 0)
    }

    func testOpenAICompletionsEmptyToolsAndMaxTokens() {
        let model = Model(id: "gpt-4o-mini", name: "GPT", api: .openAICompletions, provider: .openAI)
        let emptyTools = OpenAICompletionsProvider.buildRequestBody(model: model, context: AIContext(messages: [.user("hi")], tools: []), options: nil)
        XCTAssertNil(emptyTools["tools"])
        let noTools = OpenAICompletionsProvider.buildRequestBody(model: model, context: AIContext(messages: [.user("hi")]), options: nil)
        XCTAssertNil(noTools["tools"])
        XCTAssertNil(noTools["max_tokens"])
        XCTAssertNil(noTools["max_completion_tokens"])
        var options = StreamOptions(); options.maxTokens = 1234
        let explicit = OpenAICompletionsProvider.buildRequestBody(model: model, context: AIContext(messages: [.user("hi")]), options: options)
        XCTAssertNil(explicit["max_tokens"])
        XCTAssertEqual(explicit["max_completion_tokens"], JSONValue.number(1234))
        var compat = OpenAICompletionsCompat(); compat.maxTokensField = "max_tokens"
        let maxTokensModel = Model(id: "cf", name: "CF", api: .openAICompletions, provider: .cloudflareAIGateway, completionsCompat: compat)
        let maxTokensBody = OpenAICompletionsProvider.buildRequestBody(model: maxTokensModel, context: AIContext(messages: [.user("hi")]), options: options)
        XCTAssertEqual(maxTokensBody["max_tokens"], .number(1234))
        XCTAssertNil(maxTokensBody["max_completion_tokens"])
    }

    func testOpenAICompat0802Params() {
        let nonOpenAI = Model(id: "m", name: "M", api: .openAICompletions, provider: .openRouter, baseUrl: "https://openrouter.ai/api/v1")
        var options = StreamOptions()
        options.sessionId = "sess"
        let shortBody = OpenAICompletionsProvider.buildRequestBody(model: nonOpenAI, context: AIContext(messages: [.user("hi")]), options: options)
        XCTAssertNil(shortBody["prompt_cache_key"])
        options.cacheRetention = .long
        var compat = OpenAICompletionsCompat(); compat.supportsLongCacheRetention = true
        let longModel = Model(id: "m", name: "M", api: .openAICompletions, provider: .openRouter, baseUrl: "https://openrouter.ai/api/v1", completionsCompat: compat)
        let longBody = OpenAICompletionsProvider.buildRequestBody(model: longModel, context: AIContext(messages: [.user("hi")]), options: options)
        XCTAssertEqual(longBody["prompt_cache_key"], .string("sess"))
        var assistant = Message(role: .assistant, content: [.toolCall(id: "c", name: "t", arguments: [:])])
        let toolHistoryBody = OpenAICompletionsProvider.buildRequestBody(model: nonOpenAI, context: AIContext(messages: [assistant]), options: nil)
        XCTAssertEqual(toolHistoryBody["tools"], .array([]))
    }

    func testOpenAIThinkingAsTextReplay() {
        var compat = OpenAICompletionsCompat()
        compat.requiresThinkingAsText = true
        let model = Model(id: "repro-model", name: "Repro", api: .openAICompletions, provider: .openAI, reasoning: true, completionsCompat: compat)
        var assistant = Message(role: .assistant, content: [ContentBlock.thinking("internal reasoning"), .text("visible answer")])
        assistant.api = .openAICompletions; assistant.provider = .openAI; assistant.model = "repro-model"
        let body = OpenAICompletionsProvider.buildRequestBody(model: model, context: AIContext(messages: [.user("hello"), assistant, .user("continue")]), options: nil)
        guard case .array(let messages)? = body["messages"], case .object(let replay) = messages[1], case .array(let content)? = replay["content"] else { return XCTFail("missing assistant content parts") }
        XCTAssertEqual(content, [.object(["type": .string("text"), "text": .string("internal reasoning")]), .object(["type": .string("text"), "text": .string("visible answer")])])

        assistant.content = [ContentBlock.thinking("internal reasoning")]
        let thinkingOnly = OpenAICompletionsProvider.buildRequestBody(model: model, context: AIContext(messages: [.user("hello"), assistant]), options: nil)
        guard case .array(let thinkingMessages)? = thinkingOnly["messages"], case .object(let thinkingReplay) = thinkingMessages[1], case .array(let thinkingContent)? = thinkingReplay["content"] else { return XCTFail("missing thinking-only content") }
        XCTAssertEqual(thinkingContent, [.object(["type": .string("text"), "text": .string("internal reasoning")])])
    }

    func testOpenAIReasoningContentReplay() {
        var compat = OpenAICompletionsCompat()
        compat.requiresReasoningContentOnAssistantMessages = true
        let model = Model(id: "deep", name: "Deep", api: .openAICompletions, provider: .deepSeek, completionsCompat: compat)
        var assistant = Message(role: .assistant, content: [ContentBlock.thinking("why"), .text("answer")])
        assistant.api = model.api; assistant.provider = model.provider; assistant.model = model.id
        let body = OpenAICompletionsProvider.buildRequestBody(model: model, context: AIContext(messages: [assistant]), options: nil)
        guard case .array(let messages)? = body["messages"], case .object(let first) = messages[0] else { return XCTFail("missing assistant") }
        XCTAssertEqual(first["reasoning_content"], .string("why"))
    }

    func testOpenAICompletionsRequestCacheAndThinkingFormats() {
        var options = StreamOptions(); options.sessionId = String(repeating: "x", count: 67); options.reasoning = .high
        let openai = Model(id: "gpt", name: "GPT", api: .openAICompletions, provider: .openAI, baseUrl: "https://api.openai.com/v1", reasoning: true)
        let openaiBody = OpenAICompletionsProvider.buildRequestBody(model: openai, context: AIContext(messages: [.user("hi")]), options: options)
        XCTAssertEqual(openaiBody["prompt_cache_key"], .string(String(repeating: "x", count: 64)))
        XCTAssertEqual(openaiBody["reasoning_effort"], .string("high"))

        var openRouterCompat = OpenAICompletionsCompat()
        openRouterCompat.thinkingFormat = "openrouter"
        let openRouter = Model(id: "or", name: "OR", api: .openAICompletions, provider: .openRouter, reasoning: true, completionsCompat: openRouterCompat)
        XCTAssertEqual(OpenAICompletionsProvider.buildRequestBody(model: openRouter, context: AIContext(messages: [.user("hi")]), options: options)["reasoning"], JSONValue.object(["effort": .string("high")]))
        var qwenCompat = OpenAICompletionsCompat()
        qwenCompat.thinkingFormat = "qwen-chat-template"
        let qwen = Model(id: "q", name: "Q", api: .openAICompletions, provider: .openRouter, reasoning: true, completionsCompat: qwenCompat)
        XCTAssertEqual(OpenAICompletionsProvider.buildRequestBody(model: qwen, context: AIContext(messages: [.user("hi")]), options: options)["chat_template_kwargs"], JSONValue.object(["enable_thinking": .bool(true), "preserve_thinking": .bool(true)]))
    }

    func testOpenAIToolResultImagesBatchedAfterConsecutiveResults() {
        let model = Model(id: "gpt", name: "GPT", api: .openAICompletions, provider: .openAI, input: ["text", "image"])
        var assistant = Message(role: .assistant, content: [.toolCall(id: "tool-1", name: "read", arguments: ["path": .string("img-1.png")]), .toolCall(id: "tool-2", name: "read", arguments: ["path": .string("img-2.png")])])
        assistant.api = model.api; assistant.provider = model.provider; assistant.model = model.id; assistant.stopReason = .toolUse
        var r1 = Message(role: .toolResult, content: [.text("Read image file [image/png]"), .image(data: "ZmFrZQ==", mimeType: "image/png")])
        r1.toolCallId = "tool-1"; r1.toolName = "read"
        var r2 = Message(role: .toolResult, content: [.text("Read image file [image/png]"), .image(data: "ZmFrZQ==", mimeType: "image/png")])
        r2.toolCallId = "tool-2"; r2.toolName = "read"
        let body = OpenAICompletionsProvider.buildRequestBody(model: model, context: AIContext(messages: [.user("Read the images"), assistant, r1, r2]), options: nil)
        guard case .array(let messages)? = body["messages"] else { return XCTFail("missing messages") }
        let roles = messages.compactMap { if case .object(let obj) = $0 { return obj["role"]?.stringValue }; return nil }
        XCTAssertEqual(roles, ["user", "assistant", "tool", "tool", "user"])
        guard case .object(let imageMessage) = messages.last, case .array(let content)? = imageMessage["content"] else { return XCTFail("missing image message") }
        let imageParts = content.filter { if case .object(let obj) = $0 { return obj["type"] == .string("image_url") }; return false }
        XCTAssertEqual(imageParts.count, 2)
    }

    func testOpenAIMultimodalAndToolResultReplay() {
        var compat = OpenAICompletionsCompat()
        compat.requiresAssistantAfterToolResult = true
        let model = Model(id: "chat", name: "Chat", api: .openAICompletions, provider: .openAI, input: ["text", "image"], completionsCompat: compat)
        var result = Message(role: .toolResult, content: [.text("ok"), .image(data: "abc", mimeType: "image/png")])
        result.toolCallId = "call"
        let body = OpenAICompletionsProvider.buildRequestBody(model: model, context: AIContext(messages: [Message(role: .user, content: [.text("see"), .image(data: "img", mimeType: "image/png")]), result, .user("next")]), options: nil)
        guard case .array(let messages)? = body["messages"] else { return XCTFail("missing messages") }
        guard case .object(let first) = messages[0], case .array(let firstContent)? = first["content"] else { return XCTFail("missing user multimodal") }
        XCTAssertEqual(firstContent.count, 2)
        XCTAssertTrue(messages.contains { if case .object(let obj) = $0 { return obj["role"] == .string("assistant") && obj["content"] == .string("I have processed the tool results.") }; return false })
        XCTAssertTrue(messages.contains { if case .object(let obj) = $0, obj["role"] == .string("user"), case .array(let content)? = obj["content"] { return content.count == 2 }; return false })
    }

    func testOpenAIToolCallIDNormalizationFromResponses() {
        let failingID = "call_pAYbIr76hXIjncD9UE4eGfnS|t5nnb2qYMFWGSsr13fhCd1CaCu3t3qONEPuOudu4HSVEtA8YJSL6FAZUxvoOoD792VIJWl91g87EdqsCWp9krVsdBysQoDaf9lMCLb8BS4EYi4gQd5kBQBYLlgD71PYwvf+TbMD9J9/5OMD42oxSRj8H+vRf78/l2Xla33LWz4nOgsddBlbvabICRs8GHt5C9PK5keFtzyi3lsyVKNlfduK3iphsZqs4MLv4zyGJnvZo/+QzShyk5xnMSQX/f98+aEoNflEApCdEOXipipgeiNWnpFSHbcwmMkZoJhURNu+JEz3xCh1mrXeYoN5o+trLL3IXJacSsLYXDrYTipZZbJFRPAucgbnjYBC+/ZzJOfkwCs+Gkw7EoZR7ZQgJ8ma+9586n4tT4cI8DEhBSZsWMjrCt8dxKg=="
        var assistant = Message(role: .assistant, content: [.toolCall(id: failingID, name: "echo", arguments: ["message": .string("hello")])])
        var result = Message(role: .toolResult, content: [.text("hello")])
        result.toolCallId = failingID
        result.toolName = "echo"
        let model = Model(id: "openai/gpt-5.2-codex", name: "GPT", api: .openAICompletions, provider: .openRouter)
        let body = OpenAICompletionsProvider.buildRequestBody(model: model, context: AIContext(messages: [.user("use tool"), assistant, result]), options: nil)
        guard case .array(let messages)? = body["messages"], case .object(let replay) = messages[1], case .array(let calls)? = replay["tool_calls"], case .object(let call) = calls[0], case .object(let toolResult) = messages[2] else { return XCTFail("missing normalized tool call replay") }
        XCTAssertEqual(call["id"], .string("call_pAYbIr76hXIjncD9UE4eGfnS"))
        XCTAssertEqual(toolResult["tool_call_id"], .string("call_pAYbIr76hXIjncD9UE4eGfnS"))
    }

    func testOpenAIToolCallReplay() {
        var compat = OpenAICompletionsCompat()
        compat.requiresToolResultName = true
        let model = Model(id: "chat", name: "Chat", api: .openAICompletions, provider: .openAI, completionsCompat: compat)
        var assistant = Message(role: .assistant, content: [.toolCall(id: "call", name: "lookup", arguments: ["q": .string("x")])])
        var result = Message(role: .toolResult, content: [.text("ok")])
        result.toolCallId = "call"
        result.toolName = "lookup"
        let body = OpenAICompletionsProvider.buildRequestBody(model: model, context: AIContext(messages: [assistant, result]), options: nil)
        guard case .array(let messages)? = body["messages"], case .object(let first) = messages[0], case .array(let calls)? = first["tool_calls"], case .object(let second) = messages[1] else { return XCTFail("missing replay tool calls") }
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(second["tool_call_id"], .string("call"))
        XCTAssertEqual(second["name"], .string("lookup"))
    }

    func testOpenAIDeveloperRoleSystemPrompt() {
        var compat = OpenAICompletionsCompat()
        compat.supportsDeveloperRole = true
        let model = Model(id: "reasoner", name: "Reasoner", api: .openAICompletions, provider: .openAI, reasoning: true, completionsCompat: compat)
        let body = OpenAICompletionsProvider.buildRequestBody(model: model, context: AIContext(systemPrompt: "rules", messages: [.user("hi")]), options: nil)
        guard case .array(let messages)? = body["messages"], case .object(let first) = messages[0] else { return XCTFail("missing messages") }
        XCTAssertEqual(first["role"], .string("developer"))
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
        let tool = Tool(name: "lookup", description: "lookup", parameters: .object(["type": .string("object")]))
        let body = OpenAICompletionsProvider.buildRequestBody(model: model, context: AIContext(messages: [.user("hi")], tools: [tool]), options: options)
        guard case .array(let tools)? = body["tools"], case .object(let toolObject) = tools[0], case .object(let function)? = toolObject["function"] else { return XCTFail("missing strict tool") }
        XCTAssertEqual(function["strict"], .bool(true))
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

private struct FakeBedrockTransport: BedrockTransport {
    func stream(request: [String: JSONValue], model: Model, context: AIContext, options: StreamOptions?) -> AsyncStream<AIEvent> {
        AsyncStream { continuation in
            var message = Message(role: .assistant, content: [.text("bedrock ok")])
            message.api = model.api
            message.provider = model.provider
            message.model = model.id
            message.stopReason = .stop
            continuation.yield(.done(reason: .stop, message: message))
            continuation.finish()
        }
    }
}

private struct FakeCodexTransport: CodexTransport {
    func stream(request: [String: JSONValue], model: Model, context: AIContext, options: StreamOptions?) -> AsyncStream<AIEvent> {
        AsyncStream { continuation in
            var message = Message(role: .assistant, content: [.text("codex ok")])
            message.api = model.api
            message.provider = model.provider
            message.model = model.id
            message.stopReason = .stop
            continuation.yield(.done(reason: .stop, message: message))
            continuation.finish()
        }
    }
}
