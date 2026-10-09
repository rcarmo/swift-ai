import XCTest
@testable import SwiftAI

final class DurableTasksTests: XCTestCase {
    func testOwnedChildrenWaitAndCompletingDrainPrecedeParentSettlement() async throws {
        let session = DurableSession(storage: DurableMemoryStorage()), order = NativeTaskOrder()
        try await session.taskRegistry.register(DurableTaskDefinition(name: "child", run: { _ in await order.append("child"); return .completed(.string("child result")) }))
        try await session.taskRegistry.register(DurableTaskDefinition(name: "parent", run: { invocation in
            if invocation.checkpoint == nil {
                let child = try await invocation.child(kind: "child", input: .object([:]))
                return .waiting(checkpoint: .string("after child"), children: [child.id])
            }
            await order.append("parent"); return .completed(.string("parent result"))
        }))
        let conversation = try await session.createConversation()
        let parent = try await session.createTask(conversationID: conversation.id, kind: "parent", input: .object([:]))
        let resumed = try await session.resumeTasks(); XCTAssertEqual(resumed.first?.status, .completed)
        let snapshot = try await session.snapshot(); XCTAssertEqual(snapshot.tasks[parent.id]?.outcome?.objectValue?["result"], .string("parent result")); XCTAssertTrue(snapshot.tasks.values.allSatisfy { $0.status == .completed })
        let calls = await order.values; XCTAssertEqual(calls, ["child", "parent"])
        let graph = try await session.taskGraph(); XCTAssertEqual(graph.roots, [parent.id]); XCTAssertEqual(graph.children[parent.id]?.count, 1)
        try await session.close()
    }

    func testCompletingRecoveryDoesNotRerunEffectsAndMissingDefinitionBlocks() async throws {
        let storage = DurableMemoryStorage(), effects = NativeTaskOrder()
        _ = try await storage.commit(DurableCommitBatch(conversations: [DurableConversationRecord(id: 1)]))
        let intent = DurableNativeTaskIntent(version: 1, input: .object([:]), stagedResult: .string("staged"))
        _ = try await storage.commit(DurableCommitBatch(tasks: [DurableTaskRecord(id: 2, conversationID: 1, kind: "custom")], documents: [DurableDocumentRecord(id: 3, scope: "task", ownerID: 2, kind: "native.intent", value: try DurableGenerationPlanner.encodeJSON(intent))]))
        _ = try await storage.commit(DurableCommitBatch(tasks: [DurableTaskRecord(id: 2, conversationID: 1, kind: "custom", status: .running)]))
        _ = try await storage.commit(DurableCommitBatch(tasks: [DurableTaskRecord(id: 2, conversationID: 1, kind: "custom", status: .completing)]))
        let session = DurableSession(storage: storage)
        let blocked = try await session.resumeTasks(); XCTAssertEqual(blocked[0].status, .completing)
        try await session.taskRegistry.register(DurableTaskDefinition(name: "custom", run: { _ in await effects.append("effect"); return .completed(.null) }))
        let resumed = try await session.resumeTasks(); XCTAssertEqual(resumed[0].status, .completed); XCTAssertEqual(resumed[0].outcome?.objectValue?["result"], .string("staged"))
        let called = await effects.values; XCTAssertTrue(called.isEmpty)
        try await session.close()
    }

    func testCheckpointBeforeEffectAndFailedTaskDoesNotStopNextTask() async throws {
        let session = DurableSession(storage: DurableMemoryStorage())
        try await session.taskRegistry.register(DurableTaskDefinition(name: "checkpoint", run: { invocation in
            try await invocation.checkpoint(.object(["prepared": .bool(true)]))
            let snapshot = try await invocation.snapshot(); XCTAssertEqual(snapshot.tasks[invocation.task.id]?.checkpoint, .object(["prepared": .bool(true)]))
            throw DurableError.invalidRecord("effect failed")
        }))
        try await session.taskRegistry.register(DurableTaskDefinition(name: "next", run: { _ in .completed(.string("ok")) }))
        let conversation = try await session.createConversation()
        _ = try await session.createTask(conversationID: conversation.id, kind: "checkpoint", input: .null)
        _ = try await session.createTask(conversationID: conversation.id, kind: "next", input: .null)
        let results = try await session.resumeTasks(); XCTAssertEqual(results.map(\.status), [.failed, .completed])
        let final = try await session.snapshot()
        let intentDoc = try XCTUnwrap(final.documents.values.first { $0.kind == "native.intent" && $0.ownerID == results[0].id })
        let intent = try JSONDecoder().decode(DurableNativeTaskIntent.self, from: JSONEncoder().encode(intentDoc.value))
        XCTAssertEqual(intent.checkpoint, .object(["prepared": .bool(true)]))
        try await session.close()
    }

    func testAbortCascadeRunsHandlersAndRejectsBackgroundChild() async throws {
        let session = DurableSession(storage: DurableMemoryStorage()), calls = NativeTaskOrder()
        try await session.taskRegistry.register(DurableTaskDefinition(name: "abortable", run: { _ in .completed(.null) }, abort: { invocation in XCTAssertTrue(invocation.cancellation.isCancelled); await calls.append("abort"); return .string("aborted") }))
        let conversation = try await session.createConversation()
        let parent = try await session.createTask(conversationID: conversation.id, kind: "abortable", input: .null)
        let child = try await session.createTask(conversationID: conversation.id, kind: "abortable", input: .null, ownerTaskID: parent.id)
        do { _ = try await session.createTask(conversationID: conversation.id, kind: "abortable", input: .null, ownerTaskID: parent.id, background: true); XCTFail("background task child accepted") } catch {}
        try await session.abortTaskTree(id: parent.id)
        _ = try await session.resumeTasks()
        let snapshot = try await session.snapshot(); XCTAssertEqual(snapshot.tasks[parent.id]?.status, .aborted); XCTAssertEqual(snapshot.tasks[child.id]?.status, .aborted)
        let aborts = await calls.values; XCTAssertEqual(aborts.count, 2)
        try await session.close()
    }
}

private actor NativeTaskOrder { var values: [String] = []; func append(_ value: String) { values.append(value) } }
