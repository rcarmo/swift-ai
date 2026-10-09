import XCTest
@testable import SwiftAI

final class DurableV110Tests: XCTestCase {
    func testOrderedScanCursorRetainsDirectionAndBounds() throws {
        let conversations = Dictionary(uniqueKeysWithValues: (1...4).map { (Int64($0), DurableConversationRecord(id: Int64($0))) })
        let entries = Dictionary(uniqueKeysWithValues: (5...9).map { (Int64($0), DurableEntryRecord(id: Int64($0), conversationID: 1, kind: "message", data: .object([:]), createdSeq: 1)) })
        let inspection = DurableInspection(snapshot: DurableSnapshot(highWaterID: 9, conversations: conversations, entries: entries))
        let first = try inspection.scanConversations(order: .descending, limit: 2)
        XCTAssertEqual(first.values.map(\.id), [4, 3]); XCTAssertEqual(first.next?.order, .descending)
        let second = try inspection.scanConversations(cursor: first.next, limit: 2)
        XCTAssertEqual(second.values.map(\.id), [2, 1]); XCTAssertNil(second.next)
        XCTAssertThrowsError(try inspection.scanConversations(order: .ascending, cursor: first.next))
        XCTAssertThrowsError(try inspection.scanConversations(cursor: DurableScanCursor(after: DurableLimits.maxExactInteger + 1)))
        XCTAssertThrowsError(try inspection.scanConversations(limit: 0))
        let newest = try inspection.scanEntries(conversationID: 1, minEntryID: 6, maxEntryID: 8, limit: 2)
        XCTAssertEqual(newest.values.map(\.id), [8, 7])
        let remainder = try inspection.scanEntries(conversationID: 1, minEntryID: 6, maxEntryID: 8, cursor: newest.next, limit: 2)
        XCTAssertEqual(remainder.values.map(\.id), [6])
        let legacy = try inspection.scanEntries(cursor: DurableScanCursor(after: 8), limit: 2)
        XCTAssertEqual(legacy.values.map(\.id), [7, 6])
        let ascending = try inspection.scanEntries(order: .ascending, limit: 2)
        XCTAssertEqual(ascending.values.map(\.id), [5, 6]); XCTAssertEqual(ascending.next?.order, .ascending)
    }

    func testProviderSessionIDPersistsAcrossGenerationsAndReopen() async throws {
        let captures = DurableV110Captures()
        let model = Model(id: "session-id", name: "Session ID", api: .faux, provider: .faux, baseUrl: "runtime", contextWindow: 10000, maxTokens: 1000)
        await AIRegistry.shared.register(model)
        await AIRegistry.shared.register(APIProvider(api: .faux, stream: { model, _, options in AsyncStream { continuation in Task {
            await captures.append(options?.sessionId)
            var message = Message(role: .assistant, content: [.text("answer")]); message.api = model.api; message.provider = model.provider; message.model = model.id; message.stopReason = .stop; message.usage = Usage()
            continuation.yield(.done(reason: .stop, message: message)); continuation.finish()
        } } }))
        let storage = try DurableMemoryStorage()
        let session = DurableSession(storage: storage)
        let conversation = try await session.createConversation()
        for index in 0..<2 {
            _ = try await session.submit(DurableGenerationRequest(conversationID: conversation.id, model: model, transcript: [.user("input \(index)")]))
        }
        let snapshot = try await session.snapshot()
        let document = try XCTUnwrap(snapshot.documents.values.first { $0.kind == "pi.provider" })
        let id = try XCTUnwrap(document.value.objectValue?["sessionId"]?.stringValue)
        let first = await captures.ids; XCTAssertEqual(first, [id, id])
        let secondStorage = DurableMemoryStorage(snapshot: snapshot)
        let reopened = DurableSession(storage: secondStorage)
        _ = try await reopened.submit(DurableGenerationRequest(conversationID: conversation.id, model: model, transcript: [.user("after reopen")]))
        let all = await captures.ids; XCTAssertEqual(all, [id, id, id])
        let after = try await reopened.snapshot(); XCTAssertEqual(after.documents.values.filter { $0.kind == "pi.provider" }.count, 1)
        try await session.close(); try await reopened.close()
    }
}

private actor DurableV110Captures {
    var ids: [String?] = []
    func append(_ id: String?) { ids.append(id) }
}
