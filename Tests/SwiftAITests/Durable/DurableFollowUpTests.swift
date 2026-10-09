import XCTest
@testable import SwiftAI

final class DurableFollowUpTests: XCTestCase {
    func testAutomaticFollowUpsConsumeExistingPlacedInputWithoutDuplicates() async throws {
        let capture = FollowUpCapture()
        let model = Model(id: "follow", name: "follow", api: .faux, provider: .faux, baseUrl: "runtime")
        await AIRegistry.shared.register(model)
        await AIRegistry.shared.register(APIProvider(api: .faux, stream: { model, context, _ in AsyncStream { continuation in Task {
            await capture.append(context)
            var message = Message(role: .assistant, content: [.text("answer")]); message.api = model.api; message.provider = model.provider; message.model = model.id; message.stopReason = .stop
            continuation.yield(.done(reason: .stop, message: message)); continuation.finish()
        } } }))
        let session = DurableSession(storage: DurableMemoryStorage())
        let conversation = try await session.createConversation()
        try await session.configureAgent(conversationID: conversation.id, settings: DurableAgentSettings(model: model))
        let stream = try await session.observeCommits()
        _ = try await session.queueInput(conversationID: conversation.id, messages: [.user("one")], requestID: "one")
        _ = try await session.queueInput(conversationID: conversation.id, messages: [.user("two")], requestID: "two")
        try await session.resumeInbox(conversationID: conversation.id)
        var completed: DurableSnapshot?
        for await frame in stream {
            if frame.value.submissions.values.filter({ $0.status == .done }).count == 2 { completed = frame.value; break }
        }
        let snapshot = try XCTUnwrap(completed)
        XCTAssertEqual(snapshot.entries.values.filter { $0.kind == "pi.user" }.count, 2)
        XCTAssertEqual(snapshot.tasks.values.filter { $0.kind == "generation" }.count, 2)
        let contexts = await capture.contexts; XCTAssertEqual(contexts.count, 2); XCTAssertEqual(contexts[0].messages.map { Harness.textContent(in: $0) }, ["one"]); XCTAssertEqual(contexts[1].messages.last?.content.first?.text, "two")
        try await session.close()
    }

    func testAllModeCombinesFollowUpsAndAbortWithdrawsQueuedInputsButKeepsWrites() async throws {
        let session = DurableSession(storage: DurableMemoryStorage())
        let model = Model(id: "all", name: "all", api: .faux, provider: .faux, baseUrl: "runtime")
        await AIRegistry.shared.register(model)
        await AIRegistry.shared.register(APIProvider(api: .faux, stream: { model, context, _ in AsyncStream { continuation in
            XCTAssertEqual(context.messages.compactMap { $0.content.first?.text }, ["one", "two"])
            var message = Message(role: .assistant, content: [.text("answer")]); message.api = model.api; message.provider = model.provider; message.model = model.id; message.stopReason = .stop
            continuation.yield(.done(reason: .stop, message: message)); continuation.finish()
        } }))
        let conversation = try await session.createConversation()
        try await session.configureAgent(conversationID: conversation.id, settings: DurableAgentSettings(model: model, followUpMode: .all))
        let stream = try await session.observeCommits()
        _ = try await session.queueInput(conversationID: conversation.id, messages: [.user("one")])
        _ = try await session.queueInput(conversationID: conversation.id, messages: [.user("two")])
        try await session.resumeInbox(conversationID: conversation.id)
        for await frame in stream { if frame.value.submissions.values.filter({ $0.status == .done }).count == 2 { break } }
        let snapshot = try await session.snapshot(); XCTAssertEqual(snapshot.tasks.values.filter { $0.kind == "generation" }.count, 1)
        try await session.taskRegistry.register(DurableTaskDefinition(name: "idle", run: { _ in .completed(.null) }))
        let task = try await session.createTask(conversationID: conversation.id, kind: "idle", input: .null)
        let queued = try await session.queueInput(conversationID: conversation.id, messages: [.user("abort")])
        let write = try await session.queueWrite(conversationID: conversation.id, kind: "note", data: .string("keep"))
        _ = try await session.abort(taskID: task.id)
        let aborted = try await session.snapshot(); XCTAssertEqual(aborted.submissions[queued.id]?.status, .unanswered)
        let inbox = try await session.inbox(conversationID: conversation.id); XCTAssertEqual(inbox.map(\.submissionID), [write.id])
        try await session.close()
    }
}
private actor FollowUpCapture { var contexts: [AIContext] = []; func append(_ context: AIContext) { contexts.append(context) } }
