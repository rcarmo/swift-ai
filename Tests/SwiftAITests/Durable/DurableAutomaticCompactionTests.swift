import XCTest
@testable import SwiftAI

final class DurableAutomaticCompactionTests: XCTestCase {
    private func configure(session: DurableSession, model: Model, policy: DurableCompactionPolicy) async throws -> Int64 {
        await AIRegistry.shared.register(model)
        let conversation = try await session.createConversation()
        try await session.configureAgent(conversationID: conversation.id, settings: DurableAgentSettings(model: model, compaction: policy))
        for n in 1...4 { _ = try await session.appendEntry(conversationID: conversation.id, kind: "user", messages: [.user("old \(n) " + String(repeating: "x", count: 100))]) }
        return conversation.id
    }

    func testPressureCompactsBeforeGenerationAndRetainsOwnedUsage() async throws {
        let capture = AutomaticCompactionCapture()
        let session = DurableSession(storage: DurableMemoryStorage())
        let model = Model(id: "pressure", name: "pressure", api: .faux, provider: .faux, baseUrl: "runtime", contextWindow: 120, maxTokens: 80)
        let id = try await configure(session: session, model: model, policy: DurableCompactionPolicy(reserveTokens: 40, keepRecentTokens: 1))
        await AIRegistry.shared.register(APIProvider(api: .faux, stream: { model, context, options in AsyncStream { continuation in Task {
            await capture.append(context, options: options)
            var message = Message(role: .assistant, content: [.text(options?.cacheRetention == CacheRetention.none ? "summary" : "answer")]); message.api = model.api; message.provider = model.provider; message.model = model.id; message.stopReason = .stop
            var usage = Usage(); usage.input = 2; usage.totalTokens = 2; message.usage = usage
            continuation.yield(.done(reason: .stop, message: message)); continuation.finish()
        } } }))
        let result = try await session.generate(conversationID: id, input: [.user("new input")])
        XCTAssertEqual(result.task.status, .completed)
        let contexts = await capture.contexts, options = await capture.options
        XCTAssertEqual(contexts.count, 2); XCTAssertEqual(options[0].cacheRetention, CacheRetention.none)
        XCTAssertTrue(contexts[1].messages.first?.content.first?.text?.contains("summary") == true)
        XCTAssertEqual(contexts[1].messages.last?.content.first?.text, "new input")
        let snapshot = try await session.snapshot()
        let compact = try XCTUnwrap(snapshot.tasks.values.first { $0.kind == "compaction" }); XCTAssertEqual(compact.ownerTaskID, result.task.id); XCTAssertEqual(compact.status, .completed)
        XCTAssertEqual(snapshot.documents.values.first { $0.kind == "durable.usage" }?.value.objectValue?["input"], .number(4))
        try await session.close()
    }

    func testProviderOverflowCompactsOnceAndPreservesFailedAttemptUsage() async throws {
        let capture = AutomaticCompactionCapture(), attempts = AutomaticAttemptCounter()
        let session = DurableSession(storage: DurableMemoryStorage())
        let model = Model(id: "overflow", name: "overflow", api: .faux, provider: .faux, baseUrl: "runtime", contextWindow: 10000, maxTokens: 80)
        let id = try await configure(session: session, model: model, policy: DurableCompactionPolicy(reserveTokens: 40, keepRecentTokens: 1))
        await AIRegistry.shared.register(APIProvider(api: .faux, stream: { model, context, options in AsyncStream { continuation in Task {
            await capture.append(context, options: options)
            let summary = options?.cacheRetention == CacheRetention.none
            let attempt = summary ? 0 : await attempts.next()
            var message = Message(role: .assistant, content: [.text(summary ? "summary" : "answer")]); message.api = model.api; message.provider = model.provider; message.model = model.id
            var usage = Usage(); usage.input = summary ? 2 : (attempt == 1 ? 3 : 4); usage.totalTokens = usage.input; message.usage = usage
            if attempt == 1 { message.stopReason = .error; message.errorMessage = "context_length_exceeded"; continuation.yield(.error(reason: .error, message: message, error: AIError.provider("context_length_exceeded"))) }
            else { message.stopReason = .stop; continuation.yield(.done(reason: .stop, message: message)) }
            continuation.finish()
        } } }))
        let result = try await session.generate(conversationID: id, input: [.user("new input")])
        XCTAssertEqual(result.task.status, .completed)
        let calls = await capture.contexts; XCTAssertEqual(calls.count, 3)
        let snapshot = try await session.snapshot()
        XCTAssertEqual(snapshot.tasks.values.filter { $0.kind == "compaction" }.count, 1)
        XCTAssertEqual(snapshot.documents.values.first { $0.kind == "generation.overflow.usage" }?.value.objectValue?["input"], .number(3))
        XCTAssertEqual(snapshot.documents.values.first { $0.kind == "durable.usage" }?.value.objectValue?["input"], .number(9))
        try await session.close()
    }

    func testRepeatedOverflowStopsAfterOneCompaction() async throws {
        let attempts = AutomaticAttemptCounter()
        let session = DurableSession(storage: DurableMemoryStorage())
        let model = Model(id: "repeat-overflow", name: "repeat", api: .faux, provider: .faux, baseUrl: "runtime", contextWindow: 10000, maxTokens: 80)
        let id = try await configure(session: session, model: model, policy: DurableCompactionPolicy(reserveTokens: 40, keepRecentTokens: 1))
        await AIRegistry.shared.register(APIProvider(api: .faux, stream: { _, _, options in AsyncStream { continuation in Task {
            var message = Message(role: .assistant, content: [.text("summary")])
            if options?.cacheRetention == CacheRetention.none { message.stopReason = .stop; continuation.yield(.done(reason: .stop, message: message)) }
            else { _ = await attempts.next(); message.stopReason = .error; message.errorMessage = "context_length_exceeded"; continuation.yield(.error(reason: .error, message: message, error: AIError.provider("overflow"))) }
            continuation.finish()
        } } }))
        let result = try await session.generate(conversationID: id, input: [.user("input")]); XCTAssertEqual(result.task.status, .failed)
        let count = await attempts.count; XCTAssertEqual(count, 2)
        let snapshot = try await session.snapshot(); XCTAssertEqual(snapshot.tasks.values.filter { $0.kind == "compaction" }.count, 1)
        try await session.close()
    }

    func testLinkedStagedCompactionRecoveryDoesNotSummariseAgain() async throws {
        let storage = DurableMemoryStorage(), attempts = AutomaticAttemptCounter()
        let model = Model(id: "linked", name: "linked", api: .faux, provider: .faux, baseUrl: "runtime", contextWindow: 10000, maxTokens: 80)
        await AIRegistry.shared.register(model)
        _ = try await storage.commit(DurableCommitBatch(conversations: [DurableConversationRecord(id: 1)], entries: [DurableEntryRecord(id: 2, conversationID: 1, kind: "user", messages: [.user("old")])]))
        let request = DurableGenerationRequest(conversationID: 1, model: model, transcript: [.user("current")], requestID: "linked")
        let admission = try DurableGenerationPlanner.admitBatch(snapshot: await storage.snapshot(), request: request)
        _ = try await storage.commit(admission.batch)
        let admitted = try await storage.snapshot(), parent = try XCTUnwrap(admitted.tasks[admission.taskID])
        var intent = try DurableGenerationPlanner.intent(for: parent, in: admitted)
        _ = try await storage.commit(DurableGenerationPlanner.runningBatch(snapshot: admitted, task: parent, intent: intent))
        let running = try await storage.snapshot(), ids = try DurableSubmissionPlanner.nextID(from: running, reserving: 2)
        let childID = ids[0]
        intent = try DurableGenerationPlanner.intent(for: running.tasks[parent.id]!, in: running); intent.compactionTaskID = childID; intent.overflowCompacted = true
        var parentDocument = try XCTUnwrap(DurableGenerationPlanner.document(scope: "task", ownerID: parent.id, kind: "generation.intent", in: running))
        parentDocument.value = try DurableGenerationPlanner.encodeJSON(intent)
        var pinnedModel = model; pinnedModel.baseUrl = ""
        let staged = DurableCompactionIntent(model: pinnedModel, conversationID: 1, tail: admission.inputEntryID, firstKept: admission.inputEntryID, transcript: [.user("old")], maxTokens: 32, summary: "already paid summary")
        _ = try await storage.commit(DurableCommitBatch(tasks: [DurableTaskRecord(id: childID, conversationID: 1, ownerTaskID: parent.id, kind: "compaction")], documents: [parentDocument, DurableDocumentRecord(id: ids[1], scope: "task", ownerID: childID, kind: "compaction.intent", value: try DurableGenerationPlanner.encodeJSON(staged))]))
        _ = try await storage.commit(DurableCommitBatch(tasks: [DurableTaskRecord(id: childID, conversationID: 1, ownerTaskID: parent.id, kind: "compaction", status: .running)]))
        _ = try await storage.commit(DurableCommitBatch(tasks: [DurableTaskRecord(id: childID, conversationID: 1, ownerTaskID: parent.id, kind: "compaction", status: .completing)]))
        let persisted = try await storage.snapshot()
        let session = DurableSession(storage: DurableMemoryStorage(snapshot: persisted))
        await AIRegistry.shared.register(APIProvider(api: .faux, stream: { _, context, options in AsyncStream { continuation in Task {
            _ = await attempts.next(); XCTAssertNotEqual(options?.cacheRetention, CacheRetention.none)
            XCTAssertTrue(context.messages.first?.content.first?.text?.contains("already paid summary") == true)
            var answer = Message(role: .assistant, content: [.text("answer")]); answer.stopReason = .stop
            continuation.yield(.done(reason: .stop, message: answer)); continuation.finish()
        } } }))
        let observations = try await session.observeCommits()
        _ = try await session.resumeQueued()
        for await frame in observations { if frame.value.tasks[parent.id]?.status == .completed { break } }
        let count = await attempts.count; XCTAssertEqual(count, 1)
        let final = try await session.snapshot(); XCTAssertEqual(final.tasks[childID]?.status, .completed)
        let recovered = try DurableGenerationPlanner.intent(for: final.tasks[parent.id]!, in: final); XCTAssertNil(recovered.compactionTaskID)
        try await session.close()
    }

    func testDisabledCompactionDoesNotRetryOverflow() async throws {
        let attempts = AutomaticAttemptCounter()
        let session = DurableSession(storage: DurableMemoryStorage())
        let model = Model(id: "disabled", name: "disabled", api: .faux, provider: .faux, baseUrl: "runtime", contextWindow: 10000)
        let id = try await configure(session: session, model: model, policy: DurableCompactionPolicy(enabled: false))
        await AIRegistry.shared.register(APIProvider(api: .faux, stream: { _, _, _ in AsyncStream { continuation in Task {
            _ = await attempts.next(); var message = Message(role: .assistant, content: []); message.stopReason = .error; message.errorMessage = "context_length_exceeded"
            continuation.yield(.error(reason: .error, message: message, error: AIError.provider("overflow"))); continuation.finish()
        } } }))
        let result = try await session.generate(conversationID: id, input: [.user("input")]); XCTAssertEqual(result.task.status, .failed)
        let count = await attempts.count; XCTAssertEqual(count, 1)
        let snapshot = try await session.snapshot(); XCTAssertFalse(snapshot.tasks.values.contains { $0.kind == "compaction" })
        try await session.close()
    }
}

private actor AutomaticAttemptCounter { var count = 0; func next() -> Int { count += 1; return count } }
private actor AutomaticCompactionCapture {
    var contexts: [AIContext] = [], options: [StreamOptions] = []
    func append(_ context: AIContext, options: StreamOptions?) { contexts.append(context); self.options.append(options ?? StreamOptions()) }
}
