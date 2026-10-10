import Foundation

extension DurableSession {
    func scheduleGenerationRetry(taskID: Int64, failure: DurableFailureInfo) async throws -> Bool {
        guard failure.retryable == true else { return false }
        let snapshot = try await self.snapshot()
        guard let task = snapshot.tasks[taskID], task.status == .running, !task.abortRequested else { return false }
        let policy = try await agent(conversationID: task.conversationID)?.retry ?? DurableRetryPolicy(enabled: false)
        try policy.validate()
        let intent = try DurableGenerationPlanner.intent(for: task, in: snapshot)
        guard policy.enabled, intent.attempt <= policy.maxRetries else { return false }
        let delay = min(Double(policy.maxDelayMs), Double(policy.baseDelayMs) * pow(2, Double(intent.attempt - 1)))
        let deadline = Int64(Date().timeIntervalSince1970 * 1000) + Int64(delay)
        return try await gate.submit {
            let snapshot = try await self.storage.snapshot()
            guard var task = snapshot.tasks[taskID], !task.abortRequested, var document = DurableGenerationPlanner.document(scope: "task", ownerID: taskID, kind: "generation.intent", in: snapshot) else { return false }
            var intent = try DurableGenerationPlanner.intent(for: task, in: snapshot)
            let receiptKind = "generation.retry.usage.round.\(intent.round ?? 1).attempt.\(intent.attempt)"
            guard DurableGenerationPlanner.document(scope: "task", ownerID: taskID, kind: receiptKind, in: snapshot) == nil else { throw DurableError.corruptStorage("duplicate generation retry receipt") }
            var documents: [DurableDocumentRecord] = []
            if let usage = failure.usage {
                let aggregate = DurableGenerationPlanner.document(scope: "conversation", ownerID: task.conversationID, kind: "durable.usage", in: snapshot)
                let ids = try DurableSubmissionPlanner.nextID(from: snapshot, reserving: aggregate == nil ? 2 : 1)
                let identity = "\(intent.model.provider.rawValue)/\(intent.model.api.rawValue)/\(intent.model.id)"
                documents.append(DurableDocumentRecord(id: ids[0], scope: "task", ownerID: taskID, kind: receiptKind, value: DurableGenerationPlanner.usageValue(usage, model: identity)))
                documents.append(DurableDocumentRecord(id: aggregate?.id ?? ids[1], scope: "conversation", ownerID: task.conversationID, kind: "durable.usage", value: try DurableGenerationPlanner.aggregateUsageValue(existing: aggregate?.value, adding: usage, model: identity), createdSeq: aggregate?.createdSeq ?? 0))
            }
            intent.attempt += 1; intent.retryAtMs = deadline; intent.preparedTranscript = nil
            document.value = try DurableGenerationPlanner.encodeJSON(intent)
            task.checkpoint = .object(["phase": .string("retry"), "attempt": .number(Double(intent.attempt)), "until": .number(Double(deadline))])
            _ = try await self.storage.commit(DurableCommitBatch(tasks: [task], documents: documents + [document]))
            return true
        }
    }

    func prepareGenerationRetry(taskID: Int64) async throws {
        let snapshot = try await self.snapshot()
        guard let task = snapshot.tasks[taskID] else { throw DurableError.corruptStorage("missing retry task") }
        let intent = try DurableGenerationPlanner.intent(for: task, in: snapshot)
        guard let deadline = intent.retryAtMs else { return }
        let remaining = max(0, deadline - Int64(Date().timeIntervalSince1970 * 1000))
        guard remaining <= 300_000 else { throw DurableError.corruptStorage("invalid generation retry deadline") }
        if remaining > 0 { try await Task.sleep(nanoseconds: UInt64(remaining) * 1_000_000) }
        try await gate.submit {
            let snapshot = try await self.storage.snapshot()
            guard var task = snapshot.tasks[taskID], var document = DurableGenerationPlanner.document(scope: "task", ownerID: taskID, kind: "generation.intent", in: snapshot) else { throw DurableError.corruptStorage("missing retry intent") }
            var intent = try DurableGenerationPlanner.intent(for: task, in: snapshot)
            if let value = DurableGenerationPlanner.document(scope: "conversation", ownerID: task.conversationID, kind: "pi.agent", in: snapshot) {
                let settings = try DurableGenerationPlanner.decodeJSON(DurableAgentSettings.self, from: value.value)
                var model = settings.model; model.baseUrl = ""; model.headers = nil
                intent.model = model; intent.systemPrompt = settings.instructions; intent.extensions = settings.extensions
                intent.options.reasoning = settings.thinkingLevel == .off ? nil : ThinkingLevel(rawValue: settings.thinkingLevel.rawValue)
            }
            intent.retryAtMs = nil
            intent.preparedTranscript = DurableGenerationPlanner.preparedContextMessages(for: intent, in: snapshot)
            try DurableNativePreflight.validate(intent, maxBytes: DurableLimits.maxDocumentBytes)
            document.value = try DurableGenerationPlanner.encodeJSON(intent)
            task.checkpoint = DurableGenerationPlanner.checkpoint(intent: intent, phase: "running")
            _ = try await self.storage.commit(DurableCommitBatch(tasks: [task], documents: [document]))
        }
    }
}
