import XCTest
@testable import SwiftAI

final class CoreUtilityTests: XCTestCase {
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
        XCTAssertNotNil(await AIRegistry.shared.apiProvider(for: .openAICompletions))
        await AIRegistry.shared.unregister(api: .openAICompletions)
        XCTAssertNil(await AIRegistry.shared.apiProvider(for: .openAICompletions))
        await AIRegistry.shared.register(Model(id: "m1", name: "M1", api: .openAICompletions, provider: .openAI))
        await AIRegistry.shared.register(Model(id: "m2", name: "M2", api: .openAIResponses, provider: .openAI))
        await AIRegistry.shared.register(Model(id: "m3", name: "M3", api: .anthropicMessages, provider: .anthropic))
        XCTAssertEqual(await AIRegistry.shared.listModels(provider: .openAI).map(\.id), ["m1", "m2"])
        XCTAssertEqual(await AIRegistry.shared.model(provider: .anthropic, id: "m3")?.id, "m3")
        XCTAssertEqual(await AIRegistry.shared.listProviders(), [.anthropic, .openAI])
        let ghost = Model(id: "ghost", name: "Ghost", api: .mistralConversations, provider: .mistral)
        let events = await SwiftAI.stream(model: ghost, context: AIContext(), options: nil)
        var sawError = false
        for await event in events { if case .error(_, _, let error) = event { sawError = true; XCTAssertTrue(String(describing: error).contains("No provider registered") || String(describing: error).contains("noProvider")) } }
        XCTAssertTrue(sawError)
        await SwiftAI.bootstrap()
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
