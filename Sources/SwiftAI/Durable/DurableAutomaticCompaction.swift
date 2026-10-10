import Foundation

extension DurableSession {
    /// Link the compaction and parent intent atomically; reopened parents reuse that exact child.
    func automaticCompaction(taskID: Int64, overflow: DurableFailureInfo? = nil) async throws -> Bool {
        let snapshot = try await self.snapshot()
        guard let parent = snapshot.tasks[taskID] else { throw DurableError.corruptStorage("missing automatic compaction parent") }
        let intent = try DurableGenerationPlanner.intent(for: parent, in: snapshot)
        let settings = try await agent(conversationID: parent.conversationID)
        let policy = settings?.compaction ?? DurableCompactionPolicy(enabled: false)
        try policy.validate()
        if let linked = intent.compactionTaskID {
            _ = try await executeCompaction(taskID: linked)
            return try await refreshAfterCompaction(parentID: taskID, compactionID: linked)
        }
        guard policy.enabled, parent.status == .running, !parent.abortRequested else { return false }
        if overflow != nil, intent.overflowCompacted == true { return false }
        if overflow == nil, intent.pressureChecked == true { return false }
        let view = try DurableContext.derive(snapshot: snapshot, conversationID: parent.conversationID, at: intent.inputEntryID)
        let estimated = AIUtilities.estimateContextTokens(AIContext(systemPrompt: intent.systemPrompt, messages: view.messages)).tokens
        let pressure = intent.model.contextWindow > 0 && estimated >= max(1, intent.model.contextWindow - policy.reserveTokens)
        if overflow == nil, !pressure {
            try await markPressureChecked(taskID: taskID)
            return false
        }
        guard let cut = DurableCompaction.selectCut(view: view, keepRecentTokens: policy.keepRecentTokens), let tail = view.entries.map(\.id).max() else {
            if overflow == nil { try await markPressureChecked(taskID: taskID) }
            return false
        }
        let compactionID: Int64 = try await gate.submit {
            let current = try await self.storage.snapshot()
            guard let task = current.tasks[taskID], var document = DurableGenerationPlanner.document(scope: "task", ownerID: taskID, kind: "generation.intent", in: current) else { throw DurableError.corruptStorage("missing compaction parent intent") }
            var pinned = try DurableGenerationPlanner.intent(for: task, in: current)
            if let linked = pinned.compactionTaskID { return linked }
            let existingUsage = DurableGenerationPlanner.document(scope: "task", ownerID: taskID, kind: "generation.overflow.usage", in: current)
            let aggregate = DurableGenerationPlanner.document(scope: "conversation", ownerID: task.conversationID, kind: "durable.usage", in: current)
            var ids = try DurableSubmissionPlanner.nextID(from: current, reserving: 4)
            let childID = ids.removeFirst(), intentID = ids.removeFirst()
            let transcript = DurableContext.orderToolResults(view.contributions.prefix(cut).flatMap { $0 })
            let childIntent = DurableCompactionIntent(model: pinned.model, conversationID: task.conversationID, tail: tail, firstKept: view.entries[cut].id, transcript: transcript, maxTokens: min(max(1, Int(Double(policy.reserveTokens) * 0.8)), pinned.model.maxTokens > 0 ? pinned.model.maxTokens : Int.max))
            let child = DurableTaskRecord(id: childID, conversationID: task.conversationID, ownerTaskID: taskID, kind: "compaction", checkpoint: .object(["phase": .string("summarize")]))
            let childDocument = DurableDocumentRecord(id: intentID, scope: "task", ownerID: childID, kind: "compaction.intent", value: try DurableGenerationPlanner.encodeJSON(childIntent, maxBytes: DurableLimits.maxCheckpointBytes))
            pinned.compactionTaskID = childID; pinned.pressureChecked = true
            if overflow != nil { pinned.overflowCompacted = true }
            document.value = try DurableGenerationPlanner.encodeJSON(pinned)
            var documents = [document, childDocument]
            if let usage = overflow?.usage, existingUsage == nil {
                let identity = "\(pinned.model.provider.rawValue)/\(pinned.model.api.rawValue)/\(pinned.model.id)"
                documents.append(DurableDocumentRecord(id: ids.removeFirst(), scope: "task", ownerID: taskID, kind: "generation.overflow.usage", value: DurableGenerationPlanner.usageValue(usage, model: identity)))
                documents.append(DurableDocumentRecord(id: aggregate?.id ?? ids.removeFirst(), scope: "conversation", ownerID: task.conversationID, kind: "durable.usage", value: try DurableGenerationPlanner.aggregateUsageValue(existing: aggregate?.value, adding: usage, model: identity), createdSeq: aggregate?.createdSeq ?? 0))
            }
            _ = try await self.storage.commit(DurableCommitBatch(tasks: [child], documents: documents))
            return childID
        }
        _ = try await executeCompaction(taskID: compactionID)
        return try await refreshAfterCompaction(parentID: taskID, compactionID: compactionID)
    }

    private func markPressureChecked(taskID: Int64) async throws {
        try await gate.submit {
            let snapshot = try await self.storage.snapshot()
            guard let task = snapshot.tasks[taskID], var document = DurableGenerationPlanner.document(scope: "task", ownerID: taskID, kind: "generation.intent", in: snapshot) else { throw DurableError.corruptStorage("missing pressure intent") }
            var intent = try DurableGenerationPlanner.intent(for: task, in: snapshot); intent.pressureChecked = true
            document.value = try DurableGenerationPlanner.encodeJSON(intent)
            _ = try await self.storage.commit(DurableCommitBatch(documents: [document]))
        }
    }

    private func refreshAfterCompaction(parentID: Int64, compactionID: Int64) async throws -> Bool {
        try await gate.submit {
            let snapshot = try await self.storage.snapshot()
            guard let parent = snapshot.tasks[parentID], let child = snapshot.tasks[compactionID], var document = DurableGenerationPlanner.document(scope: "task", ownerID: parentID, kind: "generation.intent", in: snapshot) else { throw DurableError.corruptStorage("missing automatic compaction settlement") }
            var intent = try DurableGenerationPlanner.intent(for: parent, in: snapshot)
            intent.compactionTaskID = nil; intent.pressureChecked = true
            if child.status == .completed {
                let view = try DurableContext.derive(snapshot: snapshot, conversationID: parent.conversationID)
                let otherInputs = Set(snapshot.tasks.values.filter { $0.id != parentID && $0.kind == "generation" && ![.completed, .failed, .aborted].contains($0.status) }.compactMap { task in
                    (try? DurableGenerationPlanner.intent(for: task, in: snapshot))?.inputEntryID
                })
                intent.preparedTranscript = DurableContext.orderToolResults(zip(view.entries, view.contributions).filter { !otherInputs.contains($0.0.id) }.flatMap { $0.1 })
                intent.roundMessages = []
            }
            document.value = try DurableGenerationPlanner.encodeJSON(intent)
            _ = try await self.storage.commit(DurableCommitBatch(documents: [document]))
            return child.status == .completed
        }
    }
}
