import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import SwiftAI

private final class S1BMistralURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requests: [URLRequest] = []
    nonisolated(unsafe) static var holdRequests = false
    nonisolated(unsafe) static var held: [(S1BMistralURLProtocol, URLRequest)] = []
    static func releaseHeld() { let values = held; held = []; for (instance, request) in values { instance.respond(to: request) } }
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "mistral-s1b.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.requests.append(request); if Self.holdRequests { Self.held.append((self, request)); return }; respond(to: request) }
    private func respond(to request: URLRequest) {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let body = "data: {\"id\":\"wire-1\",\"model\":\"mistral-s1b\",\"choices\":[{\"delta\":{\"content\":\"wire\"},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":2,\"completion_tokens\":1,\"total_tokens\":3}}\n\ndata: [DONE]\n\n"
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

actor S1BCapture {
    var contexts: [AIContext] = []
    var effects = 0
    func record(_ context: AIContext) { contexts.append(context); effects += 1 }
    func texts() -> [[String]] { contexts.map { $0.messages.flatMap { $0.content.compactMap(\.text) } } }
}

final class DurableGenerationTests: XCTestCase {
    private func install(failure: Bool = false, capture: S1BCapture) async -> Model {
        let model = Model(id: "durable-test", name: "Durable", api: .faux, provider: .faux, baseUrl: "runtime-only", maxTokens: 100)
        await AIRegistry.shared.register(model)
        await AIRegistry.shared.register(APIProvider(api: .faux, stream: { model, context, _ in
            AsyncStream { continuation in
                Task {
                    await capture.record(context)
                    var message = Message(role: .assistant, content: [.text("answer")])
                    message.api = model.api; message.provider = model.provider; message.model = model.id; message.stopReason = failure ? .error : .stop
                    var usage = Usage(); usage.input = 4; usage.output = 2; usage.cacheRead = 1; usage.cacheWrite = 2; usage.cacheWrite1h = 3; usage.reasoning = 1; usage.totalTokens = 10; usage.cost.input = 1; usage.cost.output = 2; usage.cost.cacheRead = 3; usage.cost.cacheWrite = 4; usage.cost.total = 10; message.usage = usage
                    if failure { message.errorMessage = "billed timeout"; continuation.yield(.error(reason: .error, message: message, error: AIError.provider("billed timeout"))) }
                    else { continuation.yield(.done(reason: .stop, message: message)) }
                    continuation.finish()
                }
            }
        }))
        return model
    }

    func testSequentialContextIdempotencyAndCompleteUsage() async throws {
        let capture = S1BCapture(); let model = await install(capture: capture)
        let session = DurableSession(storage: DurableMemoryStorage())
        let conversation = try await session.createConversation()
        let firstRequest = DurableGenerationRequest(conversationID: conversation.id, model: model, transcript: [.user("first")], requestID: "first")
        let first = try await session.submit(firstRequest)
        XCTAssertEqual(first.task.status, .completed)
        _ = try await session.appendEntry(conversationID: conversation.id, kind: "note", messages: [.user("passive")])
        _ = try await session.submit(DurableGenerationRequest(conversationID: conversation.id, model: model, transcript: [.user("second")], requestID: "second"))
        let contexts = await capture.texts()
        XCTAssertEqual(contexts, [["first"], ["first", "answer", "passive", "second"]])
        let snapshot = try await session.snapshot()
        let usage = snapshot.documents.values.first { $0.kind == "generation.usage" && $0.ownerID == first.task.id }?.value.objectValue
        XCTAssertEqual(usage?["cacheWrite1h"], .number(3))
        XCTAssertEqual(usage?["model"], .string("faux/faux/durable-test"))
        let aggregate = snapshot.documents.values.first { $0.kind == "durable.usage" }?.value.objectValue
        XCTAssertEqual(aggregate?["cacheRead"], .number(2))
        XCTAssertNotNil(aggregate?["perModel"]?.objectValue?["faux/faux/durable-test"])
        var changed = firstRequest; changed.model.maxTokens = 200
        await XCTAssertThrowsAsyncError(try await session.submit(changed)) { error in XCTAssertTrue(String(describing: error).contains("request ID conflict")) }
        try await session.close()
    }

    func testProductionMistralHTTPStreamUsesLiveProcessAuthNotJournal() async throws {
        S1BMistralURLProtocol.requests = []
        let previousConfiguration = MistralConversationsProvider.urlSessionConfiguration
        MistralConversationsProvider.urlSessionConfiguration = { let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [S1BMistralURLProtocol.self]; return config }
        defer { MistralConversationsProvider.urlSessionConfiguration = previousConfiguration }
        await AIRegistry.shared.register(APIProvider(api: .mistralConversations, stream: { model, context, options in MistralConversationsProvider.stream(model: model, context: context, options: options) }))
        let model = Model(id: "mistral-s1b", name: "Mistral S1b", api: .mistralConversations, provider: .mistral, baseUrl: "https://mistral-s1b.test/v1", maxTokens: 64)
        await AIRegistry.shared.register(model)
        var options = StreamOptions(); options.apiKey = "must-not-persist"; options.temperature = 0.25
        let dir = SwiftAITestScratch.directory("s1b-http")
        let storage = try DurableJournalStorage(directory: dir); let session = DurableSession(storage: storage, toolRegistry: nil, liveConnectionResolver: { _ in DurableLiveConnection(endpoint: "https://mistral-s1b.test/v1", apiKey: "durable-test-not-secret") })
        let conversation = try await session.createConversation()
        let result = try await session.submit(DurableGenerationRequest(conversationID: conversation.id, model: model, transcript: [.user("hello wire")], requestID: "wire", options: options))
        XCTAssertEqual(result.entry?.messages?.first?.content.first?.text, "wire")
        let request = try XCTUnwrap(S1BMistralURLProtocol.requests.last)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer durable-test-not-secret")
        XCTAssertTrue(String(data: request.httpBody ?? Data(), encoding: .utf8)?.contains("\"temperature\":0.25") == true)
        let journalBytes = try Data(contentsOf: dir.appendingPathComponent("journal.log"))
        XCTAssertNil(String(data: journalBytes, encoding: .utf8)?.range(of: "must-not-persist"))
        XCTAssertNil(String(data: journalBytes, encoding: .utf8)?.range(of: "durable-test-not-secret"))
        XCTAssertNil(String(data: journalBytes, encoding: .utf8)?.range(of: "mistral-s1b.test"))
        try await session.close()
        let reopened = try DurableJournalStorage(directory: dir)
        let reopenedSnapshot = try await reopened.snapshot()
        XCTAssertEqual(reopenedSnapshot.tasks[result.task.id]?.status, .completed)
        try await reopened.close()
    }

    func testReopenRedispatchUsesFreshLiveCredentialAndPinnedBehavior() async throws {
        S1BMistralURLProtocol.requests = []; S1BMistralURLProtocol.holdRequests = false; S1BMistralURLProtocol.held = []
        let previousConfiguration = MistralConversationsProvider.urlSessionConfiguration; MistralConversationsProvider.urlSessionConfiguration = { let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [S1BMistralURLProtocol.self]; return config }; defer { MistralConversationsProvider.urlSessionConfiguration = previousConfiguration }
        await AIRegistry.shared.register(APIProvider(api: .mistralConversations, stream: { model, context, options in MistralConversationsProvider.stream(model: model, context: context, options: options) }))
        let model = Model(id: "mistral-s1c-reopen", name: "Mistral Reopen", api: .mistralConversations, provider: .mistral, baseUrl: "https://old-live.test/v1", maxTokens: 64); await AIRegistry.shared.register(model)
        var options = StreamOptions(); options.temperature = 0.37; options.apiKey = "old-live-secret"
        let dir = SwiftAITestScratch.directory("s1c-reopen"); let storage = try DurableJournalStorage(directory: dir); _ = try await storage.commit(DurableCommitBatch(conversations: [DurableConversationRecord(id: 1)]))
        let admission = try DurableGenerationPlanner.admitBatch(snapshot: try await storage.snapshot(), request: DurableGenerationRequest(conversationID: 1, model: model, transcript: [.user("redispatch")], requestID: "redispatch", options: options)); _ = try await storage.commit(admission.batch); try await storage.close()
        let reopenedStorage = try DurableJournalStorage(directory: dir); let reopened = DurableSession(storage: reopenedStorage, toolRegistry: nil, liveConnectionResolver: { _ in DurableLiveConnection(endpoint: "https://mistral-s1b.test/v1", apiKey: "fresh-live-secret") }); XCTAssertTrue(S1BMistralURLProtocol.requests.isEmpty); _ = try await reopened.resumeQueued()
        while (try await reopened.snapshot()).tasks.values.contains(where: { ![.completed, .failed, .aborted].contains($0.status) }) { await Task.yield() }
        let request = try XCTUnwrap(S1BMistralURLProtocol.requests.last); XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fresh-live-secret"); XCTAssertTrue(String(data: request.httpBody ?? Data(), encoding: .utf8)?.contains("\"temperature\":0.37") == true)
        let journal = String(data: try Data(contentsOf: dir.appendingPathComponent("journal.log")), encoding: .utf8) ?? ""; XCTAssertFalse(journal.contains("old-live-secret")); XCTAssertFalse(journal.contains("fresh-live-secret")); XCTAssertFalse(journal.contains("old-live.test")); try await reopened.close()
    }

    func testAggregateOverflowFailsLegallyAndPreservesKnownTurnUsage() async throws {
        let capture = S1BCapture(); let model = await install(capture: capture)
        let conversation = DurableConversationRecord(id: 1, createdSeq: 1)
        let aggregate = DurableDocumentRecord(id: 2, scope: "conversation", ownerID: 1, kind: "durable.usage", value: .object(["input": .number(Double(DurableLimits.maxExactInteger)), "output": .number(0), "cacheRead": .number(0), "cacheWrite": .number(0), "cacheWrite1h": .number(0), "reasoning": .number(0), "totalTokens": .number(Double(DurableLimits.maxExactInteger)), "cost": .object(["input": .number(0), "output": .number(0), "cacheRead": .number(0), "cacheWrite": .number(0), "total": .number(0)]), "perModel": .object([:])]), createdSeq: 1)
        let storage = DurableMemoryStorage(snapshot: DurableSnapshot(seq: 1, highWaterID: 2, conversations: [1: conversation], documents: [2: aggregate]))
        let session = DurableSession(storage: storage)
        let result = try await session.submit(DurableGenerationRequest(conversationID: 1, model: model, transcript: [.user("overflow")], requestID: "overflow"))
        XCTAssertEqual(result.task.status, .failed)
        XCTAssertEqual(result.submission?.status, .unanswered)
        let snapshot = try await session.snapshot()
        XCTAssertEqual(snapshot.documents[2]?.value.objectValue?["input"], .number(Double(DurableLimits.maxExactInteger)))
        XCTAssertNotNil(snapshot.documents.values.first { $0.ownerID == result.task.id && $0.kind == "generation.usage" })
        XCTAssertNotNil(snapshot.documents.values.first { $0.ownerID == result.task.id && $0.kind == "generation.aggregate-incomplete" })
        try await session.close()
    }

    func testInvalidTerminalSettlesTypedFailureWithoutAnswer() async throws {
        let model = Model(id: "invalid-terminal", name: "Invalid", api: .faux, provider: .faux, baseUrl: "runtime")
        await AIRegistry.shared.register(model)
        await AIRegistry.shared.register(APIProvider(api: .faux, stream: { model, _, _ in AsyncStream { continuation in
            var message = Message(role: .user, content: [.text("not assistant")]); message.api = model.api; message.provider = model.provider; message.model = model.id
            var usage = Usage(); usage.input = -1; usage.totalTokens = -1; message.usage = usage
            continuation.yield(.done(reason: .stop, message: message)); continuation.finish()
        } }))
        let session = DurableSession(storage: DurableMemoryStorage()); let conversation = try await session.createConversation()
        let result = try await session.submit(DurableGenerationRequest(conversationID: conversation.id, model: model, transcript: [.user("bad")], requestID: "bad"))
        XCTAssertEqual(result.task.status, .failed)
        XCTAssertNil(result.entry)
        XCTAssertEqual(result.submission?.status, .unanswered)
        try await session.close()
    }

    func testNativePreflightCountsRawEnumsAndOversizedTerminalSettlesFailure() async throws {
        XCTAssertGreaterThan(try DurableValidation.encoder.encode(API.openAICompletions).count, 2)
        XCTAssertThrowsError(try DurableNativePreflight.validate(API.openAICompletions, maxBytes: 2))
        let model = Model(id: "output-bound", name: "Output", api: .faux, provider: .faux, baseUrl: "runtime")
        await AIRegistry.shared.register(model)
        await AIRegistry.shared.register(APIProvider(api: .faux, stream: { model, _, _ in AsyncStream { continuation in
            var message = Message(role: .assistant, content: [.text(String(repeating: "x", count: DurableLimits.maxStringBytes + 1))]); message.api = model.api; message.provider = model.provider; message.model = model.id; message.stopReason = .stop
            var usage = Usage(); usage.input = 1; usage.output = 1; usage.totalTokens = 2; message.usage = usage
            continuation.yield(.done(reason: .stop, message: message)); continuation.finish()
        } }))
        let session = DurableSession(storage: DurableMemoryStorage()); let conversation = try await session.createConversation()
        let result = try await session.submit(DurableGenerationRequest(conversationID: conversation.id, model: model, transcript: [.user("large output")], requestID: "large-output"))
        XCTAssertEqual(result.task.status, .failed)
        XCTAssertNil(result.entry)
        let snapshot = try await session.snapshot()
        XCTAssertNotNil(snapshot.documents.values.first { $0.ownerID == result.task.id && $0.kind == "generation.usage" })
        XCTAssertFalse(snapshot.tasks.values.contains { $0.status == .running || $0.status == .completing })
        try await session.close()
    }

    func testNativeIntentBoundsRejectBeforeProviderEffect() async throws {
        var bounded = StreamOptions(); bounded.reasoningSummary = String(repeating: "b", count: 100_000)
        let pinned = DurablePinnedOptions(bounded)
        let actualBytes = try DurableValidation.encoder.encode(pinned).count
        XCTAssertLessThan(actualBytes, 150_000)
        XCTAssertNoThrow(try DurableNativePreflight.validate(pinned, maxBytes: 150_000))

        let capture = S1BCapture(); let model = await install(capture: capture)
        var options = StreamOptions(); options.reasoningSummary = String(repeating: "x", count: DurableLimits.maxStringBytes + 1)
        let session = DurableSession(storage: DurableMemoryStorage()); let conversation = try await session.createConversation()
        await XCTAssertThrowsAsyncError(try await session.submit(DurableGenerationRequest(conversationID: conversation.id, model: model, transcript: [.user("large")], requestID: "large", options: options)))
        let effects = await capture.effects
        XCTAssertEqual(effects, 0)
        try await session.close()
    }

    func testNoRequestIDTwoTurnHistoryUsesExactTaskIntentMapping() async throws {
        let capture = S1BCapture(); let model = await install(capture: capture)
        let dir = SwiftAITestScratch.directory("s1b-no-key")
        let firstSession = DurableSession(storage: try DurableJournalStorage(directory: dir)); let conversation = try await firstSession.createConversation()
        let first = try await firstSession.submit(DurableGenerationRequest(conversationID: conversation.id, model: model, transcript: [.user("first-no-key")]))
        XCTAssertEqual(first.task.status, .completed)
        try await firstSession.close()
        let reopened = DurableSession(storage: try DurableJournalStorage(directory: dir))
        let second = try await reopened.submit(DurableGenerationRequest(conversationID: conversation.id, model: model, transcript: [.user("second-no-key")]))
        XCTAssertEqual(second.task.status, .completed)
        let contexts = await capture.texts()
        XCTAssertEqual(contexts, [["first-no-key"], ["first-no-key", "answer", "second-no-key"]])
        let snapshot = try await reopened.snapshot()
        XCTAssertEqual(snapshot.entries.values.first { $0.byTaskID == first.task.id && $0.kind == "assistant" }?.messages?.first?.content.first?.text, "answer")
        XCTAssertEqual(snapshot.entries.values.first { $0.byTaskID == second.task.id && $0.kind == "assistant" }?.messages?.first?.content.first?.text, "answer")
        try await reopened.close()
    }

    func testDuplicateReacquiresExactTaskAndAnswerAmongMultipleTurns() async throws {
        let capture = S1BCapture(); let model = await install(capture: capture)
        let session = DurableSession(storage: DurableMemoryStorage()); let conversation = try await session.createConversation()
        let firstRequest = DurableGenerationRequest(conversationID: conversation.id, model: model, transcript: [.user("first exact")], requestID: "exact-first")
        let first = try await session.submit(firstRequest)
        let second = try await session.submit(DurableGenerationRequest(conversationID: conversation.id, model: model, transcript: [.user("second exact")], requestID: "exact-second"))
        let reacquired = try await session.submit(firstRequest)
        XCTAssertEqual(reacquired.task.id, first.task.id)
        XCTAssertEqual(reacquired.entry?.id, first.entry?.id)
        XCTAssertNotEqual(reacquired.entry?.id, second.entry?.id)
        XCTAssertEqual(reacquired.entry?.messages?.first?.content.first?.text, "answer")
        try await session.close()
    }

    func testPreparedContextLimitSettlesFailureWithoutProviderEffectOrPendingOrphan() async throws {
        let capture = S1BCapture(); let model = await install(capture: capture)
        let storage = DurableMemoryStorage(); let session = DurableSession(storage: storage); let conversation = try await session.createConversation()
        let payload = String(repeating: "p", count: 600 * 1024)
        var last: DurableGenerationResult?
        for index in 0..<6 {
            last = try await session.submit(DurableGenerationRequest(conversationID: conversation.id, model: model, transcript: [.user("\(index)-\(payload)")], requestID: "limit-\(index)"))
        }
        XCTAssertEqual(last?.task.status, .failed)
        XCTAssertEqual(last?.submission?.status, .unanswered)
        let effects = await capture.effects
        XCTAssertEqual(effects, 5)
        let snapshot = try await session.snapshot()
        XCTAssertFalse(snapshot.tasks.values.contains { $0.status == .pending || $0.status == .running || $0.status == .completing })
        try await session.close()
        let reopened = DurableSession(storage: DurableMemoryStorage(snapshot: snapshot))
        _ = try await reopened.resumeQueued()
        let reopenedEffects = await capture.effects
        XCTAssertEqual(reopenedEffects, 5)
        try await reopened.close()
    }

    func testBilledFailurePreservesValidatedUsageAndReacquires() async throws {
        let capture = S1BCapture(); let model = await install(failure: true, capture: capture)
        let session = DurableSession(storage: DurableMemoryStorage())
        let conversation = try await session.createConversation()
        let request = DurableGenerationRequest(conversationID: conversation.id, model: model, transcript: [.user("fail")], requestID: "failed")
        let failed = try await session.submit(request)
        XCTAssertEqual(failed.task.status, .failed)
        XCTAssertEqual(failed.submission?.status, .unanswered)
        let snapshot = try await session.snapshot()
        let usage = snapshot.documents.values.first { $0.ownerID == failed.task.id && $0.kind == "generation.usage" }?.value.objectValue
        XCTAssertEqual(usage?["input"], .number(4))
        XCTAssertEqual(usage?["cost"]?.objectValue?["total"], .number(10))
        let again = try await session.submit(request)
        XCTAssertEqual(again.task.id, failed.task.id)
        let effects = await capture.effects
        XCTAssertEqual(effects, 1)
        try await session.close()
    }
}
