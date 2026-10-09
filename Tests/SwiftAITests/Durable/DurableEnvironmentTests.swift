import XCTest
@testable import SwiftAI

final class DurableEnvironmentTests: XCTestCase {
    private func environment() throws -> (DurableLocalEnvironment, URL, URL) {
        let root = SwiftAITestScratch.directory("env-root"), scratch = SwiftAITestScratch.directory("env-scratch")
        return (try DurableLocalEnvironment(root: root, scratch: scratch), root, scratch)
    }

    func testReadLineBoundsBomInvalidUtf8AndCompleteLineTruncation() async throws {
        let (env, root, _) = try environment()
        try Data([0xef, 0xbb, 0xbf] + Array("one\ntwo\nthree\n".utf8)).write(to: root.appendingPathComponent("file"))
        let first = try await env.read(path: "file", offset: 2, limit: 2)
        XCTAssertEqual(first.text, "two\nthree"); XCTAssertEqual(first.totalLines, 4); XCTAssertFalse(first.truncated)
        let negative = try await env.read(path: "file", offset: -1, limit: 1); XCTAssertEqual(negative.text, "three")
        do { _ = try await env.read(path: "file", offset: 5); XCTFail("out-of-range read accepted") } catch {}
        try Data([0xff, 0x0a, 0x41]).write(to: root.appendingPathComponent("invalid"))
        let decoded = try await env.read(path: "invalid"); XCTAssertEqual(decoded.text, "\u{fffd}\nA")
        try Data(String(repeating: "x", count: 60000).utf8).write(to: root.appendingPathComponent("huge-line"))
        let truncated = try await env.read(path: "huge-line"); XCTAssertTrue(truncated.truncated); XCTAssertEqual(truncated.text, "")
    }

    func testWriteEditOriginalRegionsCrLfBomAndSymlinkGuards() async throws {
        let (env, root, _) = try environment()
        try await env.write(path: "dir/file", content: "\u{feff}one\r\ntwo\r\nthree")
        try await env.edit(path: "dir/file", edits: [DurableTextEdit(oldText: "one\ntwo", newText: "ONE\nTWO"), DurableTextEdit(oldText: "three", newText: "THREE")])
        XCTAssertEqual(String(decoding: try Data(contentsOf: root.appendingPathComponent("dir/file")), as: UTF8.self), "\u{feff}ONE\r\nTWO\r\nTHREE")
        do { try await env.edit(path: "dir/file", edits: [DurableTextEdit(oldText: "ONE", newText: "a"), DurableTextEdit(oldText: "ONE\nTWO", newText: "b")]); XCTFail("overlap accepted") } catch {}
        try await env.write(path: "duplicate", content: "same same")
        do { try await env.edit(path: "duplicate", edits: [DurableTextEdit(oldText: "same", newText: "other")]); XCTFail("nonunique accepted") } catch {}
        do { try await env.write(path: "../escape", content: "x"); XCTFail("escape accepted") } catch {}
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: root.appendingPathComponent("dir/file"))
        do { _ = try await env.read(path: "link"); XCTFail("symlink accepted") } catch {}
        do { try await env.write(path: "link", content: "x"); XCTFail("symlink mutation accepted") } catch {}
    }

    func testProcessTailSpillNonzeroTimeoutAndCancellation() async throws {
        let (env, _, _) = try environment()
        let result = try await env.execute(command: "printf 'out'; printf 'err' >&2; exit 7")
        XCTAssertEqual(result.exitCode, 7); XCTAssertTrue(result.output.contains("out")); XCTAssertTrue(result.output.contains("err"))
        let large = try await env.execute(command: "head -c 100000 /dev/zero | tr '\\0' x")
        XCTAssertTrue(large.truncated); XCTAssertLessThanOrEqual(large.output.utf8.count, 50 * 1024)
        let spill = try XCTUnwrap(large.spillPath); XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: spill)).count, 100000)
        try FileManager.default.removeItem(atPath: spill)
        let started = DispatchTime.now().uptimeNanoseconds
        do { _ = try await env.execute(command: "sleep 60 & wait", timeoutSeconds: 0.02); XCTFail("timeout ignored") } catch {}
        XCTAssertLessThan(Double(DispatchTime.now().uptimeNanoseconds - started) / 1e9, 5)
        let cancelled = DurableCancellationSignal(); cancelled.cancel()
        do { _ = try await env.execute(command: "printf no", cancellation: cancelled); XCTFail("cancelled process started") } catch is CancellationError {} catch { XCTFail("wrong cancellation") }
    }

    func testBuiltinToolsRegisterAndExecuteThroughDurableProviderLoop() async throws {
        let (env, root, _) = try environment(), registry = DurableToolRegistry()
        try await DurableBuiltinTools.register(in: registry, environment: env)
        let bindings = await registry.snapshot(); XCTAssertEqual(bindings.map { $0.definition.name }, ["bash", "edit", "read", "write"])
        let model = Model(id: "builtin", name: "builtin", api: .faux, provider: .faux, baseUrl: "runtime")
        await AIRegistry.shared.register(model)
        await AIRegistry.shared.register(APIProvider(api: .faux, stream: { model, context, _ in AsyncStream { continuation in
            var message = Message(role: .assistant, content: context.messages.contains(where: { $0.role == .toolResult }) ? [.text("done")] : [.toolCall(id: "write-call", name: "write", arguments: ["path": .string("result"), "content": .string("durable")])])
            message.api = model.api; message.provider = model.provider; message.model = model.id; message.stopReason = message.content.first?.type == "toolCall" ? .toolUse : .stop
            continuation.yield(.done(reason: message.stopReason!, message: message)); continuation.finish()
        } }))
        let session = DurableSession(storage: DurableMemoryStorage(), toolRegistry: registry)
        let conversation = try await session.createConversation()
        let result = try await session.submit(DurableGenerationRequest(conversationID: conversation.id, model: model, transcript: [.user("write")]))
        XCTAssertEqual(result.task.status, .completed); XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("result"), encoding: .utf8), "durable")
        try await session.close()
    }
}
