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
        let isOAuth = isOAuthToken(options?.apiKey ?? "")
        var body: [String: JSONValue] = [
            "model": .string(model.id),
            "max_tokens": .number(Double(options?.maxTokens ?? model.maxTokens)),
            "stream": .bool(true),
            "messages": .array(applyCacheControl(to: convertMessages(AIUtilities.transformMessages(context.messages, for: model), model: model, isOAuthToken: isOAuth), cacheControl: cacheControl(model: model, options: options)))
        ]
        let cc = cacheControl(model: model, options: options)
        if let system = context.systemPrompt, !system.isEmpty { body["system"] = .array([.object(["type": .string("text"), "text": .string(AIUtilities.sanitizeSurrogates(system)), "cache_control": cc ?? .null])]) }
        if let temperature = options?.temperature, model.anthropicCompat?.supportsTemperature != false { body["temperature"] = .number(temperature) }
        if let tools = context.tools, !tools.isEmpty { body["tools"] = .array(tools.enumerated().map { idx, tool in toolJSON(tool, model: model, isOAuthToken: isOAuth, cacheControl: (model.anthropicCompat?.supportsCacheControlOnTools != false && idx == tools.count - 1) ? cc : nil) }) }
        if model.reasoning {
            if let reasoning = options?.reasoning {
                let effort = AIUtilities.mapThinkingLevel(model: model, level: ModelThinkingLevel(rawValue: reasoning.rawValue) ?? .high) ?? reasoning.rawValue
                if model.anthropicCompat?.forceAdaptiveThinking == true {
                    body["thinking"] = .object(["type": .string("adaptive"), "display": .string("summarized")])
                    body["output_config"] = .object(["effort": .string(effort)])
                } else {
                    body["thinking"] = .object(["type": .string("enabled"), "budget_tokens": .number(Double(thinkingBudget(reasoning, options: options)))])
                }
            } else if model.thinkingLevelMap?[.off] == nil && model.thinkingLevelMap?.keys.contains(.off) == true {
                // Explicit nil off entry means the upstream model omits disabled thinking.
            } else {
                body["thinking"] = .object(["type": .string("disabled")])
            }
        }
        return body
    }

    private static func streamRequest(model: Model, context: AIContext, options: StreamOptions?, continuation: AsyncStream<AIEvent>.Continuation) async throws {
        guard let key = ProviderEnvironment.resolveAPIKey(model: model, options: options), !key.isEmpty else { throw AIError.provider("missing API key for \(model.provider.rawValue)") }
        var request = URLRequest(url: URL(string: normalizeBaseURL(model.baseUrl) + "/messages")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue(apiVersion, forHTTPHeaderField: "Anthropic-Version")
        if model.provider == .githubCopilot {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            for (k, v) in AIUtilities.copilotHeaders() { request.setValue(v, forHTTPHeaderField: k) }
        } else {
            request.setValue(key, forHTTPHeaderField: "X-Api-Key")
        }
        if let session = options?.sessionId, !session.isEmpty, model.anthropicCompat?.sendSessionAffinityHeaders == true {
            request.setValue(session, forHTTPHeaderField: "x-session-affinity")
        }
        let betas = betaHeaders(model: model, context: context)
        if !betas.isEmpty { request.setValue(betas.joined(separator: ","), forHTTPHeaderField: "Anthropic-Beta") }
        for (k, v) in options?.headers ?? [:] { request.setValue(v, forHTTPHeaderField: k) }
        var payload = buildRequestBody(model: model, context: context, options: options)
        if let hook = options?.onPayload { payload = try await hook(payload, model) }
        request.httpBody = try JSONEncoder().encode(payload)
        let (bytes, response) = try await HTTPRetry.bytes(for: request, policy: RetryPolicy(options: options))
        guard let http = response as? HTTPURLResponse else { throw AIError.invalidResponse("non-HTTP response") }
        if let hook = options?.onResponse { await hook(HTTPResponseMetadata(status: http.statusCode, headers: http.headersDictionary), model) }
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
                state.partial.usage?.cacheWrite1h = raw.message.usage?.cacheCreation?.ephemeral1hInputTokens
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
            if let cacheWrite = raw.usage?.cacheCreationInputTokens { state.partial.usage?.cacheWrite = cacheWrite }
            if let cacheWrite1h = raw.usage?.cacheCreation?.ephemeral1hInputTokens { state.partial.usage?.cacheWrite1h = cacheWrite1h }
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
        if state.sawMessageStart && !state.sawMessageStop {
            state.partial.stopReason = .error
            state.partial.errorMessage = "anthropic stream ended before message_stop"
            yield(.error(reason: .error, message: state.partial, error: AIError.provider(state.partial.errorMessage ?? "anthropic stream error")))
            return
        }
        state.partial.timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        if state.partial.stopReason == nil { state.partial.stopReason = .stop }
        yield(.done(reason: state.partial.stopReason ?? .stop, message: state.partial))
    }

    private static func ensureContentIndex(_ index: Int, state: inout AnthropicStreamState) { while state.partial.content.count <= index { state.partial.content.append(ContentBlock(type: "text")) } }
    private static func parseJSONObject(_ text: String) -> [String: JSONValue] { PartialJSONParser.parseObject(text) ?? [:] }
    private static func normalizeBaseURL(_ base: String) -> String { let b = base.isEmpty ? "https://api.anthropic.com/v1" : base.trimmingCharacters(in: CharacterSet(charactersIn: "/")); return b.hasSuffix("/v1") ? b : b + "/v1" }
    private static func betaHeaders(model: Model, context: AIContext) -> [String] { var out = [String](); if model.anthropicCompat?.forceAdaptiveThinking != true { out.append(interleavedThinkingBeta) }; if model.anthropicCompat?.supportsEagerToolInputStreaming == false, !(context.tools ?? []).isEmpty { out.append(fineGrainedToolStreamingBeta) }; return out }
    private static func thinkingBudget(_ level: ThinkingLevel, options: StreamOptions?) -> Int { switch level { case .minimal: return options?.thinkingBudgets?.minimal ?? 1024; case .low: return options?.thinkingBudgets?.low ?? 2048; case .medium: return options?.thinkingBudgets?.medium ?? 4096; case .high: return options?.thinkingBudgets?.high ?? 8192; case .xhigh: return options?.thinkingBudgets?.high ?? 16384 } }
    private static func stopReason(_ raw: String?) -> StopReason { switch raw { case "max_tokens": return .length; case "tool_use": return .toolUse; case "refusal", "sensitive": return .error; default: return .stop } }
    private static func convertMessages(_ messages: [Message], model: Model, isOAuthToken: Bool = false) -> [JSONValue] {
        messages.map { message in
            let role = message.role == .assistant ? "assistant" : "user"
            let content: [JSONValue]
            if message.role == .toolResult {
                content = [.object(["type": .string("tool_result"), "tool_use_id": .string(normalizeAnthropicToolCallID(message.toolCallId ?? "")), "content": .string(AIUtilities.sanitizeSurrogates(message.content.compactMap(\.text).joined(separator: "\n"))), "is_error": .bool(message.isError == true)])]
            } else {
                content = message.content.compactMap { contentBlock($0, message: message, model: model, isOAuthToken: isOAuthToken) }
            }
            return .object(["role": .string(role), "content": .array(content)])
        }
    }

    private static func contentBlock(_ block: ContentBlock, message: Message, model: Model, isOAuthToken: Bool = false) -> JSONValue? {
        switch block.type {
        case "text":
            return .object(["type": .string("text"), "text": .string(AIUtilities.sanitizeSurrogates(block.text ?? ""))])
        case "thinking":
            if message.role == .assistant {
                let signature = (block.thinkingSignature ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if signature.isEmpty && model.anthropicCompat?.allowEmptySignature != true {
                    return .object(["type": .string("text"), "text": .string(AIUtilities.sanitizeSurrogates(block.thinking ?? ""))])
                }
                return .object(["type": .string("thinking"), "thinking": .string(AIUtilities.sanitizeSurrogates(block.thinking ?? "")), "signature": .string(signature)])
            }
            return .object(["type": .string("text"), "text": .string(AIUtilities.sanitizeSurrogates(block.thinking ?? ""))])
        case "image":
            return .object(["type": .string("image"), "source": .object(["type": .string("base64"), "media_type": .string(block.mimeType ?? "application/octet-stream"), "data": .string(block.data ?? "")])])
        case "toolCall":
            return .object(["type": .string("tool_use"), "id": .string(normalizeAnthropicToolCallID(block.id ?? "")), "name": .string(isOAuthToken ? toClaudeCodeName(block.name ?? "") : (block.name ?? "")), "input": .object(block.arguments ?? [:])])
        default:
            return nil
        }
    }
    private static func cacheControl(model: Model, options: StreamOptions?) -> JSONValue? {
        let retention = ProviderEnvironment.resolveCacheRetention(options?.cacheRetention, env: options?.env)
        if retention == .none { return nil }
        var object: [String: JSONValue] = ["type": .string("ephemeral")]
        if retention == .long && model.anthropicCompat?.supportsLongCacheRetention != false { object["ttl"] = .string("1h") }
        return .object(object)
    }

    private static func applyCacheControl(to messages: [JSONValue], cacheControl: JSONValue?) -> [JSONValue] {
        guard let cacheControl else { return messages }
        var messages = messages
        guard let idx = messages.lastIndex(where: { if case .object(let obj) = $0 { return obj["role"] == .string("user") }; return false }), case .object(var msg) = messages[idx], case .array(var content)? = msg["content"], !content.isEmpty, case .object(var lastBlock) = content[content.count - 1] else { return messages }
        lastBlock["cache_control"] = cacheControl
        content[content.count - 1] = .object(lastBlock)
        msg["content"] = .array(content)
        messages[idx] = .object(msg)
        return messages
    }

    private static func toolJSON(_ tool: Tool, model: Model, isOAuthToken: Bool = false, cacheControl: JSONValue? = nil) -> JSONValue { var obj: [String: JSONValue] = ["name": .string(isOAuthToken ? toClaudeCodeName(tool.name) : tool.name), "description": .string(tool.description), "input_schema": tool.parameters]; if model.anthropicCompat?.supportsEagerToolInputStreaming != false { obj["eager_input_streaming"] = .bool(true) }; if let cacheControl { obj["cache_control"] = cacheControl }; return .object(obj) }
    private static func normalizeAnthropicToolCallID(_ id: String) -> String { String(id.map { ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") ? $0 : "_" }.prefix(64)) }
    private static func isOAuthToken(_ apiKey: String) -> Bool { apiKey.contains("sk-ant-oat") }
    private static func toClaudeCodeName(_ name: String) -> String {
        let tools = ["Read", "Write", "Edit", "Bash", "Grep", "Glob", "AskUserQuestion", "EnterPlanMode", "ExitPlanMode", "KillShell", "NotebookEdit", "Skill", "Task", "TaskOutput", "TodoWrite", "WebFetch", "WebSearch"]
        return tools.first { $0.lowercased() == name.lowercased() } ?? name
    }
}

private struct AnthropicStreamState { var model: Model; var partial: Message; var started = false; var sawMessageStart = false; var sawMessageStop = false; var toolJSON: [Int: String] = [:]; init(model: Model) { self.model = model; var msg = Message(role: .assistant, content: []); msg.api = model.api; msg.provider = model.provider; msg.model = model.id; msg.usage = Usage(); partial = msg } }
private struct AnthropicMessageStart: Decodable { var message: AnthropicStartedMessage; struct AnthropicStartedMessage: Decodable { var id: String?; var usage: AnthropicUsage? } }
private struct AnthropicUsage: Decodable { var inputTokens: Int?; var outputTokens: Int?; var cacheReadInputTokens: Int?; var cacheCreationInputTokens: Int?; var cacheCreation: CacheCreation?; enum CodingKeys: String, CodingKey { case inputTokens = "input_tokens"; case outputTokens = "output_tokens"; case cacheReadInputTokens = "cache_read_input_tokens"; case cacheCreationInputTokens = "cache_creation_input_tokens"; case cacheCreation = "cache_creation" }; struct CacheCreation: Decodable { var ephemeral1hInputTokens: Int?; enum CodingKeys: String, CodingKey { case ephemeral1hInputTokens = "ephemeral_1h_input_tokens" } } }
private struct AnthropicContentBlockStart: Decodable { var index: Int; var contentBlock: Block; enum CodingKeys: String, CodingKey { case index; case contentBlock = "content_block" }; struct Block: Decodable { var type: String; var id: String?; var name: String? } }
private struct AnthropicContentBlockDelta: Decodable { var index: Int; var delta: Delta; struct Delta: Decodable { var type: String; var text: String?; var thinking: String?; var partialJSON: String?; enum CodingKeys: String, CodingKey { case type, text, thinking; case partialJSON = "partial_json" } } }
private struct AnthropicContentBlockStop: Decodable { var index: Int }
private struct AnthropicMessageDelta: Decodable { var delta: Delta; var usage: AnthropicUsage?; struct Delta: Decodable { var stopReason: String?; var stopDetails: StopDetails?; enum CodingKeys: String, CodingKey { case stopReason = "stop_reason"; case stopDetails = "stop_details" }; struct StopDetails: Decodable { var explanation: String? } } }
