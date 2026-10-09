import XCTest
@testable import SwiftAI

final class DurableAgentTests: XCTestCase {
    func testConfiguredAgentRendersSelectedSectionsAndDispatchesHooks() async throws {
        let captures = AgentTestCapture()
        let model = Model(id: "agent", name: "agent", api: .faux, provider: .faux, baseUrl: "runtime", reasoning: true)
        await AIRegistry.shared.register(model)
        await AIRegistry.shared.register(APIProvider(api: .faux, stream: { model, context, options in AsyncStream { continuation in Task {
            await captures.capture(context, reasoning: options?.reasoning)
            var message = Message(role: .assistant, content: [.text("answer")]); message.api = model.api; message.provider = model.provider; message.model = model.id; message.stopReason = .stop
            continuation.yield(.done(reason: .stop, message: message)); continuation.finish()
        } } }))
        let session = DurableSession(storage: DurableMemoryStorage())
        try await session.extensionRegistry.install(DurableExtension(name: "facts", sections: [DurablePromptSection(key: "facts", render: { view in "Conversation \(view.conversation.id)" })], hooks: DurableGenerationHooks(beforeRequest: { context in
            var replacement = context; replacement.messages.append(.user("hook")); return replacement
        }, afterResponse: { _ in await captures.responded() })))
        let conversation = try await session.createConversation()
        try await session.configureAgent(conversationID: conversation.id, settings: DurableAgentSettings(model: model, instructions: "Be precise", thinkingLevel: .high, extensions: ["facts"]))
        let result = try await session.generate(conversationID: conversation.id, input: [.user("input")], requestID: "agent")
        XCTAssertEqual(result.task.status, .completed)
        let contexts = await captures.contexts; XCTAssertTrue(contexts[0].systemPrompt?.contains("Be precise") == true); XCTAssertTrue(contexts[0].systemPrompt?.contains("<facts>\nConversation") == true); XCTAssertEqual(contexts[0].messages.last?.content.first?.text, "hook")
        let reasoning = await captures.reasoning; XCTAssertEqual(reasoning, [.high]); let responded = await captures.responses; XCTAssertEqual(responded, 1)
        let stored = try await session.agent(conversationID: conversation.id); XCTAssertEqual(stored?.model.baseUrl, ""); XCTAssertNil(stored?.model.headers)
        try await session.close()
    }

    func testSectionFailureKeepsPriorTextAndReplacementKeepsRegistryPosition() async throws {
        let session = DurableSession(storage: DurableMemoryStorage())
        let conversation = try await session.createConversation()
        try await session.extensionRegistry.install(DurableExtension(name: "first", sections: [DurablePromptSection(key: "a", render: { _ in "A" })]))
        try await session.extensionRegistry.install(DurableExtension(name: "second", sections: [DurablePromptSection(key: "b", render: { _ in "B" })]))
        let first = try await session.renderPrompt(conversationID: conversation.id, instructions: nil, extensions: ["first", "second"])
        XCTAssertEqual(first, "<a>\nA\n</a>\n\n<b>\nB\n</b>")
        try await session.extensionRegistry.install(DurableExtension(name: "first", sections: [DurablePromptSection(key: "a", render: { _ in throw DurableError.invalidRecord("failed section") })]))
        let retained = try await session.renderPrompt(conversationID: conversation.id, instructions: nil, extensions: ["first", "second"])
        XCTAssertEqual(retained, first)
        do { try await session.extensionRegistry.install(DurableExtension(name: "bad", sections: [DurablePromptSection(key: "instructions", render: { _ in "bad" })])); XCTFail("reserved key accepted") } catch {}
        let missing = try await session.extensionRegistry.snapshot(names: ["first", "second"]); XCTAssertEqual(missing.map(\.name), ["first", "second"])
        try await session.close()
    }

    func testAfterResponseHookFailurePreservesBilledUsage() async throws {
        let model = Model(id: "hook-failure", name: "hook-failure", api: .faux, provider: .faux, baseUrl: "runtime")
        await AIRegistry.shared.register(model)
        await AIRegistry.shared.register(APIProvider(api: .faux, stream: { model, _, _ in AsyncStream { continuation in
            var message = Message(role: .assistant, content: [.text("answer")]); message.api = model.api; message.provider = model.provider; message.model = model.id; message.stopReason = .stop
            var usage = Usage(); usage.input = 4; usage.totalTokens = 4; message.usage = usage
            continuation.yield(.done(reason: .stop, message: message)); continuation.finish()
        } }))
        let session = DurableSession(storage: DurableMemoryStorage())
        try await session.extensionRegistry.install(DurableExtension(name: "hook", hooks: DurableGenerationHooks(afterResponse: { _ in throw DurableError.invalidRecord("hook failed") })))
        let conversation = try await session.createConversation()
        try await session.configureAgent(conversationID: conversation.id, settings: DurableAgentSettings(model: model, extensions: ["hook"]))
        let result = try await session.generate(conversationID: conversation.id, input: [.user("input")])
        XCTAssertEqual(result.task.status, .failed)
        let snapshot = try await session.snapshot(); XCTAssertEqual(snapshot.documents.values.first { $0.kind == "durable.usage" }?.value.objectValue?["input"], .number(4))
        try await session.close()
    }
}

private actor AgentTestCapture {
    var contexts: [AIContext] = [], reasoning: [ThinkingLevel?] = [], responses = 0
    func capture(_ context: AIContext, reasoning: ThinkingLevel?) { contexts.append(context); self.reasoning.append(reasoning) }
    func responded() { responses += 1 }
}
