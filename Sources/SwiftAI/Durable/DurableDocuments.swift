import Foundation

public enum DurableDocumentScope: String, Sendable { case session, conversation, task }

public struct DurableDocumentDefinition: Sendable {
    public var kind: String
    public var scope: DurableDocumentScope
    public var version: Int
    public var history: DurableDocumentHistory
    public var forkPolicy: DurableDocumentForkPolicy
    public var initial: @Sendable () throws -> JSONValue
    public var migrate: (@Sendable (JSONValue, Int) throws -> JSONValue)?
    public init(kind: String, scope: DurableDocumentScope, version: Int = 1, history: DurableDocumentHistory = .latest, fork: DurableDocumentForkPolicy = .initial, initial: @escaping @Sendable () throws -> JSONValue, migrate: (@Sendable (JSONValue, Int) throws -> JSONValue)? = nil) {
        self.kind = kind; self.scope = scope; self.version = version; self.history = history; self.forkPolicy = fork; self.initial = initial; self.migrate = migrate
    }

    func validate() throws {
        guard !kind.isEmpty, kind.utf8.count <= 256, version > 0, forkPolicy != .asOf || history == .rewindable else { throw DurableError.invalidRecord("invalid document definition") }
        guard scope == .conversation || (history == .latest && forkPolicy == .initial) else { throw DurableError.invalidRecord("only conversation documents have history/fork policy") }
    }

    func materialize(_ record: DurableDocumentRecord) throws -> JSONValue {
        let storedVersion = record.version ?? 1
        guard storedVersion <= version else { throw DurableError.invalidRecord("document stored version is newer than definition") }
        if storedVersion == version { return record.value }
        guard let migrate else { throw DurableError.invalidRecord("document migration is required") }
        let value = try migrate(record.value, storedVersion)
        try DurableNativePreflight.validate(value, maxBytes: DurableLimits.maxDocumentBytes)
        return value
    }
}

public extension DurableSession {
    /// Read access migrates detached values in memory only and never creates an absent document.
    func readDocument(_ definition: DurableDocumentDefinition, ownerID: Int64, at sequence: Int64? = nil) async throws -> JSONValue? {
        try definition.validate()
        let snapshot = try await snapshot()
        guard var record = snapshot.documents.values.first(where: { $0.scope == definition.scope.rawValue && $0.ownerID == ownerID && $0.kind == definition.kind && $0.retired != true }) else { return nil }
        if let sequence {
            guard record.history == .rewindable else { throw DurableError.invalidRecord("document is not rewindable") }
            guard let revision = snapshot.documentHistory?[record.id]?.last(where: { $0.seq <= sequence }), !revision.retired else { return nil }
            record.value = revision.value; record.version = revision.version
        }
        return try definition.materialize(record)
    }

    /// Mutation/migration is prepared on the owned line; a throwing callback persists nothing.
    @discardableResult
    func updateDocument(_ definition: DurableDocumentDefinition, ownerID: Int64, update: @escaping @Sendable (JSONValue) throws -> JSONValue = { $0 }) async throws -> JSONValue {
        try definition.validate(); try ensureAdmitting()
        return try await gate.submit {
            let snapshot = try await self.storage.snapshot()
            let record = snapshot.documents.values.first { $0.scope == definition.scope.rawValue && $0.ownerID == ownerID && $0.kind == definition.kind && $0.retired != true }
            if let record { guard record.history == definition.history, record.forkPolicy == definition.forkPolicy else { throw DurableError.invalidRecord("document definition policy mismatch") } }
            let value = try update(record.map { try definition.materialize($0) } ?? definition.initial())
            try DurableNativePreflight.validate(value, maxBytes: DurableLimits.maxDocumentBytes)
            let id = try record?.id ?? DurableSubmissionPlanner.nextID(from: snapshot)[0]
            let updated = DurableDocumentRecord(id: id, scope: definition.scope.rawValue, ownerID: ownerID, kind: definition.kind, value: value, createdSeq: record?.createdSeq ?? 0, version: definition.version, history: definition.history, forkPolicy: definition.forkPolicy)
            _ = try await self.storage.commit(DurableCommitBatch(documents: [updated]))
            return value
        }
    }
}
