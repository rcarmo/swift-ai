import Foundation

public extension DurableSession {
    func context(conversationID: Int64, at: Int64? = nil) async throws -> DurableContextView {
        try DurableContext.derive(snapshot: await snapshot(), conversationID: conversationID, at: at)
    }

    func view(conversationID: Int64) async throws -> DurableConversationView {
        try DurableObservationHub.view(snapshot: await snapshot(), conversationID: conversationID)
    }

    func observeCommits() async throws -> AsyncStream<DurableObservationFrame<DurableSnapshot>> {
        try ensureAdmitting()
        return try await gate.submit { await self.observation.observe(snapshot: try await self.storage.snapshot()) }
    }

    func watchDocument(scope: String, ownerID: Int64, kind: String) async throws -> AsyncStream<DurableObservationFrame<JSONValue?>>? {
        try ensureAdmitting()
        return try await gate.submit {
            let snapshot = try await self.storage.snapshot()
            guard let record = snapshot.documents.values.first(where: { $0.scope == scope && $0.ownerID == ownerID && $0.kind == kind && $0.retired != true }) else { return nil }
            return await self.observation.observeDocument(record: record, snapshot: snapshot)
        }
    }

    func watchView(conversationID: Int64) async throws -> AsyncStream<DurableObservationFrame<DurableConversationView>> {
        try ensureAdmitting()
        return try await gate.submit { try await self.observation.observeView(conversationID: conversationID, snapshot: self.storage.snapshot()) }
    }

    func writeDocument(scope: String, ownerID: Int64, kind: String, value: JSONValue, version: Int = 1, history: DurableDocumentHistory = .latest, fork: DurableDocumentForkPolicy = .initial) async throws -> DurableDocumentRecord {
        try ensureAdmitting()
        return try await gate.submit {
            let snapshot = try await self.storage.snapshot()
            let existing = snapshot.documents.values.first { $0.scope == scope && $0.ownerID == ownerID && $0.kind == kind && $0.retired != true }
            let id = try existing?.id ?? DurableSubmissionPlanner.nextID(from: snapshot)[0]
            let record = DurableDocumentRecord(id: id, scope: scope, ownerID: ownerID, kind: kind, value: value, createdSeq: existing?.createdSeq ?? 0, version: version, history: history, forkPolicy: fork)
            _ = try await self.storage.commit(DurableCommitBatch(documents: [record]))
            return record
        }
    }

    func document(scope: String, ownerID: Int64, kind: String, at sequence: Int64? = nil) async throws -> JSONValue? {
        let snapshot = try await snapshot()
        guard let record = snapshot.documents.values.first(where: { $0.scope == scope && $0.ownerID == ownerID && $0.kind == kind && $0.retired != true }) else { return nil }
        guard let sequence else { return record.value }
        guard record.history == .rewindable else { throw DurableError.invalidRecord("document is not rewindable") }
        guard let revision = snapshot.documentHistory?[record.id]?.last(where: { $0.seq <= sequence }) else { return nil }
        return revision.retired ? nil : revision.value
    }

    func retireDocument(scope: String, ownerID: Int64, kind: String) async throws {
        try ensureAdmitting()
        try await gate.submit {
            let snapshot = try await self.storage.snapshot()
            guard var record = snapshot.documents.values.first(where: { $0.scope == scope && $0.ownerID == ownerID && $0.kind == kind && $0.retired != true }) else { return }
            record.retired = true
            _ = try await self.storage.commit(DurableCommitBatch(documents: [record]))
        }
    }

    func forkConversation(parentID: Int64, at entryID: Int64) async throws -> DurableConversationRecord {
        try ensureAdmitting()
        return try await gate.submit {
            let snapshot = try await self.storage.snapshot()
            let visible = try DurableContext.visibleEntries(snapshot: snapshot, conversationID: parentID)
            guard let entry = visible.first(where: { $0.id == entryID }) else { throw DurableError.invalidRecord("fork entry is not visible") }
            let candidates = snapshot.documents.values.filter { $0.scope == "conversation" && $0.retired != true && (($0.ownerID == parentID && $0.forkPolicy == .current) || ($0.ownerID == entry.conversationID && $0.forkPolicy == .asOf)) }.sorted { $0.id < $1.id }
            var selected: [(DurableDocumentRecord, JSONValue, Int)] = []
            var kinds = Set<String>()
            for record in candidates {
                let value: JSONValue, version: Int
                if record.forkPolicy == .asOf {
                    guard let revision = snapshot.documentHistory?[record.id]?.last(where: { $0.seq <= entry.createdSeq }), !revision.retired else { continue }
                    value = revision.value; version = revision.version
                } else { value = record.value; version = record.version ?? 1 }
                guard kinds.insert(record.kind).inserted else { throw DurableError.invalidRecord("fork selects duplicate document address") }
                selected.append((record, value, version))
            }
            var ids = try DurableSubmissionPlanner.nextID(from: snapshot, reserving: 1 + selected.count)
            let id = ids.removeFirst()
            let child = DurableConversationRecord(id: id, parentConversationID: parentID, parentEntryID: entryID)
            let documents = selected.map { record, value, version in
                DurableDocumentRecord(id: ids.removeFirst(), scope: "conversation", ownerID: id, kind: record.kind, value: value, version: version, history: record.history, forkPolicy: record.forkPolicy)
            }
            _ = try await self.storage.commit(DurableCommitBatch(conversations: [child], documents: documents))
            return child
        }
    }

    func resetConversation(conversationID: Int64, messages: [Message] = []) async throws -> DurableEntryRecord {
        try ensureAdmitting()
        return try await gate.submit {
            let snapshot = try await self.storage.snapshot()
            let id = try DurableSubmissionPlanner.nextID(from: snapshot)[0]
            let record = DurableEntryRecord(id: id, conversationID: conversationID, kind: "pi.reset", messages: messages, head: id)
            _ = try await self.storage.commit(DurableCommitBatch(entries: [record]))
            return record
        }
    }

    func editContext(conversationID: Int64, edits: [DurableContextEdit]) async throws -> DurableEntryRecord {
        try ensureAdmitting()
        return try await gate.submit {
            let snapshot = try await self.storage.snapshot()
            let id = try DurableSubmissionPlanner.nextID(from: snapshot)[0]
            let record = DurableEntryRecord(id: id, conversationID: conversationID, kind: "pi.context.edit", edits: edits)
            _ = try await self.storage.commit(DurableCommitBatch(entries: [record]))
            return record
        }
    }
}
