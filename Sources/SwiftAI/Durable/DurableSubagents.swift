import Foundation

public struct DurableSubagent: Sendable {
    public var taskID: Int64
    public var conversationID: Int64
}

struct DurableSubagentIntent: Codable, Sendable {
    var parentConversationID: Int64
    var childConversationID: Int64
    var input: [Message]
    var settings: DurableAgentSettings
    var generationTaskID: Int64?
    var report: Message?
}

public extension DurableSession {
    /// Persist child ownership and intent before any model effects. Explicit resume controls execution.
    func spawnSubagent(parentConversationID: Int64, settings: DurableAgentSettings, input: [Message], background: Bool = false) async throws -> DurableSubagent {
        try ensureAdmitting()
        try DurableNativePreflight.validate(input, maxBytes: DurableLimits.maxEntryBytes)
        var settings = settings; settings.model.baseUrl = ""; settings.model.headers = nil
        let pinned = settings
        return try await gate.submit {
            let snapshot = try await self.storage.snapshot()
            guard snapshot.conversations[parentConversationID] != nil else { throw DurableError.invalidRecord("missing parent conversation") }
            guard snapshot.tasks.values.filter({ ![.completed, .failed, .aborted].contains($0.status) }).count < DurableLimits.maxPublicQueue else { throw DurableError.queueFull }
            let ids = try DurableSubmissionPlanner.nextID(from: snapshot, reserving: 4)
            let child = DurableConversationRecord(id: ids[0], ownerTaskID: ids[1])
            let task = DurableTaskRecord(id: ids[1], conversationID: parentConversationID, kind: "subagent", background: background)
            let intent = DurableSubagentIntent(parentConversationID: parentConversationID, childConversationID: child.id, input: input, settings: pinned)
            let doc = DurableDocumentRecord(id: ids[2], scope: "task", ownerID: task.id, kind: "subagent.intent", value: try DurableGenerationPlanner.encodeJSON(intent, maxBytes: DurableLimits.maxCheckpointBytes))
            let agent = DurableDocumentRecord(id: ids[3], scope: "conversation", ownerID: child.id, kind: "pi.agent", value: try DurableGenerationPlanner.encodeJSON(pinned), version: 1, history: .latest, forkPolicy: .current)
            _ = try await self.storage.commit(DurableCommitBatch(conversations: [child], tasks: [task], documents: [doc, agent]))
            return DurableSubagent(taskID: task.id, conversationID: child.id)
        }
    }

    func resumeSubagents() async throws -> [DurableTaskRecord] {
        try ensureAdmitting()
        guard !subagentSchedulerRunning else { throw DurableError.invalidRecord("subagent scheduler already running") }
        subagentSchedulerRunning = true; activeAdmissions += 1
        defer { subagentSchedulerRunning = false; activeAdmissions -= 1; finishCloseIfNeeded() }
        let tasks = try await snapshot().tasks.values.filter { $0.kind == "subagent" && [.pending, .running, .completing].contains($0.status) }.sorted { $0.id < $1.id }
        var results: [DurableTaskRecord] = []
        for task in tasks { results.append(try await executeSubagent(taskID: task.id)) }
        return results
    }

    private func executeSubagent(taskID: Int64) async throws -> DurableTaskRecord {
        let snapshot = try await snapshot()
        guard var task = snapshot.tasks[taskID], let document = DurableGenerationPlanner.document(scope: "task", ownerID: taskID, kind: "subagent.intent", in: snapshot) else { throw DurableError.corruptStorage("missing subagent intent") }
        var intent = try JSONDecoder().decode(DurableSubagentIntent.self, from: JSONEncoder().encode(document.value))
        if task.status != .completing {
            if task.status == .pending {
                task.status = .running
                let runningTask = task
                try await gate.submit { _ = try await self.storage.commit(DurableCommitBatch(tasks: [runningTask])) }
            }
            var options = StreamOptions(); if intent.settings.thinkingLevel != .off { options.reasoning = ThinkingLevel(rawValue: intent.settings.thinkingLevel.rawValue) }
            var request = DurableGenerationRequest(conversationID: intent.childConversationID, model: intent.settings.model, systemPrompt: intent.settings.instructions, transcript: intent.input, requestID: "subagent:\(taskID)", options: options)
            request.extensions = intent.settings.extensions
            if let registry = toolRegistry { request.offeredTools = await registry.snapshot() }
            let pinnedRequest = request
            let admission: DurableGenerationAdmission = try await gate.submit {
                let snapshot = try await self.storage.snapshot()
                let admission = try DurableGenerationPlanner.admitBatch(snapshot: snapshot, request: pinnedRequest)
                if admission.duplicate == nil { _ = try await self.storage.commit(admission.batch) }
                return admission
            }
            intent.generationTaskID = admission.taskID
            var afterAdmission = try await self.snapshot()
            if afterAdmission.tasks[taskID]?.abortRequested == true { _ = try await self.abort(taskID: admission.taskID) }
            let result = try await recover(taskID: admission.taskID)
            afterAdmission = try await self.snapshot()
            var report = Message(role: .user, content: [.text("Subagent \(taskID) completed: " + (result.entry?.messages?.first.map { Harness.textContent(in: $0) } ?? result.task.status.rawValue))])
            report.details = .object(["subagentTaskID": .number(Double(taskID)), "childConversationID": .number(Double(intent.childConversationID)), "status": .string(result.task.status.rawValue)])
            intent.report = report
            task = afterAdmission.tasks[taskID] ?? task; task.status = .completing
            let stagedTask = task, stagedIntent = intent
            try await gate.submit {
                var doc = document; doc.value = try DurableGenerationPlanner.encodeJSON(stagedIntent, maxBytes: DurableLimits.maxCheckpointBytes)
                _ = try await self.storage.commit(DurableCommitBatch(tasks: [stagedTask], documents: [doc]))
            }
        }
        let staged = intent
        return try await gate.submit {
            let snapshot = try await self.storage.snapshot(); guard var task = snapshot.tasks[taskID] else { throw DurableError.corruptStorage("missing subagent settlement") }
            if [.completed, .failed, .aborted].contains(task.status) { return task }
            guard let report = staged.report else { throw DurableError.corruptStorage("missing staged subagent report") }
            let reportKey = "subagent-report:\(taskID)"
            var inbox = try DurableInboxPlanner.state(snapshot: snapshot, conversationID: staged.parentConversationID)
            let existingInbox = DurableGenerationPlanner.document(scope: "conversation", ownerID: staged.parentConversationID, kind: "pi.inbox", in: snapshot)
            var ids = try DurableSubmissionPlanner.nextID(from: snapshot, reserving: existingInbox == nil ? 2 : 1)
            var submissions: [DurableSubmissionRecord] = [], documents: [DurableDocumentRecord] = []
            if !snapshot.submissions.values.contains(where: { $0.conversationID == staged.parentConversationID && $0.requestID == reportKey }) {
                guard inbox.items.count < DurableLimits.maxPublicQueue else { throw DurableError.queueFull }
                let submission = DurableSubmissionRecord(id: ids.removeFirst(), conversationID: staged.parentConversationID, requestID: reportKey, type: .input, payloadHash: "inbox:" + reportKey)
                submissions.append(submission); inbox.items.append(DurableInboxItem(submissionID: submission.id, mode: .followUp, messages: [report]))
                documents.append(DurableDocumentRecord(id: existingInbox?.id ?? ids.removeFirst(), scope: "conversation", ownerID: staged.parentConversationID, kind: "pi.inbox", value: try DurableGenerationPlanner.encodeJSON(inbox, maxBytes: DurableLimits.maxDocumentBytes), createdSeq: existingInbox?.createdSeq ?? 0))
            }
            task.status = task.abortRequested ? .aborted : .completed
            task.outcome = .object(["childConversationID": .number(Double(staged.childConversationID)), "reportQueued": .bool(true)])
            _ = try await self.storage.commit(DurableCommitBatch(tasks: [task], submissions: submissions, documents: documents))
            return task
        }
    }
}
