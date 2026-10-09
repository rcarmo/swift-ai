import XCTest
@testable import SwiftAI

final class DurableDocumentsTests: XCTestCase {
    func testReadMigrationNeverWritesAndFailedMutationPreservesStoredVersion() async throws {
        let session = DurableSession(storage: DurableMemoryStorage())
        let conversation = try await session.createConversation()
        let v1 = DurableDocumentDefinition(kind: "typed", scope: .conversation, history: .rewindable, fork: .asOf, initial: { .object(["old": .number(1)]) })
        let created = try await session.updateDocument(v1, ownerID: conversation.id); XCTAssertEqual(created, .object(["old": .number(1)]))
        let before = try await session.snapshot()
        let v2 = DurableDocumentDefinition(kind: "typed", scope: .conversation, version: 2, history: .rewindable, fork: .asOf, initial: { .object(["new": .number(0)]) }, migrate: { value, version in
            guard version == 1 else { throw DurableError.invalidRecord("unexpected version") }
            return .object(["new": value.objectValue?["old"] ?? .null])
        })
        let read = try await session.readDocument(v2, ownerID: conversation.id); XCTAssertEqual(read, .object(["new": .number(1)]))
        let afterRead = try await session.snapshot(); XCTAssertEqual(afterRead.seq, before.seq)
        do { _ = try await session.updateDocument(v2, ownerID: conversation.id, update: { _ in throw DurableError.invalidRecord("callback failed") }); XCTFail("callback persisted") } catch {}
        let afterThrow = try await session.snapshot(); XCTAssertEqual(afterThrow, before)
        _ = try await session.updateDocument(v2, ownerID: conversation.id)
        let migrated = try await session.snapshot(); XCTAssertEqual(migrated.documents.values.first { $0.kind == "typed" }?.version, 2)
        do { _ = try await session.readDocument(v1, ownerID: conversation.id); XCTFail("newer version accepted") } catch {}
        let historical = try await session.readDocument(v2, ownerID: conversation.id, at: before.seq)
        XCTAssertEqual(historical, .object(["new": .number(1)]))
        try await session.close()
    }

    func testWatchBuffersBeforeStartAndSerialListenerCanReenterSession() async throws {
        let session = DurableSession(storage: DurableMemoryStorage())
        let conversation = try await session.createConversation()
        _ = try await session.writeDocument(scope: "conversation", ownerID: conversation.id, kind: "watch", value: .object(["n": .number(0)]))
        let acquired = try await session.acquireDocumentWatch(scope: "conversation", ownerID: conversation.id, kind: "watch")
        let watch = try XCTUnwrap(acquired), captured = DocumentTestCapture()
        for n in 1...3 { _ = try await session.writeDocument(scope: "conversation", ownerID: conversation.id, kind: "watch", value: .object(["n": .number(Double(n))])) }
        let beforeStart = await watch.value; XCTAssertEqual(beforeStart, .object(["n": .number(0)]))
        try await watch.start { frame in
            _ = try await session.snapshot()
            await captured.append(frame.value)
        }
        try await session.retireDocument(scope: "conversation", ownerID: conversation.id, kind: "watch")
        let end = await watch.closed(); XCTAssertEqual(end, .retired)
        let values = await captured.values; XCTAssertEqual(values, [.object(["n": .number(1)]), .object(["n": .number(2)]), .object(["n": .number(3)]), nil])
        let terminal = await watch.value; XCTAssertNil(terminal)
        let lateStop = await watch.stop(); XCTAssertEqual(lateStop, .retired)
        try await session.close()
    }

    func testStoppingWatchDoesNotJoinActiveCallbackAndFirstEndWins() async throws {
        let session = DurableSession(storage: DurableMemoryStorage())
        let conversation = try await session.createConversation()
        _ = try await session.writeDocument(scope: "conversation", ownerID: conversation.id, kind: "watch", value: .object([:]))
        let acquired = try await session.acquireDocumentWatch(scope: "conversation", ownerID: conversation.id, kind: "watch")
        let watch = try XCTUnwrap(acquired), barrier = DocumentCallbackBarrier()
        try await watch.start { _ in await barrier.hold() }
        _ = try await session.writeDocument(scope: "conversation", ownerID: conversation.id, kind: "watch", value: .object(["n": .number(1)]))
        await barrier.entered()
        let stopped = await watch.stop(); XCTAssertEqual(stopped, .stopped)
        let cancelled = await watch.cancel(); XCTAssertEqual(cancelled, .stopped)
        let closed = await watch.closed(); XCTAssertEqual(closed, .stopped)
        await barrier.release()
        try await session.close()
    }

    func testListenerFailureTerminatesOnlyItsWatch() async throws {
        let session = DurableSession(storage: DurableMemoryStorage())
        let conversation = try await session.createConversation()
        _ = try await session.writeDocument(scope: "conversation", ownerID: conversation.id, kind: "watch", value: .object([:]))
        let acquired = try await session.acquireDocumentWatch(scope: "conversation", ownerID: conversation.id, kind: "watch")
        let watch = try XCTUnwrap(acquired)
        try await watch.start { _ in throw DurableError.invalidRecord("listener failed") }
        _ = try await session.writeDocument(scope: "conversation", ownerID: conversation.id, kind: "watch", value: .object(["n": .number(1)]))
        let end = await watch.closed(); if case .listenerError = end {} else { XCTFail("expected listener error") }
        _ = try await session.writeDocument(scope: "conversation", ownerID: conversation.id, kind: "watch", value: .object(["n": .number(2)]))
        try await session.close()
    }

}

private actor DocumentTestCapture { var values: [JSONValue?] = []; func append(_ value: JSONValue?) { values.append(value) } }
private actor DocumentCallbackBarrier {
    private var wait: CheckedContinuation<Void, Never>?, notice: CheckedContinuation<Void, Never>?
    private var started = false
    func hold() async { started = true; notice?.resume(); notice = nil; await withCheckedContinuation { wait = $0 } }
    func entered() async { if started { return }; await withCheckedContinuation { notice = $0 } }
    func release() { wait?.resume(); wait = nil }
}
