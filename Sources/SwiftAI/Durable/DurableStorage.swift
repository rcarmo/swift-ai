import Foundation

public protocol DurableStorage: Sendable {
    func snapshot() async throws -> DurableSnapshot
    func commit(_ batch: DurableCommitBatch) async throws -> DurableSnapshot
    func close() async throws
}

enum DurableValidation {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    static func validate(snapshot: DurableSnapshot) throws {
        _ = try validate(batch: DurableCommitBatch(), against: snapshot)
    }

    static func validate(batch: DurableCommitBatch, against snapshot: DurableSnapshot) throws -> Int64 {
        try preflight(batch)
        try validateSnapshotIndexes(snapshot)
        if batch.conversations.isEmpty, batch.entries.isEmpty, batch.tasks.isEmpty, batch.submissions.isEmpty, batch.documents.isEmpty { return snapshot.highWaterID }
        var highWater = snapshot.highWaterID
        var conversations = snapshot.conversations
        var entries = snapshot.entries
        var tasks = snapshot.tasks
        var submissions = snapshot.submissions
        var documents = snapshot.documents
        var usedIDs = Set<Int64>()
        for id in conversations.keys { try insertGlobalID(id, into: &usedIDs, label: "snapshot conversation") }
        for id in entries.keys { try insertGlobalID(id, into: &usedIDs, label: "snapshot entry") }
        for id in tasks.keys { try insertGlobalID(id, into: &usedIDs, label: "snapshot task") }
        for id in submissions.keys { try insertGlobalID(id, into: &usedIDs, label: "snapshot submission") }
        for id in documents.keys { try insertGlobalID(id, into: &usedIDs, label: "snapshot document") }
        var requestIDs: [String: DurableSubmissionRecord] = [:]
        for record in snapshot.submissions.values {
            if let requestID = record.requestID {
                let key = requestIndexKey(conversationID: record.conversationID, requestID: requestID)
                if requestIDs[key] != nil { throw DurableError.corruptStorage("duplicate requestID index in snapshot") }
                requestIDs[key] = record
            }
        }

        func admitID(_ id: Int64, _ label: String) throws {
            guard id > 0, id <= DurableLimits.maxExactInteger else { throw DurableError.invalidRecord("\(label) id out of range") }
            try insertGlobalID(id, into: &usedIDs, label: label)
            highWater = max(highWater, id)
        }
        func requireConversation(_ id: Int64, _ label: String) throws {
            guard conversations[id] != nil || batch.conversations.contains(where: { $0.id == id }) else { throw DurableError.invalidRecord("\(label) references missing conversation \(id)") }
        }
        func requireEntry(_ id: Int64, _ label: String) throws {
            guard entries[id] != nil || batch.entries.contains(where: { $0.id == id }) else { throw DurableError.invalidRecord("\(label) references missing entry \(id)") }
        }
        func requireTask(_ id: Int64, _ label: String) throws {
            guard tasks[id] != nil || batch.tasks.contains(where: { $0.id == id }) else { throw DurableError.invalidRecord("\(label) references missing task \(id)") }
        }
        func validateJSON(_ value: JSONValue, _ label: String) throws { try Self.validateJSON(value, label: label) }
        func validateSize<T: Encodable>(_ value: T, max: Int, label: String) throws {
            let data = try encoder.encode(value)
            guard data.count <= max else { throw DurableError.invalidRecord("\(label) exceeds \(max) bytes") }
        }

        for record in batch.conversations {
            try admitID(record.id, "conversation")
            guard conversations[record.id] == nil else { throw DurableError.invalidRecord("conversation \(record.id) already exists") }
            if let parentConversationID = record.parentConversationID { try requireConversation(parentConversationID, "conversation.parent") }
            if let parentEntryID = record.parentEntryID { try requireEntry(parentEntryID, "conversation.parent") }
            if let ownerTaskID = record.ownerTaskID { try requireTask(ownerTaskID, "conversation.owner") }
            try validateSize(record, max: DurableLimits.maxRecordBytes, label: "conversation")
            conversations[record.id] = record
        }
        for record in batch.entries {
            try admitID(record.id, "entry")
            guard entries[record.id] == nil else { throw DurableError.invalidRecord("entry \(record.id) already exists") }
            try requireConversation(record.conversationID, "entry")
            if let byTaskID = record.byTaskID { try requireTask(byTaskID, "entry.byTask") }
            if let data = record.data { try validateJSON(data, "entry.data") }
            try validateSize(record, max: DurableLimits.maxEntryBytes, label: "entry")
            entries[record.id] = record
        }
        for record in batch.tasks {
            let existing = tasks[record.id]
            if existing == nil { try admitID(record.id, "task") }
            try requireConversation(record.conversationID, "task")
            if let ownerTaskID = record.ownerTaskID {
                guard ownerTaskID != record.id else { throw DurableError.invalidRecord("task owner cycle") }
                try requireTask(ownerTaskID, "task.owner")
            }
            if let existing {
                guard existing.conversationID == record.conversationID, existing.kind == record.kind, existing.ownerTaskID == record.ownerTaskID else { throw DurableError.invalidRecord("task identity is immutable") }
                guard !existing.abortRequested || record.abortRequested else { throw DurableError.invalidRecord("task abort request is monotonic") }
                guard validTaskTransition(from: existing.status, to: record.status) else { throw DurableError.invalidRecord("invalid task status transition") }
                if [.completed, .failed, .aborted].contains(existing.status), existing != record { throw DurableError.invalidRecord("terminal task \(record.id) is immutable") }
            }
            if let checkpoint = record.checkpoint { try validateJSON(checkpoint, "task.checkpoint"); try validateSize(checkpoint, max: DurableLimits.maxCheckpointBytes, label: "task.checkpoint") }
            if let outcome = record.outcome { try validateJSON(outcome, "task.outcome"); try validateSize(outcome, max: DurableLimits.maxRecordBytes, label: "task.outcome") }
            try validateSize(record, max: DurableLimits.maxRecordBytes, label: "task")
            tasks[record.id] = record
        }
        for record in batch.submissions {
            let existing = submissions[record.id]
            if existing == nil { try admitID(record.id, "submission") }
            try requireConversation(record.conversationID, "submission")
            if let existing {
                guard existing.conversationID == record.conversationID, existing.requestID == record.requestID, existing.type == record.type, existing.payloadHash == record.payloadHash else { throw DurableError.invalidRecord("submission identity is immutable") }
                guard validSubmissionTransition(from: existing.status, to: record.status) else { throw DurableError.invalidRecord("invalid submission status transition") }
                if [.done, .unanswered, .withdrawn].contains(existing.status), existing != record { throw DurableError.invalidRecord("terminal submission \(record.id) is immutable") }
            } else {
                guard validInitialSubmission(record) else { throw DurableError.invalidRecord("invalid initial submission state") }
            }
            if let entryID = record.entryID { try requireEntry(entryID, "submission.entry"); if let entry = entries[entryID], entry.conversationID != record.conversationID { throw DurableError.invalidRecord("submission entry conversation mismatch") } }
            if let answerID = record.answerID { try requireEntry(answerID, "submission.answer"); if let answer = entries[answerID], answer.conversationID != record.conversationID { throw DurableError.invalidRecord("submission answer conversation mismatch") } }
            try validateSubmissionCompletion(record, missingReferenceError: DurableError.invalidRecord)
            if let requestID = record.requestID {
                guard !requestID.isEmpty else { throw DurableError.invalidRecord("empty requestID") }
                guard requestID.data(using: .utf8)?.count ?? Int.max <= DurableLimits.maxRequestIDBytes else { throw DurableError.invalidRecord("requestID exceeds \(DurableLimits.maxRequestIDBytes) bytes") }
                let key = requestIndexKey(conversationID: record.conversationID, requestID: requestID)
                if let existing = requestIDs[key], existing.id != record.id || existing.type != record.type || existing.payloadHash != record.payloadHash { throw DurableError.requestIDConflict(requestID) }
                requestIDs[key] = record
            }
            try validateSize(record, max: DurableLimits.maxRecordBytes, label: "submission")
            submissions[record.id] = record
        }
        for record in batch.documents {
            let existing = documents[record.id]
            if existing == nil { try admitID(record.id, "document") }
            guard record.scope == "session" || record.scope == "conversation" || record.scope == "task" else { throw DurableError.invalidRecord("unsupported document scope") }
            if let existing { guard existing.scope == record.scope, existing.ownerID == record.ownerID, existing.kind == record.kind else { throw DurableError.invalidRecord("document identity is immutable") } }
            if record.scope == "conversation" { try requireConversation(record.ownerID, "document.owner") }
            if record.scope == "task" { try requireTask(record.ownerID, "document.owner") }
            try validateJSON(record.value, "document.value")
            try validateSize(record, max: DurableLimits.maxDocumentBytes, label: "document")
            documents[record.id] = record
        }
        let encodedBatch = try encoder.encode(batch)
        guard encodedBatch.count <= DurableLimits.maxBatchBytes else { throw DurableError.invalidRecord("batch exceeds \(DurableLimits.maxBatchBytes) bytes") }
        guard snapshot.seq < DurableLimits.maxExactInteger else { throw DurableError.invalidRecord("sequence overflow") }
        let candidate = applying(batch, to: snapshot, seq: snapshot.seq + 1, highWater: highWater)
        try validateSnapshotIndexes(candidate)
        return highWater
    }

    static func applying(_ batch: DurableCommitBatch, to snapshot: DurableSnapshot, seq: Int64, highWater: Int64) -> DurableSnapshot {
        var next = snapshot
        next.seq = seq
        next.highWaterID = highWater
        for var record in batch.conversations { if let existing = next.conversations[record.id] { record.createdSeq = existing.createdSeq } else { record.createdSeq = seq }; next.conversations[record.id] = record }
        for var record in batch.entries { if let existing = next.entries[record.id] { record.createdSeq = existing.createdSeq } else { record.createdSeq = seq }; next.entries[record.id] = record }
        for var record in batch.tasks { if let existing = next.tasks[record.id] { record.createdSeq = existing.createdSeq } else { record.createdSeq = seq }; next.tasks[record.id] = record }
        for var record in batch.submissions { if let existing = next.submissions[record.id] { record.createdSeq = existing.createdSeq } else { record.createdSeq = seq }; next.submissions[record.id] = record }
        for var record in batch.documents { if let existing = next.documents[record.id] { record.createdSeq = existing.createdSeq } else { record.createdSeq = seq }; next.documents[record.id] = record }
        return next
    }

    private static func preflight(_ batch: DurableCommitBatch) throws {
        _ = try estimatedBatchBytes(batch, error: DurableError.invalidRecord)
    }

    static func estimatedJournalPayloadBytes(batch: DurableCommitBatch, seq: Int64, highWater: Int64) throws -> Int {
        let batchBytes = try estimatedBatchBytes(batch, error: DurableError.invalidRecord)
        var bytes = 2
        bytes += fieldBytes("seq", numberBytes(seq))
        bytes += fieldBytes("highWaterID", numberBytes(highWater))
        bytes += fieldBytes("batch", batchBytes)
        return bytes
    }

    private static func estimatedBatchBytes(_ batch: DurableCommitBatch, error: (String) -> DurableError) throws -> Int {
        var ids = Set<Int64>()
        var conversationBytes = 2
        var entryBytes = 2
        var taskBytes = 2
        var submissionBytes = 2
        var documentBytes = 2
        func total() -> Int {
            2 + fieldBytes("conversations", conversationBytes) + fieldBytes("entries", entryBytes) + fieldBytes("tasks", taskBytes) + fieldBytes("submissions", submissionBytes) + fieldBytes("documents", documentBytes)
        }
        func checkTotal(_ label: String) throws { try checkBytes(total(), max: DurableLimits.maxBatchBytes, label: label, error: error) }
        for record in batch.conversations {
            try insertGlobalID(record.id, into: &ids, label: "batch conversation")
            conversationBytes += try validateConversationRecord(record, max: DurableLimits.maxRecordBytes, label: "conversation", error: error) + 1
            try checkBytes(conversationBytes, max: DurableLimits.maxBatchBytes, label: "batch.conversations", error: error)
            try checkTotal("batch")
        }
        for record in batch.entries {
            try insertGlobalID(record.id, into: &ids, label: "batch entry")
            entryBytes += try validateEntryRecord(record, max: DurableLimits.maxEntryBytes, label: "entry", error: error) + 1
            try checkBytes(entryBytes, max: DurableLimits.maxBatchBytes, label: "batch.entries", error: error)
            try checkTotal("batch")
        }
        for record in batch.tasks {
            try insertGlobalID(record.id, into: &ids, label: "batch task")
            taskBytes += try validateTaskRecord(record, max: DurableLimits.maxRecordBytes, label: "task", error: error) + 1
            try checkBytes(taskBytes, max: DurableLimits.maxBatchBytes, label: "batch.tasks", error: error)
            try checkTotal("batch")
        }
        for record in batch.submissions {
            try insertGlobalID(record.id, into: &ids, label: "batch submission")
            submissionBytes += try validateSubmissionRecord(record, max: DurableLimits.maxRecordBytes, label: "submission", error: error) + 1
            try checkBytes(submissionBytes, max: DurableLimits.maxBatchBytes, label: "batch.submissions", error: error)
            try checkTotal("batch")
        }
        for record in batch.documents {
            try insertGlobalID(record.id, into: &ids, label: "batch document")
            documentBytes += try validateDocumentRecord(record, max: DurableLimits.maxDocumentBytes, label: "document", error: error) + 1
            try checkBytes(documentBytes, max: DurableLimits.maxBatchBytes, label: "batch.documents", error: error)
            try checkTotal("batch")
        }
        try checkTotal("batch")
        return total()
    }

    private static func validateCreatedSeq(_ createdSeq: Int64, snapshotSeq: Int64, label: String, error: (String) -> DurableError) throws {
        guard createdSeq > 0, createdSeq <= snapshotSeq else { throw error("\(label) createdSeq out of range") }
    }

    @discardableResult
    private static func validateConversationRecord(_ record: DurableConversationRecord, max: Int, label: String, error: (String) -> DurableError) throws -> Int {
        var bytes = 2 + fieldBytes("id", numberBytes(record.id)) + fieldBytes("createdSeq", numberBytes(record.createdSeq))
        if let value = record.parentConversationID { bytes += fieldBytes("parentConversationID", numberBytes(value)) }
        if let value = record.parentEntryID { bytes += fieldBytes("parentEntryID", numberBytes(value)) }
        if let value = record.ownerTaskID { bytes += fieldBytes("ownerTaskID", numberBytes(value)) }
        try checkBytes(bytes, max: max, label: label, error: error)
        return bytes
    }

    @discardableResult
    static func validateEntryRecord(_ record: DurableEntryRecord, max: Int, label: String, error: (String) -> DurableError) throws -> Int {
        var bytes = 2 + fieldBytes("id", numberBytes(record.id)) + fieldBytes("conversationID", numberBytes(record.conversationID)) + fieldBytes("createdSeq", numberBytes(record.createdSeq))
        bytes += try fieldBytes("kind", escapedStringBytes(record.kind, label: "\(label).kind", error: error))
        if let byTaskID = record.byTaskID { bytes += fieldBytes("byTaskID", numberBytes(byTaskID)) }
        if let messages = record.messages { bytes += try fieldBytes("messages", measureMessages(messages, label: "\(label).messages", error: error)) }
        if let data = record.data { bytes += try fieldBytes("data", measureJSON(data, label: "\(label).data", error: error)) }
        try checkBytes(bytes, max: max, label: label, error: error)
        return bytes
    }

    @discardableResult
    private static func validateTaskRecord(_ record: DurableTaskRecord, max: Int, label: String, error: (String) -> DurableError) throws -> Int {
        var bytes = 2 + fieldBytes("id", numberBytes(record.id)) + fieldBytes("conversationID", numberBytes(record.conversationID)) + fieldBytes("createdSeq", numberBytes(record.createdSeq))
        if let ownerTaskID = record.ownerTaskID { bytes += fieldBytes("ownerTaskID", numberBytes(ownerTaskID)) }
        bytes += try fieldBytes("kind", escapedStringBytes(record.kind, label: "\(label).kind", error: error))
        bytes += try fieldBytes("status", escapedStringBytes(record.status.rawValue, label: "\(label).status", error: error))
        bytes += fieldBytes("abortRequested", record.abortRequested ? 4 : 5)
        bytes += fieldBytes("background", record.background ? 4 : 5)
        if let checkpoint = record.checkpoint {
            let checkpointBytes = try measureJSON(checkpoint, label: "\(label).checkpoint", error: error)
            try checkBytes(checkpointBytes, max: DurableLimits.maxCheckpointBytes, label: "\(label).checkpoint", error: error)
            bytes += fieldBytes("checkpoint", checkpointBytes)
        }
        if let outcome = record.outcome { bytes += try fieldBytes("outcome", measureJSON(outcome, label: "\(label).outcome", error: error)) }
        try checkBytes(bytes, max: max, label: label, error: error)
        return bytes
    }

    @discardableResult
    private static func validateSubmissionRecord(_ record: DurableSubmissionRecord, max: Int, label: String, error: (String) -> DurableError) throws -> Int {
        var bytes = 2 + fieldBytes("id", numberBytes(record.id)) + fieldBytes("conversationID", numberBytes(record.conversationID)) + fieldBytes("createdSeq", numberBytes(record.createdSeq))
        if let requestID = record.requestID { bytes += try fieldBytes("requestID", escapedStringBytes(requestID, label: "\(label).requestID", maxUTF8: DurableLimits.maxRequestIDBytes, error: error)) }
        bytes += try fieldBytes("type", escapedStringBytes(record.type.rawValue, label: "\(label).type", error: error))
        if let payloadHash = record.payloadHash { bytes += try fieldBytes("payloadHash", escapedStringBytes(payloadHash, label: "\(label).payloadHash", error: error)) }
        bytes += try fieldBytes("status", escapedStringBytes(record.status.rawValue, label: "\(label).status", error: error))
        if let entryID = record.entryID { bytes += fieldBytes("entryID", numberBytes(entryID)) }
        if let answerID = record.answerID { bytes += fieldBytes("answerID", numberBytes(answerID)) }
        if let reason = record.reason { bytes += try fieldBytes("reason", escapedStringBytes(reason, label: "\(label).reason", error: error)) }
        try checkBytes(bytes, max: max, label: label, error: error)
        return bytes
    }

    @discardableResult
    private static func validateDocumentRecord(_ record: DurableDocumentRecord, max: Int, label: String, error: (String) -> DurableError) throws -> Int {
        var bytes = 2 + fieldBytes("id", numberBytes(record.id)) + fieldBytes("ownerID", numberBytes(record.ownerID)) + fieldBytes("createdSeq", numberBytes(record.createdSeq))
        bytes += try fieldBytes("scope", escapedStringBytes(record.scope, label: "\(label).scope", error: error))
        bytes += try fieldBytes("kind", escapedStringBytes(record.kind, label: "\(label).kind", error: error))
        bytes += try fieldBytes("value", measureJSON(record.value, label: "\(label).value", error: error))
        try checkBytes(bytes, max: max, label: label, error: error)
        return bytes
    }

    private static func measureMessages(_ messages: [Message], label: String, error: (String) -> DurableError) throws -> Int {
        var nodes = 0
        var bytes = 2
        try addNativeNode(&nodes, label: label, error: error)
        for (index, message) in messages.enumerated() {
            bytes += try measureMessage(message, label: "\(label)[\(index)]", depth: 1, nodes: &nodes, error: error) + 1
        }
        return bytes
    }

    private static func measureMessage(_ message: Message, label: String, depth: Int, nodes: inout Int, error: (String) -> DurableError) throws -> Int {
        try checkDepth(depth, label: label, error: error)
        try addNativeNode(&nodes, label: label, error: error)
        var bytes = 2 + fieldBytes("timestamp", numberBytes(message.timestamp))
        bytes += try fieldBytes("role", escapedStringBytes(message.role.rawValue, label: "\(label).role", error: error))
        bytes += try fieldBytes("content", measureContentBlocks(message.content, label: "\(label).content", depth: depth + 1, nodes: &nodes, error: error))
        if let api = message.api { bytes += try fieldBytes("api", escapedStringBytes(api.rawValue, label: "\(label).api", error: error)) }
        if let provider = message.provider { bytes += try fieldBytes("provider", escapedStringBytes(provider.rawValue, label: "\(label).provider", error: error)) }
        for (name, value) in [("model", message.model), ("responseId", message.responseId), ("responseModel", message.responseModel), ("providerThinkingLevel", message.providerThinkingLevel), ("errorMessage", message.errorMessage), ("rawStopReason", message.rawStopReason), ("toolCallId", message.toolCallId), ("toolName", message.toolName)] where value != nil {
            bytes += try fieldBytes(name, escapedStringBytes(value!, label: "\(label).\(name)", error: error))
        }
        if let thinkingLevel = message.thinkingLevel { bytes += try fieldBytes("thinkingLevel", escapedStringBytes(thinkingLevel.rawValue, label: "\(label).thinkingLevel", error: error)) }
        if let stopReason = message.stopReason { bytes += try fieldBytes("stopReason", escapedStringBytes(stopReason.rawValue, label: "\(label).stopReason", error: error)) }
        if let diagnostics = message.diagnostics { bytes += try fieldBytes("diagnostics", measureDiagnostics(diagnostics, label: "\(label).diagnostics", depth: depth + 1, nodes: &nodes, error: error)) }
        if let usage = message.usage { bytes += try fieldBytes("usage", measureUsage(usage, label: "\(label).usage", depth: depth + 1, nodes: &nodes, error: error)) }
        if let deferred = message.deferred { bytes += try fieldBytes("deferred", measureDeferred(deferred, label: "\(label).deferred", depth: depth + 1, nodes: &nodes, error: error)) }
        if let details = message.details { bytes += try fieldBytes("details", measureJSON(details, label: "\(label).details", depth: depth + 1, nodes: &nodes, error: error)) }
        if let added = message.addedToolNames { bytes += try fieldBytes("addedToolNames", measureStrings(added, label: "\(label).addedToolNames", error: error)) }
        if let tools = message.toolsAdded { bytes += try fieldBytes("toolsAdded", measureTools(tools, label: "\(label).toolsAdded", depth: depth + 1, nodes: &nodes, error: error)) }
        if let removed = message.toolsRemoved { bytes += try fieldBytes("toolsRemoved", measureToolRefs(removed, label: "\(label).toolsRemoved", error: error)) }
        if let nestedCalls = message.nestedCalls { bytes += try fieldBytes("nestedCalls", measureJSON(nestedCalls, label: "\(label).nestedCalls", depth: depth + 1, nodes: &nodes, error: error)) }
        if message.isError != nil { bytes += fieldBytes("isError", 5) }
        if message.endTurn != nil { bytes += fieldBytes("endTurn", 5) }
        return bytes
    }

    private static func measureContentBlocks(_ blocks: [ContentBlock], label: String, depth: Int, nodes: inout Int, error: (String) -> DurableError) throws -> Int {
        try checkDepth(depth, label: label, error: error)
        try addNativeNode(&nodes, label: label, error: error)
        var bytes = 2
        for (index, block) in blocks.enumerated() {
            try addNativeNode(&nodes, label: "\(label)[\(index)]", error: error)
            var blockBytes = 2 + (try fieldBytes("type", escapedStringBytes(block.type, label: "\(label)[\(index)].type", error: error)))
            for (name, value) in [("text", block.text), ("textSignature", block.textSignature), ("thinking", block.thinking), ("thinkingSignature", block.thinkingSignature), ("data", block.data), ("mimeType", block.mimeType), ("id", block.id), ("name", block.name), ("thoughtSignature", block.thoughtSignature), ("namespace", block.namespace)] where value != nil {
                blockBytes += try fieldBytes(name, escapedStringBytes(value!, label: "\(label)[\(index)].\(name)", error: error))
            }
            if block.redacted != nil { blockBytes += fieldBytes("redacted", 5) }
            if let arguments = block.arguments { blockBytes += try fieldBytes("arguments", measureJSON(.object(arguments), label: "\(label)[\(index)].arguments", depth: depth + 1, nodes: &nodes, error: error)) }
            bytes += blockBytes + 1
        }
        return bytes
    }

    private static func measureDiagnostics(_ diagnostics: [AssistantMessageDiagnostic], label: String, depth: Int, nodes: inout Int, error: (String) -> DurableError) throws -> Int {
        try checkDepth(depth, label: label, error: error)
        try addNativeNode(&nodes, label: label, error: error)
        var bytes = 2
        for (index, diagnostic) in diagnostics.enumerated() {
            try addNativeNode(&nodes, label: "\(label)[\(index)]", error: error)
            var item = 2 + (try fieldBytes("type", escapedStringBytes(diagnostic.type, label: "\(label)[\(index)].type", error: error))) + fieldBytes("timestamp", numberBytes(diagnostic.timestamp))
            item += try fieldBytes("error", measureDiagnosticError(diagnostic.error, label: "\(label)[\(index)].error", depth: depth + 1, nodes: &nodes, error: error))
            if let details = diagnostic.details { item += try fieldBytes("details", measureJSON(.object(details), label: "\(label)[\(index)].details", depth: depth + 1, nodes: &nodes, error: error)) }
            bytes += item + 1
        }
        return bytes
    }

    private static func measureDiagnosticError(_ diagnostic: DiagnosticError, label: String, depth: Int, nodes: inout Int, error: (String) -> DurableError) throws -> Int {
        try checkDepth(depth, label: label, error: error)
        try addNativeNode(&nodes, label: label, error: error)
        var bytes = 2 + (try fieldBytes("message", escapedStringBytes(diagnostic.message, label: "\(label).message", error: error)))
        if let name = diagnostic.name { bytes += try fieldBytes("name", escapedStringBytes(name, label: "\(label).name", error: error)) }
        if let stack = diagnostic.stack { bytes += try fieldBytes("stack", escapedStringBytes(stack, label: "\(label).stack", error: error)) }
        if let code = diagnostic.code { bytes += try fieldBytes("code", measureJSON(code, label: "\(label).code", depth: depth + 1, nodes: &nodes, error: error)) }
        return bytes
    }

    private static func measureDeferred(_ deferred: DeferredHandle, label: String, depth: Int, nodes: inout Int, error: (String) -> DurableError) throws -> Int {
        var bytes = 2 + (try fieldBytes("provider", escapedStringBytes(deferred.provider, label: "\(label).provider", error: error)))
        bytes += try fieldBytes("modelId", escapedStringBytes(deferred.modelId, label: "\(label).modelId", error: error))
        bytes += try fieldBytes("api", escapedStringBytes(deferred.api, label: "\(label).api", error: error))
        bytes += try fieldBytes("id", escapedStringBytes(deferred.id, label: "\(label).id", error: error))
        if let expiresAt = deferred.expiresAt { bytes += fieldBytes("expiresAt", numberBytes(expiresAt)) }
        if let pollAfterMs = deferred.pollAfterMs { bytes += fieldBytes("pollAfterMs", String(pollAfterMs).utf8.count) }
        if let data = deferred.data { bytes += try fieldBytes("data", measureJSON(data, label: "\(label).data", depth: depth + 1, nodes: &nodes, error: error)) }
        return bytes
    }

    private static func measureUsage(_ usage: Usage, label: String, depth: Int, nodes: inout Int, error: (String) -> DurableError) throws -> Int {
        try checkDepth(depth, label: label, error: error)
        try addNativeNode(&nodes, label: label, error: error)
        var bytes = 2
        for (name, value) in [("input", usage.input), ("output", usage.output), ("cacheRead", usage.cacheRead), ("cacheWrite", usage.cacheWrite), ("reasoning", usage.reasoning), ("totalTokens", usage.totalTokens)] {
            bytes += fieldBytes(name, String(value).utf8.count)
        }
        if let cacheWrite1h = usage.cacheWrite1h { bytes += fieldBytes("cacheWrite1h", String(cacheWrite1h).utf8.count) }
        bytes += try fieldBytes("cost", measureCost(usage.cost, label: "\(label).cost", error: error))
        return bytes
    }

    private static func measureCost(_ cost: CostBreakdown, label: String, error: (String) -> DurableError) throws -> Int {
        var bytes = 2
        for (name, value) in [("input", cost.input), ("output", cost.output), ("cacheRead", cost.cacheRead), ("cacheWrite", cost.cacheWrite), ("total", cost.total)] {
            guard value.isFinite else { throw error("\(label).\(name) contains non-finite number") }
            bytes += fieldBytes(name, 64)
        }
        return bytes
    }

    private static func measureTools(_ tools: [Tool], label: String, depth: Int, nodes: inout Int, error: (String) -> DurableError) throws -> Int {
        try checkDepth(depth, label: label, error: error)
        try addNativeNode(&nodes, label: label, error: error)
        var bytes = 2
        for (index, tool) in tools.enumerated() {
            try addNativeNode(&nodes, label: "\(label)[\(index)]", error: error)
            var item = 2 + (try fieldBytes("name", escapedStringBytes(tool.name, label: "\(label)[\(index)].name", error: error)))
            item += try fieldBytes("description", escapedStringBytes(tool.description, label: "\(label)[\(index)].description", error: error))
            item += try fieldBytes("parameters", measureJSON(tool.parameters, label: "\(label)[\(index)].parameters", depth: depth + 1, nodes: &nodes, error: error))
            if let constrained = tool.constrainedSampling { item += try fieldBytes("constrainedSampling", measureConstrainedSampling(constrained, label: "\(label)[\(index)].constrainedSampling", error: error)) }
            bytes += item + 1
        }
        return bytes
    }

    private static func measureConstrainedSampling(_ config: ConstrainedSamplingConfig, label: String, error: (String) -> DurableError) throws -> Int {
        var bytes = 2 + (try fieldBytes("type", escapedStringBytes(config.type, label: "\(label).type", error: error)))
        if let strict = config.strict { bytes += try fieldBytes("strict", escapedStringBytes(strict, label: "\(label).strict", error: error)) }
        if let variants = config.variants {
            var variantBytes = 2
            if let lark = variants.openaiLark { variantBytes += try fieldBytes("openai_lark", escapedStringBytes(lark, label: "\(label).variants.openai_lark", maxUTF8: DurableLimits.maxArgumentsBytes, error: error)) }
            if let regex = variants.openaiRegex { variantBytes += try fieldBytes("openai_regex", escapedStringBytes(regex, label: "\(label).variants.openai_regex", maxUTF8: DurableLimits.maxArgumentsBytes, error: error)) }
            bytes += fieldBytes("variants", variantBytes)
        }
        return bytes
    }

    private static func measureToolRefs(_ refs: [ToolReference], label: String, error: (String) -> DurableError) throws -> Int {
        var bytes = 2
        for (index, ref) in refs.enumerated() {
            let item = 2 + (try fieldBytes("name", escapedStringBytes(ref.name, label: "\(label)[\(index)].name", error: error)))
            bytes += item + 1
        }
        return bytes
    }

    private static func measureStrings(_ values: [String], label: String, error: (String) -> DurableError) throws -> Int {
        var bytes = 2
        for (index, value) in values.enumerated() { bytes += try escapedStringBytes(value, label: "\(label)[\(index)]", error: error) + 1 }
        return bytes
    }

    private static func fieldBytes(_ name: String, _ valueBytes: Int) -> Int { name.utf8.count + valueBytes + 6 }

    private static func numberBytes(_ value: Int64) -> Int { String(value).utf8.count }

    static func escapedStringBytes(_ string: String, label: String, maxUTF8: Int = DurableLimits.maxStringBytes, error: (String) -> DurableError) throws -> Int {
        guard string.utf8.count <= maxUTF8 else { throw error("\(label) string exceeds limit") }
        var total = 2
        for scalar in string.unicodeScalars {
            switch scalar.value {
            case 0...0x1f: total += 6
            case 0x22, 0x2f, 0x5c: total += 2
            default: total += String(scalar).utf8.count
            }
            guard total <= DurableLimits.maxDocumentBytes + DurableLimits.maxRecordBytes else { throw error("\(label) string escaped size exceeds limit") }
        }
        return total
    }

    static func checkBytes(_ bytes: Int, max: Int, label: String, error: (String) -> DurableError) throws {
        guard bytes <= max else { throw error("\(label) exceeds \(max) bytes") }
    }

    static func measureJSON(_ value: JSONValue, label: String, error: (String) -> DurableError) throws -> Int {
        var nodes = 0
        return try measureJSON(value, label: label, depth: 0, nodes: &nodes, error: error)
    }

    private static func measureJSON(_ value: JSONValue, label: String, depth: Int, nodes: inout Int, error: (String) -> DurableError) throws -> Int {
        try checkDepth(depth, label: label, error: error)
        try addNativeNode(&nodes, label: label, error: error)
        switch value {
        case .null: return 4
        case .bool(let bool): return bool ? 4 : 5
        case .number(let number):
            guard number.isFinite else { throw error("\(label) contains non-finite number") }
            return 64
        case .string(let string): return try escapedStringBytes(string, label: label, error: error)
        case .array(let values):
            var bytes = 2
            for (index, child) in values.enumerated() { bytes += try measureJSON(child, label: "\(label)[\(index)]", depth: depth + 1, nodes: &nodes, error: error) + 1 }
            return bytes
        case .object(let object):
            var bytes = 2
            for (key, child) in object {
                bytes += try escapedStringBytes(key, label: "\(label).key", error: error)
                bytes += try measureJSON(child, label: "\(label).\(key)", depth: depth + 1, nodes: &nodes, error: error) + 2
            }
            return bytes
        }
    }

    private static func checkDepth(_ depth: Int, label: String, error: (String) -> DurableError) throws {
        guard depth <= DurableLimits.maxJSONDepth else { throw error("\(label) exceeds JSON depth limit") }
    }

    private static func addNativeNode(_ nodes: inout Int, label: String, error: (String) -> DurableError) throws {
        nodes += 1
        guard nodes <= DurableLimits.maxJSONNodes else { throw error("\(label) exceeds JSON node limit") }
    }

    private static func validateSnapshotIndexes(_ snapshot: DurableSnapshot) throws {
        guard snapshot.seq >= 0, snapshot.seq <= DurableLimits.maxExactInteger, snapshot.highWaterID >= 0, snapshot.highWaterID <= DurableLimits.maxExactInteger else { throw DurableError.corruptStorage("snapshot counters invalid") }
        var ids = Set<Int64>()
        var requestIDs = Set<String>()
        var documentAddresses = Set<String>()
        for (id, record) in snapshot.conversations {
            guard id == record.id else { throw DurableError.corruptStorage("conversation key mismatch") }
            try insertGlobalID(id, into: &ids, label: "conversation")
            try validateCreatedSeq(record.createdSeq, snapshotSeq: snapshot.seq, label: "conversation", error: DurableError.corruptStorage)
            _ = try validateConversationRecord(record, max: DurableLimits.maxRecordBytes, label: "conversation", error: DurableError.corruptStorage)
            if let parentConversationID = record.parentConversationID { guard snapshot.conversations[parentConversationID] != nil else { throw DurableError.corruptStorage("conversation missing parent conversation") } }
            if let parentEntryID = record.parentEntryID {
                guard let parentEntry = snapshot.entries[parentEntryID] else { throw DurableError.corruptStorage("conversation missing parent entry") }
                if let parentConversationID = record.parentConversationID, parentEntry.conversationID != parentConversationID { throw DurableError.corruptStorage("conversation parent entry mismatch") }
            }
            if let ownerTaskID = record.ownerTaskID { guard snapshot.tasks[ownerTaskID] != nil else { throw DurableError.corruptStorage("conversation missing owner task") } }
        }
        for (id, record) in snapshot.entries {
            guard id == record.id else { throw DurableError.corruptStorage("entry key mismatch") }
            try insertGlobalID(id, into: &ids, label: "entry")
            try validateCreatedSeq(record.createdSeq, snapshotSeq: snapshot.seq, label: "entry", error: DurableError.corruptStorage)
            _ = try validateEntryRecord(record, max: DurableLimits.maxEntryBytes, label: "entry", error: DurableError.corruptStorage)
            guard snapshot.conversations[record.conversationID] != nil else { throw DurableError.corruptStorage("entry missing conversation") }
            if let byTaskID = record.byTaskID {
                guard let task = snapshot.tasks[byTaskID] else { throw DurableError.corruptStorage("entry missing byTask") }
                guard task.conversationID == record.conversationID else { throw DurableError.corruptStorage("entry byTask conversation mismatch") }
            }
        }
        for (id, record) in snapshot.tasks {
            guard id == record.id else { throw DurableError.corruptStorage("task key mismatch") }
            try insertGlobalID(id, into: &ids, label: "task")
            try validateCreatedSeq(record.createdSeq, snapshotSeq: snapshot.seq, label: "task", error: DurableError.corruptStorage)
            _ = try validateTaskRecord(record, max: DurableLimits.maxRecordBytes, label: "task", error: DurableError.corruptStorage)
            guard snapshot.conversations[record.conversationID] != nil else { throw DurableError.corruptStorage("task missing conversation") }
        }
        for (id, record) in snapshot.submissions {
            guard id == record.id else { throw DurableError.corruptStorage("submission key mismatch") }
            try insertGlobalID(id, into: &ids, label: "submission")
            try validateCreatedSeq(record.createdSeq, snapshotSeq: snapshot.seq, label: "submission", error: DurableError.corruptStorage)
            _ = try validateSubmissionRecord(record, max: DurableLimits.maxRecordBytes, label: "submission", error: DurableError.corruptStorage)
            guard snapshot.conversations[record.conversationID] != nil else { throw DurableError.corruptStorage("submission missing conversation") }
            if let entryID = record.entryID {
                guard let entry = snapshot.entries[entryID] else { throw DurableError.corruptStorage("submission missing entry") }
                guard entry.conversationID == record.conversationID else { throw DurableError.corruptStorage("submission entry conversation mismatch") }
            }
            if let answerID = record.answerID {
                guard let answer = snapshot.entries[answerID] else { throw DurableError.corruptStorage("submission missing answer") }
                guard answer.conversationID == record.conversationID else { throw DurableError.corruptStorage("submission answer conversation mismatch") }
            }
            try validateSubmissionCompletion(record, missingReferenceError: DurableError.corruptStorage)
            if let requestID = record.requestID {
                guard !requestID.isEmpty else { throw DurableError.corruptStorage("empty requestID") }
                let key = requestIndexKey(conversationID: record.conversationID, requestID: requestID)
                guard requestIDs.insert(key).inserted else { throw DurableError.corruptStorage("duplicate requestID index in snapshot") }
            }
        }
        for (id, record) in snapshot.documents {
            guard id == record.id else { throw DurableError.corruptStorage("document key mismatch") }
            try insertGlobalID(id, into: &ids, label: "document")
            try validateCreatedSeq(record.createdSeq, snapshotSeq: snapshot.seq, label: "document", error: DurableError.corruptStorage)
            _ = try validateDocumentRecord(record, max: DurableLimits.maxDocumentBytes, label: "document", error: DurableError.corruptStorage)
            guard record.scope == "session" || record.scope == "conversation" || record.scope == "task" else { throw DurableError.corruptStorage("unsupported document scope") }
            if record.scope == "conversation" { guard snapshot.conversations[record.ownerID] != nil else { throw DurableError.corruptStorage("document missing conversation owner") } }
            if record.scope == "task" { guard snapshot.tasks[record.ownerID] != nil else { throw DurableError.corruptStorage("document missing task owner") } }
            guard documentAddresses.insert(documentAddress(record)).inserted else { throw DurableError.corruptStorage("duplicate document address in snapshot") }
        }
        if let maxID = ids.max() { guard snapshot.highWaterID >= maxID else { throw DurableError.corruptStorage("snapshot high-water below max id") } }
        try validateTaskOwners(snapshot.tasks)
    }

    private static func insertGlobalID(_ id: Int64, into ids: inout Set<Int64>, label: String) throws {
        guard id > 0, id <= DurableLimits.maxExactInteger else { throw DurableError.invalidRecord("\(label) id out of range") }
        guard ids.insert(id).inserted else { throw DurableError.invalidRecord("global id collision for \(id)") }
    }

    private static func validateTaskOwners(_ tasks: [Int64: DurableTaskRecord]) throws {
        for task in tasks.values {
            var seen = Set<Int64>([task.id])
            var next = task.ownerTaskID
            while let ownerID = next {
                guard let owner = tasks[ownerID] else { throw DurableError.invalidRecord("missing owner task \(ownerID)") }
                guard owner.conversationID == task.conversationID else { throw DurableError.invalidRecord("owner task conversation mismatch") }
                guard seen.insert(ownerID).inserted else { throw DurableError.invalidRecord("task owner cycle") }
                next = owner.ownerTaskID
            }
        }
    }

    private static func validTaskTransition(from old: DurableTaskStatus, to new: DurableTaskStatus) -> Bool {
        if old == new { return true }
        if [.completed, .failed, .aborted].contains(old) { return false }
        switch old {
        case .pending: return [.running, .aborted].contains(new)
        case .running: return [.waiting, .completing, .failed, .aborted].contains(new)
        case .waiting: return [.running, .aborted].contains(new)
        case .completing: return [.completed, .failed, .aborted].contains(new)
        case .completed, .failed, .aborted: return false
        }
    }

    private static func validSubmissionTransition(from old: DurableSubmissionStatus, to new: DurableSubmissionStatus) -> Bool {
        if old == new { return true }
        switch old {
        case .queued: return [.placed, .withdrawn].contains(new)
        case .placed: return [.done, .unanswered, .withdrawn].contains(new)
        case .done, .unanswered, .withdrawn: return false
        }
    }

    private static func validInitialSubmission(_ record: DurableSubmissionRecord) -> Bool {
        switch record.status {
        case .queued: return record.entryID == nil && record.answerID == nil && record.reason == nil
        case .placed: return record.entryID != nil && record.answerID == nil
        case .done, .unanswered, .withdrawn: return false
        }
    }

    private static func validateSubmissionCompletion(_ record: DurableSubmissionRecord, missingReferenceError: (String) -> DurableError) throws {
        switch record.status {
        case .queued:
            guard record.entryID == nil, record.answerID == nil, record.reason == nil else { throw missingReferenceError("queued submission has settlement fields") }
        case .placed:
            guard record.entryID != nil, record.answerID == nil else { throw missingReferenceError("placed submission requires entry and no answer") }
        case .done:
            guard record.entryID != nil, record.answerID != nil, record.reason == nil else { throw missingReferenceError("done submission requires entry and answer") }
        case .unanswered:
            guard record.entryID != nil, record.answerID == nil, record.reason != nil else { throw missingReferenceError("unanswered submission requires entry and reason") }
        case .withdrawn:
            guard record.answerID == nil, record.reason != nil else { throw missingReferenceError("withdrawn submission requires reason and no answer") }
        }
    }

    private static func requestIndexKey(conversationID: Int64, requestID: String) -> String { "\(conversationID)\u{0}\(requestID)" }

    private static func documentAddress(_ record: DurableDocumentRecord) -> String { "\(record.scope)\u{0}\(record.ownerID)\u{0}\(record.kind)" }

    private static func validateJSON(_ value: JSONValue, label: String) throws {
        var nodes = 0
        try validateJSON(value, label: label, depth: 0, nodes: &nodes)
    }

    private static func validateJSON(_ value: JSONValue, label: String, depth: Int, nodes: inout Int) throws {
        guard depth <= DurableLimits.maxJSONDepth else { throw DurableError.invalidRecord("\(label) exceeds JSON depth limit") }
        nodes += 1
        guard nodes <= DurableLimits.maxJSONNodes else { throw DurableError.invalidRecord("\(label) exceeds JSON node limit") }
        switch value {
        case .number(let number): guard number.isFinite else { throw DurableError.invalidRecord("\(label) contains non-finite number") }
        case .string(let string): guard string.data(using: .utf8)?.count ?? Int.max <= DurableLimits.maxStringBytes else { throw DurableError.invalidRecord("\(label) string exceeds limit") }
        case .array(let values): for (index, child) in values.enumerated() { try validateJSON(child, label: "\(label)[\(index)]", depth: depth + 1, nodes: &nodes) }
        case .object(let object): for (key, child) in object { guard key.data(using: .utf8)?.count ?? Int.max <= DurableLimits.maxStringBytes else { throw DurableError.invalidRecord("\(label) key exceeds limit") }; try validateJSON(child, label: "\(label).\(key)", depth: depth + 1, nodes: &nodes) }
        default: break
        }
    }
}
