import XCTest
@testable import SwiftAI

final class DurableToolHooksTests: XCTestCase {
    private func run(before: @escaping @Sendable (DurableToolBinding, [String: JSONValue]) async throws -> DurableBeforeToolDecision?, after: @escaping @Sendable (DurableToolBinding, DurableToolResult) async throws -> DurableToolResult) async throws -> (DurableSnapshot, [DurableToolExecution], AIContext?) {
        let capture = HookToolCapture(), registry = DurableToolRegistry()
        try await registry.register(DurableToolRegistration(definition: Tool(name: "value", description: "", parameters: .object(["type": .string("object"), "properties": .object(["n": .object(["type": .string("integer")])]), "required": .array([.string("n")])])), implementationID: "value", implementationVersion: "1", replayPolicy: .safe, execute: { invocation in
            await capture.effect(invocation)
            var usage = Usage(); usage.input = 3; usage.totalTokens = 3
            return DurableToolResult(content: "original", usage: usage)
        }))
        let model = Model(id: "hooks", name: "hooks", api: .faux, provider: .faux, baseUrl: "runtime")
        await AIRegistry.shared.register(model)
        await AIRegistry.shared.register(APIProvider(api: .faux, stream: { model, context, _ in AsyncStream { continuation in Task {
            await capture.context(context)
            var message = Message(role: .assistant, content: context.messages.contains(where: { $0.role == .toolResult }) ? [.text("answer")] : [.toolCall(id: "call", name: "value", arguments: ["n": .number(1)])]); message.api = model.api; message.provider = model.provider; message.model = model.id; message.stopReason = message.content.first?.type == "toolCall" ? .toolUse : .stop
            continuation.yield(.done(reason: message.stopReason!, message: message)); continuation.finish()
        } } }))
        let session = DurableSession(storage: DurableMemoryStorage(), toolRegistry: registry)
        try await session.extensionRegistry.install(DurableExtension(name: "hooks", hooks: DurableGenerationHooks(beforeTool: before, afterTool: after)))
        let conversation = try await session.createConversation()
        try await session.configureAgent(conversationID: conversation.id, settings: DurableAgentSettings(model: model, extensions: ["hooks"]))
        let result = try await session.generate(conversationID: conversation.id, input: [.user("input")]); XCTAssertEqual(result.task.status, .completed)
        let snapshot = try await session.snapshot(), effects = await capture.effects, context = await capture.contexts.last
        try await session.close()
        return (snapshot, effects, context)
    }

    func testHooksTransformValidatedArgumentsAndResultWithoutChangingBilledUsage() async throws {
        let (snapshot, effects, context) = try await run(before: { _, _ in .arguments(["n": .number(7)]) }, after: { _, result in var changed = result; changed.content = "changed"; changed.usage = nil; return changed })
        XCTAssertEqual(effects.count, 1); XCTAssertEqual(effects[0].arguments, ["n": .number(7)])
        XCTAssertEqual(context?.messages.first { $0.role == .toolResult }?.content.first?.text, "changed")
        XCTAssertEqual(snapshot.documents.values.first { $0.kind == "durable.usage" }?.value.objectValue?["input"], .number(3))
        let doc = try XCTUnwrap(snapshot.documents.values.first { $0.kind == "tool.intent" })
        let intent = try DurableGenerationPlanner.decodeJSON(DurableToolIntent.self, from: doc.value)
        XCTAssertEqual(intent.executionArguments, ["n": .number(7)])
    }

    func testBeforeHookBlockOrInvalidRewriteProducesResultWithoutEffect() async throws {
        let (_, blockedEffects, blockedContext) = try await run(before: { _, _ in .block("denied") }, after: { _, value in value })
        XCTAssertTrue(blockedEffects.isEmpty); XCTAssertEqual(blockedContext?.messages.first { $0.role == .toolResult }?.content.first?.text, "denied")
        let (_, invalidEffects, invalidContext) = try await run(before: { _, _ in .arguments(["n": .string("invalid")]) }, after: { _, value in value })
        XCTAssertTrue(invalidEffects.isEmpty); XCTAssertEqual(invalidContext?.messages.first { $0.role == .toolResult }?.isError, true)
    }

    func testAfterHookFailurePreservesExecutionUsageAndContinuesRun() async throws {
        let (snapshot, effects, context) = try await run(before: { _, _ in nil }, after: { _, _ in throw DurableError.invalidRecord("hook failure") })
        XCTAssertEqual(effects.count, 1); XCTAssertEqual(context?.messages.first { $0.role == .toolResult }?.isError, true)
        XCTAssertEqual(snapshot.documents.values.first { $0.kind == "durable.usage" }?.value.objectValue?["input"], .number(3))
    }
}
private actor HookToolCapture {
    var effects: [DurableToolExecution] = [], contexts: [AIContext] = []
    func effect(_ value: DurableToolExecution) { effects.append(value) }
    func context(_ value: AIContext) { contexts.append(value) }
}
