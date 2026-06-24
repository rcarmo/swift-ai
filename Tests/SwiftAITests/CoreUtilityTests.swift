import XCTest
@testable import SwiftAI

final class CoreUtilityTests: XCTestCase {
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
