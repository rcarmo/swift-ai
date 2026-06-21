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

    func testModelThinkingLevelMapCodableShape() throws {
        let json = """
        {"id":"m","name":"M","api":"openai-completions","provider":"openai","baseUrl":"","reasoning":true,"thinkingLevelMap":{"off":"none","xhigh":null},"input":["text"],"cost":{"input":0,"output":0,"cacheRead":0,"cacheWrite":0},"contextWindow":1,"maxTokens":1}
        """.data(using: .utf8)!
        let model = try JSONDecoder().decode(Model.self, from: json)
        XCTAssertEqual(model.thinkingLevelMap?[.off] ?? nil, "none")
        XCTAssertTrue(model.thinkingLevelMap?.keys.contains(.xhigh) == true)
        XCTAssertNil(model.thinkingLevelMap?[.xhigh] ?? nil)
        let encoded = try JSONEncoder().encode(model)
        let decoded = try JSONDecoder().decode(Model.self, from: encoded)
        XCTAssertTrue(decoded.thinkingLevelMap?.keys.contains(.xhigh) == true)
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

    func testCloudflareBaseURLHelpers() {
        let model = Model(id: "cf", name: "CF", api: .openAICompletions, provider: .cloudflareWorkersAI, baseUrl: "https://api.cloudflare.com/client/v4/accounts/{CLOUDFLARE_ACCOUNT_ID}/ai/v1")
        XCTAssertTrue(AIUtilities.isCloudflareProvider(.cloudflareWorkersAI))
        XCTAssertEqual(AIUtilities.resolveCloudflareBaseURL(model: model, env: ["CLOUDFLARE_ACCOUNT_ID": "acct"]), "https://api.cloudflare.com/client/v4/accounts/acct/ai/v1")
    }

    func testHashAndSanitizeUtilities() {
        XCTAssertEqual(AIUtilities.shortHash("abc"), AIUtilities.shortHash("abc"))
        XCTAssertEqual(AIUtilities.shortHash("abc").count, 16)
        XCTAssertEqual(AIUtilities.sanitizeSurrogates("ok\u{FFFD}"), "ok")
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
        let imageModel = ImagesModel(id: "img", name: "Image", api: .openRouterImages, provider: .openRouter, cost: ModelCost(input: 2, output: 4))
        var imageUsage = Usage(); imageUsage.input = 1000; imageUsage.output = 1000
        XCTAssertEqual(AIUtilities.calculateCost(imageModel: imageModel, usage: imageUsage).total, 0.006, accuracy: 0.0000001)
    }

    func testFauxProviderHelpers() async throws {
        let registration = await FauxProvider.register()
        await registration.setResponses([.message(FauxProvider.textMessage("hello world"))])
        guard let model = await registration.model() else { return XCTFail("missing faux model") }
        let message = try await SwiftAI.complete(model: model, context: AIContext(messages: [.user("hi")]))
        XCTAssertEqual(message.content.first?.text, "hello world")
        XCTAssertEqual(await registration.pendingResponseCount(), 0)
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
        XCTAssertEqual(provider.apiKey(credentials: OAuthCredentials(refresh: "r", access: "a", expires: 0)), "a")
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

    func testRetryPolicy() throws {
        XCTAssertEqual(RetryPolicy(options: Optional<StreamOptions>.none).maxRetries, 0)
        var options = StreamOptions()
        options.maxRetryDelayMs = 1_000
        let policy = RetryPolicy(options: options)
        XCTAssertEqual(policy.maxRetries, 3)
        XCTAssertEqual(policy.maxRetryDelayMs, 1_000)
        XCTAssertGreaterThan(try policy.delayNanoseconds(attempt: 1), 0)
        XCTAssertThrowsError(try policy.delayMilliseconds(attempt: 1, retryAfterMs: 2_000))
        XCTAssertTrue(HTTPRetry.shouldRetry(statusCode: 429, policy: policy))
        XCTAssertTrue(HTTPRetry.shouldRetry(statusCode: 500, policy: policy))
        XCTAssertFalse(HTTPRetry.shouldRetry(statusCode: 501, policy: RetryPolicy(retryableStatuses: [429])))
        XCTAssertFalse(HTTPRetry.shouldRetry(statusCode: 400, policy: policy))
    }

    func testAzureReasoningEventNormalization() throws {
        let event: [String: JSONValue] = ["type": .string("response.reasoning_text.delta"), "delta": .string("why")]
        XCTAssertEqual(AzureHelpers.normalizeReasoningEvent(event)["type"], .string("response.reasoning_summary_text.delta"))
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
        XCTAssertEqual(BedrockProvider.standardEndpointRegion("https://bedrock-runtime.eu-central-1.amazonaws.com"), "eu-central-1")
        let model = Model(id: "anthropic.claude", name: "Claude", api: .bedrockConverseStream, provider: .amazonBedrock, baseUrl: "https://bedrock-runtime.eu-central-1.amazonaws.com")
        XCTAssertEqual(BedrockProvider.configuredRegion(model: model, options: nil), "eu-central-1")
        let body = BedrockProvider.buildConverseRequest(model: model, context: AIContext(systemPrompt: "sys", messages: [.user("hi")], tools: [Tool(name: "lookup", description: "lookup", parameters: .object(["type": .string("object")]))]), options: nil)
        XCTAssertEqual(body["modelId"], .string("anthropic.claude"))
        XCTAssertNotNil(body["messages"])
        XCTAssertNotNil(body["system"])
        XCTAssertNotNil(body["toolConfig"])
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
