import Foundation
import CSQLite

/// SQLite transaction persistence for the native Swift durable records. The database is not an upstream wire format.
public actor DurableSQLiteStorage: DurableStorage {
    private var database: OpaquePointer?
    private var current: DurableSnapshot
    private let writerLock: DurableJournalLock
    private var closed = false
    private var poison: String?
    public let directory: URL

    public init(directory: URL) throws {
        #if os(Linux) || os(macOS)
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.writerLock = try DurableJournalLock(directory: directory)
        self.current = DurableSnapshot()
        var handle: OpaquePointer?
        let status = sqlite3_open_v2(directory.appendingPathComponent("session.sqlite3").path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
        guard status == SQLITE_OK, let handle else { if let handle { sqlite3_close(handle) }; writerLock.release(); throw DurableError.corruptStorage("cannot open SQLite storage") }
        do {
            try Self.execute(handle, "PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; PRAGMA foreign_keys=ON; PRAGMA trusted_schema=OFF; PRAGMA temp_store=MEMORY;")
            var versionStatement: OpaquePointer?
            guard sqlite3_prepare_v2(handle, "PRAGMA user_version", -1, &versionStatement, nil) == SQLITE_OK else { throw DurableError.corruptStorage("SQLite version read failed") }
            let versionStep = sqlite3_step(versionStatement), version = sqlite3_column_int(versionStatement, 0); sqlite3_finalize(versionStatement)
            guard versionStep == SQLITE_ROW, version == 0 || version == 1 else { throw DurableError.corruptStorage("unsupported SQLite schema version") }
            try Self.execute(handle, "CREATE TABLE IF NOT EXISTS state (singleton INTEGER PRIMARY KEY CHECK(singleton=1), sequence INTEGER NOT NULL, payload BLOB NOT NULL); PRAGMA user_version=1;")
            if let loaded = try Self.load(handle) { try DurableValidation.validate(snapshot: loaded); current = loaded }
            database = handle
        } catch { sqlite3_close(handle); writerLock.release(); throw error }
        #else
        self.directory = directory
        self.current = DurableSnapshot()
        self.writerLock = try DurableJournalLock(directory: directory)
        throw DurableError.unsupportedPlatform("native SQLite persistence requires Linux/macOS ownership locking")
        #endif
    }

    public func snapshot() throws -> DurableSnapshot { try ensureOpen(); return current }

    public func commit(_ batch: DurableCommitBatch) throws -> DurableSnapshot {
        try ensureOpen()
        guard let database else { throw DurableError.closed }
        let highWater = try DurableValidation.validate(batch: batch, against: current)
        if batch.conversations.isEmpty, batch.entries.isEmpty, batch.tasks.isEmpty, batch.submissions.isEmpty, batch.documents.isEmpty { return current }
        let next = DurableValidation.applying(batch, to: current, seq: current.seq + 1, highWater: highWater)
        let payload = try DurableValidation.encoder.encode(next)
        guard payload.count <= DurableLimits.maxJournalBytes else { throw DurableError.invalidRecord("SQLite snapshot exceeds storage byte limit") }
        try Self.execute(database, "BEGIN IMMEDIATE")
        do {
            if let stored = try Self.load(database) {
                try DurableValidation.validate(snapshot: stored)
                guard stored == current else { throw DurableError.corruptStorage("SQLite storage changed outside owner") }
            } else if current.seq != 0 { throw DurableError.corruptStorage("SQLite state disappeared") }
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, "INSERT INTO state(singleton,sequence,payload) VALUES(1,?,?) ON CONFLICT(singleton) DO UPDATE SET sequence=excluded.sequence,payload=excluded.payload", -1, &statement, nil) == SQLITE_OK else { throw DurableError.corruptStorage("SQLite write preparation failed") }
            defer { sqlite3_finalize(statement) }
            guard sqlite3_bind_int64(statement, 1, next.seq) == SQLITE_OK else { throw DurableError.corruptStorage("SQLite sequence bind failed") }
            let result = payload.withUnsafeBytes { bytes -> Int32 in
                // SQLite keeps this borrowed buffer only through sqlite3_step; no pointer survives the closure.
                let bind = sqlite3_bind_blob(statement, 2, bytes.baseAddress, Int32(bytes.count), nil)
                return bind == SQLITE_OK ? sqlite3_step(statement) : bind
            }
            guard result == SQLITE_DONE else { throw DurableError.corruptStorage("SQLite write failed: \(result)") }
            do { try Self.execute(database, "COMMIT") }
            catch { poison = "SQLite commit acknowledgement failed"; throw DurableError.durabilityUncertain(poison!) }
            current = next
            return current
        } catch {
            try? Self.execute(database, "ROLLBACK")
            throw error
        }
    }

    public func close() throws {
        if closed { return }; closed = true
        guard let database else { writerLock.release(); return }
        let result = sqlite3_close_v2(database)
        self.database = nil; writerLock.release()
        if result != SQLITE_OK { throw DurableError.durabilityUncertain("SQLite close failed") }
    }

    private func ensureOpen() throws {
        if closed { throw DurableError.closed }
        if let poison { throw DurableError.poisoned(poison) }
    }

    private static func execute(_ database: OpaquePointer, _ sql: String) throws {
        let code = sqlite3_exec(database, sql, nil, nil, nil)
        guard code == SQLITE_OK else { throw DurableError.corruptStorage("SQLite operation failed: \(code)") }
    }

    private static func load(_ database: OpaquePointer) throws -> DurableSnapshot? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT sequence,payload FROM state WHERE singleton=1", -1, &statement, nil) == SQLITE_OK else { throw DurableError.corruptStorage("SQLite state query failed") }
        defer { sqlite3_finalize(statement) }
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { return nil }
        guard result == SQLITE_ROW else { throw DurableError.corruptStorage("SQLite state read failed") }
        let bytes = Int(sqlite3_column_bytes(statement, 1))
        guard bytes > 0, bytes <= DurableLimits.maxJournalBytes, let pointer = sqlite3_column_blob(statement, 1) else { throw DurableError.corruptStorage("invalid SQLite payload length") }
        let snapshot: DurableSnapshot
        do { snapshot = try JSONDecoder().decode(DurableSnapshot.self, from: Data(bytes: pointer, count: bytes)) }
        catch { throw DurableError.corruptStorage("invalid SQLite snapshot payload") }
        guard snapshot.seq == sqlite3_column_int64(statement, 0) else { throw DurableError.corruptStorage("SQLite sequence/payload mismatch") }
        return snapshot
    }

    deinit { if let database { sqlite3_close(database) }; writerLock.release() }
}
