import Foundation

public enum LogLevel: Int, Comparable, Sendable { case debug = 0, info = 1, warn = 2, error = 3, off = 4; public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool { lhs.rawValue < rhs.rawValue } }

public protocol AILogger: Sendable {
    func debug(_ message: String, _ keyValues: [String: String])
    func info(_ message: String, _ keyValues: [String: String])
    func warn(_ message: String, _ keyValues: [String: String])
    func error(_ message: String, _ keyValues: [String: String])
}

public struct DiscardLogger: AILogger {
    public init() {}
    public func debug(_ message: String, _ keyValues: [String: String] = [:]) {}
    public func info(_ message: String, _ keyValues: [String: String] = [:]) {}
    public func warn(_ message: String, _ keyValues: [String: String] = [:]) {}
    public func error(_ message: String, _ keyValues: [String: String] = [:]) {}
}

public struct StderrLogger: AILogger {
    public var level: LogLevel
    public init(level: LogLevel = .info) { self.level = level }
    public func debug(_ message: String, _ keyValues: [String: String] = [:]) { emit(.debug, message, keyValues) }
    public func info(_ message: String, _ keyValues: [String: String] = [:]) { emit(.info, message, keyValues) }
    public func warn(_ message: String, _ keyValues: [String: String] = [:]) { emit(.warn, message, keyValues) }
    public func error(_ message: String, _ keyValues: [String: String] = [:]) { emit(.error, message, keyValues) }
    private func emit(_ eventLevel: LogLevel, _ message: String, _ keyValues: [String: String]) {
        guard eventLevel.rawValue >= level.rawValue, level != .off else { return }
        let attrs = keyValues.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        let line = attrs.isEmpty ? "[swift-ai] \(eventLevel) \(message)" : "[swift-ai] \(eventLevel) \(message) \(attrs)"
        FileHandle.standardError.write((line + "\n").data(using: .utf8) ?? Data())
    }
}

public actor LoggerRegistry {
    public static let shared = LoggerRegistry()
    private var logger: any AILogger = DiscardLogger()
    public func setLogger(_ logger: (any AILogger)?) { self.logger = logger ?? DiscardLogger() }
    public func current() -> any AILogger { logger }
    public func debug(_ message: String, _ keyValues: [String: String] = [:]) { logger.debug(message, keyValues) }
    public func info(_ message: String, _ keyValues: [String: String] = [:]) { logger.info(message, keyValues) }
    public func warn(_ message: String, _ keyValues: [String: String] = [:]) { logger.warn(message, keyValues) }
    public func error(_ message: String, _ keyValues: [String: String] = [:]) { logger.error(message, keyValues) }
}
