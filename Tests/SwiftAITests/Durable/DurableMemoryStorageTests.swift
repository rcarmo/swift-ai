import XCTest
@testable import SwiftAI

final class DurableMemoryStorageTests: XCTestCase {
    func testAtomicMixedCommitSnapshotAndRequestDedup() async throws {
        let storage = DurableMemoryStorage()
        let conversation = DurableConversationRecord(id: 1)
        let entry = DurableEntryRecord(id: 2, conversationID: 1, kind: "pi.user", messages: [.user("hello")])
        let task = DurableTaskRecord(id: 3, conversationID: 1, kind: "pi.generation", checkpoint: .object(["phase": .string("start")]))
        let submission = DurableSubmissionRecord(id: 4, conversationID: 1, requestID: "req-1", type: .input, payloadHash: "hash")
        let document = DurableDocumentRecord(id: 5, scope: "conversation", ownerID: 1, kind: "pi.live", value: .object(["busy": .bool(true)]))
        let snapshot = try await storage.commit(DurableCommitBatch(conversations: [conversation], entries: [entry], tasks: [task], submissions: [submission], documents: [document]))
        XCTAssertEqual(snapshot.seq, 1)
        XCTAssertEqual(snapshot.highWaterID, 5)
        XCTAssertEqual(snapshot.conversations[1]?.id, 1)
        XCTAssertEqual(snapshot.entries[2]?.messages?.first?.content.first?.text, "hello")
        XCTAssertEqual(snapshot.tasks[3]?.checkpoint, .object(["phase": .string("start")]))
        XCTAssertEqual(snapshot.submissions[4]?.requestID, "req-1")
        XCTAssertEqual(snapshot.documents[5]?.value, .object(["busy": .bool(true)]))

        let again = DurableSubmissionRecord(id: 6, conversationID: 1, requestID: "req-1", type: .input, payloadHash: "hash")
        await XCTAssertThrowsAsyncError(try await storage.commit(DurableCommitBatch(submissions: [again]))) { error in
            XCTAssertTrue(String(describing: error).contains("request ID conflict"))
        }
        try await storage.close()
        await XCTAssertThrowsAsyncError(try await storage.snapshot())
    }

    func testInitialSnapshotDuplicateRequestIDFailsClosed() async throws {
        let a = DurableSubmissionRecord(id: 2, conversationID: 1, requestID: "same", type: .input, payloadHash: "a")
        let b = DurableSubmissionRecord(id: 3, conversationID: 1, requestID: "same", type: .input, payloadHash: "b")
        let snapshot = DurableSnapshot(seq: 1, highWaterID: 3, conversations: [1: DurableConversationRecord(id: 1)], submissions: [2: a, 3: b])
        let storage = DurableMemoryStorage(snapshot: snapshot)
        await XCTAssertThrowsAsyncError(try await storage.snapshot()) { error in
            XCTAssertTrue(String(describing: error).contains("invalid initial snapshot"))
        }
    }

    func testStrictValidationRejectsCandidateGraphViolations() async throws {
        let storage = DurableMemoryStorage()
        await XCTAssertThrowsAsyncError(try await storage.commit(DurableCommitBatch(conversations: [DurableConversationRecord(id: 1)], tasks: [DurableTaskRecord(id: 1, conversationID: 1, kind: "collision")]))) { error in
            XCTAssertTrue(String(describing: error).contains("duplicate") || String(describing: error).contains("collision"))
        }
        _ = try await storage.commit(DurableCommitBatch(conversations: [DurableConversationRecord(id: 1)]))
        let a = DurableTaskRecord(id: 2, conversationID: 1, ownerTaskID: 3, kind: "task")
        let b = DurableTaskRecord(id: 3, conversationID: 1, ownerTaskID: 2, kind: "task")
        await XCTAssertThrowsAsyncError(try await storage.commit(DurableCommitBatch(tasks: [a, b]))) { error in
            XCTAssertTrue(String(describing: error).contains("cycle"))
        }
        let pending = DurableTaskRecord(id: 4, conversationID: 1, kind: "task")
        _ = try await storage.commit(DurableCommitBatch(tasks: [pending]))
        var illegal = pending
        illegal.status = .completed
        await XCTAssertThrowsAsyncError(try await storage.commit(DurableCommitBatch(tasks: [illegal]))) { error in
            XCTAssertTrue(String(describing: error).contains("transition"))
        }
    }

    func testIdentityAndCreatedSequenceAreImmutable() async throws {
        let storage = DurableMemoryStorage()
        _ = try await storage.commit(DurableCommitBatch(conversations: [DurableConversationRecord(id: 1), DurableConversationRecord(id: 2)], tasks: [DurableTaskRecord(id: 3, conversationID: 1, kind: "task")]))
        var reparented = DurableTaskRecord(id: 3, conversationID: 2, kind: "task")
        reparented.createdSeq = 99
        await XCTAssertThrowsAsyncError(try await storage.commit(DurableCommitBatch(tasks: [reparented]))) { error in
            XCTAssertTrue(String(describing: error).contains("immutable"))
        }
        var running = DurableTaskRecord(id: 3, conversationID: 1, kind: "task", status: .running, abortRequested: true)
        running.createdSeq = 99
        let updated = try await storage.commit(DurableCommitBatch(tasks: [running]))
        XCTAssertEqual(updated.tasks[3]?.createdSeq, 1)
        XCTAssertEqual(updated.tasks[3]?.status, .running)
        var abortCleared = running
        abortCleared.abortRequested = false
        await XCTAssertThrowsAsyncError(try await storage.commit(DurableCommitBatch(tasks: [abortCleared]))) { error in
            XCTAssertTrue(String(describing: error).contains("abort"))
        }
    }

    func testDocumentAddressAndSameConversationReferencesAreValidatedOnFinalCandidate() async throws {
        let storage = DurableMemoryStorage()
        _ = try await storage.commit(DurableCommitBatch(conversations: [DurableConversationRecord(id: 1), DurableConversationRecord(id: 2)], entries: [DurableEntryRecord(id: 3, conversationID: 2, kind: "other")]))
        await XCTAssertThrowsAsyncError(try await storage.commit(DurableCommitBatch(submissions: [DurableSubmissionRecord(id: 4, conversationID: 1, type: .input, status: .placed, entryID: 3)]))) { error in
            XCTAssertTrue(String(describing: error).contains("conversation mismatch"))
        }
        let first = DurableDocumentRecord(id: 5, scope: "conversation", ownerID: 1, kind: "state", value: .object([:]))
        let duplicateAddress = DurableDocumentRecord(id: 6, scope: "conversation", ownerID: 1, kind: "state", value: .object(["other": .bool(true)]))
        await XCTAssertThrowsAsyncError(try await storage.commit(DurableCommitBatch(documents: [first, duplicateAddress]))) { error in
            XCTAssertTrue(String(describing: error).contains("duplicate document address"))
        }
    }

    func testSubmissionSettlementInvariantsAndTerminalImmutability() async throws {
        let storage = DurableMemoryStorage()
        _ = try await storage.commit(DurableCommitBatch(conversations: [DurableConversationRecord(id: 1)], entries: [DurableEntryRecord(id: 2, conversationID: 1, kind: "question"), DurableEntryRecord(id: 3, conversationID: 1, kind: "answer")]))
        await XCTAssertThrowsAsyncError(try await storage.commit(DurableCommitBatch(submissions: [DurableSubmissionRecord(id: 4, conversationID: 1, type: .input, status: .done)]))) { error in
            XCTAssertTrue(String(describing: error).contains("initial") || String(describing: error).contains("done"))
        }
        _ = try await storage.commit(DurableCommitBatch(submissions: [DurableSubmissionRecord(id: 5, conversationID: 1, type: .input)]))
        let placed = DurableSubmissionRecord(id: 5, conversationID: 1, type: .input, status: .placed, entryID: 2)
        _ = try await storage.commit(DurableCommitBatch(submissions: [placed]))
        let done = DurableSubmissionRecord(id: 5, conversationID: 1, type: .input, status: .done, entryID: 2, answerID: 3)
        _ = try await storage.commit(DurableCommitBatch(submissions: [done]))
        var mutatedTerminal = done
        mutatedTerminal.reason = "changed"
        await XCTAssertThrowsAsyncError(try await storage.commit(DurableCommitBatch(submissions: [mutatedTerminal]))) { error in
            XCTAssertTrue(String(describing: error).contains("terminal") || String(describing: error).contains("done"))
        }
    }
}

func XCTAssertThrowsAsyncError<T>(_ expression: @autoclosure @escaping () async throws -> T, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line, _ errorHandler: (_ error: Error) -> Void = { _ in }) async {
    do { _ = try await expression(); XCTFail(message(), file: file, line: line) }
    catch { errorHandler(error) }
}
