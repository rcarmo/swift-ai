import Foundation

public enum DurableSubmissionOutcome: Sendable, Equatable {
    case placed(DurableSubmissionRecord)
    case duplicate(DurableSubmissionRecord)
}

struct DurableSubmissionPlanner {
    static func existing(conversationID: Int64, requestID: String, in snapshot: DurableSnapshot) -> DurableSubmissionRecord? {
        snapshot.submissions.values.first { $0.conversationID == conversationID && $0.requestID == requestID }
    }

    static func nextID(from snapshot: DurableSnapshot, reserving count: Int = 1) throws -> [Int64] {
        guard count >= 0 else { throw DurableError.invalidRecord("negative allocation count") }
        guard snapshot.highWaterID + Int64(count) <= DurableLimits.maxExactInteger else { throw DurableError.invalidRecord("id allocation overflow") }
        return count == 0 ? [] : (1...count).map { snapshot.highWaterID + Int64($0) }
    }
}

enum DurableNativePreflight {
    private struct Budget {
        var bytes = 0
        var nodes = 0
        let maxBytes: Int
        mutating func add(_ amount: Int) throws {
            let (next, overflow) = bytes.addingReportingOverflow(amount)
            guard !overflow, next <= maxBytes else { throw DurableError.invalidRecord("durable native DTO exceeds \(maxBytes) bytes") }
            bytes = next
        }
        mutating func node() throws {
            nodes += 1
            guard nodes <= DurableLimits.maxJSONNodes else { throw DurableError.invalidRecord("durable native DTO exceeds node limit") }
        }
    }

    static func validate<T: Encodable>(_ value: T, maxBytes: Int) throws {
        var budget = Budget(maxBytes: maxBytes)
        try walkAny(value, depth: 0, budget: &budget)
    }

    private static func walkAny(_ value: Any, depth: Int, budget: inout Budget) throws {
        guard depth <= DurableLimits.maxJSONDepth else { throw DurableError.invalidRecord("durable native DTO exceeds depth limit") }
        try budget.node()
        if let string = value as? String { try budget.add(try escapedBytes(string)); return }
        if let json = value as? JSONValue { try countJSONNodes(json, depth: depth, budget: &budget); try budget.add(try DurableValidation.measureJSON(json, label: "durable native DTO", error: DurableError.invalidRecord)); return }
        if let double = value as? Double { guard double.isFinite else { throw DurableError.invalidRecord("durable native DTO contains non-finite number") }; try budget.add(64); return }
        if let value = value as? API { try budget.add(try escapedBytes(value.rawValue)); return }
        if let value = value as? Provider { try budget.add(try escapedBytes(value.rawValue)); return }
        if let value = value as? Role { try budget.add(try escapedBytes(value.rawValue)); return }
        if let value = value as? StopReason { try budget.add(try escapedBytes(value.rawValue)); return }
        if let value = value as? CacheRetention { try budget.add(try escapedBytes(value.rawValue)); return }
        if let value = value as? Transport { try budget.add(try escapedBytes(value.rawValue)); return }
        if let value = value as? ThinkingLevel { try budget.add(try escapedBytes(value.rawValue)); return }
        if let value = value as? ModelThinkingLevel { try budget.add(try escapedBytes(value.rawValue)); return }
        if let value = value as? DurableTaskStatus { try budget.add(try escapedBytes(value.rawValue)); return }
        if let value = value as? DurableSubmissionType { try budget.add(try escapedBytes(value.rawValue)); return }
        if let value = value as? DurableSubmissionStatus { try budget.add(try escapedBytes(value.rawValue)); return }
        if value is Int || value is Int8 || value is Int16 || value is Int32 || value is Int64 || value is UInt || value is UInt8 || value is UInt16 || value is UInt32 || value is UInt64 || value is Bool { try budget.add(32); return }

        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle == .optional {
            if let child = mirror.children.first { try walkAny(child.value, depth: depth + 1, budget: &budget) }
            else { try budget.add(4) }
            return
        }
        try budget.add(2)
        if mirror.children.isEmpty {
            // Unknown leaf values are conservatively budgeted rather than treated as zero-byte enums.
            try budget.add(128)
            return
        }
        for child in mirror.children {
            if let label = child.label { try budget.add(max(try escapedBytes(label), 64) + 1) }
            try walkAny(child.value, depth: depth + 1, budget: &budget)
            try budget.add(1)
        }
    }

    private static func countJSONNodes(_ value: JSONValue, depth: Int, budget: inout Budget) throws {
        guard depth <= DurableLimits.maxJSONDepth else { throw DurableError.invalidRecord("durable native DTO exceeds depth limit") }
        try budget.node()
        switch value {
        case .array(let values): for child in values { try countJSONNodes(child, depth: depth + 1, budget: &budget) }
        case .object(let object): for (_, child) in object { try countJSONNodes(child, depth: depth + 1, budget: &budget) }
        default: break
        }
    }

    private static func escapedBytes(_ string: String) throws -> Int {
        try DurableValidation.escapedStringBytes(string, label: "durable native DTO", error: DurableError.invalidRecord)
    }
}
