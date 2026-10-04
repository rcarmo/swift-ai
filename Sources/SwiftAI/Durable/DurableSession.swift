import Foundation

struct DurableSessionTestingHooks: Sendable {
    var onCloseSealed: (@Sendable () -> Void)?
    var onSubmitWaiter: (@Sendable (Int64) -> Void)?
    var onCloseWaiter: (@Sendable (Int64) -> Void)?
    var onRecoveryDeferred: (@Sendable () -> Void)?
    init(onCloseSealed: (@Sendable () -> Void)? = nil, onSubmitWaiter: (@Sendable (Int64) -> Void)? = nil, onCloseWaiter: (@Sendable (Int64) -> Void)? = nil, onRecoveryDeferred: (@Sendable () -> Void)? = nil) {
        self.onCloseSealed = onCloseSealed
        self.onSubmitWaiter = onSubmitWaiter
        self.onCloseWaiter = onCloseWaiter
        self.onRecoveryDeferred = onRecoveryDeferred
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

    private let storage: DurableStorage
    private let gate: DurableMutationGate
    private let testingHooks: DurableSessionTestingHooks?
    private let capacity: Int
    private var queue: [GenerationJob] = []
    private var worker: Task<Void, Never>?
    private var nextJobID: Int64 = 0
    private var scheduledTaskIDs = Set<Int64>()
    private var runningTaskIDs = Set<Int64>()
    private var taskWaiters: [Int64: [TaskWaiter]] = [:]
    private var nextTaskWaiterID: Int64 = 0
    private var observerReservations = 0
    private var activeAdmissions = 0
    private var recoverySweepRequested = false
    private var isClosing = false
    private var isClosed = false
    private var executorFailure: Error?
    private var closeError: Error?
    private var closeWaiters: [CloseWaiter] = []
    private var nextCloseWaiterID: Int64 = 0
    private var closeTask: Task<Void, Never>?

    public init(storage: DurableStorage) {
        self.storage = storage
        self.gate = DurableMutationGate()
        self.testingHooks = nil
        self.capacity = DurableLimits.maxPublicQueue
    }

    init(storage: DurableStorage, testingHooks: DurableSessionTestingHooks = DurableSessionTestingHooks(), capacity: Int = DurableLimits.maxPublicQueue) {
        precondition(capacity > 0 && capacity <= DurableLimits.maxPublicQueue)
        self.storage = storage
        self.gate = DurableMutationGate()
        self.testingHooks = testingHooks
        self.capacity = capacity
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
        let admission: DurableGenerationAdmission
        do {
            admission = try await gate.submit { () async throws -> DurableGenerationAdmission in
                let snapshot = try await self.storage.snapshot()
                let admission = try DurableGenerationPlanner.admitBatch(snapshot: snapshot, request: request)
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
        recoverySweepRequested = snapshot.tasks.values.contains { [.pending, .running, .completing].contains($0.status) }
        enqueueRecoverable(from: snapshot)
        wakeDeferredRecovery()
        finishCloseIfNeeded()
        return DurableRecovery.plan(from: snapshot)
    }

    public func close() async throws {
        if isClosed {
            if let closeError { throw closeError }
            if let executorFailure { throw executorFailure }
            return
        }
        isClosing = true
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
            .filter { [.pending, .running, .completing].contains($0.status) && !scheduledTaskIDs.contains($0.id) && !runningTaskIDs.contains($0.id) }
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
        let terminal: DurableStreamTerminal
        do {
            let model = try await resolvedModel(for: dispatchIntent)
            let context = DurableGenerationPlanner.context(for: dispatchIntent, in: contextSnapshot)
            terminal = try await DurableGenerationPlanner.collectTerminal(model: model, context: context, options: dispatchIntent.options.streamOptions())
        } catch DurableGenerationFailure.failure(let failure) {
            return try await settleFailure(taskID: taskID, submissionID: submissionID, inputEntryID: inputEntryID, failure: failure)
        } catch DurableGenerationFailure.outputLimit(let failure) {
            return try await settleFailure(taskID: taskID, submissionID: submissionID, inputEntryID: inputEntryID, failure: failure)
        } catch {
            return try await settleFailure(taskID: taskID, submissionID: submissionID, inputEntryID: inputEntryID, failure: DurableFailureInfo(code: DurableGenerationPlanner.errorCode(String(describing: error)), usage: nil, diagnostics: nil))
        }
        do { return try await settleSuccess(taskID: taskID, submissionID: submissionID, inputEntryID: inputEntryID, terminal: terminal) }
        catch DurableGenerationFailure.outputLimit(let failure) { return try await settleFailure(taskID: taskID, submissionID: submissionID, inputEntryID: inputEntryID, failure: failure) }
    }

    private func resolvedModel(for intent: DurableGenerationIntent) async throws -> Model {
        guard var model = await AIRegistry.shared.model(provider: intent.model.provider, id: intent.model.id), model.api == intent.model.api else { throw DurableError.invalidRecord("missing_model") }
        let endpoint = model.baseUrl
        let headers = model.headers
        model = intent.model
        model.baseUrl = endpoint
        model.headers = headers
        let provider = await AIRegistry.shared.apiProvider(for: model.api)
        guard !model.baseUrl.isEmpty || provider != nil else { throw DurableError.invalidRecord("missing_endpoint") }
        return model
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
                let finalBatch = try DurableGenerationPlanner.finalSuccessBatch(snapshot: afterCompleting, task: taskForFinal, submission: placed, inputEntryID: inputEntryID, terminal: terminal)
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

    private func finishCloseIfNeeded() { startCommonCloseIfReady() }

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

    private func ensureAdmitting() throws {
        if let executorFailure { throw executorFailure }
        if isClosed || isClosing { throw DurableError.closed }
    }
}
