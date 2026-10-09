import Foundation

struct DurableSessionTestingHooks: Sendable {
    var onCloseSealed: (@Sendable () -> Void)?
    var onSubmitWaiter: (@Sendable (Int64) -> Void)?
    var onCloseWaiter: (@Sendable (Int64) -> Void)?
    var onRecoveryDeferred: (@Sendable () -> Void)?
    var beforeToolExecution: (@Sendable ([Int64]) async -> Void)?
    init(onCloseSealed: (@Sendable () -> Void)? = nil, onSubmitWaiter: (@Sendable (Int64) -> Void)? = nil, onCloseWaiter: (@Sendable (Int64) -> Void)? = nil, onRecoveryDeferred: (@Sendable () -> Void)? = nil, beforeToolExecution: (@Sendable ([Int64]) async -> Void)? = nil) {
        self.onCloseSealed = onCloseSealed
        self.onSubmitWaiter = onSubmitWaiter
        self.onCloseWaiter = onCloseWaiter
        self.onRecoveryDeferred = onRecoveryDeferred
        self.beforeToolExecution = beforeToolExecution
    }
}

public actor DurableSession {
    private struct GenerationJob: Sendable {
        let id: Int64
        let taskID: Int64
        let continuation: CheckedContinuation<DurableGenerationResult, Error>?
    }

    private struct TaskWaiter {
        let id: Int64
        let continuation: CheckedContinuation<DurableGenerationResult, Error>
    }

    private struct CloseWaiter {
        let id: Int64
        let continuation: CheckedContinuation<Void, Error>
    }

    let storage: DurableStorage
    let observation = DurableObservationHub()
    public let extensionRegistry = DurableExtensionRegistry()
    let gate: DurableMutationGate
    private let testingHooks: DurableSessionTestingHooks?
    private let capacity: Int
    private let toolRegistry: DurableToolRegistry?
    let liveConnectionResolver: DurableLiveConnectionResolver?
    private var queue: [GenerationJob] = []
    private var worker: Task<Void, Never>?
    private var nextJobID: Int64 = 0
    private var scheduledTaskIDs = Set<Int64>()
    private var runningTaskIDs = Set<Int64>()
    private var taskWaiters: [Int64: [TaskWaiter]] = [:]
    private var nextTaskWaiterID: Int64 = 0
    private var observerReservations = 0
    var activeAdmissions = 0
    var runningCompactions = Set<Int64>()
    private var recoverySweepRequested = false
    private var isClosing = false
    private var isClosed = false
    private var executorFailure: Error?
    private var closeError: Error?
    private var closeWaiters: [CloseWaiter] = []
    private var nextCloseWaiterID: Int64 = 0
    private var closeTask: Task<Void, Never>?
    private var toolCancellationSignals: [Int64: DurableCancellationSignal] = [:]

    public init(storage: DurableStorage) {
        self.storage = DurableObservedStorage(underlying: storage, hub: observation)
        self.gate = DurableMutationGate()
        self.testingHooks = nil
        self.capacity = DurableLimits.maxPublicQueue
        self.toolRegistry = nil
        self.liveConnectionResolver = nil
    }

    public init(storage: DurableStorage, toolRegistry: DurableToolRegistry?, liveConnectionResolver: DurableLiveConnectionResolver? = nil) {
        self.storage = DurableObservedStorage(underlying: storage, hub: observation)
        self.gate = DurableMutationGate()
        self.testingHooks = nil
        self.capacity = DurableLimits.maxPublicQueue
        self.toolRegistry = toolRegistry
        self.liveConnectionResolver = liveConnectionResolver
    }

    init(storage: DurableStorage, testingHooks: DurableSessionTestingHooks = DurableSessionTestingHooks(), capacity: Int = DurableLimits.maxPublicQueue, toolRegistry: DurableToolRegistry? = nil, liveConnectionResolver: DurableLiveConnectionResolver? = nil) {
        precondition(capacity > 0 && capacity <= DurableLimits.maxPublicQueue)
        self.storage = DurableObservedStorage(underlying: storage, hub: observation)
        self.gate = DurableMutationGate()
        self.testingHooks = testingHooks
        self.capacity = capacity
        self.toolRegistry = toolRegistry
        self.liveConnectionResolver = liveConnectionResolver
    }

    public func snapshot() async throws -> DurableSnapshot {
        if let executorFailure { throw executorFailure }
        return try await storage.snapshot()
    }

    public func inspection() async throws -> DurableInspection { DurableInspection(snapshot: try await snapshot()) }

    public func createConversation(parentConversationID: Int64? = nil, parentEntryID: Int64? = nil) async throws -> DurableConversationRecord {
        try ensureAdmitting()
        return try await gate.submit {
            let snapshot = try await self.storage.snapshot()
            let id = try DurableSubmissionPlanner.nextID(from: snapshot).first!
            let record = DurableConversationRecord(id: id, parentConversationID: parentConversationID, parentEntryID: parentEntryID)
            _ = try await self.storage.commit(DurableCommitBatch(conversations: [record]))
            return record
        }
    }

    public func appendEntry(conversationID: Int64, kind: String, messages: [Message]? = nil, data: JSONValue? = nil) async throws -> DurableEntryRecord {
        try ensureAdmitting()
        return try await gate.submit {
            let snapshot = try await self.storage.snapshot()
            let id = try DurableSubmissionPlanner.nextID(from: snapshot).first!
            let record = DurableEntryRecord(id: id, conversationID: conversationID, kind: kind, messages: messages, data: data)
            _ = try await self.storage.commit(DurableCommitBatch(entries: [record]))
            return record
        }
    }

    public func submit(_ request: DurableGenerationRequest) async throws -> DurableGenerationResult {
        try ensureAdmitting()
        guard activeAdmissions + scheduledTaskIDs.count + runningTaskIDs.count < capacity else { throw DurableError.queueFull }
        guard observerReservations + taskWaiters.values.reduce(0, { $0 + $1.count }) < capacity else { throw DurableError.queueFull }
        activeAdmissions += 1
        observerReservations += 1
        var configuredRequest = request
        if let toolRegistry { configuredRequest.offeredTools = await toolRegistry.snapshot() }
        if !configuredRequest.extensions.isEmpty {
            do { configuredRequest.systemPrompt = try await renderPrompt(conversationID: request.conversationID, instructions: request.systemPrompt, extensions: configuredRequest.extensions) }
            catch { activeAdmissions -= 1; observerReservations -= 1; finishCloseIfNeeded(); throw error }
        }
        let admittedRequest = configuredRequest
        let admission: DurableGenerationAdmission
        do {
            admission = try await gate.submit { () async throws -> DurableGenerationAdmission in
                let snapshot = try await self.storage.snapshot()
                let admission = try DurableGenerationPlanner.admitBatch(snapshot: snapshot, request: admittedRequest)
                if admission.duplicate == nil { _ = try await self.storage.commit(admission.batch) }
                return admission
            }
        } catch {
            activeAdmissions -= 1
            observerReservations -= 1
            wakeDeferredRecovery()
            finishCloseIfNeeded()
            throw error
        }
        activeAdmissions -= 1
        if let duplicate = admission.duplicate, [.completed, .failed, .aborted].contains(duplicate.task.status) {
            observerReservations -= 1
            wakeDeferredRecovery()
            finishCloseIfNeeded()
            return duplicate
        }
        enqueue(taskID: admission.taskID, waiter: nil)
        observerReservations -= 1
        wakeDeferredRecovery()
        finishCloseIfNeeded()
        guard nextTaskWaiterID < DurableLimits.maxExactInteger else { throw DurableError.invalidRecord("submit waiter id overflow") }
        nextTaskWaiterID += 1
        let waiterID = nextTaskWaiterID
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled { continuation.resume(throwing: CancellationError()); return }
                attachTaskWaiter(taskID: admission.taskID, waiter: TaskWaiter(id: waiterID, continuation: continuation))
                testingHooks?.onSubmitWaiter?(waiterID)
            }
        } onCancel: {
            Task { await self.cancelTaskWaiter(taskID: admission.taskID, waiterID: waiterID) }
        }
    }

    public func recoveryPlan() async throws -> DurableRecoveryPlan { DurableRecovery.plan(from: try await storage.snapshot()) }

    public func resumeQueued() async throws -> DurableRecoveryPlan {
        try ensureAdmitting()
        activeAdmissions += 1
        let snapshot: DurableSnapshot
        do { snapshot = try await storage.snapshot() }
        catch {
            activeAdmissions -= 1
            finishCloseIfNeeded()
            throw error
        }
        activeAdmissions -= 1
        recoverySweepRequested = snapshot.tasks.values.contains { $0.kind == "generation" && [.pending, .running, .waiting, .completing].contains($0.status) }
        enqueueRecoverable(from: snapshot)
        wakeDeferredRecovery()
        finishCloseIfNeeded()
        return DurableRecovery.plan(from: snapshot)
    }

    public func abort(taskID: Int64) async throws -> DurableTaskRecord {
        try ensureAdmitting()
        let terminal: DurableTaskRecord = try await gate.submit {
            let snapshot = try await self.storage.snapshot()
            guard let task = snapshot.tasks[taskID] else { throw DurableError.invalidRecord("missing abort task") }
            if [.completed, .failed, .aborted].contains(task.status) { return task }
            var updates: [DurableTaskRecord] = []
            func abortedCopy(_ value: DurableTaskRecord) -> DurableTaskRecord {
                let noOwnedChildren = value.kind == "generation" && value.status != .running && !snapshot.tasks.values.contains { $0.ownerTaskID == value.id && ![.completed, .failed, .aborted].contains($0.status) }
                let pendingGeneration = value.kind == "generation" && value.status == .pending
                let status: DurableTaskStatus = pendingGeneration || noOwnedChildren ? .aborted : value.status
                return DurableTaskRecord(id: value.id, conversationID: value.conversationID, ownerTaskID: value.ownerTaskID, kind: value.kind, status: status, checkpoint: value.checkpoint, abortRequested: true, background: value.background, outcome: status == .aborted ? .object(["code": .string("aborted")]) : value.outcome, createdSeq: value.createdSeq)
            }
            updates.append(abortedCopy(task))
            if task.kind == "generation" { for child in snapshot.tasks.values where child.ownerTaskID == task.id && ![.completed, .failed, .aborted].contains(child.status) { updates.append(abortedCopy(child)) } }
            _ = try await self.storage.commit(DurableCommitBatch(tasks: updates))
            return updates[0]
        }
        if terminal.kind == "generation" {
            let snapshot = try await storage.snapshot()
            for child in snapshot.tasks.values where child.ownerTaskID == taskID { toolCancellationSignals[child.id]?.cancel() }
        } else { toolCancellationSignals[taskID]?.cancel() }
        return terminal
    }

    public func close() async throws {
        if isClosed {
            if let closeError { throw closeError }
            if let executorFailure { throw executorFailure }
            return
        }
        isClosing = true
        await observation.close()
        await toolRegistry?.seal()
        testingHooks?.onCloseSealed?()
        guard closeWaiters.count < capacity else { startCommonCloseIfReady(); throw DurableError.queueFull }
        guard nextCloseWaiterID < DurableLimits.maxExactInteger else { startCommonCloseIfReady(); throw DurableError.invalidRecord("close waiter id overflow") }
        nextCloseWaiterID += 1
        let waiterID = nextCloseWaiterID
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled { continuation.resume(throwing: CancellationError()); startCommonCloseIfReady(); return }
                closeWaiters.append(CloseWaiter(id: waiterID, continuation: continuation))
                testingHooks?.onCloseWaiter?(waiterID)
                startCommonCloseIfReady()
            }
        } onCancel: {
            Task { await self.cancelCloseWaiter(id: waiterID) }
        }
    }

    private func nextJobIdentifier() throws -> Int64 {
        guard nextJobID < DurableLimits.maxExactInteger else { throw DurableError.invalidRecord("generation job id overflow") }
        nextJobID += 1
        return nextJobID
    }

    private func enqueueRecoverable(from snapshot: DurableSnapshot) {
        let available = max(0, capacity - activeAdmissions - scheduledTaskIDs.count - runningTaskIDs.count)
        let recoverable = snapshot.tasks.values
            .filter { task in
                guard task.kind == "generation", [.pending, .running, .waiting, .completing].contains(task.status), !scheduledTaskIDs.contains(task.id), !runningTaskIDs.contains(task.id) else { return false }
                if let owner = task.ownerTaskID, snapshot.tasks[owner]?.kind == "generation" { return false }
                return true
            }
            .sorted { $0.id < $1.id }
        for task in recoverable.prefix(available) { enqueue(taskID: task.id, waiter: nil) }
        recoverySweepRequested = recoverable.count > available
        if recoverySweepRequested, available == 0 { testingHooks?.onRecoveryDeferred?() }
    }

    private func wakeDeferredRecovery() {
        if recoverySweepRequested, worker == nil { ensureWorker() }
    }

    private func enqueue(taskID: Int64, waiter: TaskWaiter?) {
        if let waiter { attachTaskWaiter(taskID: taskID, waiter: waiter) }
        guard !scheduledTaskIDs.contains(taskID), !runningTaskIDs.contains(taskID) else { return }
        do {
            scheduledTaskIDs.insert(taskID)
            queue.append(GenerationJob(id: try nextJobIdentifier(), taskID: taskID, continuation: nil))
            ensureWorker()
        } catch {
            scheduledTaskIDs.remove(taskID)
            let waiters = taskWaiters.removeValue(forKey: taskID) ?? []
            for waiter in waiters { waiter.continuation.resume(throwing: error) }
        }
    }

    private func ensureWorker() {
        guard worker == nil else { return }
        worker = Task { await self.runWorker() }
    }

    private func runWorker() async {
        while true {
            if queue.isEmpty, recoverySweepRequested {
                do { enqueueRecoverable(from: try await storage.snapshot()) }
                catch { failExecutor(error); return }
            }
            guard !queue.isEmpty else {
                worker = nil
                finishCloseIfNeeded()
                return
            }
            let job = queue.removeFirst()
            scheduledTaskIDs.remove(job.taskID)
            runningTaskIDs.insert(job.taskID)
            do {
                let snapshot = try await storage.snapshot()
                if snapshot.tasks[job.taskID]?.kind == "tool" {
                    try await executeToolChild(job.taskID)
                    runningTaskIDs.remove(job.taskID)
                    if let parentID = (try await storage.snapshot()).tasks[job.taskID]?.ownerTaskID { try await resumeWaitingParent(parentID) }
                    continue
                }
                let result = try await recover(taskID: job.taskID)
                runningTaskIDs.remove(job.taskID)
                let outcome: Result<DurableGenerationResult, Error> = .success(result)
                resumeTaskWaiters(taskID: job.taskID, result: outcome)
            } catch {
                runningTaskIDs.remove(job.taskID)
                resumeTaskWaiters(taskID: job.taskID, result: .failure(error))
                failExecutor(error)
                return
            }
        }
    }

    private func recover(taskID: Int64) async throws -> DurableGenerationResult {
        let snapshot = try await storage.snapshot()
        guard let task = snapshot.tasks[taskID] else { throw DurableError.corruptStorage("missing recovery task") }
        let intent = try DurableGenerationPlanner.intent(for: task, in: snapshot)
        let submission = snapshot.submissions.values.first { $0.entryID == intent.inputEntryID && $0.conversationID == intent.conversationID }
        if task.status == .waiting {
            let childIDs = task.checkpoint?.objectValue?["childIDs"]?.arrayValue?.compactMap { $0.doubleValue.map(Int64.init) } ?? []
            guard !childIDs.isEmpty else { throw DurableError.corruptStorage("waiting generation has no tool children") }
            for childID in childIDs { try await executeToolChild(childID) }
            try await resumeWaitingParent(taskID)
            let resumed = try await storage.snapshot(); guard let resumedTask = resumed.tasks[taskID] else { throw DurableError.corruptStorage("missing resumed generation") }
            if resumedTask.status == .aborted { return DurableGenerationResult(task: resumedTask, submission: submission.flatMap { resumed.submissions[$0.id] }, entry: nil) }
            let resumedIntent = try DurableGenerationPlanner.intent(for: resumedTask, in: resumed)
            return try await run(taskID: taskID, submissionID: submission?.id, inputEntryID: resumedIntent.inputEntryID, intent: resumedIntent, startIfPending: false)
        }
        if [.completed, .failed, .aborted].contains(task.status) {
            let answerID = submission?.answerID
            let answer = answerID.flatMap { snapshot.entries[$0] } ?? snapshot.entries.values.first { $0.byTaskID == task.id && $0.kind == "assistant" }
            return DurableGenerationResult(task: task, submission: submission, entry: task.status == .completed ? answer : nil)
        }
        if let terminal = try DurableGenerationPlanner.stagedTerminal(for: task) {
            return try await settleSuccess(taskID: taskID, submissionID: submission?.id, inputEntryID: intent.inputEntryID, terminal: terminal)
        }
        if let failure = try DurableGenerationPlanner.stagedFailure(for: task) {
            return try await settleFailure(taskID: taskID, submissionID: submission?.id, inputEntryID: intent.inputEntryID, failure: failure)
        }
        return try await run(taskID: taskID, submissionID: submission?.id, inputEntryID: intent.inputEntryID, intent: intent, startIfPending: task.status == .pending)
    }

    private func run(taskID: Int64, submissionID: Int64?, inputEntryID: Int64, intent: DurableGenerationIntent, startIfPending: Bool) async throws -> DurableGenerationResult {
        if startIfPending {
            do {
                try await gate.submit {
                    let snapshot = try await self.storage.snapshot()
                    guard let pending = snapshot.tasks[taskID] else { throw DurableError.corruptStorage("missing admitted generation task") }
                    if pending.status == .pending { _ = try await self.storage.commit(try DurableGenerationPlanner.runningBatch(snapshot: snapshot, task: pending, intent: intent)) }
                }
            } catch let error as DurableError {
                if case .invalidRecord = error {
                    let failure = DurableFailureInfo(code: "context_limit", usage: nil, diagnostics: nil)
                    try await gate.submit {
                        let snapshot = try await self.storage.snapshot()
                        guard let pending = snapshot.tasks[taskID] else { throw DurableError.corruptStorage("missing context-limit task") }
                        _ = try await self.storage.commit(try DurableGenerationPlanner.runningContextFailureBatch(task: pending, failure: failure))
                    }
                    return try await settleFailure(taskID: taskID, submissionID: submissionID, inputEntryID: inputEntryID, failure: failure)
                }
                throw error
            }
        }
        let dispatchIntent: DurableGenerationIntent
        let contextSnapshot = try await storage.snapshot()
        if let task = contextSnapshot.tasks[taskID] { dispatchIntent = try DurableGenerationPlanner.intent(for: task, in: contextSnapshot) }
        else { dispatchIntent = intent }
        let beforeDispatch = try await storage.snapshot()
        if beforeDispatch.tasks[taskID]?.abortRequested == true { return try await settleAbortedGeneration(taskID: taskID, submissionID: submissionID, inputEntryID: inputEntryID, usage: nil) }
        if dispatchIntent.round ?? 1 > 8 { return try await settleFailure(taskID: taskID, submissionID: submissionID, inputEntryID: inputEntryID, failure: DurableFailureInfo(code: "tool_round_limit", usage: nil, diagnostics: nil)) }
        let terminal: DurableStreamTerminal
        do {
            let (model, options) = try await resolvedDispatch(for: dispatchIntent)
            var context = DurableGenerationPlanner.context(for: dispatchIntent, in: contextSnapshot)
            let extensions = try await extensionRegistry.snapshot(names: dispatchIntent.extensions ?? [])
            for value in extensions { if let hook = value.hooks.beforeRequest { context = try await hook(context) } }
            terminal = try await DurableGenerationPlanner.collectTerminal(model: model, context: context, options: options)
            for value in extensions {
                if let hook = value.hooks.afterResponse {
                    do { try await hook(terminal.message) }
                    catch { return try await settleFailure(taskID: taskID, submissionID: submissionID, inputEntryID: inputEntryID, failure: DurableFailureInfo(code: "after_response_hook", usage: terminal.usage, diagnostics: terminal.diagnostics)) }
                }
            }
        } catch DurableGenerationFailure.failure(let failure) {
            return try await settleFailure(taskID: taskID, submissionID: submissionID, inputEntryID: inputEntryID, failure: failure)
        } catch DurableGenerationFailure.outputLimit(let failure) {
            return try await settleFailure(taskID: taskID, submissionID: submissionID, inputEntryID: inputEntryID, failure: failure)
        } catch {
            return try await settleFailure(taskID: taskID, submissionID: submissionID, inputEntryID: inputEntryID, failure: DurableFailureInfo(code: DurableGenerationPlanner.errorCode(String(describing: error)), usage: nil, diagnostics: nil))
        }
        let afterProvider = try await storage.snapshot()
        if afterProvider.tasks[taskID]?.abortRequested == true { return try await settleAbortedGeneration(taskID: taskID, submissionID: submissionID, inputEntryID: inputEntryID, usage: terminal.usage) }
        if terminal.stopReason == .toolUse {
            do {
                try await processToolRound(taskID: taskID, terminal: terminal)
                let nextSnapshot = try await storage.snapshot()
                guard let nextTask = nextSnapshot.tasks[taskID] else { throw DurableError.corruptStorage("missing waiting generation") }
                if nextTask.status == .aborted { return DurableGenerationResult(task: nextTask, submission: submissionID.flatMap { nextSnapshot.submissions[$0] }, entry: nil) }
                let nextIntent = try DurableGenerationPlanner.intent(for: nextTask, in: nextSnapshot)
                return try await run(taskID: taskID, submissionID: submissionID, inputEntryID: inputEntryID, intent: nextIntent, startIfPending: false)
            } catch DurableGenerationFailure.failure(let failure) {
                return try await settleRoundFailure(taskID: taskID, submissionID: submissionID, inputEntryID: inputEntryID, terminal: terminal, failure: failure)
            } catch let error as DurableError {
                return try await settleRoundFailure(taskID: taskID, submissionID: submissionID, inputEntryID: inputEntryID, terminal: terminal, failure: DurableFailureInfo(code: DurableGenerationPlanner.errorCode(String(describing: error)), usage: terminal.usage, diagnostics: terminal.diagnostics))
            }
        }
        do { return try await settleSuccess(taskID: taskID, submissionID: submissionID, inputEntryID: inputEntryID, terminal: terminal) }
        catch DurableGenerationFailure.outputLimit(let failure) { return try await settleFailure(taskID: taskID, submissionID: submissionID, inputEntryID: inputEntryID, failure: failure) }
    }

    func providerSessionID(conversationID: Int64) async throws -> String {
        try await gate.submit {
            let snapshot = try await self.storage.snapshot()
            if let document = DurableGenerationPlanner.document(scope: "conversation", ownerID: conversationID, kind: "pi.provider", in: snapshot) {
                guard let id = document.value.objectValue?["sessionId"]?.stringValue, !id.isEmpty else { throw DurableError.corruptStorage("invalid provider session ID") }
                return id
            }
            let id = AIUtilities.uuidv7()
            let documentID = try DurableSubmissionPlanner.nextID(from: snapshot, reserving: 1)[0]
            let document = DurableDocumentRecord(id: documentID, scope: "conversation", ownerID: conversationID, kind: "pi.provider", value: .object(["sessionId": .string(id)]))
            _ = try await self.storage.commit(DurableCommitBatch(documents: [document]))
            return id
        }
    }

    private func resolvedDispatch(for intent: DurableGenerationIntent) async throws -> (Model, StreamOptions) {
        guard var current = await AIRegistry.shared.model(provider: intent.model.provider, id: intent.model.id), current.api == intent.model.api else { throw DurableError.invalidRecord("missing_model") }
        var options = intent.options.streamOptions()
        options.sessionId = try await providerSessionID(conversationID: intent.conversationID)
        if let liveConnectionResolver {
            do {
                let connection = try await liveConnectionResolver(intent.model)
                if let endpoint = connection.endpoint { current.baseUrl = endpoint }
                if let headers = connection.headers { current.headers = headers }
                options.apiKey = connection.apiKey
                options.bearerToken = connection.bearerToken
            } catch { throw DurableError.invalidRecord("live_connection_failed") }
        }
        let endpoint = current.baseUrl
        let headers = current.headers
        current = intent.model
        current.baseUrl = endpoint
        current.headers = headers
        let provider = await AIRegistry.shared.apiProvider(for: current.api)
        guard !current.baseUrl.isEmpty || provider != nil else { throw DurableError.invalidRecord("missing_endpoint") }
        return (current, options)
    }

    private func settleAbortedGeneration(taskID: Int64, submissionID: Int64?, inputEntryID: Int64, usage: Usage?) async throws -> DurableGenerationResult {
        try await gate.submit {
            let snapshot = try await self.storage.snapshot(); guard let task = snapshot.tasks[taskID] else { throw DurableError.corruptStorage("missing aborted generation") }
            if task.status == .aborted { return DurableGenerationResult(task: task, submission: submissionID.flatMap { snapshot.submissions[$0] }, entry: nil) }
            let intent = try DurableGenerationPlanner.intent(for: task, in: snapshot), round = intent.round ?? 1
            let usageKind = "generation.usage.round.\(round)", modelIdentity = "\(intent.model.provider.rawValue)/\(intent.model.api.rawValue)/\(intent.model.id)"
            let existing = DurableGenerationPlanner.document(scope: "task", ownerID: taskID, kind: usageKind, in: snapshot)
            let existingAggregate = DurableGenerationPlanner.document(scope: "conversation", ownerID: task.conversationID, kind: "durable.usage", in: snapshot)
            var documents: [DurableDocumentRecord] = []
            var ids = try DurableSubmissionPlanner.nextID(from: snapshot, reserving: (usage != nil && existing == nil ? 1 : 0) + (usage != nil && existingAggregate == nil ? 1 : 0) + 1)
            func take() -> Int64 { ids.removeFirst() }
            if let usage, existing == nil {
                documents.append(DurableDocumentRecord(id: take(), scope: "task", ownerID: taskID, kind: usageKind, value: DurableGenerationPlanner.usageValue(usage, model: modelIdentity)))
                do { documents.append(DurableDocumentRecord(id: existingAggregate?.id ?? take(), scope: "conversation", ownerID: task.conversationID, kind: "durable.usage", value: try DurableGenerationPlanner.aggregateUsageValue(existing: existingAggregate?.value, adding: usage, model: modelIdentity), createdSeq: existingAggregate?.createdSeq ?? 0)) }
                catch { documents.append(DurableDocumentRecord(id: take(), scope: "task", ownerID: taskID, kind: "generation.aggregate-incomplete", value: .object(["code": .string("usage_overflow"), "aggregatePreserved": .bool(true)]))) }
            }
            let aborted = DurableTaskRecord(id: task.id, conversationID: task.conversationID, ownerTaskID: task.ownerTaskID, kind: task.kind, status: .aborted, checkpoint: task.checkpoint, abortRequested: true, background: task.background, outcome: .object(["code": .string("aborted")]), createdSeq: task.createdSeq)
            let submission = submissionID.flatMap { snapshot.submissions[$0] }.map { DurableSubmissionRecord(id: $0.id, conversationID: $0.conversationID, requestID: $0.requestID, type: $0.type, payloadHash: $0.payloadHash, status: .withdrawn, entryID: inputEntryID, reason: "aborted", createdSeq: $0.createdSeq) }
            _ = try await self.storage.commit(DurableCommitBatch(tasks: [aborted], submissions: submission.map { [$0] } ?? [], documents: documents))
            let final = try await self.storage.snapshot(); return DurableGenerationResult(task: final.tasks[taskID]!, submission: submissionID.flatMap { final.submissions[$0] }, entry: nil)
        }
    }

    private func settleRoundFailure(taskID: Int64, submissionID: Int64?, inputEntryID: Int64, terminal: DurableStreamTerminal, failure: DurableFailureInfo) async throws -> DurableGenerationResult {
        try await gate.submit {
            let snapshot = try await self.storage.snapshot(); guard let task = snapshot.tasks[taskID] else { throw DurableError.corruptStorage("missing round failure task") }
            let intent = try DurableGenerationPlanner.intent(for: task, in: snapshot); let round = intent.round ?? 1
            let existing = DurableGenerationPlanner.document(scope: "task", ownerID: taskID, kind: "generation.usage.round.\(round)", in: snapshot)
            if existing == nil {
                let id = try DurableSubmissionPlanner.nextID(from: snapshot).first!
                _ = try await self.storage.commit(DurableCommitBatch(documents: [DurableDocumentRecord(id: id, scope: "task", ownerID: taskID, kind: "generation.usage.round.\(round)", value: DurableGenerationPlanner.usageValue(terminal.usage, model: "\(intent.model.provider.rawValue)/\(intent.model.api.rawValue)/\(intent.model.id)"))]))
            }
        }
        return try await settleFailure(taskID: taskID, submissionID: submissionID, inputEntryID: inputEntryID, failure: failure)
    }

    private func processToolRound(taskID: Int64, terminal: DurableStreamTerminal) async throws {
        guard let registry = toolRegistry else { throw DurableGenerationFailure.failure(DurableFailureInfo(code: "tool_use_unsupported", usage: terminal.usage, diagnostics: terminal.diagnostics)) }
        let calls = terminal.message.content.filter { $0.type == "toolCall" }
        guard !calls.isEmpty, calls.count <= 32 else { throw DurableGenerationFailure.failure(DurableFailureInfo(code: "tool_call_limit", usage: terminal.usage, diagnostics: terminal.diagnostics)) }
        let childIDs: [Int64] = try await gate.submit {
            let snapshot = try await self.storage.snapshot()
            guard let parent = snapshot.tasks[taskID] else { throw DurableError.corruptStorage("missing tool parent") }
            var intent = try DurableGenerationPlanner.intent(for: parent, in: snapshot)
            guard (intent.round ?? 1) <= 8 else { throw DurableGenerationFailure.failure(DurableFailureInfo(code: "tool_round_limit", usage: terminal.usage, diagnostics: terminal.diagnostics)) }
            let bindings = Dictionary(uniqueKeysWithValues: (intent.offeredTools ?? []).map { ($0.definition.name, $0) })
            let providerIDs = calls.compactMap(\.id)
            guard providerIDs.count == calls.count, Set(providerIDs).count == providerIDs.count else { throw DurableGenerationFailure.failure(DurableFailureInfo(code: "duplicate_tool_call_id", usage: terminal.usage, diagnostics: terminal.diagnostics)) }
            var ids = try DurableSubmissionPlanner.nextID(from: snapshot, reserving: 1 + calls.count * 3 + 2)
            func take() -> Int64 { ids.removeFirst() }
            let assistantID = take()
            var children: [DurableTaskRecord] = []
            var documents: [DurableDocumentRecord] = []
            var plannedChildIDs: [Int64] = []
            for call in calls {
                guard let providerID = call.id, !providerID.isEmpty, providerID.utf8.count <= 256, let name = call.name, let binding = bindings[name], let arguments = call.arguments else { throw DurableGenerationFailure.failure(DurableFailureInfo(code: "invalid_tool_call", usage: terminal.usage, diagnostics: terminal.diagnostics)) }
                try DurableToolSchema.validate(arguments: arguments, against: binding.definition.parameters)
                let childID = take(), intentID = take(), resultPlaceholderID = take()
                plannedChildIDs.append(childID)
                let toolIntent = DurableToolIntent(parentTaskID: taskID, providerCallID: providerID, durableToolID: "tool-\(childID)", idempotencyKey: "tool-\(childID)-1", binding: binding, originalArguments: arguments, executionArguments: arguments, logicalAttempt: 1)
                children.append(DurableTaskRecord(id: childID, conversationID: parent.conversationID, ownerTaskID: taskID, kind: "tool", status: .pending, checkpoint: .object(["phase": .string("pending"), "resultPlaceholderID": .number(Double(resultPlaceholderID))])))
                documents.append(DurableDocumentRecord(id: intentID, scope: "task", ownerID: childID, kind: "tool.intent", value: try DurableGenerationPlanner.encodeJSON(toolIntent)))
            }
            let round = intent.round ?? 1
            let usageID = take(), aggregateID = take()
            let existingAggregate = DurableGenerationPlanner.document(scope: "conversation", ownerID: parent.conversationID, kind: "durable.usage", in: snapshot)
            let aggregateValue = try DurableGenerationPlanner.aggregateUsageValue(existing: existingAggregate?.value, adding: terminal.usage, model: "\(intent.model.provider.rawValue)/\(intent.model.api.rawValue)/\(intent.model.id)")
            let modelIdentity = "\(intent.model.provider.rawValue)/\(intent.model.api.rawValue)/\(intent.model.id)"
            documents.append(DurableDocumentRecord(id: usageID, scope: "task", ownerID: taskID, kind: "generation.usage.round.\(round)", value: DurableGenerationPlanner.usageValue(terminal.usage, model: modelIdentity)))
            documents.append(DurableDocumentRecord(id: existingAggregate?.id ?? aggregateID, scope: "conversation", ownerID: parent.conversationID, kind: "durable.usage", value: aggregateValue, createdSeq: existingAggregate?.createdSeq ?? 0))
            let assistant = DurableEntryRecord(id: assistantID, conversationID: parent.conversationID, kind: "assistant-tool-call", messages: [terminal.message], byTaskID: taskID)
            intent.roundMessages = (intent.roundMessages ?? []) + [terminal.message]
            let intentDoc = try Self.toolIntentDocument(snapshot: snapshot, taskID: taskID, intent: intent)
            let waiting = DurableTaskRecord(id: parent.id, conversationID: parent.conversationID, ownerTaskID: parent.ownerTaskID, kind: parent.kind, status: .waiting, checkpoint: .object(["phase": .string("waiting_tools"), "childIDs": .array(plannedChildIDs.map { .number(Double($0)) })]), abortRequested: parent.abortRequested, background: parent.background, outcome: parent.outcome, createdSeq: parent.createdSeq)
            _ = try await self.storage.commit(DurableCommitBatch(entries: [assistant], tasks: [waiting] + children, documents: documents + [intentDoc]))
            return plannedChildIDs
        }
        if let beforeToolExecution = testingHooks?.beforeToolExecution { await beforeToolExecution(childIDs) }
        for childID in childIDs { try await executeToolChild(childID) }
        try await resumeWaitingParent(taskID)
        _ = registry
    }

    private nonisolated static func toolIntentDocument(snapshot: DurableSnapshot, taskID: Int64, intent: DurableGenerationIntent) throws -> DurableDocumentRecord {
        guard let existing = DurableGenerationPlanner.document(scope: "task", ownerID: taskID, kind: "generation.intent", in: snapshot) else { throw DurableError.corruptStorage("missing parent intent") }
        return DurableDocumentRecord(id: existing.id, scope: existing.scope, ownerID: existing.ownerID, kind: existing.kind, value: try DurableGenerationPlanner.encodeJSON(intent), createdSeq: existing.createdSeq)
    }

    private func executeToolChild(_ childID: Int64) async throws {
        var snapshot = try await storage.snapshot()
        guard var child = snapshot.tasks[childID], child.kind == "tool", let intentDoc = DurableGenerationPlanner.document(scope: "task", ownerID: childID, kind: "tool.intent", in: snapshot) else { throw DurableError.corruptStorage("missing tool child intent") }
        let intent = try DurableGenerationPlanner.decodeJSON(DurableToolIntent.self, from: intentDoc.value)
        if [.completed, .failed, .aborted].contains(child.status) { return }
        if child.abortRequested, child.status == .pending {
            try await gate.submit {
                let snapshot = try await self.storage.snapshot(); guard let current = snapshot.tasks[childID] else { throw DurableError.corruptStorage("missing aborted tool child") }
                let running = DurableTaskRecord(id: current.id, conversationID: current.conversationID, ownerTaskID: current.ownerTaskID, kind: current.kind, status: .running, checkpoint: .object(["phase": .string("aborting")]), abortRequested: true, background: current.background, outcome: current.outcome, createdSeq: current.createdSeq)
                _ = try await self.storage.commit(DurableCommitBatch(tasks: [running]))
            }
            let updated = try await storage.snapshot(); child = updated.tasks[childID]!
            let aborted = DurableStagedToolResult(content: "Tool execution was aborted", isError: true, usage: nil, documents: [], code: "aborted", billingUnknown: false)
            try await stageAndFinalizeToolChild(child: child, intent: intent, result: aborted); return
        }
        if child.status == .completing, let staged = child.checkpoint?.objectValue?["result"] { let result = try DurableGenerationPlanner.decodeJSON(DurableStagedToolResult.self, from: staged); try await finalizeToolChild(child: child, intent: intent, result: result); return }
        let replayingStarted = child.status == .running
        if replayingStarted, intent.binding.replayPolicy == .unsafe {
            let interrupted = DurableStagedToolResult(content: "Tool execution was interrupted", isError: true, usage: nil, documents: [], code: "interrupted", billingUnknown: true)
            try await stageAndFinalizeToolChild(child: child, intent: intent, result: interrupted); return
        }
        try DurableToolSchema.validateDefinition(intent.binding.definition)
        guard try DurableToolSchema.identity(intent.binding.definition.parameters) == intent.binding.schemaIdentity else { throw DurableError.corruptStorage("tool binding schema identity mismatch") }
        try DurableToolSchema.validate(arguments: intent.executionArguments, against: intent.binding.definition.parameters)
        guard let registration = await toolRegistry?.resolve(intent.binding) else {
            let unavailable = DurableStagedToolResult(content: "Tool implementation unavailable", isError: true, usage: nil, documents: [], code: "tool_unavailable", billingUnknown: replayingStarted)
            try await stageAndFinalizeToolChild(child: child, intent: intent, result: unavailable); return
        }
        try await gate.submit {
            let current = try await self.storage.snapshot(); guard let value = current.tasks[childID] else { throw DurableError.corruptStorage("missing tool child") }
            let running = DurableTaskRecord(id: value.id, conversationID: value.conversationID, ownerTaskID: value.ownerTaskID, kind: value.kind, status: .running, checkpoint: .object(["phase": .string("started")]), abortRequested: value.abortRequested, background: value.background, outcome: value.outcome, createdSeq: value.createdSeq)
            _ = try await self.storage.commit(DurableCommitBatch(tasks: [running]))
        }
        snapshot = try await storage.snapshot(); child = snapshot.tasks[childID]!
        var staged: DurableStagedToolResult
        var knownUsage: Usage?
        var invalidUsage = false
        let signal = DurableCancellationSignal(); toolCancellationSignals[childID] = signal
        defer { toolCancellationSignals.removeValue(forKey: childID) }
        if child.abortRequested { signal.cancel() }
        let startedAt = DispatchTime.now().uptimeNanoseconds
        do {
            let output = try await registration.execute(DurableToolExecution(durableToolID: intent.durableToolID, idempotencyKey: intent.idempotencyKey, providerCallID: intent.providerCallID, arguments: intent.executionArguments, logicalAttempt: intent.logicalAttempt, cancellation: signal))
            knownUsage = DurableGenerationPlanner.validUsageOrNil(output.usage)
            do { try DurableToolSchema.validateOutput(output) }
            catch DurableToolOutputValidation.invalidUsage { invalidUsage = true; throw DurableToolOutputValidation.invalidUsage }
            staged = DurableStagedToolResult(content: output.content, isError: output.isError, usage: output.usage, documents: output.documents, code: output.isError ? "tool_error" : nil, billingUnknown: replayingStarted)
        } catch let error as DurableToolOutputValidation {
            let code: String
            switch error { case .outputLimit: code = "tool_output_limit"; case .invalidUsage: code = "invalid_tool_usage"; case .invalidDocuments: code = "invalid_tool_documents" }
            staged = DurableStagedToolResult(content: "Tool result was rejected", isError: true, usage: knownUsage, documents: [], code: code, billingUnknown: replayingStarted || invalidUsage)
        } catch {
            staged = DurableStagedToolResult(content: "Tool failed", isError: true, usage: knownUsage, documents: [], code: "tool_error", billingUnknown: replayingStarted)
        }
        staged.durationMs = Double((DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000)
        try await stageAndFinalizeToolChild(child: child, intent: intent, result: staged)
    }

    private func stageAndFinalizeToolChild(child: DurableTaskRecord, intent: DurableToolIntent, result: DurableStagedToolResult) async throws {
        try await gate.submit {
            let snapshot = try await self.storage.snapshot(); guard let current = snapshot.tasks[child.id] else { throw DurableError.corruptStorage("missing tool child") }
            let completing = DurableTaskRecord(id: current.id, conversationID: current.conversationID, ownerTaskID: current.ownerTaskID, kind: current.kind, status: .completing, checkpoint: .object(["phase": .string("completing"), "result": try DurableGenerationPlanner.encodeJSON(result, maxBytes: DurableLimits.maxCheckpointBytes)]), abortRequested: current.abortRequested, background: current.background, outcome: current.outcome, createdSeq: current.createdSeq)
            _ = try await self.storage.commit(DurableCommitBatch(tasks: [completing]))
        }
        let snapshot = try await storage.snapshot(); try await finalizeToolChild(child: snapshot.tasks[child.id]!, intent: intent, result: result)
    }

    private func finalizeToolChild(child: DurableTaskRecord, intent: DurableToolIntent, result: DurableStagedToolResult) async throws {
        try await gate.submit {
            let snapshot = try await self.storage.snapshot(); guard let current = snapshot.tasks[child.id] else { throw DurableError.corruptStorage("missing tool child") }
            let existingAggregate = DurableGenerationPlanner.document(scope: "conversation", ownerID: current.conversationID, kind: "durable.usage", in: snapshot)
            let required = 4 + result.documents.count + (result.usage == nil ? 0 : 1) + (result.billingUnknown ? 1 : 0)
            var ids = try DurableSubmissionPlanner.nextID(from: snapshot, reserving: required); func take() -> Int64 { ids.removeFirst() }
            var applicationInvalid = false
            let applicationDocuments: [DurableDocumentRecord]
            do { applicationDocuments = current.abortRequested ? [] : try Self.applicationDocuments(result.documents, intent: intent, child: current, snapshot: snapshot, ids: &ids) }
            catch { applicationInvalid = true; applicationDocuments = [] }
            let content = applicationInvalid ? "Tool application documents were rejected" : result.content
            let isError = result.isError || applicationInvalid
            let code = applicationInvalid ? "invalid_tool_documents" : (result.code ?? "ok")
            var message = Message(role: .toolResult, content: [.text(content)]); message.toolCallId = intent.providerCallID; message.toolName = intent.binding.definition.name; message.isError = isError; message.durationMs = result.durationMs
            let entryID = take()
            var documents = applicationDocuments
            if let usage = result.usage {
                let toolIdentity = "tool:\(intent.binding.implementationID)/\(intent.binding.implementationVersion)"
                documents.append(DurableDocumentRecord(id: take(), scope: "task", ownerID: current.id, kind: "tool.usage.attempt.\(intent.logicalAttempt)", value: DurableGenerationPlanner.usageValue(usage, model: toolIdentity)))
                do {
                    let value = try DurableGenerationPlanner.aggregateUsageValue(existing: existingAggregate?.value, adding: usage, model: toolIdentity)
                    documents.append(DurableDocumentRecord(id: existingAggregate?.id ?? take(), scope: "conversation", ownerID: current.conversationID, kind: "durable.usage", value: value, createdSeq: existingAggregate?.createdSeq ?? 0))
                } catch {
                    documents.append(DurableDocumentRecord(id: take(), scope: "task", ownerID: current.id, kind: "tool.aggregate-incomplete", value: .object(["attempt": .number(Double(intent.logicalAttempt)), "aggregatePreserved": .bool(true)])))
                }
            }
            if result.billingUnknown { documents.append(DurableDocumentRecord(id: take(), scope: "task", ownerID: current.id, kind: "tool.billing-incomplete", value: .object(["attempt": .number(Double(intent.logicalAttempt)), "unknown": .bool(true)]))) }
            let aggregateIncomplete = documents.contains { $0.kind == "tool.aggregate-incomplete" }
            let finalError = isError || aggregateIncomplete
            let finalCode = aggregateIncomplete ? "usage_overflow" : code
            if aggregateIncomplete { message.content = [.text("Tool usage aggregate overflow")]; message.isError = true; documents.removeAll { $0.kind.hasPrefix("tool.application.") } }
            let entry = DurableEntryRecord(id: entryID, conversationID: current.conversationID, kind: "tool-result", messages: [message], byTaskID: current.id)
            let status: DurableTaskStatus = current.abortRequested ? .aborted : (finalError ? .failed : .completed)
            let terminal = DurableTaskRecord(id: current.id, conversationID: current.conversationID, ownerTaskID: current.ownerTaskID, kind: current.kind, status: status, checkpoint: current.checkpoint, abortRequested: current.abortRequested, background: current.background, outcome: .object(["code": .string(finalCode), "entryID": .number(Double(entry.id))]), createdSeq: current.createdSeq)
            _ = try await self.storage.commit(DurableCommitBatch(entries: [entry], tasks: [terminal], documents: documents))
        }
    }

    private nonisolated static func applicationDocuments(_ proposed: [DurableToolApplicationDocument], intent: DurableToolIntent, child: DurableTaskRecord, snapshot: DurableSnapshot, ids: inout [Int64]) throws -> [DurableDocumentRecord] {
        var seen = Set<String>(), output: [DurableDocumentRecord] = []
        for item in proposed {
            guard DurableToolSchema.validKindPart(item.suffix) else { throw DurableError.invalidRecord("invalid application document suffix") }
            let scope = item.target == .conversation ? "conversation" : "task", owner = item.target == .conversation ? child.conversationID : child.id
            let kind = "tool.application.\(intent.binding.definition.name).\(item.suffix)", key = "\(scope)/\(owner)/\(kind)"
            guard seen.insert(key).inserted else { throw DurableError.invalidRecord("duplicate application document") }
            let existing = DurableGenerationPlanner.document(scope: scope, ownerID: owner, kind: kind, in: snapshot)
            if let existing {
                guard let creator = existing.value.objectValue?["creatorTaskID"]?.doubleValue, creator.isFinite, creator.rounded(.towardZero) == creator, creator > 0, creator <= Double(DurableLimits.maxExactInteger), Int64(creator) == child.id else { throw DurableError.invalidRecord("invalid application document creator") }
            }
            guard let id = existing?.id ?? ids.first else { throw DurableError.invalidRecord("missing application document id") }; if existing == nil { ids.removeFirst() }
            output.append(DurableDocumentRecord(id: id, scope: scope, ownerID: owner, kind: kind, value: .object(["creatorTaskID": .number(Double(child.id)), "value": item.value]), createdSeq: existing?.createdSeq ?? 0))
        }
        return output
    }

    private func resumeWaitingParent(_ taskID: Int64) async throws {
        try await gate.submit {
            let snapshot = try await self.storage.snapshot(); guard let parent = snapshot.tasks[taskID] else { throw DurableError.corruptStorage("missing waiting parent") }
            if parent.status == .aborted { return }
            guard parent.status == .waiting else { return }
            if parent.abortRequested {
                let childIDs = parent.checkpoint?.objectValue?["childIDs"]?.arrayValue?.compactMap { $0.doubleValue.map(Int64.init) } ?? []
                guard childIDs.allSatisfy({ id in snapshot.tasks[id].map { [.completed, .failed, .aborted].contains($0.status) } == true }) else { return }
                let aborted = DurableTaskRecord(id: parent.id, conversationID: parent.conversationID, ownerTaskID: parent.ownerTaskID, kind: parent.kind, status: .aborted, checkpoint: parent.checkpoint, abortRequested: true, background: parent.background, outcome: .object(["code": .string("aborted")]), createdSeq: parent.createdSeq)
                _ = try await self.storage.commit(DurableCommitBatch(tasks: [aborted])); return
            }
            let childIDs = parent.checkpoint?.objectValue?["childIDs"]?.arrayValue?.compactMap { $0.doubleValue.map(Int64.init) } ?? []
            let children = childIDs.compactMap { snapshot.tasks[$0] }; guard children.count == childIDs.count, children.allSatisfy({ [.completed, .failed, .aborted].contains($0.status) }) else { throw DurableError.corruptStorage("waiting parent has incomplete children") }
            var intent = try DurableGenerationPlanner.intent(for: parent, in: snapshot)
            let resultMessages = childIDs.compactMap { id -> Message? in guard let entryID = snapshot.tasks[id]?.outcome?.objectValue?["entryID"]?.doubleValue.map(Int64.init) else { return nil }; return snapshot.entries[entryID]?.messages?.first }
            guard resultMessages.count == childIDs.count else { throw DurableError.corruptStorage("missing ordered tool results") }
            intent.roundMessages = (intent.roundMessages ?? []) + resultMessages; intent.round = (intent.round ?? 1) + 1
            let boundary = try DurableInboxPlanner.boundary(snapshot: snapshot, conversationID: parent.conversationID, at: .postTools, steering: .oneAtATime, followUp: .oneAtATime)
            if boundary.result.reset {
                let projected = DurableValidation.applying(boundary.batch, to: snapshot, seq: snapshot.seq + 1, highWater: max(snapshot.highWaterID, boundary.batch.entries.map(\.id).max() ?? 0))
                intent.preparedTranscript = try DurableContext.derive(snapshot: projected, conversationID: parent.conversationID).messages
                intent.roundMessages = []
            } else { intent.roundMessages = (intent.roundMessages ?? []) + boundary.result.entries.flatMap { $0.messages ?? [] } }
            let intentDoc = try Self.toolIntentDocument(snapshot: snapshot, taskID: taskID, intent: intent)
            let running = DurableTaskRecord(id: parent.id, conversationID: parent.conversationID, ownerTaskID: parent.ownerTaskID, kind: parent.kind, status: .running, checkpoint: DurableGenerationPlanner.checkpoint(intent: intent, phase: "running"), abortRequested: parent.abortRequested, background: parent.background, outcome: parent.outcome, createdSeq: parent.createdSeq)
            _ = try await self.storage.commit(DurableCommitBatch(entries: boundary.batch.entries, tasks: [running], submissions: boundary.batch.submissions, documents: boundary.batch.documents + [intentDoc]))
        }
    }

    private func settleSuccess(taskID: Int64, submissionID: Int64?, inputEntryID: Int64, terminal: DurableStreamTerminal) async throws -> DurableGenerationResult {
        try await gate.submit {
            let snapshot = try await self.storage.snapshot()
            guard let running = snapshot.tasks[taskID] else { throw DurableError.corruptStorage("missing generation task") }
            let intent = try DurableGenerationPlanner.intent(for: running, in: snapshot)
            let taskForFinal: DurableTaskRecord
            if running.status == .completing { taskForFinal = running }
            else {
                _ = try await self.storage.commit(try DurableGenerationPlanner.completingBatch(task: running, intent: intent, terminal: terminal))
                let afterCompleting = try await self.storage.snapshot()
                guard let completing = afterCompleting.tasks[taskID] else { throw DurableError.corruptStorage("missing completing task") }
                taskForFinal = completing
            }
            let afterCompleting = try await self.storage.snapshot()
            let placed = submissionID.flatMap { afterCompleting.submissions[$0] }
            do {
                var finalBatch = try DurableGenerationPlanner.finalSuccessBatch(snapshot: afterCompleting, task: taskForFinal, submission: placed, inputEntryID: inputEntryID, terminal: terminal)
                for submission in afterCompleting.submissions.values where submission.conversationID == taskForFinal.conversationID && submission.status == .placed && submission.payloadHash?.hasPrefix("inbox:") == true && !finalBatch.submissions.contains(where: { $0.id == submission.id }) {
                    guard let entryID = submission.entryID else { continue }
                    var settled = submission; settled.status = .done; settled.answerID = finalBatch.entries.first?.id; settled.entryID = entryID
                    finalBatch.submissions.append(settled)
                }
                let projected = DurableValidation.applying(finalBatch, to: afterCompleting, seq: afterCompleting.seq + 1, highWater: max(afterCompleting.highWaterID, finalBatch.entries.map(\.id).max() ?? 0, finalBatch.documents.map(\.id).max() ?? 0))
                let boundary = try DurableInboxPlanner.boundary(snapshot: projected, conversationID: taskForFinal.conversationID, at: .final, steering: .oneAtATime, followUp: .oneAtATime)
                finalBatch.entries += boundary.batch.entries; finalBatch.submissions += boundary.batch.submissions; finalBatch.documents += boundary.batch.documents
                _ = try await self.storage.commit(finalBatch)
            } catch DurableGenerationFailure.failure(let failure) {
                let failureTerminal = try DurableGenerationPlanner.aggregateFailureFinalBatch(snapshot: afterCompleting, task: taskForFinal, submission: placed, inputEntryID: inputEntryID, failure: failure)
                _ = try await self.storage.commit(failureTerminal)
            }
            let final = try await self.storage.snapshot()
            guard let finalTask = final.tasks[taskID] else { throw DurableError.corruptStorage("missing final task") }
            let entry = final.entries.values.filter { $0.byTaskID == taskID }.max { $0.id < $1.id }
            return DurableGenerationResult(task: finalTask, submission: submissionID.flatMap { final.submissions[$0] }, entry: entry)
        }
    }

    private func settleFailure(taskID: Int64, submissionID: Int64?, inputEntryID: Int64, failure: DurableFailureInfo) async throws -> DurableGenerationResult {
        try await gate.submit {
            let snapshot = try await self.storage.snapshot()
            guard let running = snapshot.tasks[taskID] else { throw DurableError.corruptStorage("missing generation task") }
            let submission = submissionID.flatMap { snapshot.submissions[$0] }
            let finalSnapshot: DurableSnapshot
            if running.status == .completing { finalSnapshot = snapshot }
            else {
                let (completing, _) = try DurableGenerationPlanner.failureBatches(snapshot: snapshot, task: running, submission: submission, inputEntryID: inputEntryID, failure: failure)
                _ = try await self.storage.commit(completing)
                finalSnapshot = try await self.storage.snapshot()
            }
            guard let completingTask = finalSnapshot.tasks[taskID] else { throw DurableError.corruptStorage("missing completing failure task") }
            let stagedFailure = try DurableGenerationPlanner.stagedFailure(for: completingTask) ?? failure
            let placed = submissionID.flatMap { finalSnapshot.submissions[$0] }
            let (_, terminal) = try DurableGenerationPlanner.failureBatches(snapshot: finalSnapshot, task: completingTask, submission: placed, inputEntryID: inputEntryID, failure: stagedFailure)
            _ = try await self.storage.commit(terminal)
            let final = try await self.storage.snapshot()
            guard let finalTask = final.tasks[taskID] else { throw DurableError.corruptStorage("missing final failure task") }
            return DurableGenerationResult(task: finalTask, submission: submissionID.flatMap { final.submissions[$0] }, entry: nil)
        }
    }

    private func failExecutor(_ error: Error) {
        executorFailure = error
        isClosing = true
        testingHooks?.onCloseSealed?()
        recoverySweepRequested = false
        let abandoned = queue.map(\.taskID)
        queue.removeAll()
        scheduledTaskIDs.removeAll()
        for taskID in abandoned { resumeTaskWaiters(taskID: taskID, result: .failure(error)) }
        worker = nil
        finishCloseIfNeeded()
    }

    func finishCloseIfNeeded() { startCommonCloseIfReady() }

    private func startCommonCloseIfReady() {
        guard isClosing, !isClosed, closeTask == nil, queue.isEmpty, worker == nil, activeAdmissions == 0 else { return }
        closeTask = Task { await self.performCommonClose() }
    }

    private func performCommonClose() async {
        var result: Result<Void, Error>
        do {
            try await finishClose()
            if let executorFailure { result = .failure(executorFailure) }
            else { result = .success(()) }
        } catch {
            closeError = error
            result = .failure(error)
        }
        resumeCloseWaiters(result)
    }

    private func finishClose() async throws {
        var primaryError: Error?
        do { try await gate.close() }
        catch { primaryError = error }
        do { try await storage.close() }
        catch { if primaryError == nil { primaryError = error } }
        isClosed = true
        closeError = primaryError
        if let primaryError { throw primaryError }
    }

    private func attachTaskWaiter(taskID: Int64, waiter: TaskWaiter) {
        taskWaiters[taskID, default: []].append(waiter)
    }

    private func cancelTaskWaiter(taskID: Int64, waiterID: Int64) {
        guard var waiters = taskWaiters[taskID], let index = waiters.firstIndex(where: { $0.id == waiterID }) else { return }
        let waiter = waiters.remove(at: index)
        if waiters.isEmpty { taskWaiters.removeValue(forKey: taskID) } else { taskWaiters[taskID] = waiters }
        waiter.continuation.resume(throwing: CancellationError())
    }

    private func cancelCloseWaiter(id: Int64) {
        guard let index = closeWaiters.firstIndex(where: { $0.id == id }) else { return }
        let waiter = closeWaiters.remove(at: index)
        waiter.continuation.resume(throwing: CancellationError())
    }

    private func resumeTaskWaiters(taskID: Int64, result: Result<DurableGenerationResult, Error>) {
        let waiters = taskWaiters.removeValue(forKey: taskID) ?? []
        for waiter in waiters {
            switch result {
            case .success(let value): waiter.continuation.resume(returning: value)
            case .failure(let error): waiter.continuation.resume(throwing: error)
            }
        }
    }

    private func resumeCloseWaiters(_ result: Result<Void, Error>) {
        let waiters = closeWaiters
        closeWaiters.removeAll()
        for waiter in waiters {
            switch result {
            case .success: waiter.continuation.resume()
            case .failure(let error): waiter.continuation.resume(throwing: error)
            }
        }
    }

    func ensureAdmitting() throws {
        if let executorFailure { throw executorFailure }
        if isClosed || isClosing { throw DurableError.closed }
    }
}
