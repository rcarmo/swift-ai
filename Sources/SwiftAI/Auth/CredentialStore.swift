import Foundation

/// The store owns refresh plus persistence as one serial mutation. Persistent implementations must lock across processes.
public protocol OAuthCredentialStore: Sendable {
    func read(providerID: String) async throws -> OAuthCredentials?
    func modify(providerID: String, update: @escaping @Sendable (OAuthCredentials?) async throws -> OAuthCredentials?) async throws -> OAuthCredentials?
}

public actor InMemoryOAuthCredentialStore: OAuthCredentialStore {
    private var values: [String: OAuthCredentials]
    private var locked = Set<String>()
    private struct Waiter { var id: UUID; var continuation: CheckedContinuation<Void, Error> }
    private var waiters: [String: [Waiter]] = [:]
    public init(credentials: [String: OAuthCredentials] = [:]) { values = credentials }
    public func read(providerID: String) -> OAuthCredentials? { values[providerID] }

    public func modify(providerID: String, update: @escaping @Sendable (OAuthCredentials?) async throws -> OAuthCredentials?) async throws -> OAuthCredentials? {
        try await acquire(providerID)
        defer { release(providerID) }
        try Task.checkCancellation()
        // The callback's returned nil means unchanged, matching upstream store mutation semantics.
        if let updated = try await update(values[providerID]) { values[providerID] = updated }
        return values[providerID]
    }

    public func remove(providerID: String) async throws {
        try await acquire(providerID); defer { release(providerID) }; values.removeValue(forKey: providerID)
    }

    private func acquire(_ providerID: String) async throws {
        try Task.checkCancellation()
        if locked.insert(providerID).inserted { return }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled { continuation.resume(throwing: CancellationError()); return }
                waiters[providerID, default: []].append(Waiter(id: id, continuation: continuation))
            }
        } onCancel: { Task { await self.cancel(providerID, id: id) } }
    }
    private func cancel(_ providerID: String, id: UUID) {
        guard let index = waiters[providerID]?.firstIndex(where: { $0.id == id }) else { return }
        waiters[providerID]!.remove(at: index).continuation.resume(throwing: CancellationError())
    }
    private func release(_ providerID: String) {
        if var pending = waiters[providerID], !pending.isEmpty {
            let next = pending.removeFirst(); waiters[providerID] = pending; next.continuation.resume()
        } else { locked.remove(providerID); waiters.removeValue(forKey: providerID) }
    }
}

private actor OAuthRefreshObserver {
    private var result: Result<OAuthCredentials?, Error>?
    private var continuation: CheckedContinuation<OAuthCredentials?, Error>?
    private var cancelled = false
    func wait() async throws -> OAuthCredentials? {
        if cancelled { throw CancellationError() }
        if let result { return try result.get() }
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func finish(_ result: Result<OAuthCredentials?, Error>) {
        guard self.result == nil else { return }; self.result = result
        continuation?.resume(with: result); continuation = nil
    }
    func cancel() { cancelled = true; continuation?.resume(throwing: CancellationError()); continuation = nil }
}

private final class OAuthRefreshAdmission: @unchecked Sendable {
    private let lock = NSLock()
    private var started = false
    private var cancelled = false
    func begin() throws {
        lock.lock(); defer { lock.unlock() }
        if cancelled { throw CancellationError() }
        started = true
    }
    func cancelBeforeStart() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if started { return false }
        cancelled = true; return true
    }
}

public enum StoredOAuthRefresh {
    /// Caller cancellation detaches only the observer once refresh begins; the rotated token is persisted before unlock.
    public static func refresh(store: any OAuthCredentialStore, provider: any OAuthProvider, needsRefresh: @escaping @Sendable (OAuthCredentials) -> Bool, timeoutMilliseconds: Int = 15_000) async throws -> OAuthCredentials? {
        try Task.checkCancellation()
        guard timeoutMilliseconds > 0, timeoutMilliseconds <= 300_000 else { throw ModelsError("invalid OAuth refresh timeout") }
        let observer = OAuthRefreshObserver()
        let admission = OAuthRefreshAdmission()
        let owned = Task {
            do {
                let post = try await store.modify(providerID: provider.id) { current in
                    try admission.begin()
                    guard let current, needsRefresh(current) else { return nil }
                    // Awaiting callers do not own this task. A provider timeout still bounds owned work.
                    return try await withThrowingTaskGroup(of: OAuthCredentials.self) { group in
                        group.addTask { try await provider.refreshToken(credentials: current, cancellation: OAuthCancellation()) }
                        group.addTask { try await Task.sleep(nanoseconds: UInt64(timeoutMilliseconds) * 1_000_000); throw ModelsError("OAuth refresh timed out for \(provider.id)") }
                        defer { group.cancelAll() }
                        guard let result = try await group.next() else { throw ModelsError("OAuth refresh produced no result") }
                        return result
                    }
                }
                await observer.finish(.success(post))
            } catch { await observer.finish(.failure(error)) }
        }
        return try await withTaskCancellationHandler {
            try await observer.wait()
        } onCancel: {
            // Cancel lock admission only. Once inside the callback, cancellation must not lose a rotated token.
            if admission.cancelBeforeStart() { owned.cancel() }
            Task { await observer.cancel() }
        }
    }
}

public extension OAuthRegistry {
    func resolveStoredAPIKey(id: String, store: any OAuthCredentialStore, minimumValiditySeconds: Int = 300, now: Date = Date()) async throws -> (OAuthCredentials, String)? {
        guard minimumValiditySeconds >= 0, minimumValiditySeconds <= 86_400 else { throw ModelsError("invalid minimum OAuth validity") }
        guard let provider = provider(id: id), var credentials = try await store.read(providerID: id) else { return nil }
        let nowMs = Int64(now.timeIntervalSince1970 * 1000), window = Int64(minimumValiditySeconds) * 1000
        if credentials.expires - nowMs <= window {
            guard let refreshed = try await StoredOAuthRefresh.refresh(store: store, provider: provider, needsRefresh: { $0.expires - nowMs <= window }) else { return nil }
            credentials = refreshed
        }
        return (credentials, provider.apiKey(credentials: credentials))
    }
}
