import XCTest
@testable import SwiftAI

private final class S1BCloseBox: @unchecked Sendable {
    private let lock = NSLock()
    private var sealed = false
    private var sealedWaiter: CheckedContinuation<Void, Never>?
    private var submitIDs = Set<Int64>()
    private var submitWaiters: [Int64: CheckedContinuation<Void, Never>] = [:]
    private var closeIDs = Set<Int64>()
    private var closeWaiters: [Int64: CheckedContinuation<Void, Never>] = [:]
    func markSealed() { lock.lock(); sealed = true; let waiter = sealedWaiter; sealedWaiter = nil; lock.unlock(); waiter?.resume() }
    func waitSealed() async { await withCheckedContinuation { continuation in lock.lock(); if sealed { lock.unlock(); continuation.resume(); return }; sealedWaiter = continuation; lock.unlock() } }
    func markSubmit(_ id: Int64) { lock.lock(); submitIDs.insert(id); let waiter = submitWaiters.removeValue(forKey: id); lock.unlock(); waiter?.resume() }
    func waitSubmit(_ id: Int64) async { await withCheckedContinuation { continuation in lock.lock(); if submitIDs.contains(id) { lock.unlock(); continuation.resume(); return }; submitWaiters[id] = continuation; lock.unlock() } }
    func markClose(_ id: Int64) { lock.lock(); closeIDs.insert(id); let waiter = closeWaiters.removeValue(forKey: id); lock.unlock(); waiter?.resume() }
    func waitClose(_ id: Int64) async { await withCheckedContinuation { continuation in lock.lock(); if closeIDs.contains(id) { lock.unlock(); continuation.resume(); return }; closeWaiters[id] = continuation; lock.unlock() } }
}

private actor S1BProviderBarrier {
    private var entered = 0
    private var enteredWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []
    private var released = false
    func hold() async { entered += 1; let ready = enteredWaiters.filter { $0.0 <= entered }; enteredWaiters.removeAll { $0.0 <= entered }; for (_, waiter) in ready { waiter.resume() }; if released { return }; await withCheckedContinuation { releaseWaiters.append($0) } }
    func waitEntered(_ count: Int = 1) async { if entered >= count { return }; await withCheckedContinuation { enteredWaiters.append((count, $0)) } }
    func release() { released = true; let waiters = releaseWaiters; releaseWaiters = []; for waiter in waiters { waiter.resume() } }
}

private final class S1BSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false
    private var waiter: CheckedContinuation<Void, Never>?
    func fire() { lock.lock(); fired = true; let waiter = waiter; self.waiter = nil; lock.unlock(); waiter?.resume() }
    func wait() async { await withCheckedContinuation { continuation in lock.lock(); if fired { lock.unlock(); continuation.resume(); return }; waiter = continuation; lock.unlock() } }
}

private actor S1BBarrierStorage: DurableStorage {
    let base = DurableMemoryStorage()
    private var hold = false
    private var held = false
    private var heldWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiter: CheckedContinuation<Void, Never>?
    private(set) var closeInvocations = 0
    func seed(_ batch: DurableCommitBatch) async throws { _ = try await base.commit(batch) }
    func arm() { hold = true }
    func waitHeld() async { if held { return }; await withCheckedContinuation { heldWaiters.append($0) } }
    func release() { releaseWaiter?.resume(); releaseWaiter = nil }
    func snapshot() async throws -> DurableSnapshot { try await base.snapshot() }
    func commit(_ batch: DurableCommitBatch) async throws -> DurableSnapshot {
        let result = try await base.commit(batch)
        if hold { hold = false; held = true; let waiters = heldWaiters; heldWaiters = []; for waiter in waiters { waiter.resume() }; await withCheckedContinuation { releaseWaiter = $0 } }
        return result
    }
    func close() async throws { closeInvocations += 1; try await base.close() }
}

final class DurableSessionTests: XCTestCase {
    func testAdmissionAckCloseDrainsOwnedGenerationAndClosesOnce() async throws {
        let model = Model(id: "close-test", name: "Close", api: .faux, provider: .faux, baseUrl: "runtime")
        await AIRegistry.shared.register(model)
        await AIRegistry.shared.register(APIProvider(api: .faux, stream: { model, _, _ in AsyncStream { continuation in var message = Message(role: .assistant, content: [.text("ok")]); message.api = model.api; message.provider = model.provider; message.model = model.id; message.stopReason = .stop; continuation.yield(.done(reason: .stop, message: message)); continuation.finish() } }))
        let storage = S1BBarrierStorage(); let box = S1BCloseBox(); let session = DurableSession(storage: storage, testingHooks: DurableSessionTestingHooks(onCloseSealed: { box.markSealed() }, onCloseWaiter: { box.markClose($0) }))
        let conversation = try await session.createConversation()
        await storage.arm()
        let submitted = Task { try await session.submit(DurableGenerationRequest(conversationID: conversation.id, model: model, transcript: [.user("admitted")], requestID: "ack")) }
        await storage.waitHeld()
        let closeA = Task { try await session.close() }
        await box.waitSealed(); await box.waitClose(1)
        let closeB = Task { try await session.close() }
        await box.waitClose(2)
        closeB.cancel()
        await storage.release()
        let submittedResult = try await submitted.value
        XCTAssertEqual(submittedResult.task.status, .completed)
        try await closeA.value
        await XCTAssertThrowsAsyncError(try await closeB.value)
        try await session.close()
        let closeInvocations = await storage.closeInvocations
        XCTAssertEqual(closeInvocations, 1)
    }

    func testCancellationDuringAdmissionAckStillSchedulesOwnedProvider() async throws {
        let capture = S1BCapture(); let model = Model(id: "cancel-ack", name: "Cancel ACK", api: .faux, provider: .faux, baseUrl: "runtime")
        await AIRegistry.shared.register(model)
        await AIRegistry.shared.register(APIProvider(api: .faux, stream: { model, context, _ in AsyncStream { continuation in Task { await capture.record(context); var message = Message(role: .assistant, content: [.text("owned")]); message.api = model.api; message.provider = model.provider; message.model = model.id; message.stopReason = .stop; continuation.yield(.done(reason: .stop, message: message)); continuation.finish() } } }))
        let storage = S1BBarrierStorage(); let session = DurableSession(storage: storage); let conversation = try await session.createConversation(); await storage.arm()
        let submitted = Task { try await session.submit(DurableGenerationRequest(conversationID: conversation.id, model: model, transcript: [.user("ack cancel")], requestID: "ack-cancel")) }
        await storage.waitHeld(); submitted.cancel(); await storage.release()
        await XCTAssertThrowsAsyncError(try await submitted.value)
        while (try await session.snapshot()).tasks.values.first?.status != .completed { await Task.yield() }
        let effects = await capture.effects; XCTAssertEqual(effects, 1)
        try await session.close()
    }

    func testCancelledSubmitObserverDetachesButOwnedProviderCompletes() async throws {
        let barrier = S1BProviderBarrier(); let box = S1BCloseBox()
        let model = Model(id: "cancel-observer", name: "Cancel", api: .faux, provider: .faux, baseUrl: "runtime")
        await AIRegistry.shared.register(model)
        await AIRegistry.shared.register(APIProvider(api: .faux, stream: { model, _, _ in AsyncStream { continuation in Task { await barrier.hold(); var message = Message(role: .assistant, content: [.text("owned")]); message.api = model.api; message.provider = model.provider; message.model = model.id; message.stopReason = .stop; continuation.yield(.done(reason: .stop, message: message)); continuation.finish() } } }))
        let session = DurableSession(storage: DurableMemoryStorage(), testingHooks: DurableSessionTestingHooks(onSubmitWaiter: { box.markSubmit($0) }))
        let conversation = try await session.createConversation()
        let submitted = Task { try await session.submit(DurableGenerationRequest(conversationID: conversation.id, model: model, transcript: [.user("cancel")], requestID: "cancel")) }
        await box.waitSubmit(1); await barrier.waitEntered(); submitted.cancel()
        await XCTAssertThrowsAsyncError(try await submitted.value)
        await barrier.release()
        while (try await session.snapshot()).tasks.values.first?.status != .completed { await Task.yield() }
        try await session.close()
    }

    func testCapacityOneExplicitResumeStartsRecovery() async throws {
        let capture = S1BCapture(); let model = Model(id: "capacity-one", name: "Capacity One", api: .faux, provider: .faux, baseUrl: "runtime")
        await AIRegistry.shared.register(model)
        await AIRegistry.shared.register(APIProvider(api: .faux, stream: { model, context, _ in AsyncStream { continuation in Task { await capture.record(context); var message = Message(role: .assistant, content: [.text("ok")]); message.api = model.api; message.provider = model.provider; message.model = model.id; message.stopReason = .stop; continuation.yield(.done(reason: .stop, message: message)); continuation.finish() } } }))
        let storage = DurableMemoryStorage(); _ = try await storage.commit(DurableCommitBatch(conversations: [DurableConversationRecord(id: 1)]))
        let admission = try DurableGenerationPlanner.admitBatch(snapshot: try await storage.snapshot(), request: DurableGenerationRequest(conversationID: 1, model: model, transcript: [.user("recover")], requestID: "capacity-one")); _ = try await storage.commit(admission.batch)
        let session = DurableSession(storage: storage, capacity: 1); _ = try await session.resumeQueued()
        while (try await session.snapshot()).tasks[admission.taskID]?.status != .completed { await Task.yield() }
        let effects = await capture.effects; XCTAssertEqual(effects, 1)
        try await session.close()
    }

    func testDeferredRecoveryWakesWhenAdmissionReservationReleases() async throws {
        let capture = S1BCapture(); let signal = S1BSignal(); let box = S1BCloseBox()
        let model = Model(id: "deferred-recovery", name: "Deferred Recovery", api: .faux, provider: .faux, baseUrl: "runtime")
        await AIRegistry.shared.register(model)
        await AIRegistry.shared.register(APIProvider(api: .faux, stream: { model, context, _ in AsyncStream { continuation in Task { await capture.record(context); var message = Message(role: .assistant, content: [.text("ok")]); message.api = model.api; message.provider = model.provider; message.model = model.id; message.stopReason = .stop; continuation.yield(.done(reason: .stop, message: message)); continuation.finish() } } }))
        let storage = S1BBarrierStorage(); try await storage.seed(DurableCommitBatch(conversations: [DurableConversationRecord(id: 1)]))
        let recoveredAdmission = try DurableGenerationPlanner.admitBatch(snapshot: try await storage.snapshot(), request: DurableGenerationRequest(conversationID: 1, model: model, transcript: [.user("recover")], requestID: "recover")); try await storage.seed(recoveredAdmission.batch)
        let session = DurableSession(storage: storage, testingHooks: DurableSessionTestingHooks(onSubmitWaiter: { box.markSubmit($0) }, onRecoveryDeferred: { signal.fire() }), capacity: 1)
        await storage.arm()
        let submitted = Task { try await session.submit(DurableGenerationRequest(conversationID: 1, model: model, transcript: [.user("admit")], requestID: "admit")) }
        await storage.waitHeld()
        _ = try await session.resumeQueued(); await signal.wait(); await storage.release(); await box.waitSubmit(1)
        _ = try await submitted.value
        while (try await session.snapshot()).tasks.values.contains(where: { $0.status != .completed }) { await Task.yield() }
        let effects = await capture.effects; XCTAssertEqual(effects, 2)
        try await session.close()
    }

    func testSessionCapacityRejectsBeforeThirdAdmissionAndDrainsTwoOwnedTasks() async throws {
        let barrier = S1BProviderBarrier(); let box = S1BCloseBox()
        let model = Model(id: "capacity", name: "Capacity", api: .faux, provider: .faux, baseUrl: "runtime")
        await AIRegistry.shared.register(model)
        await AIRegistry.shared.register(APIProvider(api: .faux, stream: { model, _, _ in AsyncStream { continuation in Task { await barrier.hold(); var message = Message(role: .assistant, content: [.text("ok")]); message.api = model.api; message.provider = model.provider; message.model = model.id; message.stopReason = .stop; continuation.yield(.done(reason: .stop, message: message)); continuation.finish() } } }))
        let session = DurableSession(storage: DurableMemoryStorage(), testingHooks: DurableSessionTestingHooks(onSubmitWaiter: { box.markSubmit($0) }), capacity: 2)
        let conversation = try await session.createConversation()
        let first = Task { try await session.submit(DurableGenerationRequest(conversationID: conversation.id, model: model, transcript: [.user("one")], requestID: "one")) }
        await box.waitSubmit(1); await barrier.waitEntered()
        let second = Task { try await session.submit(DurableGenerationRequest(conversationID: conversation.id, model: model, transcript: [.user("two")], requestID: "two")) }
        await box.waitSubmit(2)
        await XCTAssertThrowsAsyncError(try await session.submit(DurableGenerationRequest(conversationID: conversation.id, model: model, transcript: [.user("three")], requestID: "three"))) { XCTAssertEqual($0 as? DurableError, .queueFull) }
        let admittedCount = try await session.snapshot().tasks.count
        XCTAssertEqual(admittedCount, 2)
        await barrier.release(); _ = try await first.value; _ = try await second.value
        try await session.close()
    }

    func testInspectionIsBoundedAndCloseRejectsNewAdmission() async throws {
        let session = DurableSession(storage: DurableMemoryStorage())
        _ = try await session.createConversation()
        _ = try await session.createConversation()
        let inspection = try await session.inspection()
        let page = try inspection.conversations(limit: 1)
        XCTAssertEqual(page.values.count, 1)
        XCTAssertEqual(page.nextOffset, 1)
        XCTAssertThrowsError(try inspection.conversations(limit: DurableLimits.maxPageLimit + 1))
        try await session.close()
        await XCTAssertThrowsAsyncError(try await session.createConversation())
    }
}
