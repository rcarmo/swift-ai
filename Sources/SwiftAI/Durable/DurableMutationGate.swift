import Foundation

struct DurableMutationGateTestingHooks: Sendable {
    var onQueued: (@Sendable (Int64) -> Void)?
    var onCloseSealed: (@Sendable () -> Void)?
    var onCloseWaiter: (@Sendable (Int64) -> Void)?
    var onCloseWaiterCancelled: (@Sendable (Int64) -> Void)?
    init(onQueued: (@Sendable (Int64) -> Void)? = nil, onCloseSealed: (@Sendable () -> Void)? = nil, onCloseWaiter: (@Sendable (Int64) -> Void)? = nil, onCloseWaiterCancelled: (@Sendable (Int64) -> Void)? = nil) {
        self.onQueued = onQueued
        self.onCloseSealed = onCloseSealed
        self.onCloseWaiter = onCloseWaiter
        self.onCloseWaiterCancelled = onCloseWaiterCancelled
    }
}

public actor DurableMutationGate {
    private struct AnySendable: @unchecked Sendable { let value: Any }
    private struct Job: Sendable {
        let id: Int64
        let token: DurableMutationAdmissionToken
        let run: @Sendable () async -> Result<AnySendable, Error>
        let complete: @Sendable (Result<AnySendable, Error>) -> Void
    }

    private var nextID: Int64 = 0
    private var queue: [Job] = []
    private var runningJob: Job?
    private var runner: Task<Void, Never>?
    private var sealed = false
    private var closed = false
    private struct CloseWaiter {
        let id: Int64
        let continuation: CheckedContinuation<Void, Error>
    }

    private var poisonError: DurableError?
    private var closeWaiters: [CloseWaiter] = []
    private var nextCloseWaiterID: Int64 = 0
    private let testingHooks: DurableMutationGateTestingHooks?

    public init() { self.testingHooks = nil }

    init(testingHooks: DurableMutationGateTestingHooks) { self.testingHooks = testingHooks }

    public func submit<T: Sendable>(_ operation: @Sendable @escaping () async throws -> T) async throws -> T {
        try await enqueue(operation)
    }

    public func close() async throws {
        if let poisonError, runningJob == nil { throw poisonError }
        if closed { return }
        sealed = true
        testingHooks?.onCloseSealed?()
        let rejected = queue
        queue.removeAll()
        for job in rejected { job.complete(.failure(DurableError.closed)) }
        if runningJob == nil { closed = true; if let poisonError { throw poisonError }; return }
        guard nextCloseWaiterID < DurableLimits.maxExactInteger else { throw DurableError.invalidRecord("close waiter id overflow") }
        nextCloseWaiterID += 1
        let waiterID = nextCloseWaiterID
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled { continuation.resume(throwing: CancellationError()); return }
                closeWaiters.append(CloseWaiter(id: waiterID, continuation: continuation))
                testingHooks?.onCloseWaiter?(waiterID)
            }
        } onCancel: {
            Task { await self.cancelCloseWaiter(id: waiterID) }
        }
    }

    public func poison(_ reason: String) {
        let error = DurableError.poisoned(reason)
        poisonError = error
        let rejected = queue
        queue.removeAll()
        for job in rejected { job.complete(.failure(error)) }
        if runningJob == nil { finishCloseWaiters(.failure(error)) }
    }

    private func enqueue<T: Sendable>(_ operation: @Sendable @escaping () async throws -> T) async throws -> T {
        if closed { throw DurableError.closed }
        if let poisonError { throw poisonError }
        if sealed { throw DurableError.closed }
        if Task.isCancelled { throw DurableError.cancelledBeforeAdmission }
        guard queue.count < DurableLimits.maxPublicQueue else { throw DurableError.queueFull }
        guard nextID < DurableLimits.maxExactInteger else { throw DurableError.invalidRecord("mutation id overflow") }
        nextID += 1
        let id = nextID
        let token = DurableMutationAdmissionToken()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let job = Job(id: id, token: token, run: {
                    guard token.claim() else { return .failure(DurableError.cancelledBeforeAdmission) }
                    do { return .success(AnySendable(value: try await operation())) }
                    catch { return .failure(error) }
                }, complete: { result in
                    switch result {
                    case .success(let boxed):
                        if let value = boxed.value as? T { continuation.resume(returning: value) }
                        else { continuation.resume(throwing: DurableError.invalidRecord("mutation result type mismatch")) }
                    case .failure(let error): continuation.resume(throwing: error)
                    }
                })
                queue.append(job)
                testingHooks?.onQueued?(id)
                ensureRunner()
            }
        } onCancel: {
            token.cancel()
            Task { await self.cancelQueued(id: id) }
        }
    }

    private func cancelQueued(id: Int64) {
        guard let index = queue.firstIndex(where: { $0.id == id }) else { return }
        let job = queue.remove(at: index)
        job.complete(.failure(DurableError.cancelledBeforeAdmission))
        completeCloseIfIdle()
    }

    private func ensureRunner() {
        guard runner == nil else { return }
        runner = Task { await self.drain() }
    }

    private func drain() async {
        while true {
            guard !queue.isEmpty else { runner = nil; completeCloseIfIdle(); return }
            let job = queue.removeFirst()
            if let poisonError { job.complete(.failure(poisonError)); continue }
            runningJob = job
            let result = await job.run()
            runningJob = nil
            job.complete(result)
            if case .failure(let error) = result, let terminal = terminalMutationError(error) { poisonError = terminal; rejectQueued(terminal) }
        }
    }

    private func terminalMutationError(_ error: Error) -> DurableError? {
        switch error {
        case let durable as DurableError:
            switch durable {
            case .poisoned, .durabilityUncertain: return durable
            default: return nil
            }
        default: return nil
        }
    }

    private func rejectQueued(_ error: Error) {
        let rejected = queue
        queue.removeAll()
        for job in rejected { job.complete(.failure(error)) }
    }

    private func cancelCloseWaiter(id: Int64) {
        guard let index = closeWaiters.firstIndex(where: { $0.id == id }) else { return }
        let waiter = closeWaiters.remove(at: index)
        testingHooks?.onCloseWaiterCancelled?(id)
        waiter.continuation.resume(throwing: CancellationError())
    }

    private func completeCloseIfIdle() {
        guard sealed, runningJob == nil, queue.isEmpty else { return }
        closed = true
        if let poisonError { finishCloseWaiters(.failure(poisonError)) }
        else { finishCloseWaiters(.success(())) }
    }

    private func finishCloseWaiters(_ result: Result<Void, Error>) {
        let waiters = closeWaiters
        closeWaiters.removeAll()
        for waiter in waiters {
            switch result {
            case .success: waiter.continuation.resume()
            case .failure(let error): waiter.continuation.resume(throwing: error)
            }
        }
    }
}

private final class DurableMutationAdmissionToken: @unchecked Sendable {
    private enum State { case queued, cancelled, claimed }
    private let lock = NSLock()
    private var state: State = .queued
    func cancel() { lock.lock(); if state == .queued { state = .cancelled }; lock.unlock() }
    func claim() -> Bool { lock.lock(); defer { lock.unlock() }; guard state == .queued else { return false }; state = .claimed; return true }
}
