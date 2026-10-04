import Foundation

public actor DurableMemoryStorage: DurableStorage {
    private var current: DurableSnapshot
    private var isClosed = false
    private var poisonReason: String?

    public init(snapshot: DurableSnapshot = DurableSnapshot()) {
        self.current = snapshot
        do { try DurableValidation.validate(snapshot: snapshot) }
        catch { self.poisonReason = "invalid initial snapshot: \(error)" }
    }

    public func snapshot() async throws -> DurableSnapshot {
        try ensureOpen()
        return current
    }

    public func commit(_ batch: DurableCommitBatch) async throws -> DurableSnapshot {
        try ensureOpen()
        let highWater = try DurableValidation.validate(batch: batch, against: current)
        current = DurableValidation.applying(batch, to: current, seq: current.seq + 1, highWater: highWater)
        return current
    }

    public func close() async throws { isClosed = true }

    public func poison(_ reason: String) { poisonReason = reason }

    private func ensureOpen() throws {
        if let poisonReason { throw DurableError.poisoned(poisonReason) }
        if isClosed { throw DurableError.closed }
    }
}
