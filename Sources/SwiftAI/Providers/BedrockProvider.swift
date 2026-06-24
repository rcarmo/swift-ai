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
        if let region = options?.region, !region.isEmpty { return region }
        if let region = ProviderEnvironment.value("AWS_REGION", env: env), !region.isEmpty { return region }
        if let region = ProviderEnvironment.value("AWS_DEFAULT_REGION", env: env), !region.isEmpty { return region }
        if let endpoint = standardEndpointRegion(model.baseUrl), !endpoint.isEmpty, options?.profile == nil { return endpoint }
        return "us-east-1"
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
        if let reasoning = options?.reasoning, model.reasoning {
            let effort = AIUtilities.mapThinkingLevel(model: model, level: ModelThinkingLevel(rawValue: reasoning.rawValue) ?? .high) ?? reasoning.rawValue
            request["additionalModelRequestFields"] = .object(["thinking": .object(["type": .string("enabled"), "effort": .string(effort)])])
        }
        if let metadata = options?.requestMetadata, !metadata.isEmpty { request["requestMetadata"] = .object(metadata.mapValues { .string($0) }) }
        return request
    }

    private static func convertMessages(_ messages: [Message]) -> [JSONValue] {
        messages.compactMap { msg in
            switch msg.role {
            case .user:
                return .object(["role": .string("user"), "content": .array(msg.content.compactMap(contentBlock))])
            case .assistant:
                return .object(["role": .string("assistant"), "content": .array(msg.content.compactMap(contentBlock))])
            case .toolResult:
                let text = AIUtilities.sanitizeSurrogates(msg.content.compactMap(\.text).joined(separator: "\n"))
                let result: [String: JSONValue] = [
                    "toolUseId": .string(msg.toolCallId ?? ""),
                    "content": .array([.object(["text": .string(text)])]),
                    "status": .string(msg.isError == true ? "error" : "success")
                ]
                return .object(["role": .string("user"), "content": .array([.object(["toolResult": .object(result)])])])
            }
        }
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

    private static func toolJSON(_ tool: Tool) -> JSONValue { .object(["toolSpec": .object(["name": .string(tool.name), "description": .string(tool.description), "inputSchema": .object(["json": tool.parameters])])]) }
}
