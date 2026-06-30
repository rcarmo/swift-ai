import Foundation
import Crypto

public struct ContextTokenEstimate: Codable, Equatable, Sendable { public var tokens: Int; public var usageTokens: Int; public var trailingTokens: Int; public var lastUsageIndex: Int?; public init(tokens: Int, usageTokens: Int, trailingTokens: Int, lastUsageIndex: Int?) { self.tokens = tokens; self.usageTokens = usageTokens; self.trailingTokens = trailingTokens; self.lastUsageIndex = lastUsageIndex } }

public struct NormalizedProviderError: Equatable, Sendable { public var status: Int?; public var body: String?; public var message: String; public var messageCarriesBody: Bool; public init(status: Int? = nil, body: String? = nil, message: String, messageCarriesBody: Bool = false) { self.status = status; self.body = body; self.message = message; self.messageCarriesBody = messageCarriesBody } }

public enum AIUtilities {
    public static let charsPerToken = 4
    public static let estimatedImageChars = 4800
    public static let contextSafetyTokens = 4096
    public static let minMaxTokens = 1
    public static let maxProviderErrorBodyChars = 4000
    private static let extendedThinkingLevels: [ModelThinkingLevel] = [.off, .minimal, .low, .medium, .high, .xhigh]

    public static func clampReasoning(_ level: ThinkingLevel) -> ThinkingLevel { level == .xhigh ? .high : level }

    public static func supportedThinkingLevels(model: Model?) -> [ModelThinkingLevel] {
        guard let model, model.reasoning else { return [.off] }
        var out: [ModelThinkingLevel] = []
        for level in extendedThinkingLevels {
            if let map = model.thinkingLevelMap {
                guard map.keys.contains(level), let mapped = map[level], mapped != nil else { continue }
            } else if level == .xhigh {
                continue
            }
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

    public static func calculateContextTokens(_ usage: Usage) -> Int { usage.totalTokens != 0 ? usage.totalTokens : usage.input + usage.output + usage.cacheRead + usage.cacheWrite }

    public static func estimateTextTokens(_ text: String) -> Int { Int(ceil(Double(text.count) / Double(charsPerToken))) }

    public static func estimateTextAndImageContentTokens(_ content: [ContentBlock]) -> Int {
        var chars = 0
        for block in content { chars += block.type == "text" ? (block.text ?? "").count : estimatedImageChars }
        return Int(ceil(Double(chars) / Double(charsPerToken)))
    }

    public static func estimateMessageTokens(_ message: Message) -> Int {
        if message.role == .user || message.role == .toolResult { return estimateTextAndImageContentTokens(message.content) }
        var chars = 0
        for block in message.content {
            switch block.type {
            case "text": chars += (block.text ?? "").count
            case "thinking": chars += (block.thinking ?? "").count
            default: chars += (block.name ?? "").count + safeJsonStringify(block.arguments ?? [:]).count
            }
        }
        return Int(ceil(Double(chars) / Double(charsPerToken)))
    }

    public static func estimateContextTokens(_ context: AIContext) -> ContextTokenEstimate {
        var usageInfo: (usage: Usage, index: Int)?
        for index in context.messages.indices.reversed() {
            let message = context.messages[index]
            guard message.role == .assistant, message.stopReason != .aborted, message.stopReason != .error, let usage = message.usage, calculateContextTokens(usage) > 0 else { continue }
            usageInfo = (usage, index)
            break
        }
        if let usageInfo {
            let usageTokens = calculateContextTokens(usageInfo.usage)
            let trailing = context.messages.dropFirst(usageInfo.index + 1).reduce(0) { $0 + estimateMessageTokens($1) }
            return ContextTokenEstimate(tokens: usageTokens + trailing, usageTokens: usageTokens, trailingTokens: trailing, lastUsageIndex: usageInfo.index)
        }
        let messageTokens = context.messages.reduce(0) { $0 + estimateMessageTokens($1) }
        var prefixTokens = context.systemPrompt.map(estimateTextTokens) ?? 0
        if let tools = context.tools, !tools.isEmpty { prefixTokens += estimateTextTokens(safeJsonStringify(tools)) }
        return ContextTokenEstimate(tokens: messageTokens + prefixTokens, usageTokens: 0, trailingTokens: messageTokens + prefixTokens, lastUsageIndex: nil)
    }

    public static func clampMaxTokensToContext(model: Model, context: AIContext, maxTokens: Int) -> Int {
        if model.contextWindow <= 0 { return max(minMaxTokens, maxTokens) }
        let available = model.contextWindow - estimateContextTokens(context).tokens - contextSafetyTokens
        return min(maxTokens, max(minMaxTokens, available))
    }

    public static func effectiveMaxTokens(model: Model, context: AIContext, options: StreamOptions?, defaultToModel: Bool) -> Int? {
        guard let requested = options?.maxTokens ?? (defaultToModel ? model.maxTokens : nil) else { return nil }
        return clampMaxTokensToContext(model: model, context: context, maxTokens: requested)
    }

    public static func normalizeProviderError(_ error: Any) -> NormalizedProviderError {
        if let error = error as? Error {
            let message = String(describing: error)
            return NormalizedProviderError(status: nil, body: nil, message: message, messageCarriesBody: false)
        }
        if let object = error as? [String: Any] {
            let status = firstInt(object, keys: ["statusCode", "status"])
                ?? ((object["$metadata"] as? [String: Any]).flatMap { firstInt($0, keys: ["httpStatusCode"]) })
                ?? ((object["$response"] as? [String: Any]).flatMap { firstInt($0, keys: ["statusCode"]) })
            let body = extractProviderErrorBody(object)
            let message = object["message"].map { String(describing: $0) } ?? safeJsonStringify(error)
            return NormalizedProviderError(status: status, body: body, message: message, messageCarriesBody: body.map { message.contains($0) } ?? true)
        }
        return NormalizedProviderError(message: safeJsonStringify(error), messageCarriesBody: false)
    }

    public static func formatProviderError(_ normalized: NormalizedProviderError, prefix: String? = nil) -> String {
        guard let status = normalized.status else { return normalized.message }
        if let body = normalized.body { return formatProviderError(status: status, body: body, prefix: prefix) }
        if normalized.messageCarriesBody, !normalized.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let prefix { return "\(prefix) (\(status)): \(normalized.message)" }
            return "\(status): \(normalized.message)"
        }
        if let prefix { return "\(prefix) (\(status))" }
        return "\(status)"
    }

    public static func formatProviderError(status: Int, body: String?, prefix: String? = nil) -> String {
        let trimmed = (body ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let head = prefix.map { "\($0) (\(status))" } ?? "\(status)"
        guard !trimmed.isEmpty else { return head }
        return "\(head): \(truncateErrorText(trimmed, maxChars: maxProviderErrorBodyChars))"
    }

    public static func truncateErrorText(_ text: String, maxChars: Int = maxProviderErrorBodyChars) -> String {
        text.count <= maxChars ? text : String(text.prefix(maxChars)) + "... [truncated \(text.count - maxChars) chars]"
    }

    public static func safeJsonStringify(_ value: Any) -> String {
        if let value = value as? JSONValue, let data = try? JSONEncoder().encode(value), let text = String(data: data, encoding: .utf8) { return text }
        if let encodable = value as? [Tool], let data = try? JSONEncoder().encode(encodable), let text = String(data: data, encoding: .utf8) { return text }
        if JSONSerialization.isValidJSONObject(value), let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), let text = String(data: data, encoding: .utf8) { return text }
        return String(describing: value)
    }

    private static func firstInt(_ object: [String: Any], keys: [String]) -> Int? { for key in keys { if let value = object[key] as? Int { return value } }; return nil }
    private static func extractProviderErrorBody(_ object: [String: Any]) -> String? {
        let body: Any?
        if let text = object["body"] as? String { body = text }
        else if let error = object["error"] as? [String: Any], !error.isEmpty { body = error }
        else if let response = object["$response"] as? [String: Any], let responseBody = response["body"] { body = responseBody }
        else { body = nil }
        guard let body else { return nil }
        let text = (body as? String) ?? safeJsonStringify(body)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == "{}" ? nil : truncateErrorText(trimmed, maxChars: maxProviderErrorBodyChars)
    }

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
        return calculateCost(cost: model.cost, usage: usage)
    }

    public static func calculateCost(imageModel: ImagesModel?, usage: Usage?) -> CostBreakdown {
        guard let imageModel, let usage else { return CostBreakdown() }
        return calculateCost(cost: imageModel.cost, usage: usage)
    }

    public static func calculateCost(cost modelCost: ModelCost, usage: Usage) -> CostBreakdown {
        let million = 1_000_000.0
        let longWrite = min(max(usage.cacheWrite1h ?? 0, 0), usage.cacheWrite)
        let shortWrite = usage.cacheWrite - longWrite
        var cost = CostBreakdown()
        cost.input = Double(usage.input) * modelCost.input / million
        cost.output = Double(usage.output) * modelCost.output / million
        cost.cacheRead = Double(usage.cacheRead) * modelCost.cacheRead / million
        cost.cacheWrite = (Double(shortWrite) * modelCost.cacheWrite + Double(longWrite) * modelCost.input * 2.0) / million
        cost.total = cost.input + cost.output + cost.cacheRead + cost.cacheWrite
        return cost
    }

    public static func applyCost(model: Model, usage: inout Usage) { usage.cost = calculateCost(model: model, usage: usage) }
    public static func applyCost(imageModel: ImagesModel, usage: inout Usage) { usage.cost = calculateCost(imageModel: imageModel, usage: usage) }

    public static func supportsXHigh(model: Model?) -> Bool { supportedThinkingLevels(model: model).contains(.xhigh) }
    public static func modelsAreEqual(_ a: Model?, _ b: Model?) -> Bool { guard let a, let b else { return false }; return a.id == b.id && a.provider == b.provider }

    public static func shortHash(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    public static func sanitizeSurrogates(_ text: String) -> String {
        String(text.unicodeScalars.filter { scalar in
            scalar.value != 0xFFFD && !(scalar.value >= 0xD800 && scalar.value <= 0xDFFF)
        })
    }

    public static func inferCopilotInitiator(_ messages: [Message]) -> String { messages.last?.role == .user || messages.isEmpty ? "user" : "agent" }

    public static func hasCopilotVisionInput(_ messages: [Message]) -> Bool {
        messages.contains { ($0.role == .user || $0.role == .toolResult) && $0.content.contains { $0.type == "image" } }
    }

    public static func buildCopilotDynamicHeaders(_ messages: [Message]) -> [String: String] {
        var headers = ["X-Initiator": inferCopilotInitiator(messages), "Openai-Intent": "conversation-edits"]
        if hasCopilotVisionInput(messages) { headers["Copilot-Vision-Request"] = "true" }
        return headers
    }

    public static func copilotHeaders(intent: String? = nil) -> [String: String] {
        var headers = ["User-Agent": "GitHubCopilotChat/0.35.0", "Editor-Version": "vscode/1.107.0", "Editor-Plugin-Version": "copilot-chat/0.35.0", "Copilot-Integration-Id": "vscode-chat"]
        if let intent, !intent.isEmpty { headers["openai-intent"] = intent }
        return headers
    }

    public static func azureSessionHeaders(_ sessionId: String) -> [String: String] { sessionId.isEmpty ? [:] : ["session_id": sessionId, "x-client-request-id": sessionId, "x-ms-client-request-id": sessionId] }

    public static func hasHeader(_ headers: [String: String]?, _ name: String) -> Bool {
        guard let headers else { return false }
        return headers.contains { $0.key.lowercased() == name.lowercased() && !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    public static func hasOpenAIAuthHeader(_ headers: [String: String]?) -> Bool { hasHeader(headers, "authorization") || hasHeader(headers, "cf-aig-authorization") }
    public static func hasAnthropicAuthHeader(_ headers: [String: String]?) -> Bool { hasHeader(headers, "x-api-key") || hasHeader(headers, "authorization") }

    public static func mergeHeaders(defaults: [String: String], provider: [String: String]?, explicit: [String: String]?) -> [String: String] {
        var result = defaults
        for (k, v) in provider ?? [:] { result[k] = v }
        for (k, v) in explicit ?? [:] { result[k] = v }
        return result
    }

    public static func isCloudflareProvider(_ provider: Provider) -> Bool { provider == .cloudflareWorkersAI || provider == .cloudflareAIGateway }

    public static func resolveCloudflareBaseURL(model: Model, env: ProviderEnv? = nil) -> String {
        var result = model.baseUrl
        while let start = result.firstIndex(of: "{"), let end = result[start...].firstIndex(of: "}") {
            let name = String(result[result.index(after: start)..<end])
            let value = ProviderEnvironment.value(name, env: env) ?? ""
            result.replaceSubrange(start...end, with: value)
        }
        return result
    }

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
        func normalized(_ id: String) -> String { String(id.map { ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") ? $0 : "_" }.prefix(64)) }
        func flush() {
            for tc in pending where !existing.contains(normalized(tc.id ?? "")) {
                var msg = Message(role: .toolResult, content: [.text("No result provided")])
                msg.toolCallId = normalized(tc.id ?? "")
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
                if let id = msg.toolCallId { existing.insert(normalized(id)) }
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
