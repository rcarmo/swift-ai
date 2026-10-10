import Foundation
import Crypto
#if os(Linux)
import Glibc
#elseif os(macOS)
import Darwin
#endif

private struct DurableJSONLFrame: Codable {
    var version: Int
    var seq: Int64
    var highWaterID: Int64
    var payload: Data
    var checksum: String
}

/// One checksummed native commit per line; complete invalid lines fail closed, incomplete EOF is truncated.
public actor DurableJSONLStorage: DurableStorage {
    private var current: DurableSnapshot
    private let lock: DurableJournalLock
    private let handle: FileHandle
    private var closed = false
    private var poison: String?
    public let directory: URL

    public init(directory: URL) throws {
        #if os(Linux) || os(macOS)
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let lock = try DurableJournalLock(directory: directory); self.lock = lock
        let path = directory.appendingPathComponent("main.jsonl")
        if !FileManager.default.fileExists(atPath: path.path) { guard FileManager.default.createFile(atPath: path.path, contents: nil) else { lock.release(); throw DurableError.corruptStorage("cannot create JSONL storage") } }
        do {
            let handle = try FileHandle(forUpdating: path)
            do {
                let size = try handle.seekToEnd(); guard size <= UInt64(DurableLimits.maxJournalBytes) else { throw DurableError.corruptStorage("JSONL file exceeds byte limit") }
                try handle.seek(toOffset: 0)
                var state = DurableSnapshot(), pending = Data(), consumed: UInt64 = 0, frames = 0
                while let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
                    pending.append(chunk)
                    while let newline = pending.firstIndex(of: 10) {
                        let line = Data(pending[..<newline]); let lineBytes = newline - pending.startIndex + 1
                        guard line.count <= DurableLimits.maxBatchBytes * 2, !line.isEmpty else { throw DurableError.corruptStorage("invalid JSONL line length") }
                        frames += 1; guard frames <= DurableLimits.maxJournalFrames else { throw DurableError.corruptStorage("too many JSONL frames") }
                        let frame: DurableJSONLFrame
                        do { frame = try JSONDecoder().decode(DurableJSONLFrame.self, from: line) }
                        catch { throw DurableError.corruptStorage("invalid complete JSONL frame") }
                        guard frame.version == 1, frame.seq == state.seq + 1, frame.highWaterID >= state.highWaterID, frame.payload.count <= DurableLimits.maxBatchBytes, Self.checksum(frame.payload) == frame.checksum else { throw DurableError.corruptStorage("JSONL version/sequence/checksum conflict") }
                        let batch: DurableCommitBatch
                        do { batch = try JSONDecoder().decode(DurableCommitBatch.self, from: frame.payload) } catch { throw DurableError.corruptStorage("invalid JSONL batch") }
                        let high = try DurableValidation.validate(batch: batch, against: state)
                        guard high == frame.highWaterID else { throw DurableError.corruptStorage("JSONL allocator mismatch") }
                        state = DurableValidation.applying(batch, to: state, seq: frame.seq, highWater: high)
                        consumed += UInt64(lineBytes); pending.removeFirst(lineBytes)
                    }
                    guard pending.count <= DurableLimits.maxBatchBytes * 2 else { throw DurableError.corruptStorage("oversized unterminated JSONL frame") }
                }
                if !pending.isEmpty { try handle.truncate(atOffset: consumed); try handle.synchronize() }
                try handle.seekToEnd(); current = state; self.handle = handle
            } catch { try? handle.close(); throw error }
        } catch { lock.release(); throw error }
        #else
        self.directory = directory
        throw DurableError.unsupportedPlatform("native JSONL storage requires Linux/macOS locking")
        #endif
    }

    public func snapshot() throws -> DurableSnapshot { try ensureOpen(); return current }

    public func commit(_ batch: DurableCommitBatch) throws -> DurableSnapshot {
        try ensureOpen()
        let highWater = try DurableValidation.validate(batch: batch, against: current)
        if batch.conversations.isEmpty, batch.entries.isEmpty, batch.tasks.isEmpty, batch.submissions.isEmpty, batch.documents.isEmpty { return current }
        let payload = try DurableValidation.encoder.encode(batch)
        let frame = DurableJSONLFrame(version: 1, seq: current.seq + 1, highWaterID: highWater, payload: payload, checksum: Self.checksum(payload))
        var line = try DurableValidation.encoder.encode(frame); line.append(10)
        let size = try handle.seekToEnd()
        guard size + UInt64(line.count) <= UInt64(DurableLimits.maxJournalBytes) else { throw DurableError.invalidRecord("JSONL file exceeds byte limit") }
        do {
            try handle.write(contentsOf: line); try handle.synchronize()
            #if os(Linux) || os(macOS)
            let fd = open(directory.path, O_RDONLY)
            guard fd >= 0 else { throw DurableError.durabilityUncertain("JSONL directory open failed") }
            let result = fsync(fd)
            #if os(Linux)
            _ = Glibc.close(fd)
            #else
            _ = Darwin.close(fd)
            #endif
            guard result == 0 else { throw DurableError.durabilityUncertain("JSONL directory sync failed") }
            #endif
            current = DurableValidation.applying(batch, to: current, seq: frame.seq, highWater: highWater)
            return current
        } catch { poison = "JSONL append/sync failed"; throw DurableError.durabilityUncertain(poison!) }
    }

    public func close() throws {
        if closed { return }; closed = true
        defer { lock.release() }
        try handle.close()
    }
    private func ensureOpen() throws { if closed { throw DurableError.closed }; if let poison { throw DurableError.poisoned(poison) } }
    private static func checksum(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}
