import XCTest
@testable import SwiftAI

final class DurableCompactionTests: XCTestCase {
    func testManualCompactionPinsSummaryStagesUsageAndSurvivesJournalReopen() async throws {
        let capture = CompactionCapture()
        let model = Model(id: "summarizer", name: "summarizer", api: .faux, provider: .faux, baseUrl: "runtime", maxTokens: 100)
        await AIRegistry.shared.register(model)
        await AIRegistry.shared.register(APIProvider(api: .faux, stream: { model, context, options in AsyncStream { continuation in Task {
            await capture.append(context, options: options)
            var message = Message(role: .assistant, content: [.text("Continue the decision and retain constraints.")]); message.api = model.api; message.provider = model.provider; message.model = model.id; message.stopReason = .stop
            var usage = Usage(); usage.input = 3; usage.output = 2; usage.totalTokens = 5; message.usage = usage
            continuation.yield(.done(reason: .stop, message: message)); continuation.finish()
        } } }))
        let directory = SwiftAITestScratch.directory("compact-reopen")
        let session = DurableSession(storage: try DurableJournalStorage(directory: directory))
        let conversation = try await session.createConversation()
        for text in ["first", "second", "third", "fourth"] { _ = try await session.appendEntry(conversationID: conversation.id, kind: "user", messages: [.user(text)]) }
        let compacted = try await session.compact(conversationID: conversation.id, model: model, keepRecentTokens: 1, reserveTokens: 100, instructions: "Keep IDs")
        let result = try XCTUnwrap(compacted); XCTAssertEqual(result.task.status, .completed); XCTAssertNotNil(result.entry?.head)
        let context = try await session.context(conversationID: conversation.id)
        XCTAssertEqual(context.entries.first?.kind, "pi.compaction"); XCTAssertEqual(context.messages.last?.content.first?.text, "fourth")
        XCTAssertFalse(context.messages.contains { $0.content.first?.text == "first" })
        let captured = await capture.prompts; XCTAssertEqual(captured.count, 1); XCTAssertTrue(captured[0].messages[0].content[0].text?.contains("Keep IDs") == true)
        let options = await capture.options; XCTAssertEqual(options[0].maxTokens, 80); XCTAssertEqual(options[0].cacheRetention, CacheRetention.none); XCTAssertNotNil(options[0].sessionId)
        let snapshot = try await session.snapshot(); XCTAssertEqual(snapshot.documents.values.first { $0.kind == "compaction.usage" }?.value.objectValue?["totalTokens"], .number(5))
        try await session.close()
        let reopened = DurableSession(storage: try DurableJournalStorage(directory: directory))
        let recovered = try await reopened.resumeCompactions(); XCTAssertTrue(recovered.isEmpty)
        let persisted = try await reopened.context(conversationID: conversation.id); XCTAssertEqual(persisted.messages, context.messages)
        try await reopened.close()
    }

    func testCutPreservesToolCallAndResultGroupAndNoOpForShortHistory() {
        var call = Message(role: .assistant, content: [.toolCall(id: "c", name: "tool", arguments: [:])]); call.stopReason = .toolUse
        var result = Message(role: .toolResult, content: [.text("tool result")]); result.toolCallId = "c"
        let contributions: [[Message]] = [[.user("old")], [call], [.user("queued")], [result], [.user("new")]]
        let entries = contributions.enumerated().map { DurableEntryRecord(id: Int64($0.offset + 1), conversationID: 1, kind: "message", messages: $0.element) }
        let view = DurableContextView(entries: entries, contributions: contributions, messages: DurableContext.orderToolResults(contributions.flatMap { $0 }))
        XCTAssertEqual(DurableCompaction.selectCut(view: view, keepRecentTokens: 3), 4)
        XCTAssertNil(DurableCompaction.selectCut(view: DurableContextView(entries: Array(entries.prefix(1)), contributions: Array(contributions.prefix(1)), messages: [.user("old")]), keepRecentTokens: 100))
    }

    func testHookSummaryAndDeclineAvoidProviderEffects() async throws {
        let session = DurableSession(storage: DurableMemoryStorage())
        let model = Model(id: "no-summary-provider", name: "none", api: .faux, provider: .faux)
        let conversation = try await session.createConversation()
        try await session.configureAgent(conversationID: conversation.id, settings: DurableAgentSettings(model: model, extensions: ["summary"]))
        for text in ["first", "second", "third"] { _ = try await session.appendEntry(conversationID: conversation.id, kind: "user", messages: [.user(text)]) }
        try await session.extensionRegistry.install(DurableExtension(name: "summary", hooks: DurableGenerationHooks(beforeCompact: { view in
            XCTAssertEqual(view.messages.count, 3); return .summary("hook supplied summary")
        })))
        let compacted = try await session.compact(conversationID: conversation.id, model: model, keepRecentTokens: 1)
        let summary = try XCTUnwrap(compacted); XCTAssertEqual(summary.task.status, .completed); XCTAssertTrue(summary.entry?.messages?.first?.content.first?.text?.contains("hook supplied summary") == true)
        _ = try await session.appendEntry(conversationID: conversation.id, kind: "user", messages: [.user("fourth")])
        try await session.extensionRegistry.install(DurableExtension(name: "summary", hooks: DurableGenerationHooks(beforeCompact: { _ in .decline })))
        let declined = try await session.compact(conversationID: conversation.id, model: model, keepRecentTokens: 1)
        let result = try XCTUnwrap(declined); XCTAssertEqual(result.task.status, .completed); XCTAssertNil(result.entry); XCTAssertEqual(result.task.outcome?.objectValue?["declined"], .bool(true))
        try await session.close()
    }

    func testPersistedHookDecisionRecoveryDoesNotInvokeHookAgain() async throws {
        let storage = DurableMemoryStorage()
        _ = try await storage.commit(DurableCommitBatch(conversations: [DurableConversationRecord(id: 1)], entries: [DurableEntryRecord(id: 2, conversationID: 1, kind: "user", messages: [.user("old")]), DurableEntryRecord(id: 3, conversationID: 1, kind: "user", messages: [.user("kept")])]))
        let model = Model(id: "none", name: "none", api: .faux, provider: .faux)
        let intent = DurableCompactionIntent(model: model, conversationID: 1, tail: 3, firstKept: 3, transcript: [.user("old")], maxTokens: 80, summary: "durable hook summary", extensions: ["missing-on-reopen"], decisionEvaluated: true)
        _ = try await storage.commit(DurableCommitBatch(tasks: [DurableTaskRecord(id: 4, conversationID: 1, kind: "compaction")], documents: [DurableDocumentRecord(id: 5, scope: "task", ownerID: 4, kind: "compaction.intent", value: try DurableGenerationPlanner.encodeJSON(intent))]))
        _ = try await storage.commit(DurableCommitBatch(tasks: [DurableTaskRecord(id: 4, conversationID: 1, kind: "compaction", status: .running)]))
        let session = DurableSession(storage: storage)
        let results = try await session.resumeCompactions(); XCTAssertEqual(results.first?.task.status, .completed); XCTAssertTrue(results.first?.entry?.messages?.first?.content.first?.text?.contains("durable hook summary") == true)
        try await session.close()
    }

    func testStagedSummaryRecoveryDoesNotCallProviderOrRebill() async throws {
        let storage = DurableMemoryStorage()
        _ = try await storage.commit(DurableCommitBatch(conversations: [DurableConversationRecord(id: 1)], entries: [DurableEntryRecord(id: 2, conversationID: 1, kind: "user", messages: [.user("old")]), DurableEntryRecord(id: 3, conversationID: 1, kind: "user", messages: [.user("kept")])]))
        let model = Model(id: "staged", name: "staged", api: .faux, provider: .faux)
        let intent = DurableCompactionIntent(model: model, conversationID: 1, tail: 3, firstKept: 3, transcript: [.user("old")], maxTokens: 80, summary: "staged summary")
        _ = try await storage.commit(DurableCommitBatch(tasks: [DurableTaskRecord(id: 4, conversationID: 1, kind: "compaction", status: .pending)], documents: [DurableDocumentRecord(id: 5, scope: "task", ownerID: 4, kind: "compaction.intent", value: try DurableGenerationPlanner.encodeJSON(intent))]))
        _ = try await storage.commit(DurableCommitBatch(tasks: [DurableTaskRecord(id: 4, conversationID: 1, kind: "compaction", status: .running)]))
        _ = try await storage.commit(DurableCommitBatch(tasks: [DurableTaskRecord(id: 4, conversationID: 1, kind: "compaction", status: .completing)]))
        let session = DurableSession(storage: storage)
        let results = try await session.resumeCompactions(); XCTAssertEqual(results.count, 1); XCTAssertEqual(results[0].task.status, .completed)
        let after = try await session.context(conversationID: 1); XCTAssertEqual(after.messages.last?.content.first?.text, "kept")
        XCTAssertTrue(after.messages.first?.content.first?.text?.contains("staged summary") == true)
        let repeated = try await session.resumeCompactions(); XCTAssertTrue(repeated.isEmpty)
        try await session.close()
    }
}

private actor CompactionCapture {
    var prompts: [AIContext] = []
    var options: [StreamOptions] = []
    func append(_ context: AIContext, options: StreamOptions?) { prompts.append(context); self.options.append(options ?? StreamOptions()) }
}
