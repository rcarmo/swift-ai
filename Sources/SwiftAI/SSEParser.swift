import Foundation

public struct SSEEvent: Equatable, Sendable { public var event: String?; public var data: String; public var id: String?; public var retry: Int? }

public struct SSEParser: Sendable {
    public init() {}

    public func parse(_ text: String) -> [SSEEvent] {
        var out: [SSEEvent] = []
        var event: String?
        var data: [String] = []
        var id: String?
        var retry: Int?

        func flush() {
            guard !data.isEmpty else { event = nil; return }
            out.append(SSEEvent(event: event, data: data.joined(separator: "\n"), id: id, retry: retry))
            event = nil; data.removeAll()
        }

        for raw in text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if line.isEmpty { flush(); continue }
            if line.hasPrefix(":") { continue }
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            let field = String(parts[0])
            var value = parts.count > 1 ? String(parts[1]) : ""
            if value.hasPrefix(" ") { value.removeFirst() }
            switch field {
            case "event": event = value
            case "data": data.append(value)
            case "id": id = value
            case "retry": retry = Int(value)
            default: break
            }
        }
        flush()
        return out
    }
}
