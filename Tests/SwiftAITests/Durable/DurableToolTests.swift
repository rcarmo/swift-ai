import Foundation
import XCTest
@testable import SwiftAI

private actor S1CToolBarrier {
    private var entered = false
    private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []
    private var released = false
    func hold() async { entered = true; let ready = enteredWaiters; enteredWaiters = []; for waiter in ready { waiter.resume() }; if released { return }; await withCheckedContinuation { releaseWaiters.append($0) } }
    func waitEntered() async { if entered { return }; await withCheckedContinuation { enteredWaiters.append($0) } }
    func release() { released = true; let waiters = releaseWaiters; releaseWaiters = []; for waiter in waiters { waiter.resume() } }
}

private final class S1CTestSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    private var waiter: CheckedContinuation<Void, Never>?
    private var closeFinished = false
    func fire() { lock.lock(); value = true; let waiter = waiter; self.waiter = nil; lock.unlock(); waiter?.resume() }
    func wait() async { await withCheckedContinuation { continuation in lock.lock(); if value { lock.unlock(); continuation.resume(); return }; waiter = continuation; lock.unlock() } }
    func finishClose() { lock.lock(); closeFinished = true; lock.unlock() }
    func isCloseFinished() -> Bool { lock.lock(); defer { lock.unlock() }; return closeFinished }
}

private actor S1CChildGate {
    private var ids: [Int64]?
    private var idWaiters: [CheckedContinuation<[Int64], Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []
    private var released = false
    func hold(_ value: [Int64]) async { ids = value; let waiters = idWaiters; idWaiters = []; for waiter in waiters { waiter.resume(returning: value) }; if released { return }; await withCheckedContinuation { releaseWaiters.append($0) } }
    func waitIDs() async -> [Int64] { if let ids { return ids }; return await withCheckedContinuation { idWaiters.append($0) } }
    func release() { released = true; let waiters = releaseWaiters; releaseWaiters = []; for waiter in waiters { waiter.resume() } }
}

private actor S1CToolCapture {
    var effects = 0
    var executions: [DurableToolExecution] = []
    var contexts: [AIContext] = []
    func tool(_ execution: DurableToolExecution) { effects += 1; executions.append(execution) }
    func context(_ context: AIContext) { contexts.append(context) }
}

final class DurableToolTests: XCTestCase {
    private func registry(capture: S1CToolCapture, replay: DurableToolReplayPolicy = .safe) async throws -> DurableToolRegistry {
        let registry = DurableToolRegistry()
        let schema: JSONValue = .object(["type": .string("object"), "properties": .object(["a": .object(["type": .string("integer"), "minimum": .number(0), "maximum": .number(100)]), "b": .object(["type": .string("integer"), "minimum": .number(0), "maximum": .number(100)])]), "required": .array([.string("a"), .string("b")]), "additionalProperties": .bool(false)])
        try await registry.register(DurableToolRegistration(definition: Tool(name: "sum", description: "sum", parameters: schema), implementationID: "sum.native", implementationVersion: "1", replayPolicy: replay, execute: { execution in
            await capture.tool(execution)
            let a = execution.arguments["a"]?.doubleValue ?? 0, b = execution.arguments["b"]?.doubleValue ?? 0
            var usage = Usage(); usage.input = 1; usage.output = 1; usage.totalTokens = 2
            return DurableToolResult(content: "\(Int(a + b))", usage: usage, documents: [DurableToolApplicationDocument(target: .toolTask, suffix: "sum", value: .number(a + b))])
        }))
        return registry
    }

    private func installModel(capture: S1CToolCapture) async -> Model {
        let model = Model(id: "s1c-model", name: "S1c", api: .faux, provider: .faux, baseUrl: "runtime")
        await AIRegistry.shared.register(model)
        await AIRegistry.shared.register(APIProvider(api: .faux, stream: { model, context, _ in AsyncStream { continuation in Task {
            await capture.context(context)
            var message: Message
            if context.messages.contains(where: { $0.role == .toolResult }) {
                message = Message(role: .assistant, content: [.text("answer 5")]); message.stopReason = .stop
            } else {
                message = Message(role: .assistant, content: [.toolCall(id: "call-1", name: "sum", arguments: ["a": .number(2), "b": .number(3)])]); message.stopReason = .toolUse
            }
            message.api = model.api; message.provider = model.provider; message.model = model.id
            var usage = Usage(); usage.input = 2; usage.output = 1; usage.totalTokens = 3; message.usage = usage
            continuation.yield(.done(reason: message.stopReason!, message: message)); continuation.finish()
        } } }))
        return model
    }

    func testOwnedToolRoundCommitsResultAwareAnswerAndExactContext() async throws {
        let capture = S1CToolCapture(); let registry = try await registry(capture: capture); let model = await installModel(capture: capture)
        let session = DurableSession(storage: DurableMemoryStorage(), testingHooks: DurableSessionTestingHooks(), capacity: 1, toolRegistry: registry)
        let conversation = try await session.createConversation()
        let result = try await session.submit(DurableGenerationRequest(conversationID: conversation.id, model: model, transcript: [.user("sum")], requestID: "sum"))
        XCTAssertEqual(result.task.status, .completed); XCTAssertEqual(result.entry?.messages?.first?.content.first?.text, "answer 5")
        let effects = await capture.effects; XCTAssertEqual(effects, 1)
        let executions = await capture.executions; XCTAssertEqual(executions.first?.arguments, ["a": .number(2), "b": .number(3)]); XCTAssertEqual(executions.first?.idempotencyKey, executions.first?.durableToolID.appending("-1"))
        let contexts = await capture.contexts; XCTAssertEqual(contexts.count, 2)
        XCTAssertEqual(contexts[1].messages.map(\.role), [.user, .assistant, .toolResult])
        XCTAssertEqual(contexts[1].messages[1].content.first?.id, "call-1"); XCTAssertEqual(contexts[1].messages[2].toolCallId, "call-1")
        let snapshot = try await session.snapshot()
        XCTAssertEqual(snapshot.tasks.values.filter { $0.kind == "tool" }.count, 1)
        XCTAssertNotNil(snapshot.documents.values.first { $0.kind == "tool.usage.attempt.1" })
        let roundReceipts = snapshot.documents.values.filter { $0.kind.hasPrefix("generation.usage.round.") }; XCTAssertEqual(roundReceipts.count, 2); XCTAssertTrue(roundReceipts.allSatisfy { $0.value.objectValue?["model"] == .string("faux/faux/s1c-model") })
        XCTAssertNotNil(snapshot.documents.values.first { $0.kind == "tool.application.sum.sum" })
        try await session.close()
    }

    func testOldS1bIntentDecodesDefaultsAndProducesPlainUsageKind() async throws {
        let capture = S1CToolCapture(); let model = await installModel(capture: capture); let request = DurableGenerationRequest(conversationID: 1, model: model, transcript: [.user("legacy")]); let intent = DurableGenerationIntent(request: request, inputEntryID: 2); var encoded = try DurableGenerationPlanner.encodeJSON(intent).objectValue!; encoded.removeValue(forKey: "offeredTools"); encoded.removeValue(forKey: "roundMessages"); encoded.removeValue(forKey: "round"); let decoded = try DurableGenerationPlanner.decodeJSON(DurableGenerationIntent.self, from: .object(encoded)); XCTAssertEqual(decoded.offeredTools ?? [], []); XCTAssertEqual(decoded.round ?? 1, 1)
    }

    func testSchemaSubsetRejectsUnknownCoercionAndNestedViolations() async throws {
        let registry = DurableToolRegistry()
        await XCTAssertThrowsAsyncError(try await registry.register(DurableToolRegistration(definition: Tool(name: "bad", description: "", parameters: .object(["type": .string("object"), "oneOf": .array([])])), implementationID: "bad", implementationVersion: "1", execute: { _ in DurableToolResult(content: "") })))
        var mutated = try DurableToolRegistration(definition: Tool(name: "mutated", description: "", parameters: .object(["type": .string("object")])), implementationID: "mutated", implementationVersion: "1", execute: { _ in DurableToolResult(content: "") }); mutated.binding.schemaIdentity = "forged"; await XCTAssertThrowsAsyncError(try await registry.register(mutated))
        let schema: JSONValue = .object(["type": .string("object"), "properties": .object(["items": .object(["type": .string("array"), "minItems": .number(1), "items": .object(["type": .string("object"), "properties": .object(["name": .object(["type": .string("string"), "enum": .array([.string("x")])])]), "required": .array([.string("name")]), "additionalProperties": .bool(false)])])]), "required": .array([.string("items")]), "additionalProperties": .bool(false)])
        try DurableToolSchema.validate(arguments: ["items": .array([.object(["name": .string("x")])])], against: schema)
        XCTAssertThrowsError(try DurableToolSchema.validate(arguments: ["items": .array([.object(["name": .number(1)])])], against: schema))
        XCTAssertThrowsError(try DurableToolSchema.validate(arguments: ["items": .array([.object(["name": .string("x"), "extra": .bool(true)])])], against: schema))
    }

    func testBindingSnapshotParticipatesInRequestIDSemantics() async throws {
        let capture = S1CToolCapture(); let model = await installModel(capture: capture); let firstRegistry = try await registry(capture: capture)
        let storage = DurableMemoryStorage(); let first = DurableSession(storage: storage, toolRegistry: firstRegistry); let conversation = try await first.createConversation()
        _ = try await first.submit(DurableGenerationRequest(conversationID: conversation.id, model: model, transcript: [.user("sum")], requestID: "same")); let saved = try await first.snapshot(); try await first.close()
        let changed = try await registry(capture: capture, replay: .unsafe); let reopened = DurableSession(storage: DurableMemoryStorage(snapshot: saved), toolRegistry: changed)
        await XCTAssertThrowsAsyncError(try await reopened.submit(DurableGenerationRequest(conversationID: conversation.id, model: model, transcript: [.user("sum")], requestID: "same")))
        try await reopened.close()
    }

    func testTwoToolRoundsWithinOneGenerationPreserveExactOrderedMessages() async throws {
        let capture = S1CToolCapture(); let registry = try await registry(capture: capture); let model = Model(id: "s1c-two-rounds", name: "Two Rounds", api: .faux, provider: .faux, baseUrl: "runtime"); await AIRegistry.shared.register(model)
        actor Count { var n = 0; func next() -> Int { n += 1; return n } }; let count = Count()
        await AIRegistry.shared.register(APIProvider(api: .faux, stream: { model, context, _ in AsyncStream { continuation in Task { await capture.context(context); let n = await count.next(); var message: Message; if n <= 2 { message = Message(role: .assistant, content: [.toolCall(id: "repeat-id", name: "sum", arguments: ["a": .number(Double(n)), "b": .number(1)])]); message.stopReason = .toolUse } else { message = Message(role: .assistant, content: [.text("final")]); message.stopReason = .stop }; message.api = model.api; message.provider = model.provider; message.model = model.id; continuation.yield(.done(reason: message.stopReason!, message: message)); continuation.finish() } } }))
        let session = DurableSession(storage: DurableMemoryStorage(), toolRegistry: registry); let conversation = try await session.createConversation(); let result = try await session.submit(DurableGenerationRequest(conversationID: conversation.id, model: model, transcript: [.user("two rounds")]))
        XCTAssertEqual(result.task.status, .completed); let contexts = await capture.contexts; XCTAssertEqual(contexts.count, 3); XCTAssertEqual(contexts[2].messages.map(\.role), [.user, .assistant, .toolResult, .assistant, .toolResult]); let executions = await capture.executions; XCTAssertEqual(executions.count, 2); XCTAssertEqual(executions.map(\.providerCallID), ["repeat-id", "repeat-id"]); XCTAssertNotEqual(executions[0].durableToolID, executions[1].durableToolID)
        try await session.close()
    }

    func testSerialMultipleCallsAndPriorRoundHistoryPersistToNextSubmission() async throws {
        let capture = S1CToolCapture(); let registry = try await registry(capture: capture)
        let model = Model(id: "s1c-multi", name: "S1c Multi", api: .faux, provider: .faux, baseUrl: "runtime"); await AIRegistry.shared.register(model)
        actor Calls { var count = 0; func next() -> Int { count += 1; return count } }; let calls = Calls()
        await AIRegistry.shared.register(APIProvider(api: .faux, stream: { model, context, _ in AsyncStream { continuation in Task {
            await capture.context(context); let n = await calls.next(); var message: Message
            if n == 1 { message = Message(role: .assistant, content: [.toolCall(id: "same", name: "sum", arguments: ["a": .number(1), "b": .number(1)]), .toolCall(id: "same-2", name: "sum", arguments: ["a": .number(2), "b": .number(2)])]); message.stopReason = .toolUse }
            else { message = Message(role: .assistant, content: [.text("done-\(n)")]); message.stopReason = .stop }
            message.api = model.api; message.provider = model.provider; message.model = model.id; continuation.yield(.done(reason: message.stopReason!, message: message)); continuation.finish()
        } } }))
        let session = DurableSession(storage: DurableMemoryStorage(), toolRegistry: registry); let conversation = try await session.createConversation()
        _ = try await session.submit(DurableGenerationRequest(conversationID: conversation.id, model: model, transcript: [.user("multi")]))
        _ = try await session.submit(DurableGenerationRequest(conversationID: conversation.id, model: model, transcript: [.user("next")]))
        let contexts = await capture.contexts; XCTAssertEqual(contexts.count, 3)
        XCTAssertEqual(contexts[1].messages.map(\.role), [.user, .assistant, .toolResult, .toolResult])
        XCTAssertEqual(contexts[2].messages.map(\.role), [.user, .assistant, .toolResult, .toolResult, .assistant, .user])
        let snapshot = try await session.snapshot(); XCTAssertEqual(snapshot.tasks.values.filter { $0.kind == "tool" }.count, 2)
        try await session.close()
    }

    func testAbortBlockedFirstProviderKeepsParentRunningUntilBilledSettlementAndStartsNoTool() async throws {
        let barrier = S1CToolBarrier(), capture = S1CToolCapture(), registry = try await registry(capture: capture)
        let model = Model(id: "s1c-abort-model", name: "Abort Model", api: .faux, provider: .faux, baseUrl: "runtime"); await AIRegistry.shared.register(model)
        await AIRegistry.shared.register(APIProvider(api: .faux, stream: { model, _, _ in AsyncStream { continuation in Task { await barrier.hold(); var message = Message(role: .assistant, content: [.toolCall(id: "late", name: "sum", arguments: ["a": .number(1), "b": .number(2)])]); message.api = model.api; message.provider = model.provider; message.model = model.id; message.stopReason = .toolUse; var usage = Usage(); usage.input = 7; usage.output = 2; usage.cacheRead = 1; usage.cacheWrite = 3; usage.cacheWrite1h = 4; usage.reasoning = 5; usage.totalTokens = 22; usage.cost.input = 1; usage.cost.output = 2; usage.cost.cacheRead = 3; usage.cost.cacheWrite = 4; usage.cost.total = 10; message.usage = usage; continuation.yield(.done(reason: .toolUse, message: message)); continuation.finish() } } }))
        let session = DurableSession(storage: DurableMemoryStorage(), toolRegistry: registry); let conversation = try await session.createConversation(); let submitted = Task { try await session.submit(DurableGenerationRequest(conversationID: conversation.id, model: model, transcript: [.user("abort model")])) }; await barrier.waitEntered(); let before = try await session.snapshot(); let parent = try XCTUnwrap(before.tasks.values.first { $0.kind == "generation" }); let abortResult = try await session.abort(taskID: parent.id); XCTAssertEqual(abortResult.status, .running); await barrier.release(); let result = try await submitted.value; XCTAssertEqual(result.task.status, .aborted); let effects = await capture.effects; XCTAssertEqual(effects, 0); let final = try await session.snapshot(); let receipt = try XCTUnwrap(final.documents.values.first { $0.ownerID == parent.id && $0.kind == "generation.usage.round.1" }?.value.objectValue); XCTAssertEqual(receipt["model"], .string("faux/faux/s1c-abort-model")); XCTAssertEqual(receipt["input"], .number(7)); XCTAssertEqual(receipt["output"], .number(2)); XCTAssertEqual(receipt["cacheRead"], .number(1)); XCTAssertEqual(receipt["cacheWrite"], .number(3)); XCTAssertEqual(receipt["cacheWrite1h"], .number(4)); XCTAssertEqual(receipt["reasoning"], .number(5)); XCTAssertEqual(receipt["totalTokens"], .number(22)); let aggregate = try XCTUnwrap(final.documents.values.first { $0.kind == "durable.usage" }?.value.objectValue); XCTAssertEqual(aggregate["input"], .number(7)); XCTAssertEqual(aggregate["totalTokens"], .number(22)); XCTAssertNotNil(aggregate["perModel"]?.objectValue?["faux/faux/s1c-abort-model"]); XCTAssertFalse(final.tasks.values.contains { $0.kind == "tool" }); let seq = final.seq; _ = try await session.abort(taskID: parent.id); let afterTerminalAbort = try await session.snapshot(); XCTAssertEqual(afterTerminalAbort.seq, seq); try await session.close()
    }

    func testPendingChildOnlyAbortProducesOrderedResultAndParentContinues() async throws {
        let gate = S1CChildGate(), capture = S1CToolCapture(), registry = try await registry(capture: capture), model = await installModel(capture: capture)
        let session = DurableSession(storage: DurableMemoryStorage(), testingHooks: DurableSessionTestingHooks(beforeToolExecution: { ids in await gate.hold(ids) }), capacity: 1, toolRegistry: registry)
        let conversation = try await session.createConversation(); let submitted = Task { try await session.submit(DurableGenerationRequest(conversationID: conversation.id, model: model, transcript: [.user("pending child")])) }; let ids = await gate.waitIDs(); let childID = try XCTUnwrap(ids.first); let abortResult = try await session.abort(taskID: childID); XCTAssertEqual(abortResult.status, .pending); await gate.release(); let result = try await submitted.value; XCTAssertEqual(result.task.status, .completed); let final = try await session.snapshot(); let child = try XCTUnwrap(final.tasks[childID]); XCTAssertEqual(child.status, .aborted); XCTAssertNotNil(child.outcome?.objectValue?["entryID"]); let effects = await capture.effects; XCTAssertEqual(effects, 0); try await session.close()
    }

    func testAbortAfterToolStartRetainsOwnershipAndSettlesParentAfterChild() async throws {
        let barrier = S1CToolBarrier(), capture = S1CToolCapture(), registry = DurableToolRegistry()
        try await registry.register(DurableToolRegistration(definition: Tool(name: "block", description: "", parameters: .object(["type": .string("object")])), implementationID: "block.native", implementationVersion: "1", replayPolicy: .unsafe, execute: { execution in await capture.tool(execution); await barrier.hold(); var usage = Usage(); usage.input = 2; usage.totalTokens = 2; return DurableToolResult(content: "late", usage: usage) }))
        let model = Model(id: "s1c-abort", name: "S1c Abort", api: .faux, provider: .faux, baseUrl: "runtime"); await AIRegistry.shared.register(model)
        await AIRegistry.shared.register(APIProvider(api: .faux, stream: { model, _, _ in AsyncStream { continuation in var message = Message(role: .assistant, content: [.toolCall(id: "block", name: "block", arguments: [:])]); message.api = model.api; message.provider = model.provider; message.model = model.id; message.stopReason = .toolUse; continuation.yield(.done(reason: .toolUse, message: message)); continuation.finish() } }))
        let session = DurableSession(storage: DurableMemoryStorage(), toolRegistry: registry); let conversation = try await session.createConversation(); let submitted = Task { try await session.submit(DurableGenerationRequest(conversationID: conversation.id, model: model, transcript: [.user("abort")])) }
        await barrier.waitEntered(); let snapshot = try await session.snapshot(); let parent = try XCTUnwrap(snapshot.tasks.values.first { $0.kind == "generation" }); _ = try await session.abort(taskID: parent.id); await barrier.release(); let result = try await submitted.value
        XCTAssertEqual(result.task.status, .aborted)
        let final = try await session.snapshot(); let child = try XCTUnwrap(final.tasks.values.first { $0.kind == "tool" }); XCTAssertEqual(child.status, .aborted); XCTAssertNotNil(final.documents.values.first { $0.ownerID == child.id && $0.kind == "tool.usage.attempt.1" })
        try await session.close()
    }

    func testCloseWaitsForNoncooperativeOwnedToolAndReleasesOnce() async throws {
        let barrier = S1CToolBarrier(), registry = DurableToolRegistry()
        try await registry.register(DurableToolRegistration(definition: Tool(name: "close", description: "", parameters: .object(["type": .string("object")])), implementationID: "close.native", implementationVersion: "1", execute: { _ in await barrier.hold(); return DurableToolResult(content: "closed") }))
        let model = Model(id: "s1c-close", name: "S1c Close", api: .faux, provider: .faux, baseUrl: "runtime"); await AIRegistry.shared.register(model)
        actor Count { var n = 0; func next() -> Int { n += 1; return n } }; let count = Count()
        await AIRegistry.shared.register(APIProvider(api: .faux, stream: { model, context, _ in AsyncStream { continuation in Task { let n = await count.next(); var message = n == 1 ? Message(role: .assistant, content: [.toolCall(id: "close", name: "close", arguments: [:])]) : Message(role: .assistant, content: [.text("done")]); message.api = model.api; message.provider = model.provider; message.model = model.id; message.stopReason = n == 1 ? .toolUse : .stop; continuation.yield(.done(reason: message.stopReason!, message: message)); continuation.finish() } } }))
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("swift-ai-s1c-close-\(UUID().uuidString)", isDirectory: true); let closeAttached = S1CTestSignal(); let storage = try DurableJournalStorage(directory: dir); let session = DurableSession(storage: storage, testingHooks: DurableSessionTestingHooks(onCloseWaiter: { _ in closeAttached.fire() }), capacity: DurableLimits.maxPublicQueue, toolRegistry: registry); let conversation = try await session.createConversation(); let submitted = Task { try await session.submit(DurableGenerationRequest(conversationID: conversation.id, model: model, transcript: [.user("close")])) }; await barrier.waitEntered(); let closed = Task { try await session.close(); closeAttached.finishClose() }; await closeAttached.wait(); XCTAssertFalse(closeAttached.isCloseFinished()); XCTAssertThrowsError(try DurableJournalStorage(directory: dir)) { XCTAssertTrue(String(describing: $0).contains("busy")) }; await barrier.release(); let submittedResult = try await submitted.value; XCTAssertEqual(submittedResult.task.status, .completed); try await closed.value; try await session.close(); let successor = try DurableJournalStorage(directory: dir); try await successor.close()
    }

    func testDuplicateProviderCallIDAndInvalidArgumentsSettleTypedWithoutClosingSession() async throws {
        for mode in ["duplicate", "invalid"] {
            let capture = S1CToolCapture(), registry = try await registry(capture: capture)
            let model = Model(id: "s1c-invalid-\(mode)", name: "S1c Invalid", api: .faux, provider: .faux, baseUrl: "runtime"); await AIRegistry.shared.register(model)
            actor Count { var n = 0; func next() -> Int { n += 1; return n } }; let count = Count()
            await AIRegistry.shared.register(APIProvider(api: .faux, stream: { model, _, _ in AsyncStream { continuation in Task { let n = await count.next(); var message: Message; if n == 1 { let first = ContentBlock.toolCall(id: "same", name: "sum", arguments: mode == "invalid" ? ["a": .number(1), "b": .number(2), "extra": .bool(true)] : ["a": .number(1), "b": .number(2)]); let content = mode == "duplicate" ? [first, ContentBlock.toolCall(id: "same", name: "sum", arguments: ["a": .number(2), "b": .number(3)])] : [first]; message = Message(role: .assistant, content: content); message.stopReason = .toolUse } else { message = Message(role: .assistant, content: [.text("later")]); message.stopReason = .stop }; message.api = model.api; message.provider = model.provider; message.model = model.id; var usage = Usage(); usage.input = 4; usage.totalTokens = 4; message.usage = usage; continuation.yield(.done(reason: message.stopReason!, message: message)); continuation.finish() } } }))
            let session = DurableSession(storage: DurableMemoryStorage(), toolRegistry: registry); let conversation = try await session.createConversation(); let failed = try await session.submit(DurableGenerationRequest(conversationID: conversation.id, model: model, transcript: [.user(mode)])); XCTAssertEqual(failed.task.status, .failed); let effectCount = await capture.effects; XCTAssertEqual(effectCount, 0)
            let snapshot = try await session.snapshot(); XCTAssertNotNil(snapshot.documents.values.first { $0.ownerID == failed.task.id && $0.kind == "generation.usage.round.1" })
            let later = try await session.submit(DurableGenerationRequest(conversationID: conversation.id, model: model, transcript: [.user("later-\(mode)")])); XCTAssertEqual(later.task.status, .completed); try await session.close()
        }
    }

    func testLaterModelRoundOverflowUsesRound2ReceiptAndPreservesPriorAggregate() async throws {
        let capture = S1CToolCapture(), registry = try await registry(capture: capture); let model = Model(id: "s1c-model-overflow", name: "Model Overflow", api: .faux, provider: .faux, baseUrl: "runtime"); await AIRegistry.shared.register(model)
        actor Count { var n = 0; func next() -> Int { n += 1; return n } }; let count = Count(); await AIRegistry.shared.register(APIProvider(api: .faux, stream: { model, _, _ in AsyncStream { continuation in Task { let n = await count.next(); var message = n == 1 ? Message(role: .assistant, content: [.toolCall(id: "overflow-model", name: "sum", arguments: ["a": .number(1), "b": .number(1)])]) : Message(role: .assistant, content: [.text("overflow")]); message.api = model.api; message.provider = model.provider; message.model = model.id; message.stopReason = n == 1 ? .toolUse : .stop; var usage = Usage(); usage.input = 1; usage.totalTokens = 1; message.usage = usage; continuation.yield(.done(reason: message.stopReason!, message: message)); continuation.finish() } } }))
        let conversation = DurableConversationRecord(id: 1, createdSeq: 1); let aggregate = DurableDocumentRecord(id: 2, scope: "conversation", ownerID: 1, kind: "durable.usage", value: .object(["input": .number(Double(DurableLimits.maxExactInteger - 2)), "output": .number(0), "cacheRead": .number(0), "cacheWrite": .number(0), "cacheWrite1h": .number(0), "reasoning": .number(0), "totalTokens": .number(Double(DurableLimits.maxExactInteger - 3)), "cost": .object(["input": .number(0), "output": .number(0), "cacheRead": .number(0), "cacheWrite": .number(0), "total": .number(0)]), "perModel": .object([:]), "perTool": .object([:])]), createdSeq: 1)
        let session = DurableSession(storage: DurableMemoryStorage(snapshot: DurableSnapshot(seq: 1, highWaterID: 2, conversations: [1: conversation], documents: [2: aggregate])), toolRegistry: registry); let result = try await session.submit(DurableGenerationRequest(conversationID: 1, model: model, transcript: [.user("model overflow") ])); XCTAssertEqual(result.task.status, .failed); let snapshot = try await session.snapshot(); XCTAssertEqual(snapshot.documents.values.filter { $0.kind == "generation.usage.round.1" }.count, 1); XCTAssertEqual(snapshot.documents.values.filter { $0.kind == "generation.usage.round.2" }.count, 1); XCTAssertFalse(snapshot.documents.values.contains { $0.kind == "generation.usage" }); XCTAssertNotNil(snapshot.documents.values.first { $0.ownerID == result.task.id && $0.kind == "generation.aggregate-incomplete" }); let round2 = try XCTUnwrap(snapshot.documents.values.first { $0.kind == "generation.usage.round.2" }?.value.objectValue); XCTAssertEqual(round2["model"], .string("faux/faux/s1c-model-overflow")); XCTAssertEqual(round2["input"], .number(1)); try await session.close()
    }

    func testPerToolAggregateOverflowPreservesPriorAggregateAndMarksChildIncomplete() async throws {
        let capture = S1CToolCapture(), registry = try await registry(capture: capture), model = await installModel(capture: capture)
        let conversation = DurableConversationRecord(id: 1, createdSeq: 1); let aggregate = DurableDocumentRecord(id: 2, scope: "conversation", ownerID: 1, kind: "durable.usage", value: .object(["input": .number(Double(DurableLimits.maxExactInteger - 2)), "output": .number(0), "cacheRead": .number(0), "cacheWrite": .number(0), "cacheWrite1h": .number(0), "reasoning": .number(0), "totalTokens": .number(Double(DurableLimits.maxExactInteger - 3)), "cost": .object(["input": .number(0), "output": .number(0), "cacheRead": .number(0), "cacheWrite": .number(0), "total": .number(0)]), "perModel": .object([:]), "perTool": .object([:])]), createdSeq: 1)
        let session = DurableSession(storage: DurableMemoryStorage(snapshot: DurableSnapshot(seq: 1, highWaterID: 2, conversations: [1: conversation], documents: [2: aggregate])), toolRegistry: registry); let result = try await session.submit(DurableGenerationRequest(conversationID: 1, model: model, transcript: [.user("overflow") ])); XCTAssertEqual(result.task.status, .failed)
        let snapshot = try await session.snapshot(); let aggregateValue = try XCTUnwrap(snapshot.documents[2]?.value.objectValue); XCTAssertEqual(aggregateValue["input"], .number(Double(DurableLimits.maxExactInteger))); XCTAssertEqual(aggregateValue["totalTokens"], .number(Double(DurableLimits.maxExactInteger))); XCTAssertEqual(aggregateValue["output"], .number(1)); XCTAssertEqual(aggregateValue["perTool"], .object([:])); XCTAssertNotNil(aggregateValue["perModel"]?.objectValue?["faux/faux/s1c-model"]); let child = try XCTUnwrap(snapshot.tasks.values.first { $0.kind == "tool" }); let attempt = try XCTUnwrap(snapshot.documents.values.first { $0.ownerID == child.id && $0.kind == "tool.usage.attempt.1" }?.value.objectValue); XCTAssertEqual(attempt["input"], .number(1)); XCTAssertEqual(attempt["output"], .number(1)); XCTAssertEqual(attempt["totalTokens"], .number(2)); XCTAssertNotNil(snapshot.documents.values.first { $0.ownerID == child.id && $0.kind == "tool.aggregate-incomplete" }); XCTAssertFalse(snapshot.documents.values.contains { $0.kind.hasPrefix("tool.application.") }); try await session.close()
    }

    func testOversizeOutputInvalidUsageAndOversizeDocumentSettleTypedAndSessionContinues() async throws {
        for mode in ["text", "usage", "document"] {
            let registry = DurableToolRegistry()
            try await registry.register(DurableToolRegistration(definition: Tool(name: "badout", description: "", parameters: .object(["type": .string("object")])), implementationID: "badout.native", implementationVersion: "1", replayPolicy: .safe, execute: { _ in
                var usage = Usage(); usage.input = 5; usage.totalTokens = 5
                if mode == "usage" { usage.input = -1; usage.totalTokens = -1; return DurableToolResult(content: "bad", usage: usage) }
                if mode == "text" { return DurableToolResult(content: String(repeating: "x", count: 33 * 1024), usage: usage) }
                return DurableToolResult(content: "bad", usage: usage, documents: [DurableToolApplicationDocument(target: .toolTask, suffix: "large", value: .string(String(repeating: "d", count: 2 * 1024 * 1024)))])
            }))
            let model = Model(id: "badout-\(mode)", name: "Bad Output", api: .faux, provider: .faux, baseUrl: "runtime"); await AIRegistry.shared.register(model)
            actor Count { var n = 0; func next() -> Int { n += 1; return n } }; let count = Count()
            await AIRegistry.shared.register(APIProvider(api: .faux, stream: { model, _, _ in AsyncStream { continuation in Task { let n = await count.next(); var message = n == 1 ? Message(role: .assistant, content: [.toolCall(id: mode, name: "badout", arguments: [:])]) : Message(role: .assistant, content: [.text("later")]); message.api = model.api; message.provider = model.provider; message.model = model.id; message.stopReason = n == 1 ? .toolUse : .stop; continuation.yield(.done(reason: message.stopReason!, message: message)); continuation.finish() } } }))
            let session = DurableSession(storage: DurableMemoryStorage(), toolRegistry: registry); let conversation = try await session.createConversation(); let first = try await session.submit(DurableGenerationRequest(conversationID: conversation.id, model: model, transcript: [.user(mode)])); XCTAssertEqual(first.task.status, .completed)
            let snapshot = try await session.snapshot(); let child = try XCTUnwrap(snapshot.tasks.values.first { $0.kind == "tool" }); XCTAssertEqual(child.status, .failed); XCTAssertFalse(snapshot.documents.values.contains { $0.kind.hasPrefix("tool.application.") }); if mode == "usage" { XCTAssertNotNil(snapshot.documents.values.first { $0.kind == "tool.billing-incomplete" }) } else { XCTAssertNotNil(snapshot.documents.values.first { $0.kind == "tool.usage.attempt.1" }) }
            let later = try await session.submit(DurableGenerationRequest(conversationID: conversation.id, model: model, transcript: [.user("later") ])); XCTAssertEqual(later.task.status, .completed); try await session.close()
        }
    }

    func testMalformedExistingApplicationCreatorRejectsUpdateWithoutPartialWrite() async throws {
        let capture = S1CToolCapture(), registry = DurableToolRegistry(), model = await installModel(capture: capture)
        let schema: JSONValue = .object(["type": .string("object"), "properties": .object(["a": .object(["type": .string("integer")]), "b": .object(["type": .string("integer")])]), "required": .array([.string("a"), .string("b")]), "additionalProperties": .bool(false)])
        try await registry.register(DurableToolRegistration(definition: Tool(name: "sum", description: "sum", parameters: schema), implementationID: "sum.native", implementationVersion: "1", replayPolicy: .safe, execute: { execution in await capture.tool(execution); var usage = Usage(); usage.input = 1; usage.totalTokens = 1; return DurableToolResult(content: "5", usage: usage, documents: [DurableToolApplicationDocument(target: .conversation, suffix: "sum", value: .number(5))]) }))
        let storage = DurableMemoryStorage(); let session = DurableSession(storage: storage, toolRegistry: registry); let conversation = try await session.createConversation(); _ = try await session.submit(DurableGenerationRequest(conversationID: conversation.id, model: model, transcript: [.user("first")]))
        var snapshot = try await session.snapshot(); let child = try XCTUnwrap(snapshot.tasks.values.first { $0.kind == "tool" }); let document = try XCTUnwrap(snapshot.documents.values.first { $0.kind == "tool.application.sum.sum" }); let malformed = DurableDocumentRecord(id: document.id, scope: document.scope, ownerID: document.ownerID, kind: document.kind, value: .object(["value": .number(5)]), createdSeq: document.createdSeq); snapshot.documents[document.id] = malformed
        let replacementStorage = DurableMemoryStorage(snapshot: snapshot); try await session.close(); let secondModel = Model(id: "s1c-creator-second", name: "Creator Second", api: .faux, provider: .faux, baseUrl: "runtime"); await AIRegistry.shared.register(secondModel); actor Count { var n = 0; func next() -> Int { n += 1; return n } }; let count = Count(); await AIRegistry.shared.register(APIProvider(api: .faux, stream: { model, _, _ in AsyncStream { continuation in Task { let n = await count.next(); var message = n == 1 ? Message(role: .assistant, content: [.toolCall(id: "creator-second", name: "sum", arguments: ["a": .number(2), "b": .number(3)])]) : Message(role: .assistant, content: [.text("done")]); message.api = model.api; message.provider = model.provider; message.model = model.id; message.stopReason = n == 1 ? .toolUse : .stop; continuation.yield(.done(reason: message.stopReason!, message: message)); continuation.finish() } } })); let reopened = DurableSession(storage: replacementStorage, toolRegistry: registry); _ = try await reopened.submit(DurableGenerationRequest(conversationID: conversation.id, model: secondModel, transcript: [.user("second")]))
        let final = try await reopened.snapshot(); XCTAssertEqual(final.documents[document.id]?.value, malformed.value); let newChildIDs = Set(final.tasks.values.filter { $0.kind == "tool" && $0.id != child.id }.map(\.id)); XCTAssertNotNil(final.documents.values.first { newChildIDs.contains($0.ownerID) && $0.kind == "tool.usage.attempt.1" }); try await reopened.close()
    }

    func testInvalidApplicationDocumentsSettleTypedAndRetainToolUsage() async throws {
        let capture = S1CToolCapture(); let registry = DurableToolRegistry()
        try await registry.register(DurableToolRegistration(definition: Tool(name: "docs", description: "", parameters: .object(["type": .string("object")])), implementationID: "docs.native", implementationVersion: "1", replayPolicy: .safe, execute: { execution in
            await capture.tool(execution); var usage = Usage(); usage.input = 3; usage.totalTokens = 3
            return DurableToolResult(content: "bad", usage: usage, documents: [DurableToolApplicationDocument(target: .toolTask, suffix: "same", value: .string("one")), DurableToolApplicationDocument(target: .toolTask, suffix: "same", value: .string("two"))])
        }))
        let model = Model(id: "s1c-docs", name: "S1c Docs", api: .faux, provider: .faux, baseUrl: "runtime"); await AIRegistry.shared.register(model)
        actor Count { var n = 0; func next() -> Int { n += 1; return n } }; let count = Count()
        await AIRegistry.shared.register(APIProvider(api: .faux, stream: { model, context, _ in AsyncStream { continuation in Task { let n = await count.next(); var message = n == 1 ? Message(role: .assistant, content: [.toolCall(id: "doc", name: "docs", arguments: [:])]) : Message(role: .assistant, content: [.text("handled")]); message.api = model.api; message.provider = model.provider; message.model = model.id; message.stopReason = n == 1 ? .toolUse : .stop; continuation.yield(.done(reason: message.stopReason!, message: message)); continuation.finish() } } }))
        let session = DurableSession(storage: DurableMemoryStorage(), toolRegistry: registry); let conversation = try await session.createConversation(); let result = try await session.submit(DurableGenerationRequest(conversationID: conversation.id, model: model, transcript: [.user("docs")]))
        XCTAssertEqual(result.task.status, .completed)
        let snapshot = try await session.snapshot(); let child = try XCTUnwrap(snapshot.tasks.values.first { $0.kind == "tool" }); XCTAssertEqual(child.status, .failed)
        XCTAssertNotNil(snapshot.documents.values.first { $0.ownerID == child.id && $0.kind == "tool.usage.attempt.1" })
        XCTAssertFalse(snapshot.documents.values.contains { $0.kind.hasPrefix("tool.application.") })
        try await session.close()
    }

}
