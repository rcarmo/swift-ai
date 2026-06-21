import Foundation

public enum PromptCache {
    public static let openAIKeyMaxLength = 64

    public static func clampOpenAIKey(_ key: String) -> String {
        guard key.count > openAIKeyMaxLength else { return key }
        return String(key.prefix(openAIKeyMaxLength))
    }
}

public actor SessionResourceRegistry {
    public typealias Cleanup = @Sendable (String) async throws -> Void
    public static let shared = SessionResourceRegistry()
    private var cleanups: [UUID: Cleanup] = [:]

    @discardableResult
    public func register(_ cleanup: @escaping Cleanup) -> @Sendable () async -> Void {
        let id = UUID()
        cleanups[id] = cleanup
        return { await self.unregister(id) }
    }

    public func unregister(_ id: UUID) { cleanups.removeValue(forKey: id) }

    public func cleanup(sessionId: String = "") async throws {
        let callbacks = Array(cleanups.values)
        var errors: [Error] = []
        for callback in callbacks {
            do { try await callback(sessionId) }
            catch { errors.append(error) }
        }
        if !errors.isEmpty { throw SessionResourceError(errors: errors) }
    }
}

public struct SessionResourceError: Error, Sendable, CustomStringConvertible {
    public var errors: [Error]
    public var description: String { errors.map { String(describing: $0) }.joined(separator: "; ") }
}
