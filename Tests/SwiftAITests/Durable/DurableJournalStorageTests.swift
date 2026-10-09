import XCTest
@testable import SwiftAI

private struct JournalFault: DurableJournalFaultInjector {
    enum Point: String { case beforeAppend, shortWrite, afterAppend, afterFileSync, afterDirectorySync }
    let point: Point
    func beforeAppend(seq: Int64, frame: Data) throws { if point == .beforeAppend { throw DurableError.poisoned("before append") } }
    func frameToAppend(seq: Int64, frame: Data) throws -> Data { point == .shortWrite ? Data(frame.prefix(frame.count / 2)) : frame }
    func afterAppendBeforeSync(seq: Int64) throws { if point == .afterAppend || point == .shortWrite { throw DurableError.poisoned("after append") } }
    func afterFileSyncBeforeDirectorySync(seq: Int64) throws { if point == .afterFileSync { throw DurableError.poisoned("after file sync") } }
    func afterDirectorySyncBeforeAck(seq: Int64) throws { if point == .afterDirectorySync { throw DurableError.poisoned("after directory sync") } }
}

#if os(Linux)
private struct CrashJournalFault: DurableJournalFaultInjector {
    let point: JournalFault.Point
    func beforeAppend(seq: Int64, frame: Data) throws { if point == .beforeAppend { kill(getpid(), SIGKILL) } }
    func frameToAppend(seq: Int64, frame: Data) throws -> Data { point == .shortWrite ? Data(frame.prefix(frame.count / 2)) : frame }
    func afterAppendBeforeSync(seq: Int64) throws { if point == .shortWrite { kill(getpid(), SIGKILL) } }
    func afterFileSyncBeforeDirectorySync(seq: Int64) throws { if point == .afterFileSync { kill(getpid(), SIGKILL) } }
    func afterDirectorySyncBeforeAck(seq: Int64) throws { if point == .afterDirectorySync { kill(getpid(), SIGKILL) } }
}
#endif

final class DurableJournalStorageTests: XCTestCase {
    private func tempDir(_ name: String = #function) -> URL {
        SwiftAITestScratch.directory("durable-\(name)")
    }

    func testJournalPersistsReopensAndReleasesLockOnClose() async throws {
        let dir = tempDir()
        let storage = try DurableJournalStorage(directory: dir)
        #if os(Linux) || os(macOS)
        let mode = try FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent("journal.log").path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(mode?.intValue, 0o600)
        #endif
        _ = try await storage.commit(DurableCommitBatch(conversations: [DurableConversationRecord(id: 1)], entries: [DurableEntryRecord(id: 2, conversationID: 1, kind: "pi.user", messages: [.user("hi")])]))
        try await storage.close()
        let reopened = try DurableJournalStorage(directory: dir)
        let snapshot = try await reopened.snapshot()
        XCTAssertEqual(snapshot.seq, 1)
        XCTAssertEqual(snapshot.highWaterID, 2)
        XCTAssertEqual(snapshot.entries[2]?.messages?.first?.content.first?.text, "hi")
        try await reopened.close()
    }

    func testIncompleteFinalFrameIsTruncatedBeforeAppend() async throws {
        let dir = tempDir()
        let storage = try DurableJournalStorage(directory: dir)
        _ = try await storage.commit(DurableCommitBatch(conversations: [DurableConversationRecord(id: 1)]))
        try await storage.close()
        let journal = dir.appendingPathComponent("journal.log")
        var data = try Data(contentsOf: journal)
        let validCount = data.count
        data.append(DurableJournalStorage.magic.prefix(2))
        try data.write(to: journal)
        let repaired = try DurableJournalStorage(directory: dir)
        let repairedSnapshot = try await repaired.snapshot()
        XCTAssertEqual(repairedSnapshot.seq, 1)
        _ = try await repaired.commit(DurableCommitBatch(entries: [DurableEntryRecord(id: 2, conversationID: 1, kind: "pi.user")]))
        try await repaired.close()
        let finalData = try Data(contentsOf: journal)
        XCTAssertGreaterThan(finalData.count, validCount)
        let reopened = try DurableJournalStorage(directory: dir)
        let reopenedSnapshot = try await reopened.snapshot()
        XCTAssertEqual(reopenedSnapshot.seq, 2)
        try await reopened.close()
    }

    func testCompleteCorruptionFailsClosed() async throws {
        let dir = tempDir()
        let storage = try DurableJournalStorage(directory: dir)
        _ = try await storage.commit(DurableCommitBatch(conversations: [DurableConversationRecord(id: 1)]))
        try await storage.close()
        let journal = dir.appendingPathComponent("journal.log")
        var data = try Data(contentsOf: journal)
        XCTAssertGreaterThan(data.count, DurableJournalStorage.headerLength + 1)
        data[DurableJournalStorage.headerLength] ^= 0xff
        try data.write(to: journal)
        XCTAssertThrowsError(try DurableJournalStorage(directory: dir)) { error in
            XCTAssertTrue(String(describing: error).contains("checksum") || String(describing: error).contains("corrupt"))
        }
    }

    func testMalformedPrefixesAndHeadersFailClosedButShortMagicTailRepairs() async throws {
        let garbageDir = tempDir()
        try FileManager.default.createDirectory(at: garbageDir, withIntermediateDirectories: true)
        try Data([0x00, 0x01]).write(to: garbageDir.appendingPathComponent("journal.log"))
        XCTAssertThrowsError(try DurableJournalStorage(directory: garbageDir)) { error in
            XCTAssertTrue(String(describing: error).contains("partial frame prefix") || String(describing: error).contains("corrupt"))
        }

        let versionDir = tempDir()
        let storage = try DurableJournalStorage(directory: versionDir)
        _ = try await storage.commit(DurableCommitBatch(conversations: [DurableConversationRecord(id: 1)]))
        try await storage.close()
        let journal = versionDir.appendingPathComponent("journal.log")
        var data = try Data(contentsOf: journal)
        data[4] = 9
        try data.write(to: journal)
        XCTAssertThrowsError(try DurableJournalStorage(directory: versionDir)) { error in
            XCTAssertTrue(String(describing: error).contains("version") || String(describing: error).contains("corrupt"))
        }

        let tailDir = tempDir()
        let tailStorage = try DurableJournalStorage(directory: tailDir)
        _ = try await tailStorage.commit(DurableCommitBatch(conversations: [DurableConversationRecord(id: 1)]))
        try await tailStorage.close()
        let tailJournal = tailDir.appendingPathComponent("journal.log")
        var tailData = try Data(contentsOf: tailJournal)
        tailData.append(contentsOf: DurableJournalStorage.magic.prefix(3))
        try tailData.write(to: tailJournal)
        let repaired = try DurableJournalStorage(directory: tailDir)
        let snapshot = try await repaired.snapshot()
        XCTAssertEqual(snapshot.seq, 1)
        try await repaired.close()
    }

    func testKnownPartialHeadersAndCommittedTrailerDamageFailClosed() async throws {
        for bytes in [Data([0x53, 0x44, 0x4a, 0x31, 0x09]), Data([0x53, 0x44, 0x4a, 0x31, 0x01, 0xff])] {
            let dir = tempDir()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try bytes.write(to: dir.appendingPathComponent("journal.log"))
            XCTAssertThrowsError(try DurableJournalStorage(directory: dir)) { error in
                XCTAssertTrue(String(describing: error).contains("partial") || String(describing: error).contains("corrupt") || String(describing: error).contains("version"))
            }
        }

        let wrongSeqDir = tempDir()
        try FileManager.default.createDirectory(at: wrongSeqDir, withIntermediateDirectories: true)
        let wrongSeqPayload = try DurableValidation.encoder.encode(DurableJournalPayload(seq: 9, highWaterID: 1, batch: DurableCommitBatch(conversations: [DurableConversationRecord(id: 1)])))
        let wrongSeqFrame = DurableJournalStorage.frame(seq: 9, highWater: 1, payload: wrongSeqPayload)
        try Data(wrongSeqFrame.prefix(DurableJournalStorage.headerLength)).write(to: wrongSeqDir.appendingPathComponent("journal.log"))
        XCTAssertThrowsError(try DurableJournalStorage(directory: wrongSeqDir)) { error in
            XCTAssertTrue(String(describing: error).contains("sequence") || String(describing: error).contains("corrupt"))
        }

        let rollbackDir = tempDir()
        let rollbackStorage = try DurableJournalStorage(directory: rollbackDir)
        _ = try await rollbackStorage.commit(DurableCommitBatch(conversations: [DurableConversationRecord(id: 1)]))
        _ = try await rollbackStorage.commit(DurableCommitBatch(entries: [DurableEntryRecord(id: 2, conversationID: 1, kind: "seq2")]))
        try await rollbackStorage.close()
        let rollbackJournal = rollbackDir.appendingPathComponent("journal.log")
        var rollbackData = try Data(contentsOf: rollbackJournal)
        rollbackData.append(DurableJournalStorage.magic)
        rollbackData.append(UInt8(1))
        rollbackData.append(contentsOf: DurableJournalStorage.be(3))
        rollbackData.append(contentsOf: DurableJournalStorage.be(1))
        try rollbackData.write(to: rollbackJournal)
        XCTAssertThrowsError(try DurableJournalStorage(directory: rollbackDir)) { error in
            XCTAssertTrue(String(describing: error).contains("high-water") || String(describing: error).contains("corrupt"))
        }

        let dir = tempDir()
        let storage = try DurableJournalStorage(directory: dir)
        _ = try await storage.commit(DurableCommitBatch(conversations: [DurableConversationRecord(id: 1)]))
        try await storage.close()
        let journal = dir.appendingPathComponent("journal.log")
        let data = try Data(contentsOf: journal)
        for cut in 1..<data.count {
            let cutDir = tempDir("cut-\(cut)")
            try FileManager.default.createDirectory(at: cutDir, withIntermediateDirectories: true)
            try Data(data.prefix(cut)).write(to: cutDir.appendingPathComponent("journal.log"))
            let opened = try DurableJournalStorage(directory: cutDir)
            let snapshot = try await opened.snapshot()
            XCTAssertEqual(snapshot.seq, 0)
            try await opened.close()
        }
        for cut in 1..<41 {
            var damaged = data
            damaged[damaged.count - cut] ^= 0xff
            let damagedDir = tempDir("damaged-\(cut)")
            try FileManager.default.createDirectory(at: damagedDir, withIntermediateDirectories: true)
            try damaged.write(to: damagedDir.appendingPathComponent("journal.log"))
            XCTAssertThrowsError(try DurableJournalStorage(directory: damagedDir))
        }
    }

    func testAppendSyncFaultsPoisonAndReopenToPriorOrCommittedTruth() async throws {
        for point in [JournalFault.Point.beforeAppend, .shortWrite, .afterAppend, .afterFileSync, .afterDirectorySync] {
            let dir = tempDir("fault-\(point)")
            let storage = try DurableJournalStorage(directory: dir, faultInjector: JournalFault(point: point))
            await XCTAssertThrowsAsyncError(try await storage.commit(DurableCommitBatch(conversations: [DurableConversationRecord(id: 1)]))) { error in
                XCTAssertTrue(String(describing: error).contains("uncertain") || String(describing: error).contains("durability"))
            }
            await XCTAssertThrowsAsyncError(try await storage.snapshot()) { error in
                XCTAssertTrue(String(describing: error).contains("uncertain") || String(describing: error).contains("poison"))
            }
            try? await storage.close()
            let reopened = try DurableJournalStorage(directory: dir)
            let snapshot = try await reopened.snapshot()
            switch point {
            case .beforeAppend, .shortWrite:
                XCTAssertEqual(snapshot.seq, 0)
            case .afterFileSync, .afterDirectorySync:
                XCTAssertEqual(snapshot.seq, 1)
            case .afterAppend:
                XCTAssertTrue(snapshot.seq == 0 || snapshot.seq == 1)
            }
            try await reopened.close()
        }
    }

    func testProductionJournalCrashPhasesRecoverExpectedTruth() async throws {
        #if os(Linux)
        if let phase = ProcessInfo.processInfo.environment["SWIFT_AI_DURABLE_CRASH_PHASE"] {
            let dir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SWIFT_AI_DURABLE_SIGKILL_DIR"]!, isDirectory: true)
            guard let point = JournalFault.Point(rawValue: phase) else { exit(2) }
            let storage = try DurableJournalStorage(directory: dir, faultInjector: CrashJournalFault(point: point))
            _ = try await storage.commit(DurableCommitBatch(entries: [DurableEntryRecord(id: 2, conversationID: 1, kind: "crash")]))
            XCTFail("expected crash before ACK")
            return
        }

        for point in [JournalFault.Point.beforeAppend, .shortWrite, .afterFileSync, .afterDirectorySync] {
            let dir = tempDir("crash-\(point.rawValue)")
            let initial = try DurableJournalStorage(directory: dir)
            _ = try await initial.commit(DurableCommitBatch(conversations: [DurableConversationRecord(id: 1)]))
            try await initial.close()

            let proc = Process()
            proc.executableURL = Bundle.main.executableURL
            proc.arguments = ["SwiftAITests.DurableJournalStorageTests/testProductionJournalCrashPhasesRecoverExpectedTruth"]
            var environment = ProcessInfo.processInfo.environment
            environment["SWIFT_AI_DURABLE_CRASH_PHASE"] = point.rawValue
            environment["SWIFT_AI_DURABLE_SIGKILL_DIR"] = dir.path
            proc.environment = environment
            try proc.run()
            proc.waitUntilExit()
            XCTAssertTrue([9, 137].contains(Int(proc.terminationStatus)))

            let reopened = try DurableJournalStorage(directory: dir)
            var snapshot = try await reopened.snapshot()
            switch point {
            case .beforeAppend, .shortWrite:
                XCTAssertEqual(snapshot.seq, 1)
                XCTAssertNil(snapshot.entries[2])
            case .afterFileSync, .afterDirectorySync:
                XCTAssertEqual(snapshot.seq, 2)
                XCTAssertEqual(snapshot.entries[2]?.kind, "crash")
            case .afterAppend:
                XCTFail("afterAppend is not part of production crash phase matrix")
            }
            _ = try await reopened.commit(DurableCommitBatch(entries: [DurableEntryRecord(id: 3, conversationID: 1, kind: "after-crash")]))
            try await reopened.close()
            let final = try DurableJournalStorage(directory: dir)
            snapshot = try await final.snapshot()
            XCTAssertEqual(snapshot.entries[3]?.kind, "after-crash")
            try await final.close()
        }
        #endif
    }

    func testLockPreventsConcurrentOpenAndCrashReleaseProcess() async throws {
        #if os(Linux)
        if ProcessInfo.processInfo.environment["SWIFT_AI_DURABLE_LOCK_CHILD"] == "1" {
            let dir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SWIFT_AI_DURABLE_LOCK_DIR"]!, isDirectory: true)
            let storage = try DurableJournalStorage(directory: dir)
            defer { withExtendedLifetime(storage) {} }
            try FileHandle.standardError.write(contentsOf: Data("LOCKED\n".utf8))
            while true { _ = pause() }
        }
        #endif
        let dir = tempDir()
        let storage = try DurableJournalStorage(directory: dir)
        XCTAssertThrowsError(try DurableJournalStorage(directory: dir))
        try await storage.close()
        let reopened = try DurableJournalStorage(directory: dir)
        try await reopened.close()

        #if os(Linux)
        let proc = Process()
        proc.executableURL = Bundle.main.executableURL
        proc.arguments = ["SwiftAITests.DurableJournalStorageTests/testLockPreventsConcurrentOpenAndCrashReleaseProcess"]
        var environment = ProcessInfo.processInfo.environment
        environment["SWIFT_AI_DURABLE_LOCK_CHILD"] = "1"
        environment["SWIFT_AI_DURABLE_LOCK_DIR"] = dir.path
        proc.environment = environment
        let pipe = Pipe()
        proc.standardError = pipe
        try proc.run()
        try pipe.fileHandleForWriting.close()
        let ack = pipe.fileHandleForReading.availableData
        XCTAssertEqual(String(data: ack, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), "LOCKED")
        XCTAssertThrowsError(try DurableJournalStorage(directory: dir))
        kill(proc.processIdentifier, SIGKILL)
        proc.waitUntilExit()
        XCTAssertNotEqual(proc.terminationStatus, 0)
        let afterKill = try DurableJournalStorage(directory: dir)
        try await afterKill.close()
        #endif
    }
}
