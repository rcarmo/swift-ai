import XCTest
import CSQLite
@testable import SwiftAI

final class DurableSQLiteStorageTests: XCTestCase {
    func testAtomicMixedCommitReopenAndWriterExclusion() async throws {
        let directory = SwiftAITestScratch.directory("sqlite-mixed")
        let storage = try DurableSQLiteStorage(directory: directory)
        let batch = DurableCommitBatch(conversations: [DurableConversationRecord(id: 1)], entries: [DurableEntryRecord(id: 2, conversationID: 1, kind: "user", messages: [.user("input")])], tasks: [DurableTaskRecord(id: 3, conversationID: 1, kind: "custom")], submissions: [DurableSubmissionRecord(id: 4, conversationID: 1, requestID: "key", type: .input, status: .placed, entryID: 2)], documents: [DurableDocumentRecord(id: 5, scope: "conversation", ownerID: 1, kind: "doc", value: .object(["n": .number(1)]), version: 1, history: .rewindable, forkPolicy: .asOf)])
        let committed = try await storage.commit(batch); XCTAssertEqual(committed.seq, 1); XCTAssertEqual(committed.highWaterID, 5)
        do { _ = try DurableSQLiteStorage(directory: directory); XCTFail("second writer accepted") } catch DurableError.storageBusy {} catch { XCTFail("wrong writer exclusion error") }
        do { _ = try await storage.commit(DurableCommitBatch(entries: [DurableEntryRecord(id: 6, conversationID: 999, kind: "invalid")])); XCTFail("invalid commit accepted") } catch {}
        let after = try await storage.snapshot(); XCTAssertEqual(after, committed)
        try await storage.close()
        let reopened = try DurableSQLiteStorage(directory: directory)
        let replay = try await reopened.snapshot(); XCTAssertEqual(replay, committed); XCTAssertEqual(replay.documentHistory?[5]?.count, 1)
        let empty = try await reopened.commit(DurableCommitBatch()); XCTAssertEqual(empty.seq, 1)
        try await reopened.close()
    }

    func testSQLiteSessionForkResetAndDocumentHistory() async throws {
        let directory = SwiftAITestScratch.directory("sqlite-session")
        let session = DurableSession(storage: try DurableSQLiteStorage(directory: directory))
        let parent = try await session.createConversation()
        _ = try await session.writeDocument(scope: "conversation", ownerID: parent.id, kind: "history", value: .object(["n": .number(1)]), history: .rewindable, fork: .asOf)
        let cut = try await session.appendEntry(conversationID: parent.id, kind: "user", messages: [.user("before")])
        _ = try await session.writeDocument(scope: "conversation", ownerID: parent.id, kind: "history", value: .object(["n": .number(2)]), history: .rewindable, fork: .asOf)
        let child = try await session.forkConversation(parentID: parent.id, at: cut.id)
        let copied = try await session.document(scope: "conversation", ownerID: child.id, kind: "history"); XCTAssertEqual(copied, .object(["n": .number(1)]))
        _ = try await session.resetConversation(conversationID: child.id, messages: [.user("reset")])
        try await session.close()
        let reopened = DurableSession(storage: try DurableSQLiteStorage(directory: directory))
        let context = try await reopened.context(conversationID: child.id); XCTAssertEqual(context.messages.compactMap { $0.content.first?.text }, ["reset"])
        try await reopened.close()
    }

    func testCorruptPayloadFailsClosedOnReopen() async throws {
        let directory = SwiftAITestScratch.directory("sqlite-corrupt")
        let storage = try DurableSQLiteStorage(directory: directory)
        _ = try await storage.commit(DurableCommitBatch(conversations: [DurableConversationRecord(id: 1)])); try await storage.close()
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(directory.appendingPathComponent("session.sqlite3").path, &database), SQLITE_OK)
        defer { sqlite3_close(database) }
        XCTAssertEqual(sqlite3_exec(database, "UPDATE state SET payload=x'7b7d'", nil, nil, nil), SQLITE_OK)
        do { _ = try DurableSQLiteStorage(directory: directory); XCTFail("corrupt payload accepted") } catch DurableError.corruptStorage {} catch { XCTFail("wrong corruption error") }
    }
}
