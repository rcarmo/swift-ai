import XCTest
@testable import SwiftAI

final class DurableInboxTests: XCTestCase {
    func testBoundaryOrdersWritesBeforeUsersAndSelectsQueueModes() async throws {
        let session = DurableSession(storage: DurableMemoryStorage())
        let conversation = try await session.createConversation()
        let follow1 = try await session.queueInput(conversationID: conversation.id, messages: [.user("follow1")])
        let steer1 = try await session.queueInput(conversationID: conversation.id, messages: [.user("steer1")], mode: .steer)
        let write = try await session.queueWrite(conversationID: conversation.id, kind: "note", messages: [.user("write")])
        let follow2 = try await session.queueInput(conversationID: conversation.id, messages: [.user("follow2")])
        let steer2 = try await session.queueInput(conversationID: conversation.id, messages: [.user("steer2")], mode: .steer)
        let post = try await session.placeInbox(conversationID: conversation.id, at: .postTools)
        XCTAssertEqual(post.users, [steer1.id]); XCTAssertEqual(post.entries.flatMap { $0.messages ?? [] }.compactMap { $0.content.first?.text }, ["write", "steer1"])
        let firstSnapshot = try await session.snapshot(); XCTAssertEqual(firstSnapshot.submissions[write.id]?.status, .placed); XCTAssertEqual(firstSnapshot.submissions[follow1.id]?.status, .queued)
        let final = try await session.placeInbox(conversationID: conversation.id, at: .final, steering: .all)
        XCTAssertEqual(final.users, [follow1.id, steer2.id])
        let remaining = try await session.inbox(conversationID: conversation.id); XCTAssertEqual(remaining.map(\.submissionID), [follow2.id])
        try await session.close()
    }

    func testQueuedResetPlacesFollowUpAndRejectsStaleHeadWrite() async throws {
        let session = DurableSession(storage: DurableMemoryStorage())
        let conversation = try await session.createConversation()
        let old = try await session.appendEntry(conversationID: conversation.id, kind: "old", messages: [.user("old")])
        let follow = try await session.queueInput(conversationID: conversation.id, messages: [.user("new user")])
        _ = try await session.queueWrite(conversationID: conversation.id, kind: "reset", reset: true)
        let stale = try await session.queueWrite(conversationID: conversation.id, kind: "stale", head: old.id)
        let boundary = try await session.placeInbox(conversationID: conversation.id, at: .postTools)
        XCTAssertTrue(boundary.reset); XCTAssertEqual(boundary.users, [follow.id])
        let snapshot = try await session.snapshot(); XCTAssertEqual(snapshot.submissions[stale.id]?.status, .unanswered); XCTAssertEqual(snapshot.submissions[stale.id]?.reason, "stale")
        let context = try await session.context(conversationID: conversation.id); XCTAssertEqual(context.messages.compactMap { $0.content.first?.text }, ["new user"])
        try await session.close()
    }

    func testSemanticDedupWithdrawalAndJournalRecovery() async throws {
        let directory = SwiftAITestScratch.directory("inbox-reopen")
        let session = DurableSession(storage: try DurableJournalStorage(directory: directory))
        let conversation = try await session.createConversation()
        let first = try await session.queueInput(conversationID: conversation.id, messages: [.user("queued")], requestID: "key")
        let duplicate = try await session.queueInput(conversationID: conversation.id, messages: [.user("queued")], requestID: "key")
        XCTAssertEqual(first.id, duplicate.id)
        do { _ = try await session.queueInput(conversationID: conversation.id, messages: [.user("different")], requestID: "key"); XCTFail("conflicting request accepted") } catch {}
        let withdrawn = try await session.queueInput(conversationID: conversation.id, messages: [.user("withdraw")])
        let record = try await session.withdrawSubmission(id: withdrawn.id); XCTAssertEqual(record.status, .withdrawn)
        try await session.close()
        let reopened = DurableSession(storage: try DurableJournalStorage(directory: directory))
        let remaining = try await reopened.inbox(conversationID: conversation.id); XCTAssertEqual(remaining.map(\.submissionID), [first.id])
        let placed = try await reopened.placeInbox(conversationID: conversation.id, at: .final); XCTAssertEqual(placed.users, [first.id])
        let empty = try await reopened.inbox(conversationID: conversation.id); XCTAssertTrue(empty.isEmpty)
        try await reopened.close()
    }

    func testToolBoundaryInjectsSteeringAndFinalBoundaryPlacesFollowUp() async throws {
        let gate = InboxTestGate(), captures = InboxTestContexts()
        let registry = DurableToolRegistry()
        try await registry.register(DurableToolRegistration(definition: Tool(name: "hold", description: "hold", parameters: .object(["type": .string("object")])), implementationID: "hold", implementationVersion: "1", replayPolicy: .safe, execute: { _ in await gate.wait(); return DurableToolResult(content: "held") }))
        let model = Model(id: "inbox", name: "inbox", api: .faux, provider: .faux, baseUrl: "runtime")
        await AIRegistry.shared.register(model)
        await AIRegistry.shared.register(APIProvider(api: .faux, stream: { model, context, _ in AsyncStream { continuation in Task {
            await captures.append(context)
            var message = Message(role: .assistant, content: context.messages.contains(where: { $0.role == .toolResult }) ? [.text("answer")] : [.toolCall(id: "call", name: "hold", arguments: [:])])
            message.api = model.api; message.provider = model.provider; message.model = model.id; message.stopReason = message.content.first?.type == "toolCall" ? .toolUse : .stop
            continuation.yield(.done(reason: message.stopReason!, message: message)); continuation.finish()
        } } }))
        let session = DurableSession(storage: DurableMemoryStorage(), toolRegistry: registry)
        let conversation = try await session.createConversation()
        let generation = Task { try await session.submit(DurableGenerationRequest(conversationID: conversation.id, model: model, transcript: [.user("start")])) }
        await gate.entered()
        let steer = try await session.queueInput(conversationID: conversation.id, messages: [.user("steer")], mode: .steer)
        let follow = try await session.queueInput(conversationID: conversation.id, messages: [.user("follow")])
        await gate.release()
        let result = try await generation.value; XCTAssertEqual(result.task.status, .completed)
        let contexts = await captures.values; XCTAssertEqual(contexts.count, 2); XCTAssertEqual(contexts[1].messages.last?.content.first?.text, "steer")
        let snapshot = try await session.snapshot(); XCTAssertEqual(snapshot.submissions[steer.id]?.status, .done); XCTAssertNotNil(snapshot.submissions[steer.id]?.answerID); XCTAssertEqual(snapshot.submissions[follow.id]?.status, .placed)
        try await session.close()
    }
}

private actor InboxTestContexts { var values: [AIContext] = []; func append(_ context: AIContext) { values.append(context) } }
private actor InboxTestGate {
    private var blocked: CheckedContinuation<Void, Never>?
    private var observer: CheckedContinuation<Void, Never>?
    private var isEntered = false
    func wait() async { isEntered = true; observer?.resume(); observer = nil; await withCheckedContinuation { blocked = $0 } }
    func entered() async { if isEntered { return }; await withCheckedContinuation { observer = $0 } }
    func release() { blocked?.resume(); blocked = nil }
}
