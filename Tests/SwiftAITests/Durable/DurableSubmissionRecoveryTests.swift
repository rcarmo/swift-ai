import Foundation
import XCTest
@testable import SwiftAI

private struct S1BFailAfterDirectorySync: DurableJournalFaultInjector {
    let targetSeq: Int64
    func afterDirectorySyncBeforeAck(seq: Int64) throws { if seq == targetSeq { throw DurableError.poisoned("injected settlement ACK loss") } }
}

private actor S1BRecoveryBarrier {
    private var entered = false
    private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiter: CheckedContinuation<Void, Never>?
    func hold() async { entered = true; let waiters = enteredWaiters; enteredWaiters = []; for waiter in waiters { waiter.resume() }; await withCheckedContinuation { releaseWaiter = $0 } }
    func waitEntered() async { if entered { return }; await withCheckedContinuation { enteredWaiters.append($0) } }
    func release() { releaseWaiter?.resume(); releaseWaiter = nil }
}

private final class S1BRecoveryHookBox: @unchecked Sendable {
    private let lock = NSLock()
    private var ids = Set<Int64>()
    private var waiters: [Int64: CheckedContinuation<Void, Never>] = [:]
    func mark(_ id: Int64) { lock.lock(); ids.insert(id); let waiter = waiters.removeValue(forKey: id); lock.unlock(); waiter?.resume() }
    func wait(_ id: Int64) async { await withCheckedContinuation { continuation in lock.lock(); if ids.contains(id) { lock.unlock(); continuation.resume(); return }; waiters[id] = continuation; lock.unlock() } }
}

#if os(Linux)
private struct S1BCrashAfterDirectorySync: DurableJournalFaultInjector {
    let targetSeq: Int64?
    init(targetSeq: Int64? = nil) { self.targetSeq = targetSeq }
    func afterDirectorySyncBeforeAck(seq: Int64) throws { if targetSeq == nil || targetSeq == seq { kill(getpid(), SIGKILL) } }
}
#endif

final class DurableSubmissionRecoveryTests: XCTestCase {
    private func tempDir() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("swift-ai-s1b-recovery-\(UUID().uuidString)", isDirectory: true) }

    func testJournalReopenCompletingTerminalFinalizesWithoutRebilling() async throws {
        let dir = tempDir(); let storage = try DurableJournalStorage(directory: dir)
        let conversation = DurableConversationRecord(id: 1)
        _ = try await storage.commit(DurableCommitBatch(conversations: [conversation]))
        let model = Model(id: "recover", name: "Recover", api: .faux, provider: .faux, baseUrl: "runtime")
        let request = DurableGenerationRequest(conversationID: 1, model: model, transcript: [.user("recover")], requestID: "recover")
        let admission = try DurableGenerationPlanner.admitBatch(snapshot: try await storage.snapshot(), request: request)
        _ = try await storage.commit(admission.batch)
        var terminalMessage = Message(role: .assistant, content: [.text("staged")]); terminalMessage.api = .faux; terminalMessage.provider = .faux; terminalMessage.model = "recover"; terminalMessage.stopReason = .stop
        let terminal = DurableStreamTerminal(message: terminalMessage, usage: nil, diagnostics: nil, stopReason: .stop)
        let admittedSnapshot = try await storage.snapshot()
        let pending = try XCTUnwrap(admittedSnapshot.tasks[admission.taskID])
        let intent = try DurableGenerationPlanner.intent(for: pending, in: admittedSnapshot)
        _ = try await storage.commit(try DurableGenerationPlanner.runningBatch(snapshot: admittedSnapshot, task: pending, intent: intent))
        let runningSnapshot = try await storage.snapshot()
        let running = try XCTUnwrap(runningSnapshot.tasks[admission.taskID])
        _ = try await storage.commit(try DurableGenerationPlanner.completingBatch(task: running, intent: intent, terminal: terminal))
        try await storage.close()

        let effects = S1BCapture()
        await AIRegistry.shared.register(model)
        await AIRegistry.shared.register(APIProvider(api: .faux, stream: { _, context, _ in AsyncStream { continuation in Task { await effects.record(context); continuation.finish() } } }))
        let reopened = try DurableJournalStorage(directory: dir); let session = DurableSession(storage: reopened)
        _ = try await session.resumeQueued()
        while true {
            let snapshot = try await session.snapshot()
            if snapshot.tasks[admission.taskID]?.status == .completed { break }
            await Task.yield()
        }
        let effectCount = await effects.effects
        XCTAssertEqual(effectCount, 0)
        try await session.close()
        let verify = try DurableJournalStorage(directory: dir)
        let verifiedSnapshot = try await verify.snapshot()
        XCTAssertEqual(verifiedSnapshot.tasks[admission.taskID]?.status, .completed)
        try await verify.close()
    }

    func testJournalReopenStagedFailureFinalizesWithoutRebillingAndPreservesUsage() async throws {
        let dir = tempDir(); let storage = try DurableJournalStorage(directory: dir)
        _ = try await storage.commit(DurableCommitBatch(conversations: [DurableConversationRecord(id: 1)]))
        let model = Model(id: "recover-failure", name: "Recover Failure", api: .faux, provider: .faux, baseUrl: "runtime")
        let request = DurableGenerationRequest(conversationID: 1, model: model, transcript: [.user("fail staged")], requestID: "fail-staged")
        let admission = try DurableGenerationPlanner.admitBatch(snapshot: try await storage.snapshot(), request: request); _ = try await storage.commit(admission.batch)
        let admitted = try await storage.snapshot(); let pending = try XCTUnwrap(admitted.tasks[admission.taskID]); let intent = try DurableGenerationPlanner.intent(for: pending, in: admitted)
        _ = try await storage.commit(try DurableGenerationPlanner.runningBatch(snapshot: admitted, task: pending, intent: intent))
        let runningSnapshot = try await storage.snapshot(); let running = try XCTUnwrap(runningSnapshot.tasks[admission.taskID])
        var usage = Usage(); usage.input = 4; usage.output = 1; usage.totalTokens = 5; usage.cost.total = 3
        let failure = DurableFailureInfo(code: "timeout", usage: usage, diagnostics: nil)
        let (completing, _) = try DurableGenerationPlanner.failureBatches(snapshot: runningSnapshot, task: running, submission: admission.submissionID.flatMap { runningSnapshot.submissions[$0] }, inputEntryID: admission.inputEntryID, failure: failure)
        _ = try await storage.commit(completing); try await storage.close()
        let effects = S1BCapture(); await AIRegistry.shared.register(model); await AIRegistry.shared.register(APIProvider(api: .faux, stream: { _, context, _ in AsyncStream { continuation in Task { await effects.record(context); continuation.finish() } } }))
        let session = DurableSession(storage: try DurableJournalStorage(directory: dir)); _ = try await session.resumeQueued()
        while (try await session.snapshot()).tasks[admission.taskID]?.status != .failed { await Task.yield() }
        let effectCount = await effects.effects
        XCTAssertEqual(effectCount, 0)
        let final = try await session.snapshot(); XCTAssertEqual(final.documents.values.first { $0.ownerID == admission.taskID && $0.kind == "generation.usage" }?.value.objectValue?["input"], .number(4))
        try await session.close()
    }

    func testContextLimitRunningCheckpointReopenFinalizesWithoutProviderEffect() async throws {
        let dir = tempDir(); let storage = try DurableJournalStorage(directory: dir); _ = try await storage.commit(DurableCommitBatch(conversations: [DurableConversationRecord(id: 1)]))
        let model = Model(id: "context-limit", name: "Context Limit", api: .faux, provider: .faux, baseUrl: "runtime")
        let request = DurableGenerationRequest(conversationID: 1, model: model, transcript: [.user("context")], requestID: "context")
        let admission = try DurableGenerationPlanner.admitBatch(snapshot: try await storage.snapshot(), request: request); _ = try await storage.commit(admission.batch)
        let snapshot = try await storage.snapshot(); let pending = try XCTUnwrap(snapshot.tasks[admission.taskID]); let failure = DurableFailureInfo(code: "context_limit", usage: nil, diagnostics: nil)
        _ = try await storage.commit(try DurableGenerationPlanner.runningContextFailureBatch(task: pending, failure: failure)); try await storage.close()
        let effects = S1BCapture(); await AIRegistry.shared.register(model); await AIRegistry.shared.register(APIProvider(api: .faux, stream: { _, context, _ in AsyncStream { continuation in Task { await effects.record(context); continuation.finish() } } }))
        let session = DurableSession(storage: try DurableJournalStorage(directory: dir)); _ = try await session.resumeQueued()
        while (try await session.snapshot()).tasks[admission.taskID]?.status != .failed { await Task.yield() }
        let effectCount = await effects.effects; XCTAssertEqual(effectCount, 0)
        try await session.close()
    }

    func testSIGKILLAfterProviderEffectAndCompletingSyncReopensWithoutRebilling() async throws {
        #if os(Linux)
        let childKey = "SWIFT_AI_S1B_COMPLETING_CRASH_CHILD"
        if ProcessInfo.processInfo.environment[childKey] == "1" {
            let environment = ProcessInfo.processInfo.environment
            let dir = URL(fileURLWithPath: environment["SWIFT_AI_S1B_CRASH_DIR"]!, isDirectory: true)
            let effectURL = URL(fileURLWithPath: environment["SWIFT_AI_S1B_EFFECT_FILE"]!)
            let storage = try DurableJournalStorage(directory: dir, faultInjector: S1BCrashAfterDirectorySync(targetSeq: 4))
            let model = Model(id: "crash-completing", name: "Crash Completing", api: .faux, provider: .faux, baseUrl: "runtime")
            await AIRegistry.shared.register(model)
            await AIRegistry.shared.register(APIProvider(api: .faux, stream: { model, _, _ in AsyncStream { continuation in Task { try! Data("effect\n".utf8).write(to: effectURL, options: .atomic); var message = Message(role: .assistant, content: [.text("staged")]); message.api = model.api; message.provider = model.provider; message.model = model.id; message.stopReason = .stop; continuation.yield(.done(reason: .stop, message: message)); continuation.finish() } } }))
            let session = DurableSession(storage: storage)
            _ = try await session.submit(DurableGenerationRequest(conversationID: 1, model: model, transcript: [.user("crash completing")], requestID: "crash-completing"))
            XCTFail("expected SIGKILL after completing sync")
            return
        }
        let dir = tempDir(); let effectURL = dir.appendingPathComponent("effects.txt")
        let initial = try DurableJournalStorage(directory: dir); _ = try await initial.commit(DurableCommitBatch(conversations: [DurableConversationRecord(id: 1)])); try await initial.close()
        let process = Process(); process.executableURL = Bundle.main.executableURL; process.arguments = ["SwiftAITests.DurableSubmissionRecoveryTests/testSIGKILLAfterProviderEffectAndCompletingSyncReopensWithoutRebilling"]
        var environment = ProcessInfo.processInfo.environment; environment[childKey] = "1"; environment["SWIFT_AI_S1B_CRASH_DIR"] = dir.path; environment["SWIFT_AI_S1B_EFFECT_FILE"] = effectURL.path; process.environment = environment
        try process.run(); process.waitUntilExit(); XCTAssertTrue([9, 137].contains(Int(process.terminationStatus)))
        let effects = S1BCapture(); let model = Model(id: "crash-completing", name: "Crash Completing", api: .faux, provider: .faux, baseUrl: "runtime")
        await AIRegistry.shared.register(model); await AIRegistry.shared.register(APIProvider(api: .faux, stream: { _, context, _ in AsyncStream { continuation in Task { await effects.record(context); continuation.finish() } } }))
        let session = DurableSession(storage: try DurableJournalStorage(directory: dir)); _ = try await session.resumeQueued()
        while (try await session.snapshot()).tasks.values.first?.status != .completed { await Task.yield() }
        let effectLines = try String(contentsOf: effectURL, encoding: .utf8).split(separator: "\n")
        XCTAssertEqual(effectLines.count, 1); let replayEffects = await effects.effects; XCTAssertEqual(replayEffects, 0)
        try await session.close()
        #endif
    }

    func testSIGKILLAfterAdmissionSyncReopensAndExplicitResumeCompletes() async throws {
        #if os(Linux)
        if ProcessInfo.processInfo.environment["SWIFT_AI_S1B_CRASH_CHILD"] == "1" {
            let dir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SWIFT_AI_S1B_CRASH_DIR"]!, isDirectory: true)
            let storage = try DurableJournalStorage(directory: dir, faultInjector: S1BCrashAfterDirectorySync())
            let model = Model(id: "crash-resume", name: "Crash", api: .faux, provider: .faux, baseUrl: "")
            let request = DurableGenerationRequest(conversationID: 1, model: model, transcript: [.user("crash")], requestID: "crash")
            let admission = try DurableGenerationPlanner.admitBatch(snapshot: try await storage.snapshot(), request: request)
            _ = try await storage.commit(admission.batch)
            XCTFail("expected SIGKILL before admission ACK")
            return
        }
        let dir = tempDir(); let initial = try DurableJournalStorage(directory: dir)
        _ = try await initial.commit(DurableCommitBatch(conversations: [DurableConversationRecord(id: 1)])); try await initial.close()
        let process = Process(); process.executableURL = Bundle.main.executableURL; process.arguments = ["SwiftAITests.DurableSubmissionRecoveryTests/testSIGKILLAfterAdmissionSyncReopensAndExplicitResumeCompletes"]
        var environment = ProcessInfo.processInfo.environment; environment["SWIFT_AI_S1B_CRASH_CHILD"] = "1"; environment["SWIFT_AI_S1B_CRASH_DIR"] = dir.path; process.environment = environment
        try process.run(); process.waitUntilExit(); XCTAssertTrue([9, 137].contains(Int(process.terminationStatus)))
        let effects = S1BCapture(); let model = Model(id: "crash-resume", name: "Crash", api: .faux, provider: .faux, baseUrl: "runtime")
        await AIRegistry.shared.register(model)
        await AIRegistry.shared.register(APIProvider(api: .faux, stream: { model, context, _ in AsyncStream { continuation in Task { await effects.record(context); var message = Message(role: .assistant, content: [.text("resumed")]); message.api = model.api; message.provider = model.provider; message.model = model.id; message.stopReason = .stop; continuation.yield(.done(reason: .stop, message: message)); continuation.finish() } } }))
        let reopened = try DurableJournalStorage(directory: dir); let session = DurableSession(storage: reopened); _ = try await session.resumeQueued()
        while (try await session.snapshot()).tasks.values.first?.status != .completed { await Task.yield() }
        let effectCount = await effects.effects; XCTAssertEqual(effectCount, 1)
        try await session.close()
        #endif
    }

    func testUncertainSettlementStopsQueuedEffectsAndReleasesJournalWriter() async throws {
        let dir = tempDir(); let initial = try DurableJournalStorage(directory: dir); _ = try await initial.commit(DurableCommitBatch(conversations: [DurableConversationRecord(id: 1)])); try await initial.close()
        let barrier = S1BRecoveryBarrier(); let hooks = S1BRecoveryHookBox(); let effects = S1BCapture()
        let model = Model(id: "uncertain-stop", name: "Uncertain Stop", api: .faux, provider: .faux, baseUrl: "runtime")
        await AIRegistry.shared.register(model)
        await AIRegistry.shared.register(APIProvider(api: .faux, stream: { model, context, _ in AsyncStream { continuation in Task { await effects.record(context); await barrier.hold(); var message = Message(role: .assistant, content: [.text("first")]); message.api = model.api; message.provider = model.provider; message.model = model.id; message.stopReason = .stop; continuation.yield(.done(reason: .stop, message: message)); continuation.finish() } } }))
        let storage = try DurableJournalStorage(directory: dir, faultInjector: S1BFailAfterDirectorySync(targetSeq: 5))
        let session = DurableSession(storage: storage, testingHooks: DurableSessionTestingHooks(onSubmitWaiter: { hooks.mark($0) }), capacity: 2)
        let first = Task { try await session.submit(DurableGenerationRequest(conversationID: 1, model: model, transcript: [.user("first")], requestID: "first")) }
        await hooks.wait(1); await barrier.waitEntered()
        let second = Task { try await session.submit(DurableGenerationRequest(conversationID: 1, model: model, transcript: [.user("second")], requestID: "second")) }
        await hooks.wait(2); await barrier.release()
        await XCTAssertThrowsAsyncError(try await first.value); await XCTAssertThrowsAsyncError(try await second.value)
        await XCTAssertThrowsAsyncError(try await session.close())
        let effectCount = await effects.effects; XCTAssertEqual(effectCount, 1)
        let reopened = try DurableJournalStorage(directory: dir); let snapshot = try await reopened.snapshot()
        XCTAssertEqual(snapshot.tasks.values.filter { $0.status == .completing }.count, 1)
        XCTAssertEqual(snapshot.tasks.values.filter { $0.status == .pending }.count, 1)
        try await reopened.close()
    }

    func testTypedProviderFailureDoesNotStopFollowingQueuedGeneration() async throws {
        let effects = S1BCapture(); let model = Model(id: "typed-continue", name: "Typed Continue", api: .faux, provider: .faux, baseUrl: "runtime")
        await AIRegistry.shared.register(model)
        await AIRegistry.shared.register(APIProvider(api: .faux, stream: { model, context, _ in AsyncStream { continuation in Task { await effects.record(context); var message = Message(role: .assistant, content: [.text("terminal")]); message.api = model.api; message.provider = model.provider; message.model = model.id; if Harness.textContent(in: context.messages.last) == "first" { message.stopReason = .error; message.errorMessage = "typed"; continuation.yield(.error(reason: .error, message: message, error: AIError.provider("typed"))) } else { message.stopReason = .stop; continuation.yield(.done(reason: .stop, message: message)) }; continuation.finish() } } }))
        let session = DurableSession(storage: DurableMemoryStorage()); let conversation = try await session.createConversation()
        async let first = session.submit(DurableGenerationRequest(conversationID: conversation.id, model: model, transcript: [.user("first")], requestID: "typed-first"))
        async let second = session.submit(DurableGenerationRequest(conversationID: conversation.id, model: model, transcript: [.user("second")], requestID: "typed-second"))
        let results = try await [first, second]
        XCTAssertEqual(Set(results.map(\.task.status)), Set([.failed, .completed]))
        let effectCount = await effects.effects; XCTAssertEqual(effectCount, 2)
        try await session.close()
    }

    func testRecoverySweepProcessesMoreThanCapacityWithoutUnboundedQueue() async throws {
        let effects = S1BCapture(); let model = Model(id: "bounded-recovery", name: "Bounded Recovery", api: .faux, provider: .faux, baseUrl: "runtime")
        await AIRegistry.shared.register(model)
        await AIRegistry.shared.register(APIProvider(api: .faux, stream: { model, context, _ in AsyncStream { continuation in Task { await effects.record(context); var message = Message(role: .assistant, content: [.text("ok")]); message.api = model.api; message.provider = model.provider; message.model = model.id; message.stopReason = .stop; continuation.yield(.done(reason: .stop, message: message)); continuation.finish() } } }))
        let storage = DurableMemoryStorage(); _ = try await storage.commit(DurableCommitBatch(conversations: [DurableConversationRecord(id: 1)]))
        for index in 0..<5 { let request = DurableGenerationRequest(conversationID: 1, model: model, transcript: [.user("\(index)")], requestID: "bounded-\(index)"); let admission = try DurableGenerationPlanner.admitBatch(snapshot: try await storage.snapshot(), request: request); _ = try await storage.commit(admission.batch) }
        let session = DurableSession(storage: storage, capacity: 2); _ = try await session.resumeQueued()
        while (try await session.snapshot()).tasks.values.contains(where: { $0.status != .completed }) { await Task.yield() }
        let effectCount = await effects.effects; XCTAssertEqual(effectCount, 5)
        try await session.close()
    }

    func testRepeatedResumeCoalescesOneProviderEffect() async throws {
        let effects = S1BCapture(); let model = Model(id: "resume", name: "Resume", api: .faux, provider: .faux, baseUrl: "runtime")
        await AIRegistry.shared.register(model)
        await AIRegistry.shared.register(APIProvider(api: .faux, stream: { model, context, _ in AsyncStream { continuation in Task { await effects.record(context); var message = Message(role: .assistant, content: [.text("ok")]); message.api = model.api; message.provider = model.provider; message.model = model.id; message.stopReason = .stop; continuation.yield(.done(reason: .stop, message: message)); continuation.finish() } } }))
        let storage = DurableMemoryStorage(); _ = try await storage.commit(DurableCommitBatch(conversations: [DurableConversationRecord(id: 1)]))
        let request = DurableGenerationRequest(conversationID: 1, model: model, transcript: [.user("one")], requestID: "same")
        let admission = try DurableGenerationPlanner.admitBatch(snapshot: try await storage.snapshot(), request: request); _ = try await storage.commit(admission.batch)
        let session = DurableSession(storage: storage)
        async let first = session.resumeQueued(); async let second = session.resumeQueued()
        _ = try await (first, second)
        while (try await session.snapshot()).tasks[admission.taskID]?.status != .completed { await Task.yield() }
        let effectCount = await effects.effects
        XCTAssertEqual(effectCount, 1)
        try await session.close()
    }
}
