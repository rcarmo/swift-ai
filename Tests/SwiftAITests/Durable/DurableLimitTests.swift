import XCTest
@testable import SwiftAI

final class DurableLimitTests: XCTestCase {
    func testIDRequestAndJSONLimitsRejectBeforeAdmission() async throws {
        let storage = DurableMemoryStorage()
        await XCTAssertThrowsAsyncError(try await storage.commit(DurableCommitBatch(conversations: [DurableConversationRecord(id: DurableLimits.maxExactInteger + 1)])))
        let conv = DurableConversationRecord(id: 1)
        _ = try await storage.commit(DurableCommitBatch(conversations: [conv]))
        let longRequest = String(repeating: "x", count: DurableLimits.maxRequestIDBytes + 1)
        let sub = DurableSubmissionRecord(id: 2, conversationID: 1, requestID: longRequest, type: .input, payloadHash: "h")
        await XCTAssertThrowsAsyncError(try await storage.commit(DurableCommitBatch(submissions: [sub])))
        let nonFinite = DurableDocumentRecord(id: 3, scope: "conversation", ownerID: 1, kind: "bad", value: .number(.infinity))
        await XCTAssertThrowsAsyncError(try await storage.commit(DurableCommitBatch(documents: [nonFinite])))
    }

    func testMissingReferencesTerminalTaskAndSequenceOverflowReject() async throws {
        let storage = DurableMemoryStorage()
        await XCTAssertThrowsAsyncError(try await storage.commit(DurableCommitBatch(entries: [DurableEntryRecord(id: 1, conversationID: 99, kind: "missing")])) )
        _ = try await storage.commit(DurableCommitBatch(conversations: [DurableConversationRecord(id: 1)], tasks: [DurableTaskRecord(id: 2, conversationID: 1, kind: "task")]))
        _ = try await storage.commit(DurableCommitBatch(tasks: [DurableTaskRecord(id: 2, conversationID: 1, kind: "task", status: .running)]))
        _ = try await storage.commit(DurableCommitBatch(tasks: [DurableTaskRecord(id: 2, conversationID: 1, kind: "task", status: .completing)]))
        _ = try await storage.commit(DurableCommitBatch(tasks: [DurableTaskRecord(id: 2, conversationID: 1, kind: "task", status: .completed)]))
        let changedTerminal = DurableTaskRecord(id: 2, conversationID: 1, kind: "task", status: .failed)
        await XCTAssertThrowsAsyncError(try await storage.commit(DurableCommitBatch(tasks: [changedTerminal])))
        let overflow = DurableSnapshot(seq: DurableLimits.maxExactInteger, highWaterID: 1, conversations: [1: DurableConversationRecord(id: 1)])
        let overflowStorage = DurableMemoryStorage(snapshot: overflow)
        await XCTAssertThrowsAsyncError(try await overflowStorage.commit(DurableCommitBatch(entries: [DurableEntryRecord(id: 2, conversationID: 1, kind: "x")])))
    }

    func testJSONDepthAndNodeLimitsRejectBeforeEncoding() async throws {
        let storage = DurableMemoryStorage()
        _ = try await storage.commit(DurableCommitBatch(conversations: [DurableConversationRecord(id: 1)]))
        var deep = JSONValue.string("leaf")
        for _ in 0...DurableLimits.maxJSONDepth { deep = .array([deep]) }
        await XCTAssertThrowsAsyncError(try await storage.commit(DurableCommitBatch(documents: [DurableDocumentRecord(id: 2, scope: "conversation", ownerID: 1, kind: "deep", value: deep)]))) { error in
            XCTAssertTrue(String(describing: error).contains("depth"))
        }
        let tooManyNodes = JSONValue.array(Array(repeating: .null, count: DurableLimits.maxJSONNodes + 1))
        await XCTAssertThrowsAsyncError(try await storage.commit(DurableCommitBatch(documents: [DurableDocumentRecord(id: 3, scope: "conversation", ownerID: 1, kind: "wide", value: tooManyNodes)]))) { error in
            XCTAssertTrue(String(describing: error).contains("node"))
        }
    }

    func testNativeMessageArgumentsAndInitialSnapshotBoundsReject() async throws {
        let storage = DurableMemoryStorage()
        _ = try await storage.commit(DurableCommitBatch(conversations: [DurableConversationRecord(id: 1)]))
        var deep = JSONValue.string("leaf")
        for _ in 0...DurableLimits.maxJSONDepth { deep = .array([deep]) }
        let message = Message(role: .assistant, content: [.toolCall(id: "tool", name: "call", arguments: ["deep": deep])])
        await XCTAssertThrowsAsyncError(try await storage.commit(DurableCommitBatch(entries: [DurableEntryRecord(id: 2, conversationID: 1, kind: "assistant", messages: [message])]))) { error in
            XCTAssertTrue(String(describing: error).contains("depth"))
        }
        let hugeGrammar = String(repeating: "g", count: DurableLimits.maxArgumentsBytes + 1)
        let tool = Tool(name: "grammar", description: "large grammar", parameters: .object([:]), constrainedSampling: .grammar(openaiLark: hugeGrammar))
        var toolMessage = Message(role: .assistant, content: [.text("tool")])
        toolMessage.toolsAdded = [tool]
        await XCTAssertThrowsAsyncError(try await storage.commit(DurableCommitBatch(entries: [DurableEntryRecord(id: 3, conversationID: 1, kind: "assistant", messages: [toolMessage])]))) { error in
            XCTAssertTrue(String(describing: error).contains("grammar") || String(describing: error).contains("string exceeds"))
        }

        let badSeq = DurableSnapshot(seq: DurableLimits.maxExactInteger + 1, highWaterID: 1, conversations: [1: DurableConversationRecord(id: 1, createdSeq: 1)])
        let badSeqStorage = DurableMemoryStorage(snapshot: badSeq)
        await XCTAssertThrowsAsyncError(try await badSeqStorage.snapshot())

        let badCreatedSeq = DurableSnapshot(seq: 1, highWaterID: 2, conversations: [1: DurableConversationRecord(id: 1, createdSeq: 999)], entries: [2: DurableEntryRecord(id: 2, conversationID: 1, kind: "bad", createdSeq: -1)])
        let badCreatedSeqStorage = DurableMemoryStorage(snapshot: badCreatedSeq)
        await XCTAssertThrowsAsyncError(try await badCreatedSeqStorage.snapshot())

        let emptyRequest = DurableSnapshot(seq: 1, highWaterID: 2, conversations: [1: DurableConversationRecord(id: 1, createdSeq: 1)], submissions: [2: DurableSubmissionRecord(id: 2, conversationID: 1, requestID: "", type: .input, createdSeq: 1)])
        let emptyRequestStorage = DurableMemoryStorage(snapshot: emptyRequest)
        await XCTAssertThrowsAsyncError(try await emptyRequestStorage.snapshot())

        var usage = Usage()
        usage.cost.total = .nan
        var costMessage = Message.user("cost")
        costMessage.usage = usage
        let badCostSnapshot = DurableSnapshot(seq: 1, highWaterID: 2, conversations: [1: DurableConversationRecord(id: 1, createdSeq: 1)], entries: [2: DurableEntryRecord(id: 2, conversationID: 1, kind: "cost", messages: [costMessage], createdSeq: 1)])
        let badCostStorage = DurableMemoryStorage(snapshot: badCostSnapshot)
        await XCTAssertThrowsAsyncError(try await badCostStorage.snapshot()) { error in
            XCTAssertTrue(String(describing: error).contains("non-finite"))
        }
    }

    func testSlashEscapedEntryBoundaryIsAccountedBeforeEncoding() async throws {
        XCTAssertEqual(try DurableValidation.encoder.encode(JSONValue.string("/")).count, 4)

        func entry(_ id: Int64, slashCount: Int) -> DurableEntryRecord {
            let value = String(repeating: "/", count: slashCount)
            let block = ContentBlock(type: "text", text: value, thinking: value)
            return DurableEntryRecord(id: id, conversationID: 1, kind: "assistant", messages: [Message(role: .assistant, content: [block])])
        }
        func accepts(_ slashCount: Int) async -> Bool {
            let storage = DurableMemoryStorage()
            do {
                _ = try await storage.commit(DurableCommitBatch(conversations: [DurableConversationRecord(id: 1)]))
                _ = try await storage.commit(DurableCommitBatch(entries: [entry(2, slashCount: slashCount)]))
                return true
            } catch {
                return false
            }
        }

        var low = 0
        var high = DurableLimits.maxStringBytes
        while low < high {
            let mid = (low + high + 1) / 2
            if await accepts(mid) { low = mid } else { high = mid - 1 }
        }
        XCTAssertGreaterThan(low, 0)
        let boundaryAccepted = await accepts(low)
        XCTAssertTrue(boundaryAccepted)
        XCTAssertLessThanOrEqual(try DurableValidation.encoder.encode(entry(2, slashCount: low)).count, DurableLimits.maxEntryBytes)
        let rejectingStorage = DurableMemoryStorage()
        _ = try await rejectingStorage.commit(DurableCommitBatch(conversations: [DurableConversationRecord(id: 1)]))
        await XCTAssertThrowsAsyncError(try await rejectingStorage.commit(DurableCommitBatch(entries: [entry(2, slashCount: low + 1)]))) { error in
            XCTAssertTrue(String(describing: error).contains("entry exceeds"))
        }
    }

    func testJournalAppendRejectsBeforeExceedingMaxJournalBytes() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("swift-ai-durable-max-journal-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let journal = dir.appendingPathComponent("journal.log")
        try Data(repeating: 0, count: DurableLimits.maxJournalBytes + 1).write(to: journal)
        XCTAssertThrowsError(try DurableJournalStorage(directory: dir)) { error in
            XCTAssertTrue(String(describing: error).contains("journal exceeds"))
        }
    }
}
