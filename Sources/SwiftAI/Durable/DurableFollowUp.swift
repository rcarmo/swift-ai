import Foundation

public extension DurableSession {
    /// Admit inbox input and wake its configured agent without making the caller own the run.
    func send(conversationID: Int64, messages: [Message], mode: DurableInboxMode = .followUp, requestID: String? = nil) async throws -> DurableSubmissionRecord {
        guard try await agent(conversationID: conversationID) != nil else { throw DurableError.invalidRecord("agent is not configured") }
        let submission = try await queueInput(conversationID: conversationID, messages: messages, mode: mode, requestID: requestID)
        try await scheduleFollowUps(conversationID: conversationID)
        return submission
    }

    func resumeInbox(conversationID: Int64) async throws {
        try ensureAdmitting()
        try await scheduleFollowUps(conversationID: conversationID)
    }

    func queueModes(conversationID: Int64, snapshot: DurableSnapshot) throws -> (DurableQueueMode, DurableQueueMode) {
        guard let document = DurableGenerationPlanner.document(scope: "conversation", ownerID: conversationID, kind: "pi.agent", in: snapshot) else { return (.oneAtATime, .oneAtATime) }
        let settings = try JSONDecoder().decode(DurableAgentSettings.self, from: JSONEncoder().encode(document.value))
        return (settings.steeringMode, settings.followUpMode)
    }

    func scheduleFollowUps(conversationID: Int64) async throws {
        if isClosing || isClosed { return }
        activeAdmissions += 1
        defer { activeAdmissions -= 1; finishCloseIfNeeded() }
        guard let settings = try await agent(conversationID: conversationID) else { return }
        let current = try await snapshot()
        guard !current.tasks.values.contains(where: { $0.conversationID == conversationID && ![.completed, .failed, .aborted].contains($0.status) }) else { return }
        guard current.submissions.values.contains(where: { $0.conversationID == conversationID && [.queued, .placed].contains($0.status) && $0.payloadHash?.hasPrefix("inbox:") == true }) else { return }
        if isClosing { return }
        let prompt = try await renderPrompt(conversationID: conversationID, instructions: settings.instructions, extensions: settings.extensions)
        let taskID: Int64? = try await gate.submit {
            var snapshot = try await self.storage.snapshot()
            guard !snapshot.tasks.values.contains(where: { $0.conversationID == conversationID && ![.completed, .failed, .aborted].contains($0.status) }) else { return nil }
            let boundary = try DurableInboxPlanner.boundary(snapshot: snapshot, conversationID: conversationID, at: .final, steering: settings.steeringMode, followUp: settings.followUpMode)
            if !boundary.batch.submissions.isEmpty { snapshot = try await self.storage.commit(boundary.batch) }
            let ready = snapshot.submissions.values.filter { $0.conversationID == conversationID && $0.type == .input && $0.status == .placed && $0.payloadHash?.hasPrefix("inbox:") == true }.sorted { $0.id < $1.id }
            guard let submission = ready.first, let entryID = submission.entryID else { return nil }
            var options = StreamOptions(); if settings.thinkingLevel != .off { options.reasoning = ThinkingLevel(rawValue: settings.thinkingLevel.rawValue) }
            var request = DurableGenerationRequest(conversationID: conversationID, model: settings.model, systemPrompt: prompt, transcript: snapshot.entries[entryID]?.messages ?? [], options: options)
            request.extensions = settings.extensions; request.existingSubmissionID = submission.id
            if let registry = self.toolRegistry { request.offeredTools = await registry.snapshot() }
            let admission = try DurableGenerationPlanner.admitBatch(snapshot: snapshot, request: request)
            if admission.duplicate == nil { _ = try await self.storage.commit(admission.batch) }
            return admission.taskID
        }
        if let taskID { enqueue(taskID: taskID, waiter: nil) }
    }
}
