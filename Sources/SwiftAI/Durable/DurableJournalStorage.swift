import Foundation
import Crypto
#if os(Linux)
import Glibc
@_silgen_name("fallocate")
private func linuxFallocate(_ fd: Int32, _ mode: Int32, _ offset: Int64, _ len: Int64) -> Int32
#elseif os(macOS)
import Darwin
#endif

public actor DurableJournalStorage: DurableStorage {
    static let magic = Data([0x53, 0x44, 0x4a, 0x31])
    static let terminator = Data([0x45, 0x4e, 0x44, 0x21])
    static let headerLength = 4 + 1 + 8 + 8 + 8 + 32
    private let directory: URL
    private let journalURL: URL
    private let lock: DurableJournalLock
    private let fileHandle: FileHandle
    private let faultInjector: DurableJournalFaultInjector?
    private var current: DurableSnapshot
    private var isClosed = false
    private var poisonReason: String?

    public init(directory: URL, faultInjector: DurableJournalFaultInjector? = nil) throws {
        #if os(Linux) || os(macOS)
        self.directory = directory
        self.journalURL = directory.appendingPathComponent("journal.log")
        self.faultInjector = faultInjector
        let existed = FileManager.default.fileExists(atPath: directory.path)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if !existed { try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path) }
        try Self.syncDirectory(directory.deletingLastPathComponent())
        self.lock = try DurableJournalLock(directory: directory)
        var created = false
        if !FileManager.default.fileExists(atPath: journalURL.path) {
            let fd = open(journalURL.path, O_CREAT | O_EXCL | O_RDWR, S_IRUSR | S_IWUSR)
            guard fd >= 0 else { throw DurableError.poisoned("cannot create journal file") }
            Self.posixClose(fd)
            created = true
        }
        if created { try Self.syncDirectory(directory) }
        let replayed = try Self.replayAndRepair(journalURL: journalURL)
        self.current = replayed.snapshot
        self.fileHandle = try FileHandle(forWritingTo: journalURL)
        try fileHandle.truncate(atOffset: UInt64(replayed.validEnd))
        try fileHandle.seekToEnd()
        if replayed.didRepair { try Self.sync(fileHandle); try Self.syncDirectory(directory) }
        #else
        throw DurableError.unsupportedPlatform("DurableJournalStorage is supported on Linux and macOS only")
        #endif
    }

    public func snapshot() async throws -> DurableSnapshot { try ensureOpen(); return current }

    public func commit(_ batch: DurableCommitBatch) async throws -> DurableSnapshot {
        try ensureOpen()
        let highWater = try DurableValidation.validate(batch: batch, against: current)
        let seq = current.seq + 1
        let estimatedPayloadBytes = try DurableValidation.estimatedJournalPayloadBytes(batch: batch, seq: seq, highWater: highWater)
        guard estimatedPayloadBytes <= DurableLimits.maxBatchBytes else { throw DurableError.invalidRecord("journal payload exceeds batch limit") }
        let payload = DurableJournalPayload(seq: seq, highWaterID: highWater, batch: batch)
        let payloadData = try DurableValidation.encoder.encode(payload)
        guard payloadData.count <= DurableLimits.maxBatchBytes else { throw DurableError.invalidRecord("journal payload exceeds batch limit") }
        let frame = Self.frame(seq: seq, highWater: highWater, payload: payloadData)
        let appendOffset = try Self.currentOffset(fileHandle)
        guard appendOffset <= Int64(DurableLimits.maxJournalBytes), Int64(frame.count) <= Int64(DurableLimits.maxJournalBytes) - appendOffset else { throw DurableError.invalidRecord("journal append exceeds \(DurableLimits.maxJournalBytes) bytes") }
        do {
            try faultInjector?.beforeAppend(seq: seq, frame: frame)
            let frameToWrite = try faultInjector?.frameToAppend(seq: seq, frame: frame) ?? frame
            try Self.preallocate(fileHandle, additionalBytes: frameToWrite.count)
            try fileHandle.write(contentsOf: frameToWrite)
            try faultInjector?.afterAppendBeforeSync(seq: seq)
            try Self.sync(fileHandle)
            try faultInjector?.afterFileSyncBeforeDirectorySync(seq: seq)
            try Self.syncDirectory(directory)
            try faultInjector?.afterDirectorySyncBeforeAck(seq: seq)
        } catch {
            poisonReason = "uncertain journal append/sync failure: \(error)"
            throw DurableError.durabilityUncertain(poisonReason ?? "uncertain journal failure")
        }
        current = DurableValidation.applying(batch, to: current, seq: seq, highWater: highWater)
        return current
    }

    public func close() async throws {
        guard !isClosed else { return }
        do { if poisonReason == nil { try Self.sync(fileHandle) }; try fileHandle.close() }
        catch { lock.release(); isClosed = true; throw error }
        lock.release()
        isClosed = true
    }

    deinit { lock.release() }

    private func ensureOpen() throws {
        if let poisonReason { throw DurableError.poisoned(poisonReason) }
        if isClosed { throw DurableError.closed }
    }

    static func frame(seq: Int64, highWater: Int64, payload: Data) -> Data {
        var header = Data()
        header.append(magic)
        header.append(UInt8(1))
        header.append(contentsOf: be(seq))
        header.append(contentsOf: be(highWater))
        header.append(contentsOf: be(Int64(payload.count)))
        header.append(contentsOf: Data(SHA256.hash(data: payload)))
        let headerHash = Data(SHA256.hash(data: header))
        var out = Data()
        out.append(header)
        out.append(payload)
        out.append(terminator)
        out.append(contentsOf: be(seq))
        out.append(headerHash)
        return out
    }

    static func replayAndRepair(journalURL: URL) throws -> (snapshot: DurableSnapshot, validEnd: Int, didRepair: Bool) {
        let attributes = try FileManager.default.attributesOfItem(atPath: journalURL.path)
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        guard size >= 0, size <= DurableLimits.maxJournalBytes else { throw DurableError.corruptStorage("journal exceeds \(DurableLimits.maxJournalBytes) bytes") }
        let readHandle = try FileHandle(forReadingFrom: journalURL)
        defer { try? readHandle.close() }
        let data = try readHandle.read(upToCount: Int(size)) ?? Data()
        guard data.count == Int(size) else { throw DurableError.corruptStorage("short journal read") }
        let extra = try readHandle.read(upToCount: 1) ?? Data()
        guard extra.isEmpty else { throw DurableError.corruptStorage("journal grew during bounded read") }
        var offset = 0
        var snapshot = DurableSnapshot()
        var frames = 0
        while offset < data.count {
            guard frames < DurableLimits.maxJournalFrames else { throw DurableError.corruptStorage("journal frame limit exceeded") }
            frames += 1
            let frameStart = offset
            let remaining = data.count - offset
            if remaining < headerLength {
                try validatePartialHeaderTail(data, frameStart: frameStart, expectedSeq: snapshot.seq + 1, minimumHighWater: snapshot.highWaterID)
                return (snapshot, frameStart, true)
            }
            guard data[offset..<offset+4] == magic else { throw DurableError.corruptStorage("bad frame magic at \(offset)") }
            offset += 4
            let version = data[offset]; offset += 1
            guard version == 1 else { throw DurableError.corruptStorage("unsupported frame version \(version)") }
            let seq = try readInt64(data, &offset)
            let highWater = try readInt64(data, &offset)
            let length = try readInt64(data, &offset)
            guard seq == snapshot.seq + 1 else { throw DurableError.corruptStorage("sequence gap or duplicate") }
            guard highWater >= snapshot.highWaterID, highWater <= DurableLimits.maxExactInteger else { throw DurableError.corruptStorage("allocator high-water invalid") }
            guard length >= 0, length <= DurableLimits.maxBatchBytes else { throw DurableError.corruptStorage("invalid payload length") }
            let digest = data[offset..<offset+32]; offset += 32
            let payloadOffset = offset
            let fullFrameLength = headerLength + Int(length) + 4 + 8 + 32
            if data.count - frameStart < fullFrameLength {
                try validateIncompleteFrameTail(data, frameStart: frameStart, seq: seq, payloadOffset: payloadOffset, payloadLength: Int(length), digest: digest)
                return (snapshot, frameStart, true)
            }
            let payloadEnd = offset + Int(length)
            let payload = data[offset..<payloadEnd]
            guard Data(SHA256.hash(data: payload)) == Data(digest) else { throw DurableError.corruptStorage("payload checksum mismatch") }
            offset = payloadEnd
            guard data[offset..<offset+4] == terminator else { throw DurableError.corruptStorage("bad frame terminator") }
            offset += 4
            let termSeq = try readInt64(data, &offset)
            guard termSeq == seq else { throw DurableError.corruptStorage("terminator sequence mismatch") }
            let headerHash = data[offset..<offset+32]; offset += 32
            guard Data(SHA256.hash(data: data[frameStart..<frameStart+headerLength])) == Data(headerHash) else { throw DurableError.corruptStorage("header checksum mismatch") }
            guard seq == snapshot.seq + 1 else { throw DurableError.corruptStorage("sequence gap or duplicate") }
            let decoded = try JSONDecoder().decode(DurableJournalPayload.self, from: Data(payload))
            guard decoded.seq == seq, decoded.highWaterID == highWater else { throw DurableError.corruptStorage("payload header mismatch") }
            let actualHighWater = try DurableValidation.validate(batch: decoded.batch, against: snapshot)
            guard highWater == actualHighWater, highWater >= snapshot.highWaterID, highWater <= DurableLimits.maxExactInteger else { throw DurableError.corruptStorage("allocator high-water invalid") }
            snapshot = DurableValidation.applying(decoded.batch, to: snapshot, seq: seq, highWater: highWater)
        }
        return (snapshot, offset, false)
    }

    static func be(_ value: Int64) -> Data { var big = UInt64(bitPattern: value).bigEndian; return Data(bytes: &big, count: 8) }

    private static func validatePartialHeaderTail(_ data: Data, frameStart: Int, expectedSeq: Int64, minimumHighWater: Int64) throws {
        let available = data.count - frameStart
        guard available > 0 else { return }
        try requirePrefix(data, at: frameStart, expected: magic, available: min(available, magic.count), label: "partial magic")
        guard available > 4 else { return }
        guard data[frameStart + 4] == 1 else { throw DurableError.corruptStorage("unsupported partial frame version \(data[frameStart + 4])") }
        let seqStart = frameStart + 5
        if available > 5 {
            let count = min(available - 5, 8)
            try requirePrefix(data, at: seqStart, expected: be(expectedSeq), available: count, label: "partial sequence")
        }
        let highStart = frameStart + 13
        if available > 13 {
            let count = min(available - 13, 8)
            try validateBoundedInt64Prefix(data, at: highStart, count: count, min: minimumHighWater, max: DurableLimits.maxExactInteger, label: "partial high-water")
        }
        let lengthStart = frameStart + 21
        if available > 21 {
            let count = min(available - 21, 8)
            try validateBoundedInt64Prefix(data, at: lengthStart, count: count, min: 0, max: Int64(DurableLimits.maxBatchBytes), label: "partial payload length")
        }
    }

    private static func validateIncompleteFrameTail(_ data: Data, frameStart: Int, seq: Int64, payloadOffset: Int, payloadLength: Int, digest: Data.SubSequence) throws {
        let availablePayload = min(max(0, data.count - payloadOffset), payloadLength)
        guard availablePayload == payloadLength else { return }
        let payloadEnd = payloadOffset + payloadLength
        let payload = data[payloadOffset..<payloadEnd]
        guard Data(SHA256.hash(data: payload)) == Data(digest) else { throw DurableError.corruptStorage("payload checksum mismatch") }
        let availableTrailer = data.count - payloadEnd
        guard availableTrailer > 0 else { return }
        var expectedTrailer = Data()
        expectedTrailer.append(terminator)
        expectedTrailer.append(contentsOf: be(seq))
        expectedTrailer.append(contentsOf: Data(SHA256.hash(data: data[frameStart..<frameStart+headerLength])))
        try requirePrefix(data, at: payloadEnd, expected: expectedTrailer, available: min(availableTrailer, expectedTrailer.count), label: "partial trailer")
        guard availableTrailer < expectedTrailer.count else { throw DurableError.corruptStorage("incomplete frame length mismatch") }
    }

    private static func requirePrefix(_ data: Data, at offset: Int, expected: Data, available: Int, label: String) throws {
        guard available >= 0, offset + available <= data.count else { throw DurableError.corruptStorage("\(label) outside journal bounds") }
        guard Data(data[offset..<offset+available]) == Data(expected.prefix(available)) else { throw DurableError.corruptStorage("invalid \(label)") }
    }

    private static func validateBoundedInt64Prefix(_ data: Data, at offset: Int, count: Int, min: Int64, max: Int64, label: String) throws {
        guard count > 0 else { return }
        guard min >= 0, max >= min else { throw DurableError.corruptStorage("invalid \(label)") }
        guard count <= 8, offset + count <= data.count else { throw DurableError.corruptStorage("\(label) outside journal bounds") }
        var prefix = UInt64(0)
        for byte in data[offset..<offset+count] { prefix = (prefix << 8) | UInt64(byte) }
        let suffixBits = UInt64((8 - count) * 8)
        let minValue = suffixBits == 64 ? 0 : prefix << suffixBits
        let maxSuffix = suffixBits == 64 ? UInt64.max : (UInt64(1) << suffixBits) - 1
        let maxValue = minValue | maxSuffix
        guard minValue <= UInt64(Int64.max), maxValue >= UInt64(min), minValue <= UInt64(max) else { throw DurableError.corruptStorage("invalid \(label)") }
    }

    static func readInt64(_ data: Data, _ offset: inout Int) throws -> Int64 {
        guard offset + 8 <= data.count else { throw DurableError.corruptStorage("short int64") }
        let value = data[offset..<offset+8].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        offset += 8
        return Int64(bitPattern: value)
    }

    static func currentOffset(_ handle: FileHandle) throws -> Int64 {
        #if os(Linux) || os(macOS)
        let offset = lseek(handle.fileDescriptor, 0, SEEK_CUR)
        guard offset >= 0 else { throw DurableError.durabilityUncertain("journal offset seek failed") }
        return Int64(offset)
        #else
        return 0
        #endif
    }

    static func preallocate(_ handle: FileHandle, additionalBytes: Int) throws {
        guard additionalBytes >= 0 else { throw DurableError.durabilityUncertain("invalid preallocation size") }
        #if os(Linux)
        let current = lseek(handle.fileDescriptor, 0, SEEK_CUR)
        guard current >= 0 else { throw DurableError.durabilityUncertain("preallocation seek failed") }
        let result = linuxFallocate(handle.fileDescriptor, Int32(1), Int64(current), Int64(additionalBytes))
        guard result == 0 else { throw DurableError.durabilityUncertain("preallocation failed: \(errno)") }
        #endif
    }

    static func sync(_ handle: FileHandle) throws {
        if #available(macOS 10.15.4, iOS 13.4, tvOS 13.4, watchOS 6.2, *) { try handle.synchronize() }
        #if os(macOS)
        if fcntl(handle.fileDescriptor, F_FULLFSYNC) != 0 { throw DurableError.poisoned("F_FULLFSYNC failed") }
        #elseif os(Linux)
        if fsync(handle.fileDescriptor) != 0 { throw DurableError.poisoned("fsync failed") }
        #endif
    }

    static func syncDirectory(_ url: URL) throws {
        #if os(Linux) || os(macOS)
        let fd = open(url.path, O_RDONLY)
        guard fd >= 0 else { throw DurableError.poisoned("cannot open directory for sync: \(url.path)") }
        defer { posixClose(fd) }
        if fsync(fd) != 0 { throw DurableError.poisoned("directory fsync failed: \(url.path)") }
        #endif
    }

    private static func posixClose(_ fd: Int32) {
        #if os(Linux)
        Glibc.close(fd)
        #elseif os(macOS)
        Darwin.close(fd)
        #endif
    }
}

public protocol DurableJournalFaultInjector: Sendable {
    func beforeAppend(seq: Int64, frame: Data) throws
    func frameToAppend(seq: Int64, frame: Data) throws -> Data
    func afterAppendBeforeSync(seq: Int64) throws
    func afterFileSyncBeforeDirectorySync(seq: Int64) throws
    func afterDirectorySyncBeforeAck(seq: Int64) throws
}

extension DurableJournalFaultInjector {
    public func beforeAppend(seq: Int64, frame: Data) throws {}
    public func frameToAppend(seq: Int64, frame: Data) throws -> Data { frame }
    public func afterAppendBeforeSync(seq: Int64) throws {}
    public func afterFileSyncBeforeDirectorySync(seq: Int64) throws {}
    public func afterDirectorySyncBeforeAck(seq: Int64) throws {}
}
