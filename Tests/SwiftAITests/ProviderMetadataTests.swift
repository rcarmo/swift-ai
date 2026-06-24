import XCTest
@testable import SwiftAI

final class ProviderMetadataTests: XCTestCase {
    private func model(_ provider: Provider, _ id: String) throws -> Model {
        try XCTUnwrap(try BuiltinModels.all().first { $0.provider == provider && $0.id == id }, "missing \(provider.rawValue)/\(id)")
    }

    func testCompatProviderDetectionAndModelRegistry() throws {
        let models = try BuiltinModels.all()
        XCTAssertFalse(models.isEmpty)
        XCTAssertTrue(models.contains { $0.provider == .openAI && $0.api == .openAIResponses })
        XCTAssertTrue(models.contains { $0.provider == .openAI && $0.api == .openAICompletions })
        XCTAssertTrue(models.contains { $0.provider == .githubCopilot })
        XCTAssertTrue(models.contains { $0.completionsCompat != nil || $0.responsesCompat != nil || $0.anthropicCompat != nil })
        let providers = Set(models.map(\.provider))
        XCTAssertTrue(providers.contains(.openAI))
        XCTAssertTrue(providers.contains(.anthropic))
        XCTAssertTrue(providers.contains(.openRouter))
    }

    func testXHighReasoningSupportAndUnsupportedError() async throws {
        let models = try BuiltinModels.all()
        let codexMax = try XCTUnwrap(models.first { $0.provider == .openAI && $0.id == "gpt-5.1-codex-max" })
        XCTAssertTrue(AIUtilities.supportsXHigh(model: codexMax))
        let mini = try XCTUnwrap(models.first { $0.provider == .openAI && $0.id == "gpt-5-mini" })
        XCTAssertFalse(AIUtilities.supportsXHigh(model: mini))
        var options = StreamOptions(); options.reasoning = .xhigh; options.apiKey = "fake"
        let events = await SwiftAI.stream(model: mini, context: AIContext(messages: [.user("hi")]), options: options)
        var sawError = false
        for await event in events {
            if case .error(_, let message, _) = event {
                sawError = true
                XCTAssertEqual(message?.stopReason, .error)
                XCTAssertTrue(message?.errorMessage?.contains("xhigh") == true)
            }
        }
        XCTAssertTrue(sawError)
    }

    func testThinkingDisableRequestShapes() throws {
        let models = try BuiltinModels.all()
        let gemini25 = try XCTUnwrap(models.first { $0.provider == .google && $0.id == "gemini-2.5-flash" })
        let google25 = GoogleGenerativeAIProvider.buildRequestBody(model: gemini25, context: AIContext(messages: [.user("hi")]), options: nil)
        XCTAssertEqual(google25["generationConfig"]?.objectValue?["thinkingConfig"], .object(["thinkingBudget": .number(0)]))

        let gemini3 = try XCTUnwrap(models.first { $0.provider == .google && $0.id == "gemini-3-flash-preview" })
        let google3 = GoogleGenerativeAIProvider.buildRequestBody(model: gemini3, context: AIContext(messages: [.user("hi")]), options: nil)
        XCTAssertEqual(google3["generationConfig"]?.objectValue?["thinkingConfig"], .object(["thinkingLevel": .string("MINIMAL")]))

        let anthropicBudget = try XCTUnwrap(models.first { $0.provider == .anthropic && $0.id == "claude-sonnet-4-5" })
        let anthropicBody = AnthropicMessagesProvider.buildRequestBody(model: anthropicBudget, context: AIContext(messages: [.user("hi")]), options: nil)
        XCTAssertEqual(anthropicBody["thinking"], .object(["type": .string("disabled")]))

        let openai = try XCTUnwrap(models.first { $0.provider == .openAI && $0.id == "gpt-5.4-mini" })
        let openaiBody = OpenAIResponsesProvider.buildRequestBody(model: openai, context: AIContext(messages: [.user("hi")]), options: nil)
        XCTAssertEqual(openaiBody["reasoning"], .object(["effort": .string("none"), "summary": .string("auto")]))
    }

    func testGoogleThinkingSignatureDetectionAndRetention() {
        XCTAssertTrue(GoogleGenerativeAIProvider.isThinkingPart(thought: true, thoughtSignature: nil))
        XCTAssertTrue(GoogleGenerativeAIProvider.isThinkingPart(thought: true, thoughtSignature: "opaque-signature"))
        XCTAssertFalse(GoogleGenerativeAIProvider.isThinkingPart(thought: nil, thoughtSignature: "opaque-signature"))
        XCTAssertFalse(GoogleGenerativeAIProvider.isThinkingPart(thought: false, thoughtSignature: "opaque-signature"))
        XCTAssertFalse(GoogleGenerativeAIProvider.isThinkingPart(thought: nil, thoughtSignature: nil))
        XCTAssertFalse(GoogleGenerativeAIProvider.isThinkingPart(thought: false, thoughtSignature: ""))
        let first = GoogleGenerativeAIProvider.retainThoughtSignature(existing: nil, incoming: "sig-1")
        XCTAssertEqual(first, "sig-1")
        let second = GoogleGenerativeAIProvider.retainThoughtSignature(existing: first, incoming: nil)
        XCTAssertEqual(second, "sig-1")
        let third = GoogleGenerativeAIProvider.retainThoughtSignature(existing: second, incoming: "")
        XCTAssertEqual(third, "sig-1")
        XCTAssertEqual(GoogleGenerativeAIProvider.retainThoughtSignature(existing: third, incoming: "sig-2"), "sig-2")
    }

    func testGoogleStreamURLEscapingAndMultilineSSE() throws {
        let model = Model(id: "models/gemini test", name: "Gemini", api: .googleGenerativeAI, provider: .google)
        let url = try GoogleGenerativeAIProvider.buildStreamURL(model: model, apiKey: "key with space", options: nil)
        XCTAssertTrue(url.contains("models/models%2Fgemini%20test:streamGenerateContent"))
        XCTAssertTrue(url.contains("key=key%20with%20space"))
        let vertex = Model(id: "gemini/test", name: "Gemini", api: .googleVertex, provider: .googleVertex)
        var options = StreamOptions(); options.project = "proj ect"; options.location = "us-central1"
        let vertexURL = try GoogleGenerativeAIProvider.buildStreamURL(model: vertex, apiKey: "<authenticated>", options: options)
        XCTAssertTrue(vertexURL.contains("projects/proj%20ect/locations/us-central1/publishers/google/models/gemini%2Ftest"))
        let sse = """
        data: {"responseId":"r","candidates":[{"content":{"parts":[{"text":"hel"}]}}]}
        data: {"candidates":[{"content":{"parts":[{"text":"lo"}]},"finishReason":"STOP"}],"usageMetadata":{"promptTokenCount":1,"candidatesTokenCount":1,"totalTokenCount":2}}

        """
        let events = GoogleGenerativeAIProvider.processSSEText(sse, model: Model(id: "g", name: "G", api: .googleGenerativeAI, provider: .google))
        guard case .done(let reason, let message)? = events.last else { return XCTFail("missing done") }
        XCTAssertEqual(reason, .stop)
        XCTAssertEqual(message.content.first?.text, "hello")
        XCTAssertEqual(message.responseId, "r")
    }

    func testGoogleVertexAPIKeyResolutionURLSemantics() throws {
        let model = Model(id: "gemini-3-flash-preview", name: "Gemini", api: .googleVertex, provider: .googleVertex)
        var options = StreamOptions(); options.project = "test-project"; options.location = "us-central1"
        let adc = try GoogleGenerativeAIProvider.buildStreamURL(model: model, apiKey: "<authenticated>", options: options)
        XCTAssertTrue(adc.contains("/v1/projects/test-project/locations/us-central1/"))
        XCTAssertFalse(adc.contains("key=%3Cauthenticated%3E"))
        XCTAssertFalse(adc.contains("key=<authenticated>"))
        let adc2 = try GoogleGenerativeAIProvider.buildStreamURL(model: model, apiKey: "gcp-vertex-credentials", options: options)
        XCTAssertFalse(adc2.contains("key=gcp-vertex-credentials"))
        let keyed = try GoogleGenerativeAIProvider.buildStreamURL(model: model, apiKey: "AIzaSyExampleRealisticLookingApiKey123456", options: options)
        XCTAssertTrue(keyed.contains("key=AIzaSyExampleRealisticLookingApiKey123456"))

        let custom = Model(id: "gemini-3-flash-preview", name: "Gemini", api: .googleVertex, provider: .googleVertex, baseUrl: "https://proxy.example.com")
        let customURL = try GoogleGenerativeAIProvider.buildStreamURL(model: custom, apiKey: "<authenticated>", options: options)
        XCTAssertTrue(customURL.hasPrefix("https://proxy.example.com/v1/projects/test-project/locations/us-central1/"))
        let fullBase = Model(id: "gemini-3-flash-preview", name: "Gemini", api: .googleVertex, provider: .googleVertex, baseUrl: "https://proxy.example.com/v1/projects/test-project/locations/global")
        let fullURL = try GoogleGenerativeAIProvider.buildStreamURL(model: fullBase, apiKey: "<authenticated>", options: options)
        XCTAssertTrue(fullURL.hasPrefix("https://proxy.example.com/v1/projects/test-project/locations/global/publishers/google/models/"))
        XCTAssertFalse(fullURL.contains("/v1/projects/test-project/locations/global/v1/projects/"))
        XCTAssertTrue(GoogleGenerativeAIProvider.isVertexADCMarker("<authenticated>"))
        XCTAssertTrue(GoogleGenerativeAIProvider.isVertexADCMarker("gcp-vertex-credentials"))
        XCTAssertFalse(GoogleGenerativeAIProvider.isVertexADCMarker("AIzaSyExampleRealisticLookingApiKey123456"))
    }

    func testMistralToolSchemaSerializesAsJSON() {
        let tool = Tool(name: "inspect_schema", description: "Inspect the schema", parameters: .object([
            "type": .string("object"),
            "properties": .object(["nested": .object(["type": .string("object"), "properties": .object(["value": .object(["type": .string("string")])])])])
        ]))
        let model = Model(id: "devstral-medium-latest", name: "Devstral", api: .mistralConversations, provider: .mistral)
        let body = MistralConversationsProvider.buildRequestBody(model: model, context: AIContext(messages: [.user("Hi")], tools: [tool]), options: nil)
        guard case .array(let tools)? = body["tools"], case .object(let first) = tools[0], case .object(let function)? = first["function"], case .object(let parameters)? = function["parameters"], case .object(let properties)? = parameters["properties"], case .object(let nested)? = properties["nested"] else { return XCTFail("missing mistral tool schema") }
        XCTAssertEqual(first["type"], .string("function"))
        XCTAssertEqual(function["name"], .string("inspect_schema"))
        XCTAssertEqual(parameters["type"], .string("object"))
        XCTAssertNotNil(nested["properties"])
    }

    func testMistralReasoningModeAndPromptCacheKey() throws {
        let models = try BuiltinModels.all()
        func body(_ id: String, reasoning: ThinkingLevel? = nil, sessionId: String? = nil, cacheRetention: CacheRetention? = nil) throws -> [String: JSONValue] {
            let model = try XCTUnwrap(models.first { $0.provider == .mistral && $0.id == id })
            var options = StreamOptions()
            options.reasoning = reasoning
            options.sessionId = sessionId
            options.cacheRetention = cacheRetention
            return MistralConversationsProvider.buildRequestBody(model: model, context: AIContext(messages: [.user("Hello")]), options: options)
        }
        let small = try body("mistral-small-2603", reasoning: .medium)
        XCTAssertEqual(small["reasoning_effort"], .string("high"))
        XCTAssertNil(small["prompt_mode"])
        let smallOff = try body("mistral-small-2603")
        XCTAssertNil(smallOff["reasoning_effort"])
        XCTAssertNil(smallOff["prompt_mode"])

        let magistral = try body("magistral-medium-latest", reasoning: .medium)
        XCTAssertEqual(magistral["prompt_mode"], .string("reasoning"))
        XCTAssertNil(magistral["reasoning_effort"])
        let medium = try body("mistral-medium-3.5", reasoning: .medium)
        XCTAssertEqual(medium["reasoning_effort"], .string("high"))
        XCTAssertNil(medium["prompt_mode"])
        let mediumOff = try body("mistral-medium-3.5")
        XCTAssertNil(mediumOff["reasoning_effort"])
        XCTAssertNil(mediumOff["prompt_mode"])

        XCTAssertEqual(try body("mistral-large-latest", sessionId: "session-123")["prompt_cache_key"], .string("session-123"))
        XCTAssertNil(try body("mistral-large-latest", sessionId: "session-123", cacheRetention: .none)["prompt_cache_key"])
    }

    func testGoogleSharedImageToolResultRouting() {
        func context(_ model: Model) -> AIContext {
            var assistant = Message(role: .assistant, content: [
                .toolCall(id: "call_a", name: "read", arguments: ["path": .string("a.txt")]),
                .toolCall(id: "call_img", name: "read", arguments: ["path": .string("image.png")]),
                .toolCall(id: "call_b", name: "read", arguments: ["path": .string("b.txt")])
            ])
            assistant.api = model.api; assistant.provider = model.provider; assistant.model = model.id; assistant.stopReason = .toolUse
            var a = Message(role: .toolResult, content: [.text("alpha text")]); a.toolCallId = "call_a"; a.toolName = "read"
            var img = Message(role: .toolResult, content: [.image(data: "abc", mimeType: "image/png")]); img.toolCallId = "call_img"; img.toolName = "read"
            var b = Message(role: .toolResult, content: [.text("beta text")]); b.toolCallId = "call_b"; b.toolName = "read"
            return AIContext(messages: [.user("read the files"), assistant, a, img, b])
        }
        let gemini2 = Model(id: "gemini-2.5-flash", name: "Gemini", api: .googleGenerativeAI, provider: .google, reasoning: true, input: ["text", "image"], contextWindow: 128000, maxTokens: 8192)
        let two = GoogleGenerativeAIProvider.convertMessages(model: gemini2, messages: context(gemini2).messages)
        XCTAssertEqual(two.count, 5)
        guard case .object(let twoA) = two[2], case .array(let twoAParts)? = twoA["parts"], case .object(let twoImage) = two[3], case .array(let twoImageParts)? = twoImage["parts"], case .object(let twoB) = two[4], case .array(let twoBParts)? = twoB["parts"] else { return XCTFail("bad Gemini 2 routing") }
        XCTAssertTrue(twoAParts.allSatisfy { if case .object(let obj) = $0 { return obj["functionResponse"] != nil }; return false })
        XCTAssertEqual(twoImageParts.first, .object(["text": .string("Tool result image:")]))
        XCTAssertNotNil(twoImageParts.dropFirst().first)
        XCTAssertTrue(twoBParts.first.flatMap { if case .object(let obj) = $0 { return obj["functionResponse"] }; return nil } != nil)

        let gemini3 = Model(id: "gemini-3-pro-preview", name: "Gemini", api: .googleGenerativeAI, provider: .google, reasoning: true, input: ["text", "image"], contextWindow: 128000, maxTokens: 8192)
        let three = GoogleGenerativeAIProvider.convertMessages(model: gemini3, messages: context(gemini3).messages)
        XCTAssertEqual(three.count, 3)
        guard case .object(let toolTurn) = three[2], case .array(let parts)? = toolTurn["parts"], case .object(let imagePart) = parts[1], case .object(let imageResponse)? = imagePart["functionResponse"], case .array(let nestedParts)? = imageResponse["parts"] else { return XCTFail("bad Gemini 3 routing") }
        XCTAssertEqual(parts.count, 3)
        XCTAssertNotNil(nestedParts.first)
    }

    func testGoogleSharedConvertToolsSchemaMetaHandling() {
        let parameters: JSONValue = .object([
            "$schema": .string("http://json-schema.org/draft-07/schema#"),
            "$id": .string("urn:bash-tool"),
            "$comment": .string("comment"),
            "$defs": .object(["commandDef": .object(["type": .string("string")])]),
            "definitions": .object(["legacyDef": .object(["type": .string("number")])]),
            "type": .string("object"),
            "properties": .object(["command": .object(["type": .string("string")]), "refProp": .object(["$ref": .string("#/$defs/someDef"), "type": .string("string")])]),
            "required": .array([.string("command")])
        ])
        let tool = Tool(name: "test_tool", description: "A test tool", parameters: parameters)
        guard case .array(let groups)? = GoogleGenerativeAIProvider.convertTools([tool], useParameters: true), case .object(let group) = groups[0], case .array(let decls)? = group["functionDeclarations"], case .object(let decl) = decls[0], case .object(let stripped)? = decl["parameters"] else { return XCTFail("missing parameters") }
        XCTAssertNil(stripped["$schema"])
        XCTAssertNil(stripped["$id"])
        XCTAssertNil(stripped["$comment"])
        XCTAssertNil(stripped["$defs"])
        XCTAssertNil(stripped["definitions"])
        XCTAssertEqual(stripped["type"], .string("object"))
        guard case .object(let properties)? = stripped["properties"], case .object(let refProp)? = properties["refProp"] else { return XCTFail("missing properties") }
        XCTAssertEqual(refProp["$ref"], .string("#/$defs/someDef"))

        guard case .array(let schemaGroups)? = GoogleGenerativeAIProvider.convertTools([tool], useParameters: false), case .object(let schemaGroup) = schemaGroups[0], case .array(let schemaDecls)? = schemaGroup["functionDeclarations"], case .object(let schemaDecl) = schemaDecls[0] else { return XCTFail("missing schema decl") }
        XCTAssertEqual(schemaDecl["parametersJsonSchema"], parameters)
        XCTAssertNil(GoogleGenerativeAIProvider.convertTools([]))
    }

    func testGitHubCopilotOAuthModelFilteringAndVerificationURI() throws {
        XCTAssertEqual(try GitHubCopilotOAuthProvider.normalizeVerificationURI("https://github.com/login/device"), "https://github.com/login/device")
        XCTAssertThrowsError(try GitHubCopilotOAuthProvider.normalizeVerificationURI("$(id>/tmp/pwned)")) { error in
            XCTAssertTrue(String(describing: error).contains("Untrusted verification_uri"))
        }
        let provider = GitHubCopilotOAuthProvider()
        let allModels = [
            Model(id: "gpt-4.1", name: "GPT", api: .openAICompletions, provider: .githubCopilot),
            Model(id: "claude-opus-4.7", name: "Claude", api: .anthropicMessages, provider: .githubCopilot),
            Model(id: "gpt-5.4-nano", name: "GPT", api: .openAIResponses, provider: .githubCopilot),
            Model(id: "openai", name: "Other", api: .openAICompletions, provider: .openAI)
        ]
        let credentials = OAuthCredentials(refresh: "ghu_refresh_token", access: "tid=test;exp=9999999999;proxy-ep=proxy.individual.githubcopilot.com;", expires: 9999999999, extra: ["availableModelIds": .array([.string("gpt-4.1")])])
        let filtered = provider.modifyModels(allModels, credentials: credentials)
        XCTAssertEqual(filtered.filter { $0.provider == .githubCopilot }.map(\.id), ["gpt-4.1"])
        XCTAssertEqual(filtered.first { $0.provider == .githubCopilot }?.baseUrl, "https://api.individual.githubcopilot.com")
        XCTAssertTrue(filtered.contains { $0.provider == .openAI })
    }

    func testAnthropicBaseURLNormalizationAddsV1() {
        XCTAssertEqual(AnthropicMessagesProvider.normalizeBaseURL(""), "https://api.anthropic.com/v1")
        XCTAssertEqual(AnthropicMessagesProvider.normalizeBaseURL("https://api.anthropic.com"), "https://api.anthropic.com/v1")
        XCTAssertEqual(AnthropicMessagesProvider.normalizeBaseURL("https://api.anthropic.com/"), "https://api.anthropic.com/v1")
        XCTAssertEqual(AnthropicMessagesProvider.normalizeBaseURL("https://proxy.example/v1"), "https://proxy.example/v1")
    }

    func testGitHubCopilotAnthropicHeadersAndAdaptiveThinking() throws {
        let opus47 = try model(.githubCopilot, "claude-opus-4.7")
        XCTAssertEqual(opus47.thinkingLevelMap?[.minimal]!, "low")
        XCTAssertEqual(opus47.thinkingLevelMap?[.xhigh]!, "xhigh")
        XCTAssertTrue(AIUtilities.supportedThinkingLevels(model: opus47).contains(.xhigh))

        let sonnet46 = try model(.githubCopilot, "claude-sonnet-4.6")
        XCTAssertEqual(sonnet46.api, .anthropicMessages)
        XCTAssertEqual(sonnet46.thinkingLevelMap?[.minimal]!, "low")
        XCTAssertEqual(sonnet46.thinkingLevelMap?[.xhigh]!, "max")
        XCTAssertTrue(AIUtilities.supportedThinkingLevels(model: sonnet46).contains(.xhigh))

        let context = AIContext(systemPrompt: "You are a helpful assistant.", messages: [.user("Hello")])
        let headers = AnthropicMessagesProvider.buildRequestHeaders(model: sonnet46, context: context, apiKey: "tid_copilot_session_test_token", options: nil)
        XCTAssertEqual(headers["Authorization"], "Bearer tid_copilot_session_test_token")
        XCTAssertTrue(headers["User-Agent"]?.contains("GitHubCopilotChat") == true)
        XCTAssertEqual(headers["Copilot-Integration-Id"], "vscode-chat")
        XCTAssertEqual(headers["X-Initiator"], "user")
        XCTAssertEqual(headers["Openai-Intent"], "conversation-edits")
        XCTAssertFalse(headers["Anthropic-Beta"]?.contains("fine-grained-tool-streaming") == true)
        XCTAssertFalse(headers["Anthropic-Beta"]?.contains("interleaved-thinking-2025-05-14") == true)

        let body = AnthropicMessagesProvider.buildRequestBody(model: sonnet46, context: context, options: nil)
        XCTAssertEqual(body["model"], .string("claude-sonnet-4.6"))
        XCTAssertEqual(body["stream"], .bool(true))
        XCTAssertEqual(body["max_tokens"], .number(Double(sonnet46.maxTokens)))
        XCTAssertNotNil(body["messages"]?.arrayValue)
    }

    func testBedrockRegionStopReasonAndImageBlockHelpers() {
        XCTAssertEqual(BedrockProvider.standardEndpointRegion("https://bedrock-runtime.eu-central-1.amazonaws.com"), "eu-central-1")
        XCTAssertEqual(BedrockProvider.standardEndpointRegion("https://bedrock-runtime-fips.us-gov-west-1.amazonaws.com"), "us-gov-west-1")
        XCTAssertNil(BedrockProvider.standardEndpointRegion("https://proxy.example.com"))
        XCTAssertEqual(BedrockProvider.mapStopReason("end_turn"), .stop)
        XCTAssertEqual(BedrockProvider.mapStopReason("tool_use"), .toolUse)
        XCTAssertEqual(BedrockProvider.mapStopReason("max_tokens"), .length)
        XCTAssertEqual(BedrockProvider.mapStopReason("guardrail_intervened"), .error)
        XCTAssertEqual(BedrockProvider.createImageBlock(data: "YWJj", mimeType: "image/png"), .object(["image": .object(["format": .string("png"), "source": .object(["bytes": .string("YWJj")])])]))
    }

    func testFireworksKimiK26ModelMetadataAndCompat() throws {
        let model = try model(.fireworks, "accounts/fireworks/models/kimi-k2p6")
        XCTAssertEqual(model.api, .anthropicMessages)
        XCTAssertEqual(model.provider, .fireworks)
        XCTAssertEqual(model.baseUrl, "https://api.fireworks.ai/inference")
        XCTAssertTrue(model.reasoning)
        XCTAssertEqual(model.input, ["text", "image"])
        XCTAssertEqual(model.contextWindow, 262_000)
        XCTAssertEqual(model.maxTokens, 262_000)
        XCTAssertEqual(model.cost, ModelCost(input: 0.95, output: 4, cacheRead: 0.16, cacheWrite: 0))
        XCTAssertEqual(model.anthropicCompat?.sendSessionAffinityHeaders, true)
        XCTAssertEqual(model.anthropicCompat?.supportsEagerToolInputStreaming, false)
        XCTAssertEqual(model.anthropicCompat?.supportsCacheControlOnTools, false)
        XCTAssertEqual(model.anthropicCompat?.supportsLongCacheRetention, false)
        XCTAssertNotNil(try BuiltinModels.all().first { $0.provider == .fireworks && $0.id.hasPrefix("accounts/fireworks/routers/") && $0.id.hasSuffix("-turbo") })
        XCTAssertEqual(ProviderEnvironment.apiKey(for: .fireworks, env: ["FIREWORKS_API_KEY": "test-fireworks-key"]), "test-fireworks-key")
    }

    func testFireworksAnthropicToolCompatRequestShape() {
        let model = Model(id: "accounts/fireworks/models/kimi-k2p6", name: "Kimi", api: .anthropicMessages, provider: .fireworks, anthropicCompat: AnthropicMessagesCompat(supportsEagerToolInputStreaming: false, supportsLongCacheRetention: false, sendSessionAffinityHeaders: true, supportsCacheControlOnTools: false))
        let tool = Tool(name: "lookup", description: "lookup", parameters: .object(["type": .string("object")]))
        let body = AnthropicMessagesProvider.buildRequestBody(model: model, context: AIContext(messages: [.user("hi")], tools: [tool]), options: nil)
        guard case .array(let tools)? = body["tools"], case .object(let first) = tools[0] else { return XCTFail("missing fireworks tool") }
        XCTAssertNil(first["cache_control"])
        XCTAssertNil(first["eager_input_streaming"])
        let native = Model(id: "claude", name: "Claude", api: .anthropicMessages, provider: .anthropic)
        let nativeBody = AnthropicMessagesProvider.buildRequestBody(model: native, context: AIContext(messages: [.user("hi")], tools: [tool]), options: nil)
        guard case .array(let nativeTools)? = nativeBody["tools"], case .object(let nativeTool) = nativeTools[0] else { return XCTFail("missing native tool") }
        XCTAssertNotNil(nativeTool["cache_control"])
        XCTAssertEqual(nativeTool["eager_input_streaming"], .bool(true))
    }

    func testTogetherKimiK26ModelMetadata() throws {
        let model = try model(.together, "moonshotai/Kimi-K2.6")
        XCTAssertEqual(model.api, .openAICompletions)
        XCTAssertEqual(model.provider, .together)
        XCTAssertEqual(model.baseUrl, "https://api.together.ai/v1")
        XCTAssertTrue(model.reasoning)
        XCTAssertNil(model.thinkingLevelMap?[.minimal]!)
        XCTAssertNil(model.thinkingLevelMap?[.low]!)
        XCTAssertNil(model.thinkingLevelMap?[.medium]!)
        XCTAssertEqual(model.input, ["text", "image"])
        XCTAssertEqual(model.contextWindow, 262_144)
        XCTAssertEqual(model.maxTokens, 131_000)
        XCTAssertEqual(model.cost, ModelCost(input: 1.2, output: 4.5, cacheRead: 0.2, cacheWrite: 0))
        XCTAssertEqual(model.completionsCompat?.supportsStore, false)
        XCTAssertEqual(model.completionsCompat?.supportsDeveloperRole, false)
        XCTAssertEqual(model.completionsCompat?.supportsReasoningEffort, false)
        XCTAssertEqual(model.completionsCompat?.maxTokensField, "max_tokens")
        XCTAssertEqual(model.completionsCompat?.thinkingFormat, "together")
        XCTAssertEqual(model.completionsCompat?.supportsStrictMode, false)
        XCTAssertEqual(model.completionsCompat?.supportsLongCacheRetention, false)
    }

    func testTogetherReasoningControls() throws {
        let gptOss = try model(.together, "openai/gpt-oss-120b")
        XCTAssertNil(gptOss.thinkingLevelMap?[.off]!)
        XCTAssertNil(gptOss.thinkingLevelMap?[.minimal]!)
        XCTAssertEqual(gptOss.completionsCompat?.supportsReasoningEffort, true)
        XCTAssertEqual(gptOss.completionsCompat?.thinkingFormat, "openai")

        let deepSeek = try model(.together, "deepseek-ai/DeepSeek-V4-Pro")
        XCTAssertNil(deepSeek.thinkingLevelMap?[.minimal]!)
        XCTAssertNil(deepSeek.thinkingLevelMap?[.low]!)
        XCTAssertNil(deepSeek.thinkingLevelMap?[.medium]!)
        XCTAssertEqual(deepSeek.thinkingLevelMap?[.high]!, "high")
        XCTAssertNil(deepSeek.thinkingLevelMap?[.xhigh]!)
        XCTAssertEqual(deepSeek.completionsCompat?.supportsReasoningEffort, true)
        XCTAssertEqual(deepSeek.completionsCompat?.thinkingFormat, "together")

        let minimax = try model(.together, "MiniMaxAI/MiniMax-M2.7")
        XCTAssertNil(minimax.thinkingLevelMap?[.off]!)
        XCTAssertNil(minimax.thinkingLevelMap?[.minimal]!)
        XCTAssertNil(minimax.thinkingLevelMap?[.low]!)
        XCTAssertNil(minimax.thinkingLevelMap?[.medium]!)
        XCTAssertNil(minimax.completionsCompat?.thinkingFormat)
        XCTAssertEqual(minimax.completionsCompat?.supportsReasoningEffort, false)
    }

    func testTogetherAPIKeyEnvironment() {
        XCTAssertEqual(ProviderEnvironment.apiKey(for: .together, env: ["TOGETHER_API_KEY": "test-together-key"]), "test-together-key")
    }
}
