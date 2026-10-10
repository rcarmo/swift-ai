import XCTest
@testable import SwiftAI

final class StoredOAuthTests: XCTestCase {
    func testConcurrentResolutionRefreshesOnceAndPersistsBeforeReturning() async throws {
        let calls = StoredOAuthGate(), registry = OAuthRegistry(), old = OAuthCredentials(refresh: "old-refresh", access: "old-access", expires: 0)
        let store = InMemoryOAuthCredentialStore(credentials: ["test": old])
        await registry.register(StoredOAuthProvider(gate: calls))
        let first = Task { try await registry.resolveStoredAPIKey(id: "test", store: store, now: Date(timeIntervalSince1970: 1)) }
        await calls.entered()
        let second = Task { try await registry.resolveStoredAPIKey(id: "test", store: store, now: Date(timeIntervalSince1970: 1)) }
        await calls.release()
        let a = try await first.value, b = try await second.value
        XCTAssertEqual(a?.0.refresh, "rotated-refresh"); XCTAssertEqual(b?.1, "fresh-access")
        let persisted = await store.read(providerID: "test"); XCTAssertEqual(persisted?.refresh, "rotated-refresh")
        let count = await calls.count; XCTAssertEqual(count, 1)
    }

    func testCallerCancellationAfterRefreshStartsDoesNotLoseRotatedToken() async throws {
        let gate = StoredOAuthGate(), store = InMemoryOAuthCredentialStore(credentials: ["test": OAuthCredentials(refresh: "old-refresh", access: "old-access", expires: 0)])
        let provider = StoredOAuthProvider(gate: gate)
        let observer = Task { try await StoredOAuthRefresh.refresh(store: store, provider: provider, needsRefresh: { _ in true }) }
        await gate.entered(); observer.cancel()
        do { _ = try await observer.value; XCTFail("cancelled observer waited") } catch is CancellationError {} catch { XCTFail("wrong cancellation") }
        await gate.release()
        // Acquire the same mutation lock after the owned refresh; no timing sleep is needed.
        let persisted = try await store.modify(providerID: "test", update: { _ in nil })
        XCTAssertEqual(persisted?.refresh, "rotated-refresh"); XCTAssertEqual(persisted?.access, "fresh-access")
        let count = await gate.count; XCTAssertEqual(count, 1)
    }

    func testCancelledLockWaitDoesNotStartAnotherRefresh() async throws {
        let gate = StoredOAuthGate(), store = InMemoryOAuthCredentialStore(credentials: ["test": OAuthCredentials(refresh: "old", access: "old", expires: 0)])
        let provider = StoredOAuthProvider(gate: gate)
        let first = Task { try await StoredOAuthRefresh.refresh(store: store, provider: provider, needsRefresh: { $0.expires == 0 }) }
        await gate.entered()
        let waiting = Task { try await StoredOAuthRefresh.refresh(store: store, provider: provider, needsRefresh: { _ in true }) }
        waiting.cancel()
        do { _ = try await waiting.value; XCTFail("cancelled admission accepted") } catch is CancellationError {} catch { XCTFail("wrong cancellation") }
        await gate.release(); _ = try await first.value
        let count = await gate.count; XCTAssertEqual(count, 1)
    }

    func testCustomLoginNameAndLegacyProviderOptionsCompatibility() async throws {
        let url = try OpenAIChatGPTOAuthUtilities.authorizationURL(deviceID: "12345678-1234-1234-1234-123456789abc", state: "state", nonce: "nonce", challenge: "challenge", agentName: "Swift App")
        let items = try XCTUnwrap(URLComponents(string: url)?.queryItems)
        XCTAssertEqual(items.first { $0.name == "agent_name_hint" }?.value, "Swift App")
        let legacy = try OpenAIChatGPTOAuthUtilities.authorizationURL(deviceID: "12345678-1234-1234-1234-123456789abc", state: "state", nonce: "nonce", challenge: "challenge")
        XCTAssertEqual(URLComponents(string: legacy)?.queryItems?.first { $0.name == "agent_name_hint" }?.value, "Pi")
        let registry = OAuthRegistry(), gate = StoredOAuthGate()
        await registry.register(StoredOAuthProvider(gate: gate))
        let credential = try await registry.login(id: "test", options: OAuthLoginOptions(agentName: "Swift App"))
        XCTAssertEqual(credential.access, "login")
    }
}

private struct StoredOAuthProvider: OAuthProvider {
    let id = "test", name = "Test"
    let gate: StoredOAuthGate
    func login(callbacks: OAuthLoginCallbacks) async throws -> OAuthCredentials { OAuthCredentials(refresh: "refresh", access: "login", expires: 1000000) }
    func refreshToken(credentials: OAuthCredentials) async throws -> OAuthCredentials {
        await gate.wait()
        try Task.checkCancellation()
        return OAuthCredentials(refresh: "rotated-refresh", access: "fresh-access", expires: 1_000_000)
    }
    func apiKey(credentials: OAuthCredentials) -> String { credentials.access }
    func modifyModels(_ models: [Model], credentials: OAuthCredentials) -> [Model] { models }
}
private actor StoredOAuthGate {
    var count = 0
    private var blocked: CheckedContinuation<Void, Never>?, observer: CheckedContinuation<Void, Never>?
    private var started = false
    func wait() async { count += 1; started = true; observer?.resume(); observer = nil; await withCheckedContinuation { blocked = $0 } }
    func entered() async { if started { return }; await withCheckedContinuation { observer = $0 } }
    func release() { blocked?.resume(); blocked = nil }
}
