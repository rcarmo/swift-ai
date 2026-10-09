import Foundation

public enum DurableScanOrder: String, Codable, Sendable { case ascending, descending }

/// The order travels with the cursor so later pages cannot silently reverse direction.
public struct DurableScanCursor: Codable, Equatable, Sendable {
    public var after: Int64
    public var order: DurableScanOrder?
    public init(after: Int64, order: DurableScanOrder? = nil) { self.after = after; self.order = order }
}

public struct DurableScanPage<Value: Sendable>: Sendable {
    public var values: [Value]
    public var next: DurableScanCursor?
    public init(values: [Value], next: DurableScanCursor?) { self.values = values; self.next = next }
}

public extension DurableInspection {
    func scanConversations(order: DurableScanOrder? = nil, cursor: DurableScanCursor? = nil, limit: Int = DurableLimits.maxPageLimit) throws -> DurableScanPage<DurableConversationRecord> {
        try scan(Array(snapshot.conversations.values), fallback: .ascending, order: order, cursor: cursor, limit: limit, id: { $0.id })
    }

    func scanEntries(conversationID: Int64? = nil, minEntryID: Int64? = nil, maxEntryID: Int64? = nil, order: DurableScanOrder? = nil, cursor: DurableScanCursor? = nil, limit: Int = DurableLimits.maxPageLimit) throws -> DurableScanPage<DurableEntryRecord> {
        let visible = try conversationID.map { try DurableContext.visibleEntries(snapshot: snapshot, conversationID: $0) } ?? Array(snapshot.entries.values)
        let values = visible.filter {
            (minEntryID == nil || $0.id >= minEntryID!) && (maxEntryID == nil || $0.id <= maxEntryID!)
        }
        return try scan(Array(values), fallback: .descending, order: order, cursor: cursor, limit: limit, id: { $0.id })
    }

    func scanTasks(conversationID: Int64? = nil, order: DurableScanOrder? = nil, cursor: DurableScanCursor? = nil, limit: Int = DurableLimits.maxPageLimit) throws -> DurableScanPage<DurableTaskRecord> {
        try scan(snapshot.tasks.values.filter { conversationID == nil || $0.conversationID == conversationID }, fallback: .ascending, order: order, cursor: cursor, limit: limit, id: { $0.id })
    }

    func scanSubmissions(conversationID: Int64? = nil, order: DurableScanOrder? = nil, cursor: DurableScanCursor? = nil, limit: Int = DurableLimits.maxPageLimit) throws -> DurableScanPage<DurableSubmissionRecord> {
        try scan(snapshot.submissions.values.filter { conversationID == nil || $0.conversationID == conversationID }, fallback: .ascending, order: order, cursor: cursor, limit: limit, id: { $0.id })
    }

    private func scan<T: Sendable>(_ values: [T], fallback: DurableScanOrder, order requested: DurableScanOrder?, cursor: DurableScanCursor?, limit: Int, id: (T) -> Int64) throws -> DurableScanPage<T> {
        guard limit > 0, limit <= DurableLimits.maxPageLimit else { throw DurableError.invalidRecord("invalid scan limit") }
        if let cursor { guard cursor.after >= 0, cursor.after <= 9_007_199_254_740_991 else { throw DurableError.invalidRecord("invalid scan cursor") } }
        let order = cursor.map { $0.order ?? fallback } ?? requested ?? fallback
        if cursor != nil, let requested, requested != order { throw DurableError.invalidRecord("scan cursor order does not match query order") }
        let sorted = values.filter { value in
            guard let cursor else { return true }
            return order == .ascending ? id(value) > cursor.after : id(value) < cursor.after
        }.sorted { order == .ascending ? id($0) < id($1) : id($0) > id($1) }
        let items = Array(sorted.prefix(limit))
        let next = sorted.count > limit ? items.last.map { DurableScanCursor(after: id($0), order: order) } : nil
        return DurableScanPage(values: items, next: next)
    }
}
