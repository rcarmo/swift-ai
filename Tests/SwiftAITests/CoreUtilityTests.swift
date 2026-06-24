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
