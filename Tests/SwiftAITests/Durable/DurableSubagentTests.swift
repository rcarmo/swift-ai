import XCTest
@testable import SwiftAI

final class DurableSubagentTests: XCTestCase {
    func testChildConversationAndExactlyOnceReportSurviveJournalReopen() async throws {
        let capture = SubagentCapture()
        let model = Model(id: "subagent", name: "subagent", api: .faux, provider: .faux, baseUrl: "runtime")
        await AIRegistry.shared.register(model)
        await AIRegistry.shared.register(APIProvider(api: .faux, stream: { model, context, _ in AsyncStream { continuation in Task {
            await capture.append(context)
            var message = Message(role: .assistant, content: [.text("child answer")]); message.api = model.api; message.provider = model.provider; message.model = model.id; message.stopReason = .stop
            continuation.yield(.done(reason: .stop, message: message)); continuation.finish()
        } } }))
        let directory = SwiftAITestScratch.directory("subagent")
        let session = DurableSession(storage: try DurableJournalStorage(directory: directory))
        let parent = try await session.createConversation()
        let child = try await session.spawnSubagent(parentConversationID: parent.id, settings: DurableAgentSettings(model: model), input: [.user("child input")], background: true)
        let before = await capture.contexts; XCTAssertTrue(before.isEmpty)
        let admitted = try await session.snapshot(); XCTAssertEqual(admitted.conversations[child.conversationID]?.ownerTaskID, child.taskID); XCTAssertEqual(admitted.tasks[child.taskID]?.background, true)
        let resumed = try await session.resumeSubagents(); XCTAssertEqual(resumed.map(\.status), [.completed])
        let inbox = try await session.inbox(conversationID: parent.id); XCTAssertEqual(inbox.count, 1); XCTAssertTrue(inbox[0].messages?.first?.content.first?.text?.contains("child answer") == true)
        try await session.close()
        let reopened = DurableSession(storage: try DurableJournalStorage(directory: directory))
        let repeatRun = try await reopened.resumeSubagents(); XCTAssertTrue(repeatRun.isEmpty)
        let reports = try await reopened.inbox(conversationID: parent.id); XCTAssertEqual(reports.count, 1)
        let called = await capture.contexts; XCTAssertEqual(called.count, 1)
        try await reopened.close()
    }

    func testCompletingSubagentRecoveryOnlyQueuesStagedReport() async throws {
        let storage = DurableMemoryStorage()
        let settings = DurableAgentSettings(model: Model(id: "missing", name: "missing", api: .faux, provider: .faux))
        _ = try await storage.commit(DurableCommitBatch(conversations: [DurableConversationRecord(id: 1), DurableConversationRecord(id: 2, ownerTaskID: 3)], tasks: [DurableTaskRecord(id: 3, conversationID: 1, kind: "subagent")]))
        let intent = DurableSubagentIntent(parentConversationID: 1, childConversationID: 2, input: [.user("input")], settings: settings, report: .user("staged report"))
        _ = try await storage.commit(DurableCommitBatch(tasks: [DurableTaskRecord(id: 3, conversationID: 1, kind: "subagent", status: .running)], documents: [DurableDocumentRecord(id: 4, scope: "task", ownerID: 3, kind: "subagent.intent", value: try DurableGenerationPlanner.encodeJSON(intent))]))
        _ = try await storage.commit(DurableCommitBatch(tasks: [DurableTaskRecord(id: 3, conversationID: 1, kind: "subagent", status: .completing)]))
        let session = DurableSession(storage: storage)
        let resumed = try await session.resumeSubagents(); XCTAssertEqual(resumed[0].status, .completed)
        let inbox = try await session.inbox(conversationID: 1); XCTAssertEqual(inbox.count, 1); XCTAssertEqual(inbox[0].messages?.first?.content.first?.text, "staged report")
        let again = try await session.resumeSubagents(); XCTAssertTrue(again.isEmpty)
        try await session.close()
    }
}
private actor SubagentCapture { var contexts: [AIContext] = []; func append(_ context: AIContext) { contexts.append(context) } }
