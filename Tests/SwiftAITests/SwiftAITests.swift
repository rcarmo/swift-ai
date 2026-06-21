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
