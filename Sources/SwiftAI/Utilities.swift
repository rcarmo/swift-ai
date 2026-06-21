import Foundation

public enum AIUtilities {
    private static let extendedThinkingLevels: [ModelThinkingLevel] = [.off, .minimal, .low, .medium, .high, .xhigh]

    public static func clampReasoning(_ level: ThinkingLevel) -> ThinkingLevel { level == .xhigh ? .high : level }

    public static func supportedThinkingLevels(model: Model?) -> [ModelThinkingLevel] {
        guard let model, model.reasoning else { return [.off] }
        var out: [ModelThinkingLevel] = []
        for level in extendedThinkingLevels {
            if let map = model.thinkingLevelMap, let maybe = map[level], maybe == nil { continue }
            if level == .xhigh && model.thinkingLevelMap?[level] == nil { continue }
            out.append(level)
        }
        return out.isEmpty ? [.off] : out
    }

    public static func clampThinkingLevel(model: Model?, level: ModelThinkingLevel) -> ModelThinkingLevel {
        let available = supportedThinkingLevels(model: model)
        if available.contains(level) { return level }
        guard let idx = extendedThinkingLevels.firstIndex(of: level) else { return available.first ?? .off }
        for candidate in extendedThinkingLevels[idx...] where available.contains(candidate) { return candidate }
        if idx > 0 { for candidate in extendedThinkingLevels[..<idx].reversed() where available.contains(candidate) { return candidate } }
        return available.first ?? .off
    }

    public static func mapThinkingLevel(model: Model?, level: ModelThinkingLevel) -> String? {
        let clamped = clampThinkingLevel(model: model, level: level)
        if let map = model?.thinkingLevelMap, let maybe = map[clamped] { return maybe }
        return clamped == .off ? "none" : clamped.rawValue
    }

    public static func defaultThinkingBudgets() -> ThinkingBudgets { ThinkingBudgets(minimal: 1024, low: 2048, medium: 8192, high: 16_384) }

    public static func adjustMaxTokensForThinking(baseMaxTokens: Int, modelMaxTokens: Int, level: ThinkingLevel, custom: ThinkingBudgets? = nil) -> (maxTokens: Int, thinkingBudget: Int) {
        let defaults = defaultThinkingBudgets()
        let level = clampReasoning(level)
        let budget: Int
        switch level {
        case .minimal: budget = custom?.minimal ?? defaults.minimal ?? 1024
        case .low: budget = custom?.low ?? defaults.low ?? 2048
        case .medium: budget = custom?.medium ?? defaults.medium ?? 8192
        case .high, .xhigh: budget = custom?.high ?? defaults.high ?? 16_384
        }
        let minOutputTokens = 1024
        var maxTokens = baseMaxTokens + budget
        if modelMaxTokens > 0, maxTokens > modelMaxTokens { maxTokens = modelMaxTokens }
        if maxTokens < 0 { maxTokens = 0 }
        var thinkingBudget = budget
        if maxTokens <= thinkingBudget { thinkingBudget = max(0, maxTokens - minOutputTokens) }
        return (maxTokens, thinkingBudget)
    }

    public static func calculateCost(model: Model?, usage: Usage?) -> CostBreakdown {
        guard let model, let usage else { return CostBreakdown() }
        let million = 1_000_000.0
        let longWrite = min(max(usage.cacheWrite1h ?? 0, 0), usage.cacheWrite)
        let shortWrite = usage.cacheWrite - longWrite
        var cost = CostBreakdown()
        cost.input = Double(usage.input) * model.cost.input / million
        cost.output = Double(usage.output) * model.cost.output / million
        cost.cacheRead = Double(usage.cacheRead) * model.cost.cacheRead / million
        cost.cacheWrite = (Double(shortWrite) * model.cost.cacheWrite + Double(longWrite) * model.cost.input * 2.0) / million
        cost.total = cost.input + cost.output + cost.cacheRead + cost.cacheWrite
        return cost
    }

    public static func applyCost(model: Model, usage: inout Usage) { usage.cost = calculateCost(model: model, usage: usage) }

    public static func supportsXHigh(model: Model?) -> Bool { supportedThinkingLevels(model: model).contains(.xhigh) }
    public static func modelsAreEqual(_ a: Model?, _ b: Model?) -> Bool { guard let a, let b else { return false }; return a.id == b.id && a.provider == b.provider }

    public static func transformMessages(_ messages: [Message], for model: Model?) -> [Message] {
        guard let model else { return messages }
        let downgraded = downgradeUnsupportedImages(messages, for: model)
        var transformed: [Message] = []
        for msg in downgraded {
            switch msg.role {
            case .user, .toolResult:
                transformed.append(msg)
            case .assistant:
                if msg.stopReason == .error || msg.stopReason == .aborted { continue }
                let sameModel = msg.provider == model.provider && msg.api == model.api && msg.model == model.id
                var copy = msg
                copy.content = msg.content.compactMap { block in
                    switch block.type {
                    case "thinking":
                        if block.redacted == true { return sameModel ? block : nil }
                        if sameModel && !(block.thinkingSignature ?? "").isEmpty { return block }
                        guard !(block.thinking ?? "").isEmpty else { return nil }
                        return sameModel ? block : ContentBlock.text(block.thinking ?? "")
                    case "text":
                        return sameModel ? block : ContentBlock.text(block.text ?? "")
                    case "toolCall":
                        var tc = block
                        if !sameModel { tc.thoughtSignature = nil }
                        return tc
                    default:
                        return block
                    }
                }
                transformed.append(copy)
            }
        }
        return insertSyntheticToolResults(transformed)
    }

    public static func downgradeUnsupportedImages(_ messages: [Message], for model: Model) -> [Message] {
        guard !model.input.contains("image") else { return messages }
        return messages.map { message in
            guard message.role == .user || message.role == .toolResult else { return message }
            var copy = message
            var previousPlaceholder = false
            copy.content = message.content.compactMap { block in
                if block.type == "image" {
                    defer { previousPlaceholder = true }
                    guard !previousPlaceholder else { return nil }
                    let text = message.role == .toolResult ? "(tool image omitted: model does not support images)" : "(image omitted: model does not support images)"
                    return ContentBlock.text(text)
                }
                previousPlaceholder = false
                return block
            }
            return copy
        }
    }

    public static func insertSyntheticToolResults(_ messages: [Message]) -> [Message] {
        var result: [Message] = []
        var pending: [ContentBlock] = []
        var existing: Set<String> = []
        func flush() {
            for tc in pending where !existing.contains(tc.id ?? "") {
                var msg = Message(role: .toolResult, content: [.text("No result provided")])
                msg.toolCallId = tc.id
                msg.toolName = tc.name
                msg.isError = true
                result.append(msg)
            }
            pending.removeAll()
            existing.removeAll()
        }
        for msg in messages {
            switch msg.role {
            case .assistant:
                flush()
                pending.append(contentsOf: msg.content.filter { $0.type == "toolCall" })
                result.append(msg)
            case .toolResult:
                if let id = msg.toolCallId { existing.insert(id) }
                result.append(msg)
            case .user:
                flush()
                result.append(msg)
            }
        }
        flush()
        return result
    }
}
