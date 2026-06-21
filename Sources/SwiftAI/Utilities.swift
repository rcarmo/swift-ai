import Foundation

public enum AIUtilities {
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

    public static func supportedThinkingLevels(model: Model?) -> [ModelThinkingLevel] {
        guard let model, let map = model.thinkingLevelMap else { return [] }
        return map.keys.sorted { $0.rawValue < $1.rawValue }
    }

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
