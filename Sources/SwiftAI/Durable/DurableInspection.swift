import Foundation

public struct DurablePage<Element: Sendable>: Sendable {
    public var values: [Element]
    public var nextOffset: Int?
    public init(values: [Element], nextOffset: Int? = nil) { self.values = values; self.nextOffset = nextOffset }
}

public struct DurableInspection: Sendable {
    public var snapshot: DurableSnapshot
    public init(snapshot: DurableSnapshot) { self.snapshot = snapshot }

    public func conversations(offset: Int = 0, limit: Int = DurableLimits.maxPageLimit) throws -> DurablePage<DurableConversationRecord> {
        try page(snapshot.conversations.values.sorted { $0.id < $1.id }, offset: offset, limit: limit)
    }

    public func entries(conversationID: Int64? = nil, offset: Int = 0, limit: Int = DurableLimits.maxPageLimit) throws -> DurablePage<DurableEntryRecord> {
        let values = snapshot.entries.values.filter { conversationID == nil || $0.conversationID == conversationID! }.sorted { $0.id < $1.id }
        return try page(values, offset: offset, limit: limit)
    }

    public func tasks(conversationID: Int64? = nil, offset: Int = 0, limit: Int = DurableLimits.maxPageLimit) throws -> DurablePage<DurableTaskRecord> {
        let values = snapshot.tasks.values.filter { conversationID == nil || $0.conversationID == conversationID! }.sorted { $0.id < $1.id }
        return try page(values, offset: offset, limit: limit)
    }

    public func submissions(conversationID: Int64? = nil, offset: Int = 0, limit: Int = DurableLimits.maxPageLimit) throws -> DurablePage<DurableSubmissionRecord> {
        let values = snapshot.submissions.values.filter { conversationID == nil || $0.conversationID == conversationID! }.sorted { $0.id < $1.id }
        return try page(values, offset: offset, limit: limit)
    }

    public func documents(scope: String? = nil, ownerID: Int64? = nil, offset: Int = 0, limit: Int = DurableLimits.maxPageLimit) throws -> DurablePage<DurableDocumentRecord> {
        let values = snapshot.documents.values.filter { record in
            (scope == nil || record.scope == scope!) && (ownerID == nil || record.ownerID == ownerID!)
        }.sorted { $0.id < $1.id }
        return try page(values, offset: offset, limit: limit)
    }

    private func page<Element>(_ values: [Element], offset: Int, limit: Int) throws -> DurablePage<Element> {
        guard offset >= 0 else { throw DurableError.invalidRecord("negative page offset") }
        guard limit >= 0, limit <= DurableLimits.maxPageLimit else { throw DurableError.invalidRecord("page limit exceeds \(DurableLimits.maxPageLimit)") }
        guard offset <= values.count else { return DurablePage(values: [], nextOffset: nil) }
        let end = min(values.count, offset + limit)
        let next = end < values.count ? end : nil
        return DurablePage(values: Array(values[offset..<end]), nextOffset: next)
    }
}
