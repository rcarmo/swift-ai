import XCTest
@testable import SwiftAI

final class ProviderMetadataTests: XCTestCase {
    private func model(_ provider: Provider, _ id: String) throws -> Model {
        try XCTUnwrap(try BuiltinModels.all().first { $0.provider == provider && $0.id == id }, "missing \(provider.rawValue)/\(id)")
    }

    private func encodedMap<T: Encodable>(_ values: [T], key: (T) -> String) throws -> [String: String] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var out: [String: String] = [:]
        for value in values { out[key(value)] = String(data: try encoder.encode(value), encoding: .utf8)! }
        return out
    }

    private func normalizedTextModelData(path: String) throws -> Data {
        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path)))
        guard var records = raw as? [[String: Any]] else { throw AIError.invalidResponse("model data must be an array") }
        for index in records.indices {
            guard let compat = records[index].removeValue(forKey: "compat") as? [String: Any] else { continue }
            switch records[index]["api"] as? String {
            case "openai-completions": records[index]["completionsCompat"] = compat
            case "openai-responses", "azure-openai-responses", "openai-codex-responses": records[index]["responsesCompat"] = compat
            case "anthropic-messages": records[index]["anthropicCompat"] = compat
            default: records[index]["compat"] = compat
            }
        }
        return try JSONSerialization.data(withJSONObject: records, options: [.sortedKeys])
    }

    func testCompatProviderDetectionAndModelRegistry() throws {
        let models = try BuiltinModels.all()
        XCTAssertFalse(models.isEmpty)
        XCTAssertTrue(models.contains { $0.provider == .openAI && $0.api == .openAIResponses })
        XCTAssertTrue(models.contains { $0.provider == .openAI })
        XCTAssertTrue(models.contains { $0.provider == .githubCopilot })
        XCTAssertTrue(models.contains { !$0.input.isEmpty || $0.contextWindow > 0 || $0.maxTokens > 0 })
        let providers = Set(models.map(\.provider))
        XCTAssertTrue(providers.contains(.openAI))
        XCTAssertTrue(providers.contains(.anthropic))
        XCTAssertTrue(providers.contains(.openRouter))
    }

    func testXHighReasoningSupportAndUnsupportedError() async throws {
        let codexMax = Model(id: "xhigh-fixture", name: "XHigh", api: .openAIResponses, provider: .openAI, reasoning: true, thinkingLevelMap: [.low: "low", .medium: "medium", .high: "high", .xhigh: "xhigh"])
        XCTAssertTrue(AIUtilities.supportsXHigh(model: codexMax))
        let mini = Model(id: "no-xhigh-fixture", name: "No XHigh", api: .openAIResponses, provider: .openAI, reasoning: true, thinkingLevelMap: [.low: "low", .medium: "medium", .high: "high"])
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
        func model(_ id: String, reasoning: Bool = true) -> Model {
            Model(id: id, name: id, api: .mistralConversations, provider: .mistral, reasoning: reasoning, thinkingLevelMap: [ModelThinkingLevel.medium: "high"])
        }
        func body(_ model: Model, reasoning: ThinkingLevel? = nil, sessionId: String? = nil, cacheRetention: CacheRetention? = nil) -> [String: JSONValue] {
            var options = StreamOptions()
            options.reasoning = reasoning
            options.sessionId = sessionId
            options.cacheRetention = cacheRetention
            return MistralConversationsProvider.buildRequestBody(model: model, context: AIContext(messages: [.user("Hello")]), options: options)
        }
        let small = body(model("mistral-small-2603"), reasoning: .medium)
        XCTAssertEqual(small["reasoning_effort"], .string("high"))
        XCTAssertNil(small["prompt_mode"])
        let smallOff = body(model("mistral-small-2603"))
        XCTAssertNil(smallOff["reasoning_effort"])
        XCTAssertNil(smallOff["prompt_mode"])

        let magistral = body(model("magistral-medium-latest"), reasoning: .medium)
        XCTAssertEqual(magistral["prompt_mode"], .string("reasoning"))
        XCTAssertNil(magistral["reasoning_effort"])
        let medium = body(model("mistral-medium-3.5"), reasoning: .medium)
        XCTAssertEqual(medium["reasoning_effort"], .string("high"))
        XCTAssertNil(medium["prompt_mode"])
        let mediumOff = body(model("mistral-medium-3.5"))
        XCTAssertNil(mediumOff["reasoning_effort"])
        XCTAssertNil(mediumOff["prompt_mode"])

        XCTAssertEqual(body(model("mistral-large-latest", reasoning: false), sessionId: "session-123")["prompt_cache_key"], JSONValue.string("session-123"))
        XCTAssertNil(body(model("mistral-large-latest", reasoning: false), sessionId: "session-123", cacheRetention: CacheRetention.none)["prompt_cache_key"])
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
        XCTAssertEqual(GitHubCopilotOAuthProvider.nextDevicePollIntervalAfterSlowDown(current: 5, serverInterval: nil), 10)
        XCTAssertEqual(GitHubCopilotOAuthProvider.nextDevicePollIntervalAfterSlowDown(current: 5, serverInterval: 12), 12)
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

    func testAnthropicRequestJSONRoundTrip() throws {
        let model = Model(id: "claude", name: "Claude", api: .anthropicMessages, provider: .anthropic)
        let body = AnthropicMessagesProvider.buildRequestBody(model: model, context: AIContext(systemPrompt: "sys", messages: [.user("hi")], tools: [Tool(name: "lookup", description: "Lookup", parameters: .object(["type": .string("object")]))]), options: nil)
        let data = try JSONEncoder().encode(JSONValue.object(body))
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        XCTAssertEqual(decoded, .object(body))
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
        XCTAssertEqual(sonnet46.thinkingLevelMap?[.max]!, "max")
        XCTAssertFalse(AIUtilities.supportedThinkingLevels(model: sonnet46).contains(.xhigh))
        XCTAssertTrue(AIUtilities.supportedThinkingLevels(model: sonnet46).contains(.max))

        let sonnet5 = try model(.githubCopilot, "claude-sonnet-5")
        XCTAssertEqual(sonnet5.thinkingLevelMap?[.xhigh]!, "xhigh")
        XCTAssertEqual(sonnet5.thinkingLevelMap?[.max]!, "max")
        XCTAssertTrue(AIUtilities.supportedThinkingLevels(model: sonnet5).contains(.xhigh))

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

    func testBedrockConverseRequestIncludesSystemToolsAndThinking() {
        let tool = Tool(name: "lookup", description: "Lookup", parameters: .object(["type": .string("object")]))
        let model = Model(id: "global.anthropic.claude-opus-4-7-v1", name: "Claude", api: .bedrockConverseStream, provider: .amazonBedrock, reasoning: true, thinkingLevelMap: [.xhigh: "xhigh"])
        var options = StreamOptions(); options.reasoning = .xhigh; options.maxTokens = 256; options.temperature = 0.2
        let request = BedrockProvider.buildConverseRequest(model: model, context: AIContext(systemPrompt: "sys", messages: [.user("hi")], tools: [tool]), options: options)
        XCTAssertEqual(request["modelId"], .string(model.id))
        XCTAssertNotNil(request["system"])
        XCTAssertNotNil(request["toolConfig"])
        XCTAssertEqual(request["inferenceConfig"]?.objectValue?["maxTokens"], .number(256))
        XCTAssertEqual(request["additionalModelRequestFields"]?.objectValue?["thinking"], .object(["type": .string("adaptive"), "display": .string("summarized"), "block_binding": .object(["prefix_mismatch_behavior": .string("drop_block")])]))
        XCTAssertEqual(request["additionalModelRequestFields"]?.objectValue?["output_config"], .object(["effort": .string("xhigh")]))
        XCTAssertEqual(request["additionalModelRequestFields"]?.objectValue?["anthropic_beta"], .array([.string("thinking-binding-controls-2026-08-01")]))

        var r1 = Message(role: .toolResult, content: [.text("one")]); r1.toolCallId = "t1"; r1.toolName = "lookup"
        var r2 = Message(role: .toolResult, content: [.text("two")]); r2.toolCallId = "t2"; r2.toolName = "lookup"
        let coalesced = BedrockProvider.buildConverseRequest(model: model, context: AIContext(messages: [r1, r2]), options: nil)
        guard case .array(let messages)? = coalesced["messages"], case .object(let first) = messages.first, case .array(let content)? = first["content"] else { return XCTFail("missing coalesced tool results") }
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(content.count, 2)
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

    func testFireworksKimiK3ModelMetadataAndCompat() throws {
        let model = try model(.fireworks, "accounts/fireworks/models/kimi-k3")
        XCTAssertEqual(model.api, .openAICompletions)
        XCTAssertEqual(model.provider, .fireworks)
        XCTAssertEqual(model.baseUrl, "https://api.fireworks.ai/inference/v1")
        XCTAssertTrue(model.reasoning)
        XCTAssertEqual(model.input, ["text", "image"])
        XCTAssertEqual(model.contextWindow, 1_048_576)
        XCTAssertEqual(model.maxTokens, 131_072)
        XCTAssertEqual(model.cost, ModelCost(input: 3, output: 15, cacheRead: 0.3, cacheWrite: 0))
        XCTAssertEqual(model.completionsCompat?.supportsStore, false)
        XCTAssertEqual(model.completionsCompat?.supportsDeveloperRole, false)
        XCTAssertEqual(model.completionsCompat?.sendSessionAffinityHeaders, true)
        XCTAssertEqual(model.completionsCompat?.thinkingFormat, "openai")
        XCTAssertNil(try BuiltinModels.all().first { $0.provider == .fireworks && $0.id == "accounts/fireworks/routers/kimi-k2-instruct-turbo" })
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

    func testTogetherKimiK3ModelMetadata() throws {
        let model = try model(.together, "moonshotai/Kimi-K3")
        XCTAssertEqual(model.api, .openAICompletions)
        XCTAssertEqual(model.provider, .together)
        XCTAssertEqual(model.baseUrl, "https://api.together.ai/v1")
        XCTAssertTrue(model.reasoning)
        XCTAssertNil(model.thinkingLevelMap?[.minimal]!)
        XCTAssertNil(model.thinkingLevelMap?[.low]!)
        XCTAssertNil(model.thinkingLevelMap?[.medium]!)
        XCTAssertEqual(model.input, ["text", "image"])
        XCTAssertEqual(model.contextWindow, 1_048_576)
        XCTAssertEqual(model.maxTokens, 131_072)
        XCTAssertEqual(model.cost, ModelCost(input: 3, output: 15, cacheRead: 0.3, cacheWrite: 0))
        XCTAssertEqual(model.completionsCompat?.supportsStore, false)
        XCTAssertEqual(model.completionsCompat?.supportsDeveloperRole, false)
        XCTAssertEqual(model.completionsCompat?.supportsReasoningEffort, false)
        XCTAssertEqual(model.completionsCompat?.maxTokensField, "max_tokens")
        XCTAssertEqual(model.completionsCompat?.thinkingFormat, "together")
        XCTAssertEqual(model.completionsCompat?.supportsStrictMode, false)
        XCTAssertEqual(model.completionsCompat?.supportsLongCacheRetention, false)
    }

    func testV101TypedCatalogPreservesOfficialCompatFlags() throws {
        let models = try BuiltinModels.all()
        let completionGrammar = models.filter { $0.completionsCompat?.supportsOpenAIGrammarTools == true }
        let responseGrammar = models.filter { $0.responsesCompat?.supportsOpenAIGrammarTools == true }
        XCTAssertEqual(completionGrammar.count + responseGrammar.count, 111)
        XCTAssertTrue(models.contains { $0.completionsCompat?.supportsStrictMode == false })
        XCTAssertTrue(models.contains { $0.completionsCompat?.sendSessionAffinityHeaders == true })
        XCTAssertTrue(models.contains { $0.responsesCompat?.supportsAdditionalTools == true })
    }

    func testV101TypedBuiltinModelsMatchRawSnapshotsAfterDecode() throws {
        let rawOfficial = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: "scripts/models.v1.0.1.json"))) as! [[String: Any]]
        let typed = try BuiltinModels.all()
        XCTAssertEqual(typed.count, rawOfficial.count)
        let typedGrammar = typed.filter { $0.completionsCompat?.supportsOpenAIGrammarTools == true || $0.responsesCompat?.supportsOpenAIGrammarTools == true }.count
        let rawGrammar = rawOfficial.filter { (($0["compat"] as? [String: Any])?["supportsOpenAIGrammarTools"] as? Bool) == true || (($0["compat"] as? [String: Any])?["supportsOpenaiGrammarTools"] as? Bool) == true }.count
        XCTAssertEqual(typedGrammar, 111)
        XCTAssertEqual(typedGrammar, rawGrammar)
        let typedCompletionMidSystem = typed.filter { $0.completionsCompat?.supportsMidConvoSystemMessages == true }.count
        let rawCompletionMidSystem = rawOfficial.filter { ($0["api"] as? String) == "openai-completions" && (($0["compat"] as? [String: Any])?["supportsMidConvoSystemMessages"] as? Bool) == true }.count
        XCTAssertEqual(typedCompletionMidSystem, 25)
        XCTAssertEqual(typedCompletionMidSystem, rawCompletionMidSystem)
        let typedCompletionToolAdditions = typed.filter { $0.completionsCompat?.supportsMidConvoToolAdditions == true }.count
        let rawCompletionToolAdditions = rawOfficial.filter { ($0["api"] as? String) == "openai-completions" && (($0["compat"] as? [String: Any])?["supportsMidConvoToolAdditions"] as? Bool) == true }.count
        XCTAssertEqual(typedCompletionToolAdditions, 6)
        XCTAssertEqual(typedCompletionToolAdditions, rawCompletionToolAdditions)
        let typedResponsesMidSystem = typed.filter { $0.responsesCompat?.supportsMidConvoSystemMessages == true }.count
        let rawResponsesMidSystem = rawOfficial.filter { (($0["api"] as? String)?.contains("responses") == true) && (($0["compat"] as? [String: Any])?["supportsMidConvoSystemMessages"] as? Bool) == true }.count
        XCTAssertEqual(typedResponsesMidSystem, 42)
        XCTAssertEqual(typedResponsesMidSystem, rawResponsesMidSystem)
        XCTAssertEqual(typed.filter { $0.responsesCompat?.supportsReasoningEffort == false }.count, 1)
        let rawStrictFalse = rawOfficial.filter { (($0["compat"] as? [String: Any])?["supportsStrictMode"] as? Bool) == false }.count
        let typedStrictFalse = typed.filter { $0.completionsCompat?.supportsStrictMode == false || $0.responsesCompat?.supportsStrictMode == false }.count
        XCTAssertEqual(typedStrictFalse, rawStrictFalse)
        let rawAffinity = rawOfficial.filter { (($0["compat"] as? [String: Any])?["sendSessionAffinityHeaders"] as? Bool) == true }.count
        let typedAffinity = typed.filter { $0.completionsCompat?.sendSessionAffinityHeaders == true || $0.anthropicCompat?.sendSessionAffinityHeaders == true }.count
        XCTAssertEqual(typedAffinity, rawAffinity)
        let rawAdditionalTools = rawOfficial.filter { (($0["compat"] as? [String: Any])?["supportsAdditionalTools"] as? Bool) == true }.count
        let typedAdditionalTools = typed.filter { $0.responsesCompat?.supportsAdditionalTools == true }.count
        XCTAssertEqual(typedAdditionalTools, rawAdditionalTools)
        let actualImages = try encodedMap(BuiltinImageModels.all()) { "\($0.provider.rawValue)/\($0.id)" }
        let rawImages = try JSONDecoder().decode([ImagesModel].self, from: Data(contentsOf: URL(fileURLWithPath: "scripts/image-models.v1.0.1.json")))
        let expectedImages = try encodedMap(rawImages) { "\($0.provider.rawValue)/\($0.id)" }
        XCTAssertEqual(actualImages, expectedImages)
        XCTAssertEqual(try BuiltinImageModels.all().filter { $0.inputLimits != nil }.count, 57)
        let actualClassifiers = try encodedMap(BuiltinClassifierModels.all()) { "\($0.provider.rawValue)/\($0.id)" }
        let rawClassifiers = try JSONDecoder().decode([ClassifierModel].self, from: Data(contentsOf: URL(fileURLWithPath: "scripts/classifier-models.v1.0.1.json")))
        let expectedClassifiers = try encodedMap(rawClassifiers) { "\($0.provider.rawValue)/\($0.id)" }
        XCTAssertEqual(actualClassifiers, expectedClassifiers)
    }

    func testTogetherReasoningControls() throws {
        let gptOss = try model(.together, "openai/gpt-oss-120b")
        XCTAssertNil(gptOss.thinkingLevelMap?[.off]!)
        XCTAssertNil(gptOss.thinkingLevelMap?[.minimal]!)
        XCTAssertEqual(gptOss.completionsCompat?.supportsReasoningEffort, true)
        XCTAssertEqual(gptOss.completionsCompat?.thinkingFormat, "openai")

        let deepSeek = try model(.together, "deepseek-ai/DeepSeek-V4-Pro-0813")
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

    func testUpstream08010KimiAndMoonshotCatalogMetadata() throws {
        let kimiK3 = try model(.kimiCoding, "k3")
        XCTAssertEqual(kimiK3.anthropicCompat?.forceAdaptiveThinking, true)
        XCTAssertEqual(kimiK3.anthropicCompat?.allowEmptySignature, true)
        XCTAssertEqual(kimiK3.thinkingLevelMap?[.max]!, "max")
        XCTAssertNil(kimiK3.thinkingLevelMap?[.xhigh]!)

        for provider in [Provider.moonshotAI, Provider.moonshotAICN] {
            let moonshot = try model(provider, "kimi-k3")
            XCTAssertEqual(moonshot.cost.input, 3)
            XCTAssertEqual(moonshot.cost.output, 15)
            XCTAssertEqual(moonshot.cost.cacheRead, 0.3)
            XCTAssertEqual(moonshot.cost.cacheWrite, 0)
        }
    }

    func testUpstream08010XAIAndOpenCodeCatalogDisposition() throws {
        let models = try BuiltinModels.all()
        let xaiIDs = Set(models.filter { $0.provider == .xai }.map(\.id))
        XCTAssertEqual(xaiIDs, ["grok-4.3", "grok-4.5", "grok-4.6", "grok-4.7"])
        XCTAssertFalse(xaiIDs.contains("grok-3"))
        XCTAssertFalse(xaiIDs.contains("grok-code-fast-1"))
        XCTAssertFalse(xaiIDs.contains("grok-4.3-fast"))

        let openCodeIDs = Set(models.filter { $0.provider == .openCodeGo }.map(\.id))
        XCTAssertFalse(openCodeIDs.contains("qwen3.7-max"))
        XCTAssertTrue(openCodeIDs.contains("qwen3.8-max"))
        XCTAssertTrue(openCodeIDs.contains("kimi-k3"))
        XCTAssertTrue(openCodeIDs.contains("glm-5.3"))
        XCTAssertFalse(openCodeIDs.contains("qwen3-coder"))
        XCTAssertFalse(openCodeIDs.contains("glm-4.6"))

        let openCodeResponses = try model(.openCodeGo, "grok-4.6")
        XCTAssertEqual(openCodeResponses.api, .openAIResponses)
        let openCodeGrok47 = try model(.openCodeGo, "grok-4.7")
        XCTAssertEqual(openCodeGrok47.api, .openAIResponses)
    }

    func testUpstream0811QwenTokenPlanCatalogMetadata() throws {
        for provider in [Provider.qwenTokenPlan, Provider.qwenTokenPlanCN] {
            let ids = Set(try BuiltinModels.all().filter { $0.provider == provider }.map(\.id))
            XCTAssertEqual(ids.count, 20)
            XCTAssertTrue(ids.contains("qwen3.8-max"))
            XCTAssertTrue(ids.contains("glm-5.2"))
            let model = try self.model(provider, "qwen3.8-max")
            XCTAssertEqual(model.api, .openAICompletions)
            XCTAssertTrue(model.baseUrl.contains("aliyuncs.com"))
        }
        XCTAssertEqual(ProviderEnvironment.apiKey(for: .qwenTokenPlan, env: ["QWEN_TOKEN_PLAN_API_KEY": "qwen-key"]), "qwen-key")
        XCTAssertEqual(ProviderEnvironment.apiKey(for: .qwenTokenPlanCN, env: ["DASHSCOPE_API_KEY": "dashscope-key"]), "dashscope-key")
    }

    func testUpstream0841QwenTokenPlanIndividualProvider() throws {
        let models = try BuiltinModels.all()
        let individual = models.filter { $0.provider == .qwenTokenPlanIndividual }
        let individualIDs = Set(individual.map(\.id))
        XCTAssertEqual(individualIDs, [
            "deepseek-v4-flash-0731",
            "deepseek-v4-pro",
            "deepseek-v4-pro-0813",
            "glm-5.2",
            "qwen3.6-flash",
            "qwen3.7-max",
            "qwen3.7-plus",
            "qwen3.8-flash",
            "qwen3.8-max"
        ])
        XCTAssertFalse(individualIDs.contains("qwen3.8-max-preview"))
        XCTAssertFalse(individualIDs.contains("qwen-image-2.0"))

        let qwen38 = try model(.qwenTokenPlanIndividual, "qwen3.8-max")
        XCTAssertEqual(qwen38.api, .openAICompletions)
        XCTAssertEqual(qwen38.baseUrl, "https://token-plan.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1")
        XCTAssertTrue(qwen38.input.contains("text"))
        XCTAssertTrue(qwen38.reasoning)
        XCTAssertEqual(qwen38.completionsCompat?.thinkingFormat, "qwen")
        XCTAssertEqual(qwen38.completionsCompat?.supportsDeveloperRole, false)
        XCTAssertEqual(qwen38.completionsCompat?.supportsStore, false)
        XCTAssertEqual(qwen38.completionsCompat?.supportsReasoningEffort, true)
        XCTAssertNil(qwen38.thinkingLevelMap?[.high]!)
        XCTAssertEqual(qwen38.thinkingLevelMap?[.xhigh]!, "xhigh")
        XCTAssertNil(qwen38.thinkingLevelMap?[.max]!)

        XCTAssertEqual(ProviderEnvironment.apiKey(for: .qwenTokenPlanIndividual, env: ["QWEN_TOKEN_PLAN_API_KEY": "qwen-key"]), "qwen-key")
        XCTAssertEqual(ProviderEnvironment.apiKey(for: .qwenTokenPlanIndividual, env: ["DASHSCOPE_API_KEY": "dashscope-key"]), "dashscope-key")
    }

    func testUpstream0841QwenTokenPlanIndividualRequestShape() throws {
        let deepSeek = try model(.qwenTokenPlanIndividual, "deepseek-v4-pro")
        var high = StreamOptions()
        high.reasoning = .high
        let highBody = OpenAICompletionsProvider.buildRequestBody(model: deepSeek, context: AIContext(messages: [.user("hi")]), options: high)
        XCTAssertEqual(highBody["enable_thinking"], .bool(true))
        XCTAssertEqual(highBody["reasoning_effort"], .string("high"))
        XCTAssertNil(highBody["thinking"])

        let qwen38 = try model(.qwenTokenPlanIndividual, "qwen3.8-max")
        var xhigh = StreamOptions()
        xhigh.reasoning = .xhigh
        let xhighBody = OpenAICompletionsProvider.buildRequestBody(model: qwen38, context: AIContext(messages: [.user("hi")]), options: xhigh)
        XCTAssertEqual(xhighBody["enable_thinking"], .bool(true))
        XCTAssertEqual(xhighBody["reasoning_effort"], .string("xhigh"))
        XCTAssertNil(xhighBody["thinking"])

        let noReasoningBody = OpenAICompletionsProvider.buildRequestBody(model: qwen38, context: AIContext(messages: [.user("hi")]), options: nil)
        XCTAssertEqual(noReasoningBody["enable_thinking"], .bool(false))
        XCTAssertNil(noReasoningBody["reasoning_effort"])
    }

    func testTogetherAPIKeyEnvironment() {
        XCTAssertEqual(ProviderEnvironment.apiKey(for: .together, env: ["TOGETHER_API_KEY": "test-together-key"]), "test-together-key")
    }

    func testV0992AnthropicFederationAndStrictToolBehavior() async throws {
        await AnthropicMessagesProvider.clearFederationTokenCache()
        defer { Task { await AnthropicMessagesProvider.clearFederationTokenCache() } }
        let tokenFile = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("anthropic-identity-\(UUID().uuidString).jwt")
        try "  header.payload.signature  \n".write(to: tokenFile, atomically: true, encoding: .utf8)
        let model = Model(id: "claude", name: "Claude", api: .anthropicMessages, provider: .anthropic, baseUrl: "https://api.anthropic.com/v1")
        var options = StreamOptions()
        options.env = [
            "ANTHROPIC_FEDERATION_RULE_ID": "fdrl_test",
            "ANTHROPIC_ORGANIZATION_ID": "org-test",
            "ANTHROPIC_WORKSPACE_ID": "wrk-test",
            "ANTHROPIC_SERVICE_ACCOUNT_ID": "svc-test",
            "ANTHROPIC_IDENTITY_TOKEN_FILE": tokenFile.path
        ]
        XCTAssertNotNil(AnthropicMessagesProvider.workloadIdentityFederationConfig(model: model, options: options))
        var explicit = options
        explicit.apiKey = "anthropic-key"
        XCTAssertNil(AnthropicMessagesProvider.workloadIdentityFederationConfig(model: model, options: explicit))
        var headerOptions = options
        headerOptions.headers = ["Authorization": "Bearer explicit"]
        XCTAssertNil(AnthropicMessagesProvider.workloadIdentityFederationConfig(model: model, options: headerOptions))

        let config = try XCTUnwrap(AnthropicMessagesProvider.workloadIdentityFederationConfig(model: model, options: options))
        let (request, body) = try AnthropicMessagesProvider.federationTokenRequest(model: model, config: config, identityToken: "jwt-token")
        XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/v1/oauth/token")
        XCTAssertFalse(request.url?.absoluteString.contains("jwt-token") == true)
        XCTAssertFalse((request.allHTTPHeaderFields ?? [:]).values.contains { $0.contains("jwt-token") })
        XCTAssertEqual(body["subject_token"], .string("jwt-token"))
        XCTAssertEqual(body["federation_rule_id"], .string("fdrl_test"))
        XCTAssertEqual(body["organization_id"], .string("org-test"))
        XCTAssertEqual(body["workspace_id"], .string("wrk-test"))
        XCTAssertEqual(body["service_account_id"], .string("svc-test"))

        final class Box: @unchecked Sendable { var calls = 0; var bodies: [[String: JSONValue]] = []; func record(_ body: [String: JSONValue]) { calls += 1; bodies.append(body) } }
        let box = Box()
        await AnthropicMessagesProvider.setFederationTokenTransport { _, body in
            box.record(body)
            return ["access_token": .string("federated-access"), "expires_in": .number(3600)]
        }
        let concurrentOptions = options
        async let first = AnthropicMessagesProvider.resolveFederationAccessToken(model: model, options: concurrentOptions, nowMs: 1_000)
        async let second = AnthropicMessagesProvider.resolveFederationAccessToken(model: model, options: concurrentOptions, nowMs: 1_000)
        let tokens = try await [first, second]
        XCTAssertEqual(tokens, ["federated-access", "federated-access"])
        XCTAssertEqual(box.calls, 1)
        XCTAssertEqual(box.bodies.first?["subject_token"], .string("header.payload.signature"))
        let cached = try await AnthropicMessagesProvider.resolveFederationAccessToken(model: model, options: options, nowMs: 2_000)
        XCTAssertEqual(cached, "federated-access")
        XCTAssertEqual(box.calls, 1)
        _ = try await AnthropicMessagesProvider.resolveFederationAccessToken(model: model, options: options, nowMs: 3_600_000)
        XCTAssertEqual(box.calls, 2)
        let headers = AnthropicMessagesProvider.buildRequestHeaders(model: model, context: AIContext(messages: [.user("hi")]), apiKey: "Bearer federated-access", options: options)
        XCTAssertEqual(headers["Authorization"], "Bearer federated-access")
        XCTAssertNil(headers["X-Api-Key"])

        await AnthropicMessagesProvider.clearFederationTokenCache()
        await AnthropicMessagesProvider.setFederationTokenTransport { _, _ in ["expires_in": .number(3600)] }
        do {
            _ = try await AnthropicMessagesProvider.resolveFederationAccessToken(model: model, options: options, nowMs: 1_000)
            XCTFail("missing access_token should throw")
        } catch {
            XCTAssertTrue(String(describing: error).contains("access_token"))
            XCTAssertFalse(String(describing: error).contains("header.payload.signature"))
        }
        await AnthropicMessagesProvider.clearFederationTokenCache()
        await AnthropicMessagesProvider.setFederationTokenTransport { _, _ in throw AIError.provider("exchange failed") }
        do {
            _ = try await AnthropicMessagesProvider.resolveFederationAccessToken(model: model, options: options, nowMs: 1_000)
            XCTFail("transport error should throw")
        } catch {
            XCTAssertTrue(String(describing: error).contains("exchange failed"))
            XCTAssertFalse(String(describing: error).contains("header.payload.signature"))
        }

        let strictTool = Tool(name: "lookup", description: "Lookup", parameters: .object([
            "type": .string("object"),
            "properties": .object(["query": .object(["type": .string("string")]), "limit": .object(["type": .string("number")])]),
            "required": .array([.string("query")])
        ]), constrainedSampling: .jsonSchema(strict: "prefer"))
        let bodyStrict = AnthropicMessagesProvider.buildRequestBody(model: model, context: AIContext(messages: [.user("hi")], tools: [strictTool]), options: nil)
        guard case .array(let tools)? = bodyStrict["tools"], case .object(let toolJSON) = tools.first, case .object(let schema)? = toolJSON["input_schema"] else { return XCTFail("missing strict tool") }
        XCTAssertEqual(toolJSON["strict"], .bool(true))
        XCTAssertEqual(schema["additionalProperties"], .bool(false))
        XCTAssertEqual(schema["required"], .array([.string("limit"), .string("query")]))
        XCTAssertNotNil(schema["properties"]?.objectValue?["limit"]?.objectValue?["anyOf"])
        XCTAssertEqual(toolJSON["eager_input_streaming"], .bool(true))
        let unsupportedPrefer = Tool(name: "prefer", description: "Prefer", parameters: .object([
            "type": .string("object"),
            "properties": .object(["count": .object(["type": .string("integer"), "minimum": .number(1)])])
        ]), constrainedSampling: .jsonSchema(strict: "prefer"))
        XCTAssertNoThrow(try ContextUtilities.makeStrictJSONSchema(unsupportedPrefer.parameters), "OpenAI/generic strict schema still accepts numeric bounds")
        let preferBody = AnthropicMessagesProvider.buildRequestBody(model: model, context: AIContext(messages: [.user("hi")], tools: [unsupportedPrefer]), options: nil)
        guard case .array(let preferTools)? = preferBody["tools"], case .object(let preferTool)? = preferTools.first else { return XCTFail("missing prefer tool") }
        XCTAssertNil(preferTool["strict"])
        XCTAssertEqual(preferTool["input_schema"]?.objectValue?["properties"]?.objectValue?["count"]?.objectValue?["minimum"], .number(1))
        let unsupportedArrayPrefer = Tool(name: "prefer_array", description: "Prefer array", parameters: .object([
            "type": .string("object"),
            "properties": .object(["items": .object(["type": .string("array"), "minItems": .number(2), "items": .object(["type": .string("string")])])])
        ]), constrainedSampling: .jsonSchema(strict: "prefer"))
        let arrayBody = AnthropicMessagesProvider.buildRequestBody(model: model, context: AIContext(messages: [.user("hi")], tools: [unsupportedArrayPrefer]), options: nil)
        guard case .array(let arrayTools)? = arrayBody["tools"], case .object(let arrayTool)? = arrayTools.first else { return XCTFail("missing array prefer tool") }
        XCTAssertNil(arrayTool["strict"])
        XCTAssertEqual(arrayTool["input_schema"]?.objectValue?["properties"]?.objectValue?["items"]?.objectValue?["minItems"], .number(2))
        let unsupportedFormatPrefer = Tool(name: "prefer_format", description: "Prefer format", parameters: .object([
            "type": .string("object"),
            "properties": .object(["pattern": .object(["type": .string("string"), "format": .string("regex")])])
        ]), constrainedSampling: .jsonSchema(strict: "prefer"))
        let formatBody = AnthropicMessagesProvider.buildRequestBody(model: model, context: AIContext(messages: [.user("hi")], tools: [unsupportedFormatPrefer]), options: nil)
        guard case .array(let formatTools)? = formatBody["tools"], case .object(let formatTool)? = formatTools.first else { return XCTFail("missing format prefer tool") }
        XCTAssertNil(formatTool["strict"])
        XCTAssertEqual(formatTool["input_schema"]?.objectValue?["properties"]?.objectValue?["pattern"]?.objectValue?["format"], .string("regex"))
        let supportedAnthropic = Tool(name: "supported", description: "Supported", parameters: .object([
            "type": .string("object"),
            "properties": .object(["url": .object(["type": .string("string"), "format": .string("uri")]), "tags": .object(["type": .string("array"), "minItems": .number(1), "items": .object(["type": .string("string")])])])
        ]), constrainedSampling: .jsonSchema(strict: "prefer"))
        let supportedBody = AnthropicMessagesProvider.buildRequestBody(model: model, context: AIContext(messages: [.user("hi")], tools: [supportedAnthropic]), options: nil)
        guard case .array(let supportedTools)? = supportedBody["tools"], case .object(let supportedTool)? = supportedTools.first else { return XCTFail("missing supported strict tool") }
        XCTAssertEqual(supportedTool["strict"], .bool(true))
        XCTAssertTrue(String(describing: supportedTool["input_schema"] ?? .null).contains("uri"))
        XCTAssertTrue(String(describing: supportedTool["input_schema"] ?? .null).contains("minItems"))
        let unsupportedRequire = Tool(name: "require", description: "Require", parameters: unsupportedPrefer.parameters, constrainedSampling: .jsonSchema(strict: "require"))
        XCTAssertThrowsError(try AnthropicMessagesProvider.validateConstrainedSampling(tools: [unsupportedRequire])) { error in
            XCTAssertTrue(String(describing: error).contains("requires JSON-schema constrained sampling"))
        }
        var compat = AnthropicMessagesCompat(); compat.supportsEagerToolInputStreaming = false
        let legacy = Model(id: "claude", name: "Claude", api: .anthropicMessages, provider: .anthropic, anthropicCompat: compat)
        let legacyHeaders = AnthropicMessagesProvider.buildRequestHeaders(model: legacy, context: AIContext(messages: [.user("hi")], tools: [strictTool]), apiKey: "key", options: nil)
        XCTAssertTrue(legacyHeaders["Anthropic-Beta"]?.contains("fine-grained-tool-streaming") == true)
        let legacyBody = AnthropicMessagesProvider.buildRequestBody(model: legacy, context: AIContext(messages: [.user("hi")], tools: [strictTool]), options: nil)
        guard case .array(let legacyTools)? = legacyBody["tools"], case .object(let legacyTool)? = legacyTools.first else { return XCTFail("missing legacy tool") }
        XCTAssertNil(legacyTool["eager_input_streaming"])
    }

    func testV0992RetryAfterFallbackAndZAICNOverflow() throws {
        let invalid = ProviderRetryError(status: 429, headers: ["Retry-After": "not-a-date"], message: "rate limited")
        XCTAssertEqual(try ProviderRetry.retryDelayMilliseconds(invalid, retryIndex: 0, maxRetryDelayMs: 60_000), 500)
        let nonFinite = ProviderRetryError(status: 429, headers: ["Retry-After-Ms": "inf"], message: "rate limited")
        XCTAssertEqual(try ProviderRetry.retryDelayMilliseconds(nonFinite, retryIndex: 1, maxRetryDelayMs: 60_000), 1000)
        var msg = Message(role: .assistant, content: [])
        msg.stopReason = .error
        msg.errorMessage = "Z.AI API error: prompt tokens exceed model context window"
        XCTAssertTrue(ContextUtilities.isContextOverflow(msg, contextWindow: 131_072))
    }

}
