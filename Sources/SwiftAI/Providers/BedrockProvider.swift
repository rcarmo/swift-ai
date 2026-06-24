import Foundation

public protocol BedrockTransport: Sendable {
    func stream(request: [String: JSONValue], model: Model, context: AIContext, options: StreamOptions?) -> AsyncStream<AIEvent>
}

public actor BedrockTransportRegistry {
    public static let shared = BedrockTransportRegistry()
    private var transport: (any BedrockTransport)?
    public func setTransport(_ transport: (any BedrockTransport)?) { self.transport = transport }
    public func current() -> (any BedrockTransport)? { transport }
}

public enum BedrockProvider {
    public static func stream(model: Model, context: AIContext, options: StreamOptions?) -> AsyncStream<AIEvent> {
        AsyncStream { continuation in
            Task {
                let request = buildConverseRequest(model: model, context: context, options: options)
                if let transport = await BedrockTransportRegistry.shared.current() {
                    for await event in transport.stream(request: request, model: model, context: context, options: options) { continuation.yield(event) }
                } else {
                    let message = Message(role: .assistant, content: [])
                    continuation.yield(.error(reason: .error, message: message, error: AIError.provider("Amazon Bedrock runtime requires a BedrockTransport implementation for AWS SigV4/event-stream transport")))
                }
                continuation.finish()
            }
        }
    }

    public static func configuredRegion(model: Model, options: StreamOptions?, env: ProviderEnv? = nil) -> String {
        if let arn = arnRegion(model.id), !arn.isEmpty { return arn }
        let scopedEnv = options?.env ?? env
        if let region = options?.region, !region.isEmpty { return region }
        if let region = ProviderEnvironment.value("AWS_REGION", env: scopedEnv), !region.isEmpty { return region }
        if let region = ProviderEnvironment.value("AWS_DEFAULT_REGION", env: scopedEnv), !region.isEmpty { return region }
        if let endpoint = standardEndpointRegion(model.baseUrl), !endpoint.isEmpty, shouldUseExplicitEndpoint(baseURL: model.baseUrl, configuredRegion: nil, hasAmbientConfiguredProfile: false) { return endpoint }
        return "us-east-1"
    }

    public static func shouldUseExplicitEndpoint(baseURL: String, configuredRegion: String?, hasAmbientConfiguredProfile: Bool) -> Bool {
        guard standardEndpointRegion(baseURL) != nil else { return true }
        return (configuredRegion ?? "").isEmpty && !hasAmbientConfiguredProfile
    }

    public static func arnRegion(_ modelId: String) -> String? {
        let parts = modelId.split(separator: ":")
        guard parts.count >= 4, parts[0] == "arn", parts[2].hasPrefix("bedrock") else { return nil }
        return String(parts[3])
    }

    public static func standardEndpointRegion(_ baseURL: String) -> String? {
        guard let host = URL(string: baseURL)?.host?.lowercased() else { return nil }
        let prefix = "bedrock-runtime."
        let fipsPrefix = "bedrock-runtime-fips."
        let rest: String
        if host.hasPrefix(prefix) { rest = String(host.dropFirst(prefix.count)) }
        else if host.hasPrefix(fipsPrefix) { rest = String(host.dropFirst(fipsPrefix.count)) }
        else { return nil }
        return rest.components(separatedBy: ".amazonaws.com").first?.components(separatedBy: ".amazonaws.com.cn").first
    }

    public static func mapStopReason(_ raw: String?) -> StopReason {
        switch raw { case "end_turn", "stop_sequence": return .stop; case "tool_use": return .toolUse; case "max_tokens": return .length; case "guardrail_intervened", "content_filtered", "error": return .error; default: return .stop }
    }

    public static func createImageBlock(data: String, mimeType: String) -> JSONValue {
        .object(["image": .object(["format": .string(mimeType.components(separatedBy: "/").last ?? "png"), "source": .object(["bytes": .string(data)])])])
    }

    public static func buildConverseRequest(model: Model, context: AIContext, options: StreamOptions?) -> [String: JSONValue] {
        var request: [String: JSONValue] = ["modelId": .string(model.id), "messages": .array(convertMessages(AIUtilities.transformMessages(context.messages, for: model)))]
        if let system = context.systemPrompt, !system.isEmpty { request["system"] = .array([.object(["text": .string(AIUtilities.sanitizeSurrogates(system))])]) }
        var inference: [String: JSONValue] = [:]
        if let max = options?.maxTokens { inference["maxTokens"] = .number(Double(max)) }
        if let temp = options?.temperature { inference["temperature"] = .number(temp) }
        if !inference.isEmpty { request["inferenceConfig"] = .object(inference) }
        if let tools = context.tools, !tools.isEmpty { request["toolConfig"] = .object(["tools": .array(tools.map(toolJSON))]) }
        if let fields = additionalModelRequestFields(model: model, options: options) { request["additionalModelRequestFields"] = .object(fields) }
        if let metadata = options?.requestMetadata, !metadata.isEmpty { request["requestMetadata"] = .object(metadata.mapValues { .string($0) }) }
        return request
    }

    private static func convertMessages(_ messages: [Message]) -> [JSONValue] {
        var out: [JSONValue] = []
        var pendingToolResults: [JSONValue] = []
        func flushToolResults() {
            guard !pendingToolResults.isEmpty else { return }
            out.append(.object(["role": .string("user"), "content": .array(pendingToolResults)]))
            pendingToolResults.removeAll()
        }
        for msg in messages {
            switch msg.role {
            case .user:
                flushToolResults()
                var content = msg.content.compactMap(contentBlock).filter { !isEmptyBedrockText($0) }
                if content.isEmpty { content = [.object(["text": .string("<empty>")])] }
                out.append(.object(["role": .string("user"), "content": .array(content)]))
            case .assistant:
                flushToolResults()
                let content = msg.content.compactMap(contentBlock).filter { !isEmptyBedrockText($0) }
                guard !content.isEmpty else { continue }
                out.append(.object(["role": .string("assistant"), "content": .array(content)]))
            case .toolResult:
                var text = AIUtilities.sanitizeSurrogates(msg.content.compactMap(\.text).joined(separator: "\n")).trimmingCharacters(in: .whitespacesAndNewlines)
                if text.isEmpty { text = "<empty>" }
                let result: [String: JSONValue] = [
                    "toolUseId": .string(msg.toolCallId ?? ""),
                    "content": .array([.object(["text": .string(text)])]),
                    "status": .string(msg.isError == true ? "error" : "success")
                ]
                pendingToolResults.append(.object(["toolResult": .object(result)]))
            }
        }
        flushToolResults()
        return out
    }

    private static func contentBlock(_ block: ContentBlock) -> JSONValue? {
        switch block.type {
        case "text": return .object(["text": .string(AIUtilities.sanitizeSurrogates(block.text ?? ""))])
        case "image": return createImageBlock(data: block.data ?? "", mimeType: block.mimeType ?? "image/png")
        case "toolCall": return .object(["toolUse": .object(["toolUseId": .string(block.id ?? ""), "name": .string(block.name ?? ""), "input": .object(block.arguments ?? [:])])])
        case "thinking": return .object(["text": .string(AIUtilities.sanitizeSurrogates(block.thinking ?? ""))])
        default: return nil
        }
    }

    public static func additionalModelRequestFields(model: Model, options: StreamOptions?) -> [String: JSONValue]? {
        guard let reasoning = options?.reasoning, model.reasoning, isAnthropicClaude(model) else { return nil }
        if supportsAdaptiveThinking(model) {
            var thinking: [String: JSONValue] = ["type": .string("adaptive")]
            if !isGovCloudTarget(model: model, options: options) { thinking["display"] = .string("summarized") }
            return ["thinking": .object(thinking), "output_config": .object(["effort": .string(mapBedrockEffort(model: model, reasoning: reasoning))])]
        }
        let budgets = options?.thinkingBudgets
        let defaults = AIUtilities.defaultThinkingBudgets()
        let budget: Int
        switch reasoning {
        case .minimal: budget = budgets?.minimal ?? defaults.minimal ?? 1024
        case .low: budget = budgets?.low ?? defaults.low ?? 2048
        case .medium: budget = budgets?.medium ?? defaults.medium ?? 8192
        case .high, .xhigh: budget = budgets?.high ?? defaults.high ?? 16_384
        }
        var thinking: [String: JSONValue] = ["type": .string("enabled"), "budget_tokens": .number(Double(budget))]
        if !isGovCloudTarget(model: model, options: options) { thinking["display"] = .string("summarized") }
        return ["thinking": .object(thinking), "anthropic_beta": .array([.string("interleaved-thinking-2025-05-14")])]
    }

    public static func applyCustomHeaders(_ custom: [String: String]?, to headers: inout [String: String]) {
        guard let custom, !custom.isEmpty else { return }
        let reserved = Set(["authorization", "x-amz-date", "x-amz-security-token", "host"])
        for (key, value) in custom where !reserved.contains(key.lowercased()) { headers[key] = value }
    }

    private static func isAnthropicClaude(_ model: Model) -> Bool {
        let values = modelMatchCandidates(model)
        return values.contains { $0.contains("anthropic.claude") || $0.contains("anthropic/claude") || $0.contains("claude") }
    }

    private static func supportsAdaptiveThinking(_ model: Model) -> Bool {
        modelMatchCandidates(model).contains { value in
            value.contains("opus-4-6") || value.contains("opus-4-7") || value.contains("opus-4-8") || value.contains("sonnet-4-6") || value.contains("fable-5")
        }
    }

    private static func supportsNativeXHighEffort(_ model: Model) -> Bool {
        modelMatchCandidates(model).contains { $0.contains("opus-4-7") || $0.contains("opus-4-8") || $0.contains("fable-5") }
    }

    private static func mapBedrockEffort(model: Model, reasoning: ThinkingLevel) -> String {
        if reasoning == .xhigh, supportsNativeXHighEffort(model) { return "xhigh" }
        if let level = ModelThinkingLevel(rawValue: reasoning.rawValue), let mapped = model.thinkingLevelMap?[level], let mapped { return mapped }
        switch reasoning { case .minimal, .low: return "low"; case .medium: return "medium"; case .high, .xhigh: return "high" }
    }

    private static func isGovCloudTarget(model: Model, options: StreamOptions?) -> Bool {
        if let region = options?.region, region.lowercased().hasPrefix("us-gov-") { return true }
        let id = model.id.lowercased()
        return id.hasPrefix("us-gov.") || id.hasPrefix("arn:aws-us-gov:")
    }

    private static func modelMatchCandidates(_ model: Model) -> [String] {
        [model.id, model.name].flatMap { value -> [String] in
            let lower = value.lowercased()
            let normalized = lower.replacingOccurrences(of: #"[\s_.:]+"#, with: "-", options: .regularExpression)
            return [lower, normalized]
        }
    }

    private static func isEmptyBedrockText(_ value: JSONValue) -> Bool {
        if case .object(let object) = value, case .string(let text)? = object["text"] { return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return false
    }

    private static func toolJSON(_ tool: Tool) -> JSONValue { .object(["toolSpec": .object(["name": .string(tool.name), "description": .string(tool.description), "inputSchema": .object(["json": tool.parameters])])]) }
}
