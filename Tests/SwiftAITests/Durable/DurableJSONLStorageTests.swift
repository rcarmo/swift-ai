import XCTest
@testable import SwiftAI

final class DurableJSONLStorageTests: XCTestCase {
    func testMixedBatchReopenAndTornFinalLineRepair() async throws {
        let directory = SwiftAITestScratch.directory("jsonl-torn")
        let storage = try DurableJSONLStorage(directory: directory)
        let committed = try await storage.commit(DurableCommitBatch(conversations: [DurableConversationRecord(id: 1)], entries: [DurableEntryRecord(id: 2, conversationID: 1, kind: "user", messages: [.user("input")])], documents: [DurableDocumentRecord(id: 3, scope: "conversation", ownerID: 1, kind: "doc", value: .object(["n": .number(1)]), history: .rewindable, forkPolicy: .asOf)]))
        try await storage.close()
        let path = directory.appendingPathComponent("main.jsonl")
        let size = try Data(contentsOf: path).count
        let append = try FileHandle(forWritingTo: path); try append.seekToEnd(); try append.write(contentsOf: Data("{\"partial\":".utf8)); try append.close()
        let reopened = try DurableJSONLStorage(directory: directory)
        let snapshot = try await reopened.snapshot(); XCTAssertEqual(snapshot, committed); XCTAssertEqual(try Data(contentsOf: path).count, size)
        let next = try await reopened.commit(DurableCommitBatch(entries: [DurableEntryRecord(id: 4, conversationID: 1, kind: "user", messages: [.user("next")])]))
        XCTAssertEqual(next.seq, 2); try await reopened.close()
        let verify = try DurableJSONLStorage(directory: directory); let final = try await verify.snapshot(); XCTAssertEqual(final.entries.count, 2); try await verify.close()
    }

    func testCompleteCorruptionAndSequenceFaultFailClosed() async throws {
        let directory = SwiftAITestScratch.directory("jsonl-corrupt")
        let storage = try DurableJSONLStorage(directory: directory)
        _ = try await storage.commit(DurableCommitBatch(conversations: [DurableConversationRecord(id: 1)])); try await storage.close()
        let path = directory.appendingPathComponent("main.jsonl")
        var object = try JSONSerialization.jsonObject(with: Data(contentsOf: path)) as! [String: Any]
        object["checksum"] = String(repeating: "0", count: 64)
        var corrupt = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]); corrupt.append(10); try corrupt.write(to: path)
        do { _ = try DurableJSONLStorage(directory: directory); XCTFail("checksum conflict accepted") } catch DurableError.corruptStorage {} catch { XCTFail("wrong checksum error") }
        object["version"] = 99
        var unsupported = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]); unsupported.append(10); try unsupported.write(to: path)
        do { _ = try DurableJSONLStorage(directory: directory); XCTFail("unknown version accepted") } catch {}
    }

    func testInvalidBatchPublishesNothingAndWriterIsExclusive() async throws {
        let directory = SwiftAITestScratch.directory("jsonl-exclusive")
        let storage = try DurableJSONLStorage(directory: directory)
        let before = try await storage.snapshot()
        do { _ = try await storage.commit(DurableCommitBatch(entries: [DurableEntryRecord(id: 1, conversationID: 999, kind: "invalid")])); XCTFail("invalid write accepted") } catch {}
        let after = try await storage.snapshot(); XCTAssertEqual(after, before)
        do { _ = try DurableJSONLStorage(directory: directory); XCTFail("second writer accepted") } catch DurableError.storageBusy {} catch { XCTFail("wrong lock error") }
        try await storage.close()
    }
}
