import Foundation

public enum DurableTaskStep: Sendable {
    case checkpoint(JSONValue)
    case waiting(checkpoint: JSONValue, children: [Int64])
    case completed(JSONValue)
    case failed(code: String, result: JSONValue?)
}

public struct DurableTaskInvocation: Sendable {
    public let task: DurableTaskRecord
    public let input: JSONValue
    public let checkpoint: JSONValue?
    public let cancellation: DurableCancellationSignal
    let session: DurableSession

    /// Persist progress before effects that depend on it. The task invocation owns settlement.
    public func checkpoint(_ value: JSONValue) async throws { try await session.checkpointNativeTask(id: task.id, value: value) }
    public func snapshot() async throws -> DurableSnapshot { try await session.snapshot() }
    public func child(kind: String, input: JSONValue, background: Bool = false) async throws -> DurableTaskRecord {
        guard !background else { throw DurableError.invalidRecord("background children must be conversation-owned") }
        return try await session.admitNativeTask(conversationID: task.conversationID, kind: kind, input: input, ownerTaskID: task.id, background: false)
    }
}

public struct DurableTaskDefinition: Sendable {
    public var name: String
    public var version: Int
    public var run: @Sendable (DurableTaskInvocation) async throws -> DurableTaskStep
    public var abort: (@Sendable (DurableTaskInvocation) async throws -> JSONValue?)?
    public init(name: String, version: Int = 1, run: @escaping @Sendable (DurableTaskInvocation) async throws -> DurableTaskStep, abort: (@Sendable (DurableTaskInvocation) async throws -> JSONValue?)? = nil) { self.name = name; self.version = version; self.run = run; self.abort = abort }
}

public actor DurableTaskRegistry {
    private var definitions: [String: DurableTaskDefinition] = [:]
    public init() {}
    public func register(_ definition: DurableTaskDefinition) throws {
        guard !definition.name.isEmpty, definition.name.utf8.count <= 128, definition.version > 0, !["generation", "tool", "compaction"].contains(definition.name) else { throw DurableError.invalidRecord("invalid native task definition") }
        definitions[definition.name] = definition
    }
    public func remove(_ name: String) { definitions.removeValue(forKey: name) }
    public func definition(_ name: String) -> DurableTaskDefinition? { definitions[name] }
}

struct DurableNativeTaskIntent: Codable, Sendable {
    var version: Int
    var input: JSONValue
    var checkpoint: JSONValue?
    var children: [Int64]?
    var stagedResult: JSONValue?
    var stagedFailure: String?
}

public struct DurableTaskGraph: Sendable {
    public var tasks: [DurableTaskRecord]
    public var roots: [Int64]
    public var children: [Int64: [Int64]]
    public init(snapshot: DurableSnapshot, conversationID: Int64? = nil) {
        tasks = snapshot.tasks.values.filter { conversationID == nil || $0.conversationID == conversationID }.sorted { $0.id < $1.id }
        let ids = Set(tasks.map(\.id)); roots = tasks.filter { $0.ownerTaskID == nil || !ids.contains($0.ownerTaskID!) }.map(\.id)
        children = Dictionary(grouping: tasks.filter { $0.ownerTaskID != nil }, by: { $0.ownerTaskID! }).mapValues { $0.map(\.id) }
    }
}

public extension DurableSession {
    func createTask(conversationID: Int64, kind: String, input: JSONValue, ownerTaskID: Int64? = nil, background: Bool = false) async throws -> DurableTaskRecord {
        try ensureAdmitting()
        activeAdmissions += 1; defer { activeAdmissions -= 1; finishCloseIfNeeded() }
        return try await admitNativeTask(conversationID: conversationID, kind: kind, input: input, ownerTaskID: ownerTaskID, background: background)
    }

    func taskGraph(conversationID: Int64? = nil) async throws -> DurableTaskGraph { DurableTaskGraph(snapshot: try await snapshot(), conversationID: conversationID) }

    /// Opening has no effects. Explicit resume runs registered tasks under one bounded owned executor.
    func resumeTasks(conversationID: Int64? = nil) async throws -> [DurableTaskRecord] {
        try ensureAdmitting()
        guard !nativeSchedulerRunning else { throw DurableError.invalidRecord("native scheduler already running") }
        nativeSchedulerRunning = true; activeAdmissions += 1
        defer { nativeSchedulerRunning = false; activeAdmissions -= 1; finishCloseIfNeeded() }
        let snapshot = try await snapshot()
        let tasks = snapshot.tasks.values.filter { (conversationID == nil || $0.conversationID == conversationID) && !["generation", "tool", "compaction"].contains($0.kind) && ![.completed, .failed, .aborted].contains($0.status) }.sorted { $0.id < $1.id }
        guard tasks.count <= DurableLimits.maxPublicQueue else { throw DurableError.queueFull }
        var results: [DurableTaskRecord] = []
        for task in tasks { results.append(try await executeNativeTask(id: task.id, ancestry: [])) }
        return results
    }

    func abortTaskTree(id: Int64) async throws {
        try ensureAdmitting()
        let ids: [Int64] = try await gate.submit {
            let snapshot = try await self.storage.snapshot()
            guard snapshot.tasks[id] != nil else { throw DurableError.invalidRecord("missing abort task") }
            var descendants = Set([id]), changed = true
            while changed {
                changed = false
                for task in snapshot.tasks.values where task.ownerTaskID.map(descendants.contains) == true {
                    if descendants.insert(task.id).inserted { changed = true }
                }
            }
            let updates = snapshot.tasks.values.filter { descendants.contains($0.id) && ![.completed, .failed, .aborted].contains($0.status) }.map { task -> DurableTaskRecord in
                var value = task; value.abortRequested = true; return value
            }
            if !updates.isEmpty { _ = try await self.storage.commit(DurableCommitBatch(tasks: updates)) }
            return Array(descendants)
        }
        for id in ids { nativeTaskSignals[id]?.cancel() }
    }

    func checkpointNativeTask(id: Int64, value: JSONValue) async throws {
        try DurableNativePreflight.validate(value, maxBytes: DurableLimits.maxCheckpointBytes)
        try await gate.submit {
            let snapshot = try await self.storage.snapshot()
            guard var task = snapshot.tasks[id], task.status == .running, let doc = DurableGenerationPlanner.document(scope: "task", ownerID: id, kind: "native.intent", in: snapshot) else { throw DurableError.invalidRecord("task is not running") }
            var intent = try JSONDecoder().decode(DurableNativeTaskIntent.self, from: JSONEncoder().encode(doc.value)); intent.checkpoint = value; task.checkpoint = value
            var updated = doc; updated.value = try DurableGenerationPlanner.encodeJSON(intent, maxBytes: DurableLimits.maxCheckpointBytes)
            _ = try await self.storage.commit(DurableCommitBatch(tasks: [task], documents: [updated]))
        }
    }

    func admitNativeTask(conversationID: Int64, kind: String, input: JSONValue, ownerTaskID: Int64?, background: Bool) async throws -> DurableTaskRecord {
        guard let definition = await taskRegistry.definition(kind), ownerTaskID == nil || !background else { throw DurableError.invalidRecord("invalid task ownership or missing definition") }
        try DurableNativePreflight.validate(input, maxBytes: DurableLimits.maxCheckpointBytes)
        return try await gate.submit {
            let snapshot = try await self.storage.snapshot()
            guard snapshot.tasks.values.filter({ ![.completed, .failed, .aborted].contains($0.status) }).count < DurableLimits.maxPublicQueue else { throw DurableError.queueFull }
            if let ownerTaskID { guard let owner = snapshot.tasks[ownerTaskID], owner.conversationID == conversationID, ![.completed, .failed, .aborted].contains(owner.status) else { throw DurableError.invalidRecord("invalid task owner") } }
            let ids = try DurableSubmissionPlanner.nextID(from: snapshot, reserving: 2)
            let task = DurableTaskRecord(id: ids[0], conversationID: conversationID, ownerTaskID: ownerTaskID, kind: kind, background: background)
            let intent = DurableNativeTaskIntent(version: definition.version, input: input)
            let document = DurableDocumentRecord(id: ids[1], scope: "task", ownerID: task.id, kind: "native.intent", value: try DurableGenerationPlanner.encodeJSON(intent, maxBytes: DurableLimits.maxCheckpointBytes))
            _ = try await self.storage.commit(DurableCommitBatch(tasks: [task], documents: [document]))
            return task
        }
    }

    private func executeNativeTask(id: Int64, ancestry: Set<Int64>) async throws -> DurableTaskRecord {
        guard !ancestry.contains(id), ancestry.count < 128 else { throw DurableError.invalidRecord("task wait cycle/depth") }
        var ancestry = ancestry; ancestry.insert(id)
        let signal = DurableCancellationSignal(); nativeTaskSignals[id] = signal
        defer { nativeTaskSignals.removeValue(forKey: id) }
        for _ in 0..<DurableLimits.maxPublicQueue {
            let snapshot = try await snapshot()
            guard var task = snapshot.tasks[id], let document = DurableGenerationPlanner.document(scope: "task", ownerID: id, kind: "native.intent", in: snapshot) else { throw DurableError.corruptStorage("missing native task intent") }
            if [.completed, .failed, .aborted].contains(task.status) { return task }
            var intent = try JSONDecoder().decode(DurableNativeTaskIntent.self, from: JSONEncoder().encode(document.value))
            guard let definition = await taskRegistry.definition(task.kind), definition.version == intent.version else { return task } // blocked until the matching definition returns
            if task.status == .completing {
                for child in snapshot.tasks.values.filter({ $0.ownerTaskID == id && ![.completed, .failed, .aborted].contains($0.status) }).sorted(by: { $0.id < $1.id }) {
                    let settled = try await executeNativeTask(id: child.id, ancestry: ancestry)
                    if ![.completed, .failed, .aborted].contains(settled.status) { return task }
                }
                return try await settleNativeTask(id: id, intent: intent)
            }
            if task.status == .waiting {
                let children = intent.children ?? []
                for childID in children {
                    guard let child = snapshot.tasks[childID], child.ownerTaskID == id else { throw DurableError.invalidRecord("wait target is not an owned child") }
                    let settled = try await executeNativeTask(id: childID, ancestry: ancestry)
                    if ![.completed, .failed, .aborted].contains(settled.status) { return task }
                }
                task.status = .running; intent.children = nil
                try await storeNativeTask(task, intent: intent, document: document)
            } else if task.status == .pending {
                task.status = .running; try await storeNativeTask(task, intent: intent, document: document)
            }
            let invocation = DurableTaskInvocation(task: task, input: intent.input, checkpoint: intent.checkpoint, cancellation: signal, session: self)
            if task.abortRequested {
                signal.cancel()
                let result = try await definition.abort?(invocation)
                intent.stagedResult = result; intent.stagedFailure = "aborted"; task.status = .completing
                try await storeNativeTask(task, intent: intent, document: document); continue
            }
            let step: DurableTaskStep
            do { step = try await definition.run(invocation) }
            catch { step = .failed(code: "task_error", result: nil) }
            switch step {
            case .checkpoint(let checkpoint): intent.checkpoint = checkpoint; task.checkpoint = checkpoint
            case .waiting(let checkpoint, let children):
                let current = try await self.snapshot()
                guard !children.isEmpty, Set(children).count == children.count, children.allSatisfy({ current.tasks[$0]?.ownerTaskID == id && !ancestry.contains($0) }) else { throw DurableError.invalidRecord("invalid task wait target") }
                intent.checkpoint = checkpoint; intent.children = children; task.checkpoint = checkpoint; task.status = .waiting
            case .completed(let result): intent.stagedResult = result; intent.stagedFailure = nil; task.status = .completing
            case .failed(let code, let result): intent.stagedFailure = String(code.prefix(128)); intent.stagedResult = result; task.status = .completing
            }
            switch step {
            case .completed, .failed:
                let latest = try await self.snapshot()
                if let doc = DurableGenerationPlanner.document(scope: "task", ownerID: id, kind: "native.intent", in: latest) {
                    let committed = try JSONDecoder().decode(DurableNativeTaskIntent.self, from: JSONEncoder().encode(doc.value))
                    intent.checkpoint = committed.checkpoint
                }
            case .checkpoint, .waiting: break
            }
            try await storeNativeTask(task, intent: intent, document: document)
        }
        throw DurableError.invalidRecord("native task step limit")
    }

    private func storeNativeTask(_ task: DurableTaskRecord, intent: DurableNativeTaskIntent, document: DurableDocumentRecord) async throws {
        try await gate.submit {
            let snapshot = try await self.storage.snapshot(); guard let current = snapshot.tasks[task.id] else { throw DurableError.corruptStorage("missing native task") }
            var updated = task; updated.abortRequested = current.abortRequested
            var doc = document; doc.value = try DurableGenerationPlanner.encodeJSON(intent, maxBytes: DurableLimits.maxCheckpointBytes)
            _ = try await self.storage.commit(DurableCommitBatch(tasks: [updated], documents: [doc]))
        }
    }

    private func settleNativeTask(id: Int64, intent: DurableNativeTaskIntent) async throws -> DurableTaskRecord {
        try await gate.submit {
            let snapshot = try await self.storage.snapshot(); guard var task = snapshot.tasks[id] else { throw DurableError.corruptStorage("missing native task settlement") }
            guard task.status == .completing else { return task }
            task.status = task.abortRequested || intent.stagedFailure == "aborted" ? .aborted : (intent.stagedFailure == nil ? .completed : .failed)
            var outcome: [String: JSONValue] = [:]
            if let result = intent.stagedResult { outcome["result"] = result }
            if let failure = intent.stagedFailure { outcome["code"] = .string(failure) }
            task.outcome = .object(outcome)
            _ = try await self.storage.commit(DurableCommitBatch(tasks: [task]))
            return task
        }
    }
}
