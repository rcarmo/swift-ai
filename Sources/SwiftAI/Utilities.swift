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
}
