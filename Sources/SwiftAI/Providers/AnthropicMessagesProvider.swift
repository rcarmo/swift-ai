import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum AnthropicMessagesProvider {
    private static let apiVersion = "2023-06-01"
    private static let interleavedThinkingBeta = "interleaved-thinking-2025-05-14"
    private static let fineGrainedToolStreamingBeta = "fine-grained-tool-streaming-2025-05-14"

    public static func stream(model: Model, context: AIContext, options: StreamOptions?) -> AsyncStream<AIEvent> {
        AsyncStream { continuation in
            Task {
                do { try await streamRequest(model: model, context: context, options: options, continuation: continuation) }
                catch { continuation.yield(.error(reason: .error, message: nil, error: error)) }
                continuation.finish()
            }
        }
    }

    public static func buildRequestBody(model: Model, context: AIContext, options: StreamOptions?) -> [String: JSONValue] {
        var body: [String: JSONValue] = [
            "model": .string(model.id),
            "max_tokens": .number(Double(options?.maxTokens ?? model.maxTokens)),
            "stream": .bool(true),
            "messages": .array(convertMessages(AIUtilities.transformMessages(context.messages, for: model)))
        ]
        if let system = context.systemPrompt, !system.isEmpty { body["system"] = .string(system) }
        if let temperature = options?.temperature, model.anthropicCompat?.supportsTemperature != false { body["temperature"] = .number(temperature) }
        if let tools = context.tools, !tools.isEmpty { body["tools"] = .array(tools.map(toolJSON)) }
        if let reasoning = options?.reasoning, model.reasoning {
            if model.anthropicCompat?.forceAdaptiveThinking == true { body["thinking"] = .object(["type": .string("adaptive")]) }
            else { body["thinking"] = .object(["type": .string("enabled"), "budget_tokens": .number(Double(thinkingBudget(reasoning, options: options)))]) }
        }
        return body
    }

    private static func streamRequest(model: Model, context: AIContext, options: StreamOptions?, continuation: AsyncStream<AIEvent>.Continuation) async throws {
        guard let key = ProviderEnvironment.apiKey(for: model.provider, env: options?.env), !key.isEmpty else { throw AIError.provider("missing API key for \(model.provider.rawValue)") }
        var request = URLRequest(url: URL(string: normalizeBaseURL(model.baseUrl) + "/messages")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue(apiVersion, forHTTPHeaderField: "Anthropic-Version")
        request.setValue(key, forHTTPHeaderField: "X-Api-Key")
        let betas = betaHeaders(model: model, context: context)
        if !betas.isEmpty { request.setValue(betas.joined(separator: ","), forHTTPHeaderField: "Anthropic-Beta") }
        for (k, v) in options?.headers ?? [:] { request.setValue(v, forHTTPHeaderField: k) }
        request.httpBody = try JSONEncoder().encode(buildRequestBody(model: model, context: context, options: options))
        let (bytes, response) = try await HTTPRetry.bytes(for: request, policy: RetryPolicy(options: options))
        guard let http = response as? HTTPURLResponse else { throw AIError.invalidResponse("non-HTTP response") }
        guard (200..<300).contains(http.statusCode) else { throw AIError.apiError(status: http.statusCode, body: "HTTP \(http.statusCode)") }
        var state = AnthropicStreamState(model: model)
        var buffer = ""
        for try await byte in bytes {
            buffer += String(decoding: [byte], as: UTF8.self)
            while let range = buffer.range(of: "\n\n") ?? buffer.range(of: "\r\n\r\n") {
                let frame = String(buffer[..<range.lowerBound])
                buffer.removeSubrange(..<range.upperBound)
                for event in SSEParser().parse(frame + "\n\n") { process(event: event, state: &state) { continuation.yield($0) } }
            }
        }
        finish(state: &state) { continuation.yield($0) }
    }

    public static func processSSEText(_ text: String, model: Model) -> [AIEvent] {
        var events: [AIEvent] = []
        var state = AnthropicStreamState(model: model)
        for event in SSEParser().parse(text) { process(event: event, state: &state) { events.append($0) } }
        finish(state: &state) { events.append($0) }
        return events
    }

    private static func process(event: SSEEvent, state: inout AnthropicStreamState, yield: (AIEvent) -> Void) {
        if !state.started { state.started = true; yield(.start(partial: state.partial)) }
        guard let data = event.data.data(using: .utf8) else { return }
        switch event.event {
        case "message_start":
            if let raw = try? JSONDecoder().decode(AnthropicMessageStart.self, from: data) {
                state.partial.responseId = raw.message.id
                state.partial.usage?.input = raw.message.usage?.inputTokens ?? 0
                state.partial.usage?.cacheRead = raw.message.usage?.cacheReadInputTokens ?? 0
                state.partial.usage?.cacheWrite = raw.message.usage?.cacheCreationInputTokens ?? 0
                state.sawMessageStart = true
            }
        case "content_block_start":
            guard let raw = try? JSONDecoder().decode(AnthropicContentBlockStart.self, from: data) else { return }
            ensureContentIndex(raw.index, state: &state)
            switch raw.contentBlock.type {
            case "text": state.partial.content[raw.index] = ContentBlock(type: "text"); yield(.textStart(contentIndex: raw.index, partial: state.partial))
            case "thinking": state.partial.content[raw.index] = ContentBlock(type: "thinking"); yield(.thinkingStart(contentIndex: raw.index, partial: state.partial))
            case "tool_use": state.partial.content[raw.index] = ContentBlock(type: "toolCall", id: raw.contentBlock.id, name: raw.contentBlock.name); yield(.toolCallStart(contentIndex: raw.index, partial: state.partial))
            default: break
            }
        case "content_block_delta":
            guard let raw = try? JSONDecoder().decode(AnthropicContentBlockDelta.self, from: data), raw.index < state.partial.content.count else { return }
            switch raw.delta.type {
            case "text_delta": let text = raw.delta.text ?? ""; state.partial.content[raw.index].text = (state.partial.content[raw.index].text ?? "") + text; yield(.textDelta(contentIndex: raw.index, delta: text, partial: state.partial))
            case "thinking_delta": let text = raw.delta.thinking ?? ""; state.partial.content[raw.index].thinking = (state.partial.content[raw.index].thinking ?? "") + text; yield(.thinkingDelta(contentIndex: raw.index, delta: text, partial: state.partial))
            case "input_json_delta": let part = raw.delta.partialJSON ?? ""; state.toolJSON[raw.index, default: ""] += part; state.partial.content[raw.index].arguments = parseJSONObject(state.toolJSON[raw.index] ?? ""); yield(.toolCallDelta(contentIndex: raw.index, delta: part, partial: state.partial))
            default: break
            }
        case "content_block_stop":
            guard let raw = try? JSONDecoder().decode(AnthropicContentBlockStop.self, from: data), raw.index < state.partial.content.count else { return }
            let block = state.partial.content[raw.index]
            switch block.type {
            case "text": yield(.textEnd(contentIndex: raw.index, content: block.text ?? "", partial: state.partial))
            case "thinking": yield(.thinkingEnd(contentIndex: raw.index, content: block.thinking ?? "", partial: state.partial))
            case "toolCall": state.partial.content[raw.index].arguments = state.partial.content[raw.index].arguments ?? parseJSONObject(state.toolJSON[raw.index] ?? ""); yield(.toolCallEnd(contentIndex: raw.index, toolCall: state.partial.content[raw.index], partial: state.partial))
            default: break
            }
        case "message_delta":
            guard let raw = try? JSONDecoder().decode(AnthropicMessageDelta.self, from: data) else { return }
            state.partial.usage?.output = raw.usage?.outputTokens ?? 0
            state.partial.usage?.totalTokens = (state.partial.usage?.input ?? 0) + (state.partial.usage?.output ?? 0)
            if var usage = state.partial.usage { AIUtilities.applyCost(model: state.model, usage: &usage); state.partial.usage = usage }
            state.partial.stopReason = stopReason(raw.delta.stopReason)
            if state.partial.stopReason == .error { state.partial.errorMessage = raw.delta.stopDetails?.explanation ?? "The model refused to complete the request" }
        case "message_stop": state.sawMessageStop = true
        default: break
        }
    }

    private static func finish(state: inout AnthropicStreamState, yield: (AIEvent) -> Void) {
        if !state.started { state.started = true; yield(.start(partial: state.partial)) }
        state.partial.timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        if state.partial.stopReason == nil { state.partial.stopReason = .stop }
        yield(.done(reason: state.partial.stopReason ?? .stop, message: state.partial))
    }

    private static func ensureContentIndex(_ index: Int, state: inout AnthropicStreamState) { while state.partial.content.count <= index { state.partial.content.append(ContentBlock(type: "text")) } }
    private static func parseJSONObject(_ text: String) -> [String: JSONValue] { guard let data = text.data(using: .utf8), let object = try? JSONDecoder().decode([String: JSONValue].self, from: data) else { return [:] }; return object }
    private static func normalizeBaseURL(_ base: String) -> String { let b = base.isEmpty ? "https://api.anthropic.com/v1" : base.trimmingCharacters(in: CharacterSet(charactersIn: "/")); return b.hasSuffix("/v1") ? b : b + "/v1" }
    private static func betaHeaders(model: Model, context: AIContext) -> [String] { var out = [String](); if model.anthropicCompat?.forceAdaptiveThinking != true { out.append(interleavedThinkingBeta) }; if model.anthropicCompat?.supportsEagerToolInputStreaming == false, !(context.tools ?? []).isEmpty { out.append(fineGrainedToolStreamingBeta) }; return out }
    private static func thinkingBudget(_ level: ThinkingLevel, options: StreamOptions?) -> Int { switch level { case .minimal: return options?.thinkingBudgets?.minimal ?? 1024; case .low: return options?.thinkingBudgets?.low ?? 2048; case .medium: return options?.thinkingBudgets?.medium ?? 4096; case .high: return options?.thinkingBudgets?.high ?? 8192; case .xhigh: return options?.thinkingBudgets?.high ?? 16384 } }
    private static func stopReason(_ raw: String?) -> StopReason { switch raw { case "max_tokens": return .length; case "tool_use": return .toolUse; case "refusal", "sensitive": return .error; default: return .stop } }
    private static func convertMessages(_ messages: [Message]) -> [JSONValue] { messages.map { .object(["role": .string($0.role == .assistant ? "assistant" : "user"), "content": .array($0.content.compactMap(contentBlock))]) } }
    private static func contentBlock(_ block: ContentBlock) -> JSONValue? { if block.type == "text" { return .object(["type": .string("text"), "text": .string(block.text ?? "")]) }; if block.type == "image" { return .object(["type": .string("image"), "source": .object(["type": .string("base64"), "media_type": .string(block.mimeType ?? "application/octet-stream"), "data": .string(block.data ?? "")])]) }; return nil }
    private static func toolJSON(_ tool: Tool) -> JSONValue { .object(["name": .string(tool.name), "description": .string(tool.description), "input_schema": tool.parameters]) }
}

private struct AnthropicStreamState { var model: Model; var partial: Message; var started = false; var sawMessageStart = false; var sawMessageStop = false; var toolJSON: [Int: String] = [:]; init(model: Model) { self.model = model; var msg = Message(role: .assistant, content: []); msg.api = model.api; msg.provider = model.provider; msg.model = model.id; msg.usage = Usage(); partial = msg } }
private struct AnthropicMessageStart: Decodable { var message: AnthropicStartedMessage; struct AnthropicStartedMessage: Decodable { var id: String?; var usage: AnthropicUsage? } }
private struct AnthropicUsage: Decodable { var inputTokens: Int?; var outputTokens: Int?; var cacheReadInputTokens: Int?; var cacheCreationInputTokens: Int?; enum CodingKeys: String, CodingKey { case inputTokens = "input_tokens"; case outputTokens = "output_tokens"; case cacheReadInputTokens = "cache_read_input_tokens"; case cacheCreationInputTokens = "cache_creation_input_tokens" } }
private struct AnthropicContentBlockStart: Decodable { var index: Int; var contentBlock: Block; enum CodingKeys: String, CodingKey { case index; case contentBlock = "content_block" }; struct Block: Decodable { var type: String; var id: String?; var name: String? } }
private struct AnthropicContentBlockDelta: Decodable { var index: Int; var delta: Delta; struct Delta: Decodable { var type: String; var text: String?; var thinking: String?; var partialJSON: String?; enum CodingKeys: String, CodingKey { case type, text, thinking; case partialJSON = "partial_json" } } }
private struct AnthropicContentBlockStop: Decodable { var index: Int }
private struct AnthropicMessageDelta: Decodable { var delta: Delta; var usage: AnthropicUsage?; struct Delta: Decodable { var stopReason: String?; var stopDetails: StopDetails?; enum CodingKeys: String, CodingKey { case stopReason = "stop_reason"; case stopDetails = "stop_details" }; struct StopDetails: Decodable { var explanation: String? } } }
