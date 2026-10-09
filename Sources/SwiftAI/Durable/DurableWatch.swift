import Foundation

public enum DurableWatchEnd: Sendable, Equatable {
    case stopped, cancelled, sessionClosed, retired
    case listenerError(String)
}

/// Serial off-line callbacks over immutable native root revisions. Active callbacks stay caller-owned at stop.
public actor DurableWatch<Value: Sendable> {
    public typealias Listener = @Sendable (DurableObservationFrame<Value>) async throws -> Void
    public private(set) var value: Value
    private var pending: [DurableObservationFrame<Value>] = []
    private var listener: Listener?
    private var started = false
    private var delivering = false
    private var end: DurableWatchEnd?
    private var terminalQueued = false
    private var pump: Task<Void, Never>?
    private var waiters: [CheckedContinuation<DurableWatchEnd, Never>] = []
    private let terminal: @Sendable (Value) -> Bool

    init(value: Value, terminal: @escaping @Sendable (Value) -> Bool = { _ in false }) { self.value = value; self.terminal = terminal }

    func attach(iterator: AsyncStream<DurableObservationFrame<Value>>.Iterator) {
        pump = Task {
            var iterator = iterator
            while let frame = await iterator.next() {
                if Task.isCancelled { return }
                self.receive(frame)
            }
            self.sourceEnded()
        }
    }

    public func start(_ listener: @escaping Listener) throws {
        guard !started, end == nil else { throw DurableError.invalidRecord("watch already started or stopped") }
        started = true; self.listener = listener
        scheduleDelivery()
    }

    public func stop() -> DurableWatchEnd { finish(.stopped); return end! }
    public func cancel() -> DurableWatchEnd { finish(.cancelled); return end! }
    public func closed() async -> DurableWatchEnd {
        if let end { return end }
        return await withCheckedContinuation { waiters.append($0) }
    }

    private func receive(_ frame: DurableObservationFrame<Value>) {
        guard end == nil, !terminalQueued else { return }
        if pending.count == 100 { pending = [frame] } else { pending.append(frame) }
        if terminal(frame.value) { terminalQueued = true }
        scheduleDelivery()
    }

    private func scheduleDelivery() {
        guard started, !delivering, end == nil, !pending.isEmpty else { return }
        delivering = true
        Task { await self.deliver() }
    }

    private func deliver() async {
        defer { delivering = false }
        while end == nil, !pending.isEmpty, let listener {
            let frame = pending.removeFirst(); value = frame.value
            do { try await listener(frame) }
            catch { finish(.listenerError(String(describing: error))); return }
            if terminal(frame.value) { finish(.retired); return }
        }
    }

    private func sourceEnded() {
        // Retirement's final null revision must be delivered before closing. Ordinary close seals immediately.
        if !terminalQueued { finish(.sessionClosed) }
    }

    private func finish(_ reason: DurableWatchEnd) {
        guard end == nil else { return }
        end = reason; pending.removeAll(); listener = nil; pump?.cancel(); pump = nil
        for waiter in waiters { waiter.resume(returning: reason) }; waiters.removeAll()
    }
}

public extension DurableSession {
    func acquireDocumentWatch(scope: String, ownerID: Int64, kind: String) async throws -> DurableWatch<JSONValue?>? {
        guard let stream = try await watchDocument(scope: scope, ownerID: ownerID, kind: kind) else { return nil }
        var iterator = stream.makeAsyncIterator()
        guard let baseline = await iterator.next() else { return nil }
        let watch = DurableWatch(value: baseline.value, terminal: { $0 == nil })
        await watch.attach(iterator: iterator)
        return watch
    }

    func acquireConversationWatch(conversationID: Int64) async throws -> DurableWatch<DurableConversationView> {
        let stream = try await watchView(conversationID: conversationID)
        var iterator = stream.makeAsyncIterator()
        guard let baseline = await iterator.next() else { throw DurableError.closed }
        let watch = DurableWatch(value: baseline.value)
        await watch.attach(iterator: iterator)
        return watch
    }
}
