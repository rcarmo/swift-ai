import Foundation

public struct DurableContextView: Sendable, Equatable {
    public var head: DurableEntryRecord?
    public var entries: [DurableEntryRecord]
    public var contributions: [[Message]]
    public var messages: [Message]
}

public enum DurableContext {
    /// Fork segments share immutable entries through each parent's concrete cut.
    public static func visibleEntries(snapshot: DurableSnapshot, conversationID: Int64, at: Int64? = nil) throws -> [DurableEntryRecord] {
        guard snapshot.conversations[conversationID] != nil else { throw DurableError.invalidRecord("missing conversation") }
        var segments: [(Int64, Int64)] = []
        var id = conversationID, upper = at ?? DurableLimits.maxExactInteger
        var seen = Set<Int64>()
        while true {
            guard seen.insert(id).inserted, let conversation = snapshot.conversations[id] else { throw DurableError.corruptStorage("conversation parent cycle") }
            segments.append((id, upper))
            guard let parent = conversation.parentConversationID, let cut = conversation.parentEntryID else { break }
            upper = min(upper, cut); id = parent
        }
        var result: [DurableEntryRecord] = []
        for (id, upper) in segments.reversed() {
            result.append(contentsOf: snapshot.entries.values.filter { $0.conversationID == id && $0.id <= upper }.sorted { $0.id < $1.id })
        }
        if let at, !result.contains(where: { $0.id == at }) { throw DurableError.invalidRecord("entry is not visible from conversation") }
        return result
    }

    public static func derive(snapshot: DurableSnapshot, conversationID: Int64, at: Int64? = nil) throws -> DurableContextView {
        let visible = try visibleEntries(snapshot: snapshot, conversationID: conversationID, at: at)
        let head = visible.last { $0.head != nil }
        let range = visible.filter { $0.id >= (head?.head ?? 0) }
        var edits: [Int64: DurableContextEdit] = [:]
        for entry in range { for edit in entry.edits ?? [] { edits[edit.target] = edit } }
        let active = head.map { marker in [marker] + range.filter { $0.head == nil } } ?? range
        let contributions: [[Message]] = active.map { entry in
            let edit = edits[entry.id]
            if edit?.action == .omit { return [] }
            let messages = edit?.action == .replace ? (edit?.messages ?? []) : (entry.messages ?? [])
            return messages.filter { $0.role != .assistant || ![StopReason.error, .aborted, .deferred].contains($0.stopReason ?? .stop) }
        }
        return DurableContextView(head: head, entries: active, contributions: contributions, messages: orderToolResults(contributions.flatMap { $0 }))
    }

    /// First matching result wins; missing calls receive an explicit error result.
    public static func orderToolResults(_ messages: [Message]) -> [Message] {
        var ordered: [Message] = []
        for (index, message) in messages.enumerated() {
            if message.role == .toolResult { continue }
            ordered.append(message)
            guard message.role == .assistant else { continue }
            let calls = message.content.filter { $0.type == "toolCall" }
            guard !calls.isEmpty else { continue }
            var results: [String: Message] = [:]
            for candidate in messages.dropFirst(index + 1) {
                if candidate.role == .assistant { break }
                if candidate.role == .toolResult, let id = candidate.toolCallId, results[id] == nil { results[id] = candidate }
            }
            for call in calls {
                if let result = results[call.id ?? ""] { ordered.append(result) }
                else {
                    var missing = Message(role: .toolResult, content: [.text("Tool result unavailable: history ends before this call completed.")], timestamp: message.timestamp)
                    missing.toolCallId = call.id; missing.toolName = call.name; missing.isError = true; missing.details = .object(["reason": .string("missing_result")])
                    ordered.append(missing)
                }
            }
        }
        return ordered
    }
}
