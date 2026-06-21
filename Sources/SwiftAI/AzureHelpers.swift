import Foundation

public struct ToolCallLimitConfig: Equatable, Sendable {
    public var limit: Int
    public var summaryMax: Int
    public var outputChars: Int
    public var maxEstimatedTokens: Int
    public init(limit: Int = 128, summaryMax: Int = 8000, outputChars: Int = 200, maxEstimatedTokens: Int = 0) { self.limit = limit; self.summaryMax = summaryMax; self.outputChars = outputChars; self.maxEstimatedTokens = maxEstimatedTokens }
    public static let `default` = ToolCallLimitConfig()
}

public struct ToolCallLimitResult: Equatable, Sendable {
    public var messages: [JSONValue]
    public var toolCallTotal = 0
    public var toolCallKept = 0
    public var toolCallRemoved = 0
    public var toolCallDeduped = 0
    public var toolCallBudgetRemoved = 0
    public var summaryText = ""
    public var estimatedTokensBefore = 0
    public var estimatedTokensAfter = 0
}

public enum AzureHelpers {
    public static func applyToolCallLimit(_ messages: [JSONValue], config original: ToolCallLimitConfig = .default) -> ToolCallLimitResult {
        var config = original
        if config.limit <= 0 { config.limit = 128 }
        if config.summaryMax <= 0 { config.summaryMax = 8000 }
        if config.outputChars <= 0 { config.outputChars = 200 }
        var result = ToolCallLimitResult(messages: messages)
        result.estimatedTokensBefore = estimateInputTokens(messages)

        struct Entry { var callIndex: Int; var outputIndex: Int; var name: String; var output: String }
        var entries: [Entry] = []
        for (idx, message) in messages.enumerated() {
            guard case .object(let object) = message, case .string(let type)? = object["type"] else { continue }
            if type == "function_call" { entries.append(Entry(callIndex: idx, outputIndex: -1, name: object["name"]?.stringValue ?? "", output: "")) }
            if type == "function_call_output" {
                for i in entries.indices.reversed() where entries[i].outputIndex == -1 { entries[i].outputIndex = idx; entries[i].output = object["output"]?.stringValue ?? ""; break }
            }
        }
        result.toolCallTotal = entries.count
        if entries.count <= config.limit && (config.maxEstimatedTokens <= 0 || result.estimatedTokensBefore <= config.maxEstimatedTokens) {
            result.toolCallKept = entries.count
            result.estimatedTokensAfter = result.estimatedTokensBefore
            return result
        }

        var removeCount = max(0, entries.count - config.limit)
        var toRemove = Set<Int>()
        var summaryParts: [String] = []
        var budgetRemoved = 0
        func mark(_ entry: Entry) {
            toRemove.insert(entry.callIndex)
            if entry.outputIndex >= 0 { toRemove.insert(entry.outputIndex) }
            let snippet = truncate(entry.output, max: config.outputChars)
            summaryParts.append("- \(entry.name) → \(snippet.isEmpty ? "(no output)" : snippet)")
        }
        for i in 0..<min(removeCount, entries.count) { mark(entries[i]) }
        while config.maxEstimatedTokens > 0 && estimateInputTokens(removeIndexes(messages, toRemove: toRemove)) > config.maxEstimatedTokens {
            let next = removeCount + budgetRemoved
            if next >= entries.count { break }
            mark(entries[next])
            budgetRemoved += 1
        }
        var trimmed: [JSONValue] = []
        var insertedSummary = false
        for (idx, message) in messages.enumerated() {
            if toRemove.contains(idx) {
                if !insertedSummary {
                    var summary = summaryParts.joined(separator: "\n")
                    if summary.count > config.summaryMax { summary = String(summary.prefix(config.summaryMax)) + "\n..." }
                    result.summaryText = summary
                    trimmed.append(.object(["type": .string("message"), "role": .string("assistant"), "content": .array([.object(["type": .string("output_text"), "text": .string("Earlier tool calls (summarized):\n" + summary)])]), "status": .string("completed")]))
                    insertedSummary = true
                }
                continue
            }
            trimmed.append(message)
        }
        result.messages = trimmed
        result.toolCallRemoved = removeCount + budgetRemoved
        result.toolCallBudgetRemoved = budgetRemoved
        result.toolCallKept = max(0, entries.count - result.toolCallRemoved)
        result.estimatedTokensAfter = estimateInputTokens(trimmed)
        return result
    }

    public static func estimateInputTokens(_ messages: [JSONValue]) -> Int { ((try? JSONEncoder().encode(messages).count) ?? 0) / 4 }
    private static func removeIndexes(_ messages: [JSONValue], toRemove: Set<Int>) -> [JSONValue] { messages.enumerated().compactMap { toRemove.contains($0.offset) ? nil : $0.element } }
    private static func truncate(_ value: String, max: Int) -> String { let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines); return trimmed.count <= max ? trimmed : String(trimmed.prefix(max - 1)) + "…" }
}
