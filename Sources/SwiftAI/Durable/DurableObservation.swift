import Foundation

public struct DurableObservationFrame<Value: Sendable>: Sendable {
    public var sequence: Int64
    public var value: Value
    /// Every native frame is self-contained, including after bounded-buffer overflow.
    public var replacesRoot: Bool
    public init(sequence: Int64, value: Value, replacesRoot: Bool = true) { self.sequence = sequence; self.value = value; self.replacesRoot = replacesRoot }
}

public struct DurableConversationView: Sendable, Equatable {
    public var conversation: DurableConversationRecord
    public var entries: [DurableEntryRecord]
    public var documents: [String: JSONValue]
}

actor DurableObservationHub {
    private var snapshots: [UUID: AsyncStream<DurableObservationFrame<DurableSnapshot>>.Continuation] = [:]
    private var documents: [UUID: (Int64, AsyncStream<DurableObservationFrame<JSONValue?>>.Continuation)] = [:]
    private var views: [UUID: (Int64, AsyncStream<DurableObservationFrame<DurableConversationView>>.Continuation)] = [:]
    private var sealed = false

    func observe(snapshot: DurableSnapshot) -> AsyncStream<DurableObservationFrame<DurableSnapshot>> {
        let id = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(100)) { continuation in
            if sealed { continuation.finish(); return }
            snapshots[id] = continuation
            continuation.yield(DurableObservationFrame(sequence: snapshot.seq, value: snapshot))
            continuation.onTermination = { _ in Task { await self.remove(id) } }
        }
    }

    func observeDocument(record: DurableDocumentRecord, snapshot: DurableSnapshot) -> AsyncStream<DurableObservationFrame<JSONValue?>>? {
        guard !sealed, record.retired != true else { return nil }
        let id = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(100)) { continuation in
            documents[id] = (record.id, continuation)
            continuation.yield(DurableObservationFrame(sequence: snapshot.seq, value: record.value))
            continuation.onTermination = { _ in Task { await self.remove(id) } }
        }
    }

    static func view(snapshot: DurableSnapshot, conversationID: Int64) throws -> DurableConversationView {
        guard let conversation = snapshot.conversations[conversationID] else { throw DurableError.invalidRecord("missing conversation") }
        let entries = try DurableContext.derive(snapshot: snapshot, conversationID: conversationID).entries
        let kinds = Set(["pi.agent", "pi.live", "pi.inbox", "pi.provider", "pi.usage", "durable.usage"])
        let docs = Dictionary(uniqueKeysWithValues: snapshot.documents.values.filter { $0.scope == "conversation" && $0.ownerID == conversationID && $0.retired != true && kinds.contains($0.kind) }.map { ($0.kind, $0.value) })
        return DurableConversationView(conversation: conversation, entries: entries, documents: docs)
    }

    func observeView(conversationID: Int64, snapshot: DurableSnapshot) throws -> AsyncStream<DurableObservationFrame<DurableConversationView>> {
        let value = try Self.view(snapshot: snapshot, conversationID: conversationID)
        let id = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(100)) { continuation in
            if sealed { continuation.finish(); return }
            views[id] = (conversationID, continuation)
            continuation.yield(DurableObservationFrame(sequence: snapshot.seq, value: value))
            continuation.onTermination = { _ in Task { await self.remove(id) } }
        }
    }

    func publish(_ snapshot: DurableSnapshot, batch: DurableCommitBatch) {
        guard !sealed else { return }
        for continuation in snapshots.values { continuation.yield(DurableObservationFrame(sequence: snapshot.seq, value: snapshot)) }
        let changed = Set(batch.documents.map(\.id))
        for (id, (recordID, continuation)) in documents where changed.contains(recordID) {
            let record = snapshot.documents[recordID]
            continuation.yield(DurableObservationFrame(sequence: snapshot.seq, value: record?.retired == true ? nil : record?.value))
            if record?.retired == true || record == nil { continuation.finish(); documents.removeValue(forKey: id) }
        }
        for (conversationID, continuation) in views.values {
            if let value = try? Self.view(snapshot: snapshot, conversationID: conversationID) { continuation.yield(DurableObservationFrame(sequence: snapshot.seq, value: value)) }
        }
    }

    func close() {
        sealed = true
        for continuation in snapshots.values { continuation.finish() }
        for (_, continuation) in documents.values { continuation.finish() }
        for (_, continuation) in views.values { continuation.finish() }
        snapshots.removeAll(); documents.removeAll(); views.removeAll()
    }

    private func remove(_ id: UUID) { snapshots.removeValue(forKey: id); documents.removeValue(forKey: id); views.removeValue(forKey: id) }
}

/// Only acknowledged, adopted commits reach observers. Uncertain storage failures publish nothing.
struct DurableObservedStorage: DurableStorage {
    let underlying: any DurableStorage
    let hub: DurableObservationHub
    func snapshot() async throws -> DurableSnapshot { try await underlying.snapshot() }
    func commit(_ batch: DurableCommitBatch) async throws -> DurableSnapshot {
        let value = try await underlying.commit(batch)
        await hub.publish(value, batch: batch)
        return value
    }
    func close() async throws { await hub.close(); try await underlying.close() }
}
