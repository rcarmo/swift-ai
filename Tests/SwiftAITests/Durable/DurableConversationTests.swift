import XCTest
@testable import SwiftAI

final class DurableConversationTests: XCTestCase {
    func testForkCopiesHistoricalAndCurrentDocumentsAndSharesCutHistory() async throws {
        let directory = SwiftAITestScratch.directory("fork-history")
        let session = DurableSession(storage: try DurableJournalStorage(directory: directory))
        let parent = try await session.createConversation()
        _ = try await session.writeDocument(scope: "conversation", ownerID: parent.id, kind: "historic", value: .object(["n": .number(1)]), history: .rewindable, fork: .asOf)
        let cut = try await session.appendEntry(conversationID: parent.id, kind: "user", messages: [.user("before")])
        _ = try await session.writeDocument(scope: "conversation", ownerID: parent.id, kind: "historic", value: .object(["n": .number(2)]), history: .rewindable, fork: .asOf)
        _ = try await session.writeDocument(scope: "conversation", ownerID: parent.id, kind: "current", value: .object(["n": .number(3)]), fork: .current)
        _ = try await session.writeDocument(scope: "conversation", ownerID: parent.id, kind: "initial", value: .object(["n": .number(4)]))
        _ = try await session.appendEntry(conversationID: parent.id, kind: "user", messages: [.user("after")])
        let child = try await session.forkConversation(parentID: parent.id, at: cut.id)
        let childContext = try await session.context(conversationID: child.id)
        XCTAssertEqual(childContext.messages.compactMap { $0.content.first?.text }, ["before"])
        let historic = try await session.document(scope: "conversation", ownerID: child.id, kind: "historic")
        let current = try await session.document(scope: "conversation", ownerID: child.id, kind: "current")
        let initial = try await session.document(scope: "conversation", ownerID: child.id, kind: "initial")
        XCTAssertEqual(historic, .object(["n": .number(1)])); XCTAssertEqual(current, .object(["n": .number(3)])); XCTAssertNil(initial)
        _ = try await session.writeDocument(scope: "conversation", ownerID: child.id, kind: "historic", value: .object(["n": .number(9)]), history: .rewindable, fork: .asOf)
        let parentValue = try await session.document(scope: "conversation", ownerID: parent.id, kind: "historic")
        XCTAssertEqual(parentValue, .object(["n": .number(2)]))
        let childEntry = try await session.appendEntry(conversationID: child.id, kind: "user", messages: [.user("child")])
        let grandchild = try await session.forkConversation(parentID: child.id, at: cut.id)
        XCTAssertLessThan(cut.id, childEntry.id)
        let grandchildContext = try await session.context(conversationID: grandchild.id)
        XCTAssertEqual(grandchildContext.messages.compactMap { $0.content.first?.text }, ["before"])
        try await session.close()
        let reopened = DurableSession(storage: try DurableJournalStorage(directory: directory))
        let persisted = try await reopened.context(conversationID: child.id)
        XCTAssertEqual(persisted.messages.compactMap { $0.content.first?.text }, ["before", "child"])
        let inspection = try await reopened.inspection()
        XCTAssertEqual(try inspection.scanEntries(conversationID: child.id, order: .ascending).values.map(\.id), [cut.id, childEntry.id])
        let history = try await reopened.document(scope: "conversation", ownerID: parent.id, kind: "historic", at: cut.createdSeq == 0 ? 3 : cut.createdSeq)
        XCTAssertEqual(history, .object(["n": .number(1)]))
        try await reopened.close()
    }

    func testResetAndLatestEditsOrderToolResultsAndFailClosedOnInvisibleTargets() async throws {
        let session = DurableSession(storage: DurableMemoryStorage())
        let conversation = try await session.createConversation()
        let user = try await session.appendEntry(conversationID: conversation.id, kind: "user", messages: [.user("old")])
        var assistant = Message(role: .assistant, content: [.toolCall(id: "a", name: "one", arguments: [:]), .toolCall(id: "b", name: "two", arguments: [:])]); assistant.stopReason = .toolUse
        _ = try await session.appendEntry(conversationID: conversation.id, kind: "assistant", messages: [assistant])
        var b = Message(role: .toolResult, content: [.text("B")]); b.toolCallId = "b"
        _ = try await session.appendEntry(conversationID: conversation.id, kind: "result", messages: [b])
        _ = try await session.editContext(conversationID: conversation.id, edits: [DurableContextEdit(target: user.id, action: .replace, messages: [.user("new")])])
        let context = try await session.context(conversationID: conversation.id)
        XCTAssertEqual(context.messages[0].content[0].text, "new")
        XCTAssertEqual(context.messages.map(\.role), [.user, .assistant, .toolResult, .toolResult])
        XCTAssertEqual(context.messages[2].toolCallId, "a"); XCTAssertEqual(context.messages[2].isError, true)
        XCTAssertEqual(context.messages[3].toolCallId, "b")
        _ = try await session.resetConversation(conversationID: conversation.id, messages: [.user("reset")])
        let reset = try await session.context(conversationID: conversation.id)
        XCTAssertEqual(reset.messages.compactMap { $0.content.first?.text }, ["reset"])
        do { _ = try await session.editContext(conversationID: conversation.id, edits: [DurableContextEdit(target: 999999, action: .omit)]); XCTFail("invalid edit accepted") } catch {}
        try await session.close()
    }

    func testAtomicWatchBaselineRetirementRecreationAndClose() async throws {
        let session = DurableSession(storage: DurableMemoryStorage())
        let conversation = try await session.createConversation()
        _ = try await session.writeDocument(scope: "conversation", ownerID: conversation.id, kind: "pi.agent", value: .object(["n": .number(0)]))
        let acquired = try await session.watchDocument(scope: "conversation", ownerID: conversation.id, kind: "pi.agent")
        var iterator = try XCTUnwrap(acquired).makeAsyncIterator()
        let baseline = await iterator.next(); XCTAssertEqual(baseline?.value, .object(["n": .number(0)]))
        let view = try await session.watchView(conversationID: conversation.id)
        var viewIterator = view.makeAsyncIterator()
        let firstView = await viewIterator.next(); XCTAssertEqual(firstView?.value.documents["pi.agent"], .object(["n": .number(0)]))
        _ = try await session.writeDocument(scope: "conversation", ownerID: conversation.id, kind: "pi.agent", value: .object(["n": .number(1)]))
        let update = await iterator.next(); XCTAssertEqual(update?.value, .object(["n": .number(1)])); XCTAssertGreaterThan(update!.sequence, baseline!.sequence)
        let viewUpdate = await viewIterator.next(); XCTAssertEqual(viewUpdate?.value.documents["pi.agent"], .object(["n": .number(1)]))
        try await session.retireDocument(scope: "conversation", ownerID: conversation.id, kind: "pi.agent")
        let retired = await iterator.next(); XCTAssertNil(retired?.value); let ended = await iterator.next(); XCTAssertNil(ended)
        _ = try await session.writeDocument(scope: "conversation", ownerID: conversation.id, kind: "pi.agent", value: .object(["n": .number(2)]))
        let absent = try await session.watchDocument(scope: "conversation", ownerID: conversation.id, kind: "absent")
        XCTAssertNil(absent)
        try await session.close()
        while let _ = await viewIterator.next() {}
    }

    func testBoundedWatchRootFramesConvergeWithoutMutatingPriorRevision() async throws {
        let session = DurableSession(storage: DurableMemoryStorage())
        let conversation = try await session.createConversation()
        _ = try await session.writeDocument(scope: "conversation", ownerID: conversation.id, kind: "watch", value: .object(["n": .number(0)]))
        let acquired = try await session.watchDocument(scope: "conversation", ownerID: conversation.id, kind: "watch")
        let stream = try XCTUnwrap(acquired)
        var iterator = stream.makeAsyncIterator(); let initial = await iterator.next()
        for n in 1...105 { _ = try await session.writeDocument(scope: "conversation", ownerID: conversation.id, kind: "watch", value: .object(["n": .number(Double(n))])) }
        try await session.close()
        var last: JSONValue?; var count = 0
        while let frame = await iterator.next() { last = frame.value; count += 1; XCTAssertTrue(frame.replacesRoot) }
        XCTAssertEqual(count, 100); XCTAssertEqual(last, .object(["n": .number(105)])); XCTAssertEqual(initial?.value, .object(["n": .number(0)]))
    }
}
