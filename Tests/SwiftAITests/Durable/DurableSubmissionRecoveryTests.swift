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
private final class S1CCrashAtMarker: DurableJournalFaultInjector, @unchecked Sendable {
    private let markers: [Data]
    private let lock = NSLock()
    private var targetSeq: Int64?
    init(_ marker: String) { self.markers = marker.split(separator: "|").map { Data($0.utf8) } }
    func beforeAppend(seq: Int64, frame: Data) throws { lock.lock(); if targetSeq == nil, markers.allSatisfy({ frame.range(of: $0) != nil }) { targetSeq = seq }; lock.unlock() }
    func afterDirectorySyncBeforeAck(seq: Int64) throws { lock.lock(); let crash = targetSeq == seq; lock.unlock(); if crash { kill(getpid(), SIGKILL) } }
}

private struct S1BCrashAfterDirectorySync: DurableJournalFaultInjector {
    let targetSeq: Int64?
    init(targetSeq: Int64? = nil) { self.targetSeq = targetSeq }
    func afterDirectorySyncBeforeAck(seq: Int64) throws { if targetSeq == nil || targetSeq == seq { kill(getpid(), SIGKILL) } }
}
#endif

final class DurableSubmissionRecoveryTests: XCTestCase {
    private func tempDir() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("swift-ai-s1b-recovery-\(UUID().uuidString)", isDirectory: true) }

    private func appendReceipt(_ value: String, to url: URL) {
        if !FileManager.default.fileExists(atPath: url.path) { _ = FileManager.default.createFile(atPath: url.path, contents: nil) }
        let handle = try! FileHandle(forWritingTo: url); try! handle.seekToEnd(); try! handle.write(contentsOf: Data((value + "\n").utf8)); try! handle.close()
    }

    private func installCrashToolRuntime(effectURL: URL, modelURL: URL, replay: DurableToolReplayPolicy = .safe, crashAfterEffect: Bool = false, billedFailureAfterTool: Bool = false) async throws -> (DurableToolRegistry, Model) {
        let registry = DurableToolRegistry(); let schema: JSONValue = .object(["type": .string("object")])
        try await registry.register(DurableToolRegistration(definition: Tool(name: "effect", description: "", parameters: schema), implementationID: "effect.native", implementationVersion: "1", replayPolicy: replay, execute: { execution in self.appendReceipt(execution.idempotencyKey, to: effectURL); if crashAfterEffect { kill(getpid(), SIGKILL) }; var usage = Usage(); usage.input = 1; usage.totalTokens = 1; return DurableToolResult(content: "effect", usage: usage) }))
        let model = Model(id: "s1c-crash", name: "S1c Crash", api: .faux, provider: .faux, baseUrl: "runtime"); await AIRegistry.shared.register(model)
        await AIRegistry.shared.register(APIProvider(api: .faux, stream: { model, context, _ in AsyncStream { continuation in Task { self.appendReceipt("model", to: modelURL); var message: Message; var usage = Usage(); let afterTool = context.messages.contains(where: { $0.role == .toolResult }); usage.input = afterTool ? 3 : 2; usage.totalTokens = usage.input; if afterTool { message = Message(role: .assistant, content: [.text("done")]); message.stopReason = billedFailureAfterTool ? .error : .stop; message.errorMessage = billedFailureAfterTool ? "billed parent failure" : nil } else { message = Message(role: .assistant, content: [.toolCall(id: "effect-call", name: "effect", arguments: [:])]); message.stopReason = .toolUse }; message.api = model.api; message.provider = model.provider; message.model = model.id; message.usage = usage; if billedFailureAfterTool { if afterTool { continuation.yield(.error(reason: .error, message: message, error: AIError.provider("billed parent failure"))) } else { continuation.yield(.done(reason: .toolUse, message: message)) } } else { continuation.yield(.done(reason: message.stopReason!, message: message)) }; continuation.finish() } } }))
        return (registry, model)
    }

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

    func testS1cNamedJournalSIGKILLBoundariesRecoverOwnedToolLoop() async throws {
        #if os(Linux)
        let childKey = "SWIFT_AI_S1C_CRASH_CHILD"
        if ProcessInfo.processInfo.environment[childKey] == "1" {
            let environment = ProcessInfo.processInfo.environment
            let dir = URL(fileURLWithPath: environment["SWIFT_AI_S1C_CRASH_DIR"]!, isDirectory: true)
            let effectURL = URL(fileURLWithPath: environment["SWIFT_AI_S1C_EFFECT_FILE"]!), modelURL = URL(fileURLWithPath: environment["SWIFT_AI_S1C_MODEL_FILE"]!)
            let marker = environment["SWIFT_AI_S1C_MARKER"]!, replay = DurableToolReplayPolicy(rawValue: environment["SWIFT_AI_S1C_REPLAY"]!)!
            let runtime = try await installCrashToolRuntime(effectURL: effectURL, modelURL: modelURL, replay: replay)
            let session = DurableSession(storage: try DurableJournalStorage(directory: dir, faultInjector: S1CCrashAtMarker(marker)), toolRegistry: runtime.0)
            _ = try await session.submit(DurableGenerationRequest(conversationID: 1, model: runtime.1, transcript: [.user("crash")], requestID: "named-boundary"))
            XCTFail("expected SIGKILL at \(marker)")
            return
        }
        let boundaries: [(String, DurableToolReplayPolicy, DurableTaskStatus, String)] = [("tool.intent", .safe, .waiting, "pending"), ("started", .safe, .waiting, "started"), ("completing|tool", .safe, .waiting, "completing"), ("tool-result", .safe, .waiting, "terminal"), ("\"round\":2|\"phase\":\"running\"", .safe, .running, "parent-resumed"), ("terminal-staged", .safe, .completing, "parent-completing")]
        for (marker, replay, expectedParent, expectedChildPhase) in boundaries {
            let dir = tempDir(), effectURL = dir.appendingPathComponent("effects.txt"), modelURL = dir.appendingPathComponent("models.txt")
            let initial = try DurableJournalStorage(directory: dir); _ = try await initial.commit(DurableCommitBatch(conversations: [DurableConversationRecord(id: 1)])); try await initial.close()
            let process = Process(); process.executableURL = Bundle.main.executableURL; process.arguments = ["SwiftAITests.DurableSubmissionRecoveryTests/testS1cNamedJournalSIGKILLBoundariesRecoverOwnedToolLoop"]
            var environment = ProcessInfo.processInfo.environment; environment[childKey] = "1"; environment["SWIFT_AI_S1C_CRASH_DIR"] = dir.path; environment["SWIFT_AI_S1C_EFFECT_FILE"] = effectURL.path; environment["SWIFT_AI_S1C_MODEL_FILE"] = modelURL.path; environment["SWIFT_AI_S1C_MARKER"] = marker; environment["SWIFT_AI_S1C_REPLAY"] = replay.rawValue; process.environment = environment
            try process.run(); process.waitUntilExit(); XCTAssertTrue([9, 137].contains(Int(process.terminationStatus)), marker)
            let runtime = try await installCrashToolRuntime(effectURL: effectURL, modelURL: modelURL, replay: replay)
            let reopenedStorage = try DurableJournalStorage(directory: dir); let killed = try await reopenedStorage.snapshot(); let killedParent = try XCTUnwrap(killed.tasks.values.first { $0.kind == "generation" }); XCTAssertEqual(killedParent.status, expectedParent, marker); let killedChild = killed.tasks.values.first { $0.kind == "tool" }; if expectedChildPhase == "pending" { XCTAssertEqual(killedChild?.status, .pending, marker) } else if expectedChildPhase == "started" { XCTAssertEqual(killedChild?.status, .running, marker); XCTAssertEqual(killedChild?.checkpoint?.objectValue?["phase"], .string("started"), marker) } else if expectedChildPhase == "completing" { XCTAssertEqual(killedChild?.status, .completing, marker) } else if expectedChildPhase == "terminal" { XCTAssertTrue(killedChild.map { [.completed, .failed, .aborted].contains($0.status) } == true, marker); XCTAssertNotNil(killedChild?.outcome?.objectValue?["entryID"], marker) } else if expectedChildPhase == "parent-resumed" { XCTAssertEqual(killedParent.status, .running, marker); XCTAssertTrue(killed.tasks.values.filter { $0.kind == "tool" }.allSatisfy { [.completed, .failed, .aborted].contains($0.status) }, marker) } else { XCTAssertEqual(killedParent.status, .completing, marker) }
            let session = DurableSession(storage: reopenedStorage, toolRegistry: runtime.0); _ = try await session.resumeQueued()
            while (try await session.snapshot()).tasks.values.contains(where: { $0.kind == "generation" && ![.completed, .failed, .aborted].contains($0.status) }) { await Task.yield() }
            let snapshot = try await session.snapshot(); XCTAssertEqual(snapshot.tasks.values.first { $0.kind == "generation" }?.status, .completed, marker)
            let modelLines = try String(contentsOf: modelURL, encoding: .utf8).split(separator: "\n"); XCTAssertEqual(modelLines.count, 2, marker)
            let effectLines = try String(contentsOf: effectURL, encoding: .utf8).split(separator: "\n")
            XCTAssertEqual(effectLines.count, 1, marker); XCTAssertEqual(Set(effectLines).count, 1, marker)
            if marker == "started" { XCTAssertNotNil(snapshot.documents.values.first { $0.kind == "tool.billing-incomplete" }, marker) }
            XCTAssertNotNil(snapshot.documents.values.first { $0.kind == "generation.usage.round.1" }, marker)
            try await session.close(); let verify = try DurableJournalStorage(directory: dir); let verified = try await verify.snapshot(); XCTAssertEqual(verified.tasks.values.first { $0.kind == "generation" }?.status, .completed); try await verify.close()
        }
        #endif
    }

    func testS1cSafeEffectLossReplaysStableLogicalIdentityAndMarksUnknownBilling() async throws {
        #if os(Linux)
        let childKey = "SWIFT_AI_S1C_SAFE_EFFECT_CRASH_CHILD"
        if ProcessInfo.processInfo.environment[childKey] == "1" {
            let environment = ProcessInfo.processInfo.environment, dir = URL(fileURLWithPath: environment["SWIFT_AI_S1C_CRASH_DIR"]!, isDirectory: true)
            let runtime = try await installCrashToolRuntime(effectURL: URL(fileURLWithPath: environment["SWIFT_AI_S1C_EFFECT_FILE"]!), modelURL: URL(fileURLWithPath: environment["SWIFT_AI_S1C_MODEL_FILE"]!), replay: .safe, crashAfterEffect: true)
            let session = DurableSession(storage: try DurableJournalStorage(directory: dir), toolRegistry: runtime.0); _ = try await session.submit(DurableGenerationRequest(conversationID: 1, model: runtime.1, transcript: [.user("safe")], requestID: "safe")); return
        }
        let dir = tempDir(), effectURL = dir.appendingPathComponent("effects.txt"), modelURL = dir.appendingPathComponent("models.txt"); let initial = try DurableJournalStorage(directory: dir); _ = try await initial.commit(DurableCommitBatch(conversations: [DurableConversationRecord(id: 1)])); try await initial.close(); let process = Process(); process.executableURL = Bundle.main.executableURL; process.arguments = ["SwiftAITests.DurableSubmissionRecoveryTests/testS1cSafeEffectLossReplaysStableLogicalIdentityAndMarksUnknownBilling"]; var environment = ProcessInfo.processInfo.environment; environment[childKey] = "1"; environment["SWIFT_AI_S1C_CRASH_DIR"] = dir.path; environment["SWIFT_AI_S1C_EFFECT_FILE"] = effectURL.path; environment["SWIFT_AI_S1C_MODEL_FILE"] = modelURL.path; process.environment = environment; try process.run(); process.waitUntilExit(); XCTAssertTrue([9, 137].contains(Int(process.terminationStatus)))
        let before = try String(contentsOf: effectURL, encoding: .utf8).split(separator: "\n"); XCTAssertEqual(before.count, 1); let runtime = try await installCrashToolRuntime(effectURL: effectURL, modelURL: modelURL, replay: .safe); let session = DurableSession(storage: try DurableJournalStorage(directory: dir), toolRegistry: runtime.0); _ = try await session.resumeQueued(); while (try await session.snapshot()).tasks.values.contains(where: { $0.kind == "generation" && ![.completed, .failed, .aborted].contains($0.status) }) { await Task.yield() }; let effects = try String(contentsOf: effectURL, encoding: .utf8).split(separator: "\n"); XCTAssertEqual(effects.count, 2); XCTAssertEqual(Set(effects).count, 1); let snapshot = try await session.snapshot(); XCTAssertNotNil(snapshot.documents.values.first { $0.kind == "tool.billing-incomplete" }); XCTAssertEqual(snapshot.tasks.values.first { $0.kind == "generation" }?.status, .completed); try await session.close()
        #endif
    }

    func testS1cBilledParentFailureACKLossRecoversUsageExactlyOnceWithoutEffects() async throws {
        #if os(Linux)
        let childKey = "SWIFT_AI_S1C_BILLED_FAILURE_CHILD"
        if ProcessInfo.processInfo.environment[childKey] == "1" {
            let environment = ProcessInfo.processInfo.environment, dir = URL(fileURLWithPath: environment["SWIFT_AI_S1C_CRASH_DIR"]!, isDirectory: true); let runtime = try await installCrashToolRuntime(effectURL: URL(fileURLWithPath: environment["SWIFT_AI_S1C_EFFECT_FILE"]!), modelURL: URL(fileURLWithPath: environment["SWIFT_AI_S1C_MODEL_FILE"]!), billedFailureAfterTool: true); let session = DurableSession(storage: try DurableJournalStorage(directory: dir, faultInjector: S1CCrashAtMarker("\"failure\":|\"phase\":\"completing\"")), toolRegistry: runtime.0); _ = try await session.submit(DurableGenerationRequest(conversationID: 1, model: runtime.1, transcript: [.user("billed")], requestID: "billed")); return
        }
        let dir = tempDir(), effectURL = dir.appendingPathComponent("effects.txt"), modelURL = dir.appendingPathComponent("models.txt"); let initial = try DurableJournalStorage(directory: dir); _ = try await initial.commit(DurableCommitBatch(conversations: [DurableConversationRecord(id: 1)])); try await initial.close(); let process = Process(); process.executableURL = Bundle.main.executableURL; process.arguments = ["SwiftAITests.DurableSubmissionRecoveryTests/testS1cBilledParentFailureACKLossRecoversUsageExactlyOnceWithoutEffects"]; var environment = ProcessInfo.processInfo.environment; environment[childKey] = "1"; environment["SWIFT_AI_S1C_CRASH_DIR"] = dir.path; environment["SWIFT_AI_S1C_EFFECT_FILE"] = effectURL.path; environment["SWIFT_AI_S1C_MODEL_FILE"] = modelURL.path; process.environment = environment; try process.run(); process.waitUntilExit(); XCTAssertTrue([9, 137].contains(Int(process.terminationStatus))); let beforeEffects = try String(contentsOf: effectURL, encoding: .utf8).split(separator: "\n").count, beforeModels = try String(contentsOf: modelURL, encoding: .utf8).split(separator: "\n").count
        let runtime = try await installCrashToolRuntime(effectURL: effectURL, modelURL: modelURL, billedFailureAfterTool: true); let storage = try DurableJournalStorage(directory: dir); let killed = try await storage.snapshot(); XCTAssertEqual(killed.tasks.values.first { $0.kind == "generation" }?.status, .completing); let session = DurableSession(storage: storage, toolRegistry: runtime.0); _ = try await session.resumeQueued(); while (try await session.snapshot()).tasks.values.contains(where: { $0.kind == "generation" && ![.completed, .failed, .aborted].contains($0.status) }) { await Task.yield() }; let snapshot = try await session.snapshot(); XCTAssertEqual(snapshot.tasks.values.first { $0.kind == "generation" }?.status, .failed); XCTAssertEqual(try String(contentsOf: effectURL, encoding: .utf8).split(separator: "\n").count, beforeEffects); XCTAssertEqual(try String(contentsOf: modelURL, encoding: .utf8).split(separator: "\n").count, beforeModels); XCTAssertEqual(snapshot.documents.values.filter { $0.kind == "generation.usage.round.2" }.count, 1); let round1 = try XCTUnwrap(snapshot.documents.values.first { $0.kind == "generation.usage.round.1" }?.value.objectValue); let round2 = try XCTUnwrap(snapshot.documents.values.first { $0.kind == "generation.usage.round.2" }?.value.objectValue); XCTAssertEqual(round1["model"], .string("faux/faux/s1c-crash")); XCTAssertEqual(round2["model"], .string("faux/faux/s1c-crash")); let aggregate = try XCTUnwrap(snapshot.documents.values.first { $0.kind == "durable.usage" }?.value.objectValue); XCTAssertEqual(aggregate["input"], .number(6)); XCTAssertEqual(aggregate["totalTokens"], .number(6)); XCTAssertEqual(aggregate["perModel"]?.objectValue?["faux/faux/s1c-crash"]?.objectValue?["input"], .number(5)); XCTAssertEqual(aggregate["perTool"]?.objectValue?["tool:effect.native/1"]?.objectValue?["input"], .number(1)); try await session.close()
        #endif
    }

    func testS1cUnsafeEffectLossDoesNotReplayAndMarksUnknownBilling() async throws {
        #if os(Linux)
        let childKey = "SWIFT_AI_S1C_EFFECT_CRASH_CHILD"
        if ProcessInfo.processInfo.environment[childKey] == "1" {
            let environment = ProcessInfo.processInfo.environment, dir = URL(fileURLWithPath: environment["SWIFT_AI_S1C_CRASH_DIR"]!, isDirectory: true)
            let runtime = try await installCrashToolRuntime(effectURL: URL(fileURLWithPath: environment["SWIFT_AI_S1C_EFFECT_FILE"]!), modelURL: URL(fileURLWithPath: environment["SWIFT_AI_S1C_MODEL_FILE"]!), replay: .unsafe, crashAfterEffect: true)
            let session = DurableSession(storage: try DurableJournalStorage(directory: dir), toolRegistry: runtime.0); _ = try await session.submit(DurableGenerationRequest(conversationID: 1, model: runtime.1, transcript: [.user("unsafe")], requestID: "unsafe")); return
        }
        let dir = tempDir(), effectURL = dir.appendingPathComponent("effects.txt"), modelURL = dir.appendingPathComponent("models.txt"); let initial = try DurableJournalStorage(directory: dir); _ = try await initial.commit(DurableCommitBatch(conversations: [DurableConversationRecord(id: 1)])); try await initial.close()
        let process = Process(); process.executableURL = Bundle.main.executableURL; process.arguments = ["SwiftAITests.DurableSubmissionRecoveryTests/testS1cUnsafeEffectLossDoesNotReplayAndMarksUnknownBilling"]; var environment = ProcessInfo.processInfo.environment; environment[childKey] = "1"; environment["SWIFT_AI_S1C_CRASH_DIR"] = dir.path; environment["SWIFT_AI_S1C_EFFECT_FILE"] = effectURL.path; environment["SWIFT_AI_S1C_MODEL_FILE"] = modelURL.path; process.environment = environment; try process.run(); process.waitUntilExit(); XCTAssertTrue([9, 137].contains(Int(process.terminationStatus)))
        let runtime = try await installCrashToolRuntime(effectURL: effectURL, modelURL: modelURL, replay: .unsafe); let session = DurableSession(storage: try DurableJournalStorage(directory: dir), toolRegistry: runtime.0); _ = try await session.resumeQueued(); while (try await session.snapshot()).tasks.values.contains(where: { $0.kind == "generation" && ![.completed, .failed, .aborted].contains($0.status) }) { await Task.yield() }
        let effects = try String(contentsOf: effectURL, encoding: .utf8).split(separator: "\n"); XCTAssertEqual(effects.count, 1)
        let snapshot = try await session.snapshot(); XCTAssertNotNil(snapshot.documents.values.first { $0.kind == "tool.billing-incomplete" }); XCTAssertEqual(snapshot.tasks.values.first { $0.kind == "generation" }?.status, .completed); try await session.close()
        #endif
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
