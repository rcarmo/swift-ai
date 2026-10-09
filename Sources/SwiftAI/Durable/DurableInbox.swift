import Foundation
import Crypto

public enum DurableInboxMode: String, Codable, Sendable { case steer, followUp, write }
public enum DurableQueueMode: String, Codable, Sendable { case oneAtATime, all }
public enum DurableBoundary: String, Sendable { case postTools, final }

public struct DurableInboxItem: Codable, Equatable, Sendable {
    public var submissionID: Int64
    public var mode: DurableInboxMode
    public var messages: [Message]?
    public var entry: DurableEntryRecord?
    public init(submissionID: Int64, mode: DurableInboxMode, messages: [Message]? = nil, entry: DurableEntryRecord? = nil) { self.submissionID = submissionID; self.mode = mode; self.messages = messages; self.entry = entry }
}

public struct DurableBoundaryResult: Sendable {
    public var users: [Int64]
    public var entries: [DurableEntryRecord]
    public var reset: Bool
}

struct DurableInboxState: Codable, Sendable { var items: [DurableInboxItem] }

public extension DurableSession {
    /// Queuing is durable admission only; boundary placement happens separately from provider effects.
    func queueInput(conversationID: Int64, messages: [Message], mode: DurableInboxMode = .followUp, requestID: String? = nil) async throws -> DurableSubmissionRecord {
        guard mode != .write, !messages.isEmpty, messages.allSatisfy({ $0.role == .user }) else { throw DurableError.invalidRecord("invalid inbox input") }
        return try await queueInbox(conversationID: conversationID, mode: mode, messages: messages, entry: nil, requestID: requestID)
    }

    func queueWrite(conversationID: Int64, kind: String, messages: [Message]? = nil, data: JSONValue? = nil, reset: Bool = false, head: Int64? = nil, requestID: String? = nil) async throws -> DurableSubmissionRecord {
        guard !reset || head == nil else { throw DurableError.invalidRecord("ambiguous reset/head write") }
        let entry = DurableEntryRecord(id: 0, conversationID: conversationID, kind: kind, messages: messages, data: data, head: reset ? 0 : head)
        return try await queueInbox(conversationID: conversationID, mode: .write, messages: nil, entry: entry, requestID: requestID)
    }

    func inbox(conversationID: Int64) async throws -> [DurableInboxItem] {
        try DurableInboxPlanner.state(snapshot: await snapshot(), conversationID: conversationID).items
    }

    func placeInbox(conversationID: Int64, at boundary: DurableBoundary, steering: DurableQueueMode = .oneAtATime, followUp: DurableQueueMode = .oneAtATime) async throws -> DurableBoundaryResult {
        try ensureAdmitting()
        return try await gate.submit {
            let snapshot = try await self.storage.snapshot()
            let plan = try DurableInboxPlanner.boundary(snapshot: snapshot, conversationID: conversationID, at: boundary, steering: steering, followUp: followUp)
            if !plan.batch.entries.isEmpty || !plan.batch.submissions.isEmpty { _ = try await self.storage.commit(plan.batch) }
            return plan.result
        }
    }

    func withdrawSubmission(id: Int64) async throws -> DurableSubmissionRecord {
        try ensureAdmitting()
        return try await gate.submit {
            let snapshot = try await self.storage.snapshot()
            guard var submission = snapshot.submissions[id], submission.status == .queued else { throw DurableError.invalidRecord("only queued submission can be withdrawn") }
            var state = try DurableInboxPlanner.state(snapshot: snapshot, conversationID: submission.conversationID)
            state.items.removeAll { $0.submissionID == id }; submission.status = .withdrawn; submission.reason = "withdrawn"
            let document = try DurableInboxPlanner.document(snapshot: snapshot, conversationID: submission.conversationID, state: state)
            _ = try await self.storage.commit(DurableCommitBatch(submissions: [submission], documents: [document]))
            return submission
        }
    }

    private func queueInbox(conversationID: Int64, mode: DurableInboxMode, messages: [Message]?, entry: DurableEntryRecord?, requestID: String?) async throws -> DurableSubmissionRecord {
        try ensureAdmitting()
        return try await gate.submit {
            let snapshot = try await self.storage.snapshot()
            guard snapshot.conversations[conversationID] != nil else { throw DurableError.invalidRecord("missing conversation") }
            var state = try DurableInboxPlanner.state(snapshot: snapshot, conversationID: conversationID)
            guard state.items.count < DurableLimits.maxPublicQueue else { throw DurableError.queueFull }
            let payload = DurableInboxItem(submissionID: 0, mode: mode, messages: messages, entry: entry)
            try DurableNativePreflight.validate(payload, maxBytes: DurableLimits.maxEntryBytes)
            let bytes = try DurableValidation.encoder.encode(payload)
            let digest = "inbox:" + SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            if let requestID, let existing = snapshot.submissions.values.first(where: { $0.conversationID == conversationID && $0.requestID == requestID }) {
                guard existing.type == (mode == .write ? .write : .input), existing.payloadHash == digest else { throw DurableError.requestIDConflict(requestID) }
                return existing
            }
            let existingDocument = DurableGenerationPlanner.document(scope: "conversation", ownerID: conversationID, kind: "pi.inbox", in: snapshot)
            let ids = try DurableSubmissionPlanner.nextID(from: snapshot, reserving: existingDocument == nil ? 2 : 1)
            let submission = DurableSubmissionRecord(id: ids[0], conversationID: conversationID, requestID: requestID, type: mode == .write ? .write : .input, payloadHash: digest)
            state.items.append(DurableInboxItem(submissionID: submission.id, mode: mode, messages: messages, entry: entry))
            let document = DurableDocumentRecord(id: existingDocument?.id ?? ids[1], scope: "conversation", ownerID: conversationID, kind: "pi.inbox", value: try DurableGenerationPlanner.encodeJSON(state, maxBytes: DurableLimits.maxDocumentBytes), createdSeq: existingDocument?.createdSeq ?? 0)
            _ = try await self.storage.commit(DurableCommitBatch(submissions: [submission], documents: [document]))
            return submission
        }
    }
}

enum DurableInboxPlanner {
    static func state(snapshot: DurableSnapshot, conversationID: Int64) throws -> DurableInboxState {
        guard let record = DurableGenerationPlanner.document(scope: "conversation", ownerID: conversationID, kind: "pi.inbox", in: snapshot) else { return DurableInboxState(items: []) }
        return try JSONDecoder().decode(DurableInboxState.self, from: JSONEncoder().encode(record.value))
    }

    static func document(snapshot: DurableSnapshot, conversationID: Int64, state: DurableInboxState) throws -> DurableDocumentRecord {
        guard let existing = DurableGenerationPlanner.document(scope: "conversation", ownerID: conversationID, kind: "pi.inbox", in: snapshot) else { throw DurableError.corruptStorage("missing inbox document") }
        return DurableDocumentRecord(id: existing.id, scope: existing.scope, ownerID: existing.ownerID, kind: existing.kind, value: try DurableGenerationPlanner.encodeJSON(state, maxBytes: DurableLimits.maxDocumentBytes), createdSeq: existing.createdSeq)
    }

    static func boundary(snapshot: DurableSnapshot, conversationID: Int64, at boundary: DurableBoundary, steering: DurableQueueMode, followUp: DurableQueueMode) throws -> (batch: DurableCommitBatch, result: DurableBoundaryResult) {
        var state = try state(snapshot: snapshot, conversationID: conversationID)
        let writes = state.items.filter { $0.mode == .write }.sorted { $0.submissionID < $1.submissionID }
        let reset = writes.contains { $0.entry?.head == 0 }
        func selected(_ mode: DurableInboxMode, _ policy: DurableQueueMode) -> [DurableInboxItem] {
            let values = state.items.filter { $0.mode == mode }.sorted { $0.submissionID < $1.submissionID }
            return policy == .all ? values : Array(values.prefix(1))
        }
        let users = (selected(.steer, steering) + ((boundary == .final || reset) ? selected(.followUp, followUp) : [])).sorted { $0.submissionID < $1.submissionID }
        guard !writes.isEmpty || !users.isEmpty else { return (DurableCommitBatch(), DurableBoundaryResult(users: [], entries: [], reset: false)) }
        var ids = try DurableSubmissionPlanner.nextID(from: snapshot, reserving: writes.count + users.count)
        var entries: [DurableEntryRecord] = [], submissions: [DurableSubmissionRecord] = []
        var head = try DurableContext.derive(snapshot: snapshot, conversationID: conversationID).head?.head
        for item in writes + users {
            guard var submission = snapshot.submissions[item.submissionID], submission.status == .queued else { throw DurableError.corruptStorage("inbox submission is not queued") }
            let id = ids.removeFirst()
            var entry: DurableEntryRecord
            if var draft = item.entry {
                if let target = draft.head, target != 0, let head, target < head {
                    submission.status = .unanswered; submission.reason = "stale"; submissions.append(submission); continue
                }
                draft.id = id; draft.createdSeq = 0; draft.byTaskID = nil
                if draft.head == 0 { draft.head = id }
                if let newHead = draft.head { head = newHead }
                entry = draft
            } else { entry = DurableEntryRecord(id: id, conversationID: conversationID, kind: "pi.user", messages: item.messages) }
            entries.append(entry); submission.status = .placed; submission.entryID = id; submissions.append(submission)
        }
        let removed = Set((writes + users).map(\.submissionID)); state.items.removeAll { removed.contains($0.submissionID) }
        return (DurableCommitBatch(entries: entries, submissions: submissions, documents: [try document(snapshot: snapshot, conversationID: conversationID, state: state)]), DurableBoundaryResult(users: users.map(\.submissionID), entries: entries, reset: reset))
    }
}
