import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum OpenAICompletionsProvider {
    public static func stream(model: Model, context: AIContext, options: StreamOptions?) -> AsyncStream<AIEvent> {
        AsyncStream { continuation in
            Task {
                do {
                    try await streamRequest(model: model, context: context, options: options, continuation: continuation)
                } catch {
                    continuation.yield(.error(reason: .error, message: nil, error: error))
                }
                continuation.finish()
            }
        }
    }

    public static func buildRequestBody(model: Model, context: AIContext, options: StreamOptions?) -> [String: JSONValue] {
        buildRequestBody(model: model, context: context, options: options, stream: false)
    }

    public static func buildRequestBody(model: Model, context: AIContext, options: StreamOptions?, stream: Bool) -> [String: JSONValue] {
        let compat = Compat.detect(for: model)
        var body: [String: JSONValue] = [
            "model": .string(model.id),
            "stream": .bool(stream),
            "messages": .array(convertMessages(model: model, context: context, compat: compat))
        ]
        if stream, compat.supportsUsageInStreaming != false { body["stream_options"] = .object(["include_usage": .bool(true)]) }
        if compat.supportsStore != false { body["store"] = .bool(false) }
        if let temperature = options?.temperature { body["temperature"] = .number(temperature) }
        let maxTokensField = compat.maxTokensField ?? "max_tokens"
        if let maxTokens = options?.maxTokens { body[maxTokensField] = .number(Double(maxTokens)) }
        if let tools = context.tools, !tools.isEmpty { body["tools"] = .array(tools.map { toolJSON($0, compat: compat) }) }
        else if hasToolHistory(context.messages) { body["tools"] = .array([]) }
        let cacheRetention = ProviderEnvironment.resolveCacheRetention(options?.cacheRetention, env: options?.env)
        let shouldSendCacheKey = (model.baseUrl.contains("api.openai.com") && cacheRetention != .none) || (cacheRetention == .long && compat.supportsLongCacheRetention == true)
        if let session = options?.sessionId, !session.isEmpty, shouldSendCacheKey { body["prompt_cache_key"] = .string(PromptCache.clampOpenAIKey(session)) }
        if cacheRetention == .long, compat.supportsLongCacheRetention == true { body["prompt_cache_retention"] = .string("24h") }
        if let toolChoice = options?.toolChoice { body["tool_choice"] = toolChoice }
        if let reasoning = options?.reasoning, model.reasoning { applyThinking(model: model, options: options, compat: compat, effort: reasoning.rawValue, body: &body) }
        return body
    }

    private static func applyThinking(model: Model, options: StreamOptions?, compat: OpenAICompletionsCompat, effort: String, body: inout [String: JSONValue]) {
        let mapped = mappedThinkingEffort(model: model, effort: effort)
        switch compat.thinkingFormat ?? "openai" {
        case "openai": body["reasoning_effort"] = .string(mapped)
        case "openrouter": body["reasoning"] = .object(["effort": .string(mapped)])
        case "deepseek": body["thinking"] = .object(["type": .string("enabled")]); body["reasoning_effort"] = .string(mapped)
        case "together": body["reasoning"] = .object(["enabled": .bool(true)]); body["reasoning_effort"] = .string(mapped)
        case "zai": body["thinking"] = .object(["type": .string("enabled")]); if compat.zaiToolStream == true { body["tool_stream"] = .bool(true) }
        case "qwen": body["enable_thinking"] = .bool(true)
        case "qwen-chat-template": body["chat_template_kwargs"] = .object(["enable_thinking": .bool(true), "preserve_thinking": .bool(true)])
        case "chat-template": if let kwargs = buildChatTemplateKwargs(model: model, compat: compat, effort: effort) { body["chat_template_kwargs"] = .object(kwargs) }
        case "string-thinking": body["thinking"] = .object(["type": .string(mapped)])
        default: break
        }
    }

    private static func mappedThinkingEffort(model: Model, effort: String) -> String {
        AIUtilities.mapThinkingLevel(model: model, level: ModelThinkingLevel(rawValue: effort) ?? .high) ?? effort
    }

    private static func buildChatTemplateKwargs(model: Model, compat: OpenAICompletionsCompat, effort: String?) -> [String: JSONValue]? {
        guard let source = compat.chatTemplateKwargs else { return nil }
        var out: [String: JSONValue] = [:]
        for (key, value) in source {
            if let variable = value.variable {
                if effort == nil && value.omitWhenOff == true { continue }
                switch variable {
                case "thinking.enabled": out[key] = .bool(effort != nil)
                case "thinking.effort": if let effort { out[key] = .string(mappedThinkingEffort(model: model, effort: effort)) }
                default: if let v = value.value { out[key] = v }
                }
            } else if let v = value.value { out[key] = v }
        }
        return out.isEmpty ? nil : out
    }

    private static func convertMessages(model: Model, context: AIContext, compat: OpenAICompletionsCompat) -> [JSONValue] {
        var out: [JSONValue] = []
        if let system = context.systemPrompt, !system.isEmpty {
            let role = model.reasoning && compat.supportsDeveloperRole == true ? "developer" : "system"
            out.append(.object(["role": .string(role), "content": .string(AIUtilities.sanitizeSurrogates(system))]))
        }
        var lastRole: Role?
        for message in AIUtilities.transformMessages(context.messages, for: model) {
            if compat.requiresAssistantAfterToolResult == true, lastRole == .toolResult, message.role == .user {
                out.append(.object(["role": .string("assistant"), "content": .string("I have processed the tool results.")]))
            }
            let role: String = message.role == .toolResult ? "tool" : message.role.rawValue
            let contentValue: JSONValue
            if message.role == .user, message.content.contains(where: { $0.type == "image" }) {
                contentValue = .array(openAIContentParts(message.content, leadingText: nil))
            } else {
                let contentText = message.content.compactMap { block -> String? in
                    if block.type == "text" { return block.text }
                    if compat.requiresThinkingAsText == true, block.type == "thinking" { return block.thinking }
                    return nil
                }.joined()
                contentValue = .string(AIUtilities.sanitizeSurrogates(contentText))
            }
            var obj: [String: JSONValue] = ["role": .string(role), "content": contentValue]
            if message.role == .assistant {
                if compat.requiresReasoningContentOnAssistantMessages == true {
                    let reasoning = message.content.filter { $0.type == "thinking" }.compactMap(\.thinking).joined()
                    obj["reasoning_content"] = .string(AIUtilities.sanitizeSurrogates(reasoning))
                }
                let calls = message.content.filter { $0.type == "toolCall" }.map { block in
                    JSONValue.object(["id": .string(block.id ?? ""), "type": .string("function"), "function": .object(["name": .string(block.name ?? ""), "arguments": .string(jsonString(block.arguments ?? [:]))])])
                }
                if !calls.isEmpty { obj["tool_calls"] = .array(calls) }
            }
            if message.role == .toolResult, let id = message.toolCallId {
                obj["tool_call_id"] = .string(id)
                if compat.requiresToolResultName == true, let name = message.toolName { obj["name"] = .string(name) }
            }
            out.append(.object(obj))
            if message.role == .toolResult {
                let images = message.content.filter { $0.type == "image" }
                if !images.isEmpty {
                    if compat.requiresAssistantAfterToolResult == true { out.append(.object(["role": .string("assistant"), "content": .string("I have processed the tool results.")])) }
                    out.append(.object(["role": .string("user"), "content": .array(openAIContentParts(images, leadingText: "Tool result image:"))]))
                }
            }
            lastRole = message.role
        }
        return out
    }

    private static func jsonString(_ object: [String: JSONValue]) -> String { guard let data = try? JSONEncoder().encode(object) else { return "{}" }; return String(data: data, encoding: .utf8) ?? "{}" }

    private static func hasToolHistory(_ messages: [Message]) -> Bool {
        messages.contains { message in message.role == .toolResult || (message.role == .assistant && message.content.contains { $0.type == "toolCall" }) }
    }

    private static func clientAPIKey(model: Model, options: StreamOptions?) -> String? {
        if let key = ProviderEnvironment.resolveAPIKey(model: model, options: options), !key.isEmpty { return key }
        let headers = (model.headers ?? [:]).merging(options?.headers ?? [:]) { _, new in new }
        if hasHeader(headers, "authorization") || hasHeader(headers, "cf-aig-authorization") { return "unused" }
        return nil
    }

    private static func hasHeader(_ headers: [String: String], _ name: String) -> Bool {
        headers.contains { $0.key.lowercased() == name.lowercased() && !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private static func openAIContentParts(_ blocks: [ContentBlock], leadingText: String?) -> [JSONValue] {
        var parts: [JSONValue] = []
        if let leadingText { parts.append(.object(["type": .string("text"), "text": .string(leadingText)])) }
        for block in blocks {
            if block.type == "text" { parts.append(.object(["type": .string("text"), "text": .string(AIUtilities.sanitizeSurrogates(block.text ?? ""))])) }
            if block.type == "image" { parts.append(.object(["type": .string("image_url"), "image_url": .object(["url": .string("data:\(block.mimeType ?? "application/octet-stream");base64,\(block.data ?? "")")])])) }
        }
        return parts
    }

    private static func toolJSON(_ tool: Tool, compat: OpenAICompletionsCompat) -> JSONValue {
        var function: [String: JSONValue] = ["name": .string(tool.name), "description": .string(tool.description), "parameters": tool.parameters]
        if compat.supportsStrictMode != false { function["strict"] = .bool(true) }
        return .object(["type": .string("function"), "function": .object(function)])
    }

    private static func makeRequest(model: Model, context: AIContext, options: StreamOptions?, stream: Bool) async throws -> URLRequest {
        guard let key = clientAPIKey(model: model, options: options), !key.isEmpty else { throw AIError.provider("missing API key for \(model.provider.rawValue)") }
        let baseURL = AIUtilities.isCloudflareProvider(model.provider) ? AIUtilities.resolveCloudflareBaseURL(model: model, env: options?.env) : model.baseUrl
        let url = URL(string: baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        if stream { request.setValue("text/event-stream", forHTTPHeaderField: "Accept") }
        let compat = Compat.detect(for: model)
        if let session = options?.sessionId, !session.isEmpty, compat.sendSessionAffinityHeaders == true {
            request.setValue(session, forHTTPHeaderField: "session_id")
            request.setValue(session, forHTTPHeaderField: "x-client-request-id")
            request.setValue(session, forHTTPHeaderField: "x-session-affinity")
        }
        if model.provider == .githubCopilot {
            for (k, v) in AIUtilities.buildCopilotDynamicHeaders(context.messages) { request.setValue(v, forHTTPHeaderField: k) }
        }
        for (k, v) in model.headers ?? [:] { request.setValue(v, forHTTPHeaderField: k) }
        for (k, v) in options?.headers ?? [:] { request.setValue(v, forHTTPHeaderField: k) }
        var payload = buildRequestBody(model: model, context: context, options: options, stream: stream)
        if let hook = options?.onPayload { payload = try await hook(payload, model) }
        request.httpBody = try JSONEncoder().encode(payload)
        return request
    }

    private static func streamRequest(model: Model, context: AIContext, options: StreamOptions?, continuation: AsyncStream<AIEvent>.Continuation) async throws {
        let request = try await makeRequest(model: model, context: context, options: options, stream: true)
        let (bytes, response) = try await HTTPRetry.bytes(for: request, policy: RetryPolicy(options: options))
        guard let http = response as? HTTPURLResponse else { throw AIError.invalidResponse("non-HTTP response") }
        if let hook = options?.onResponse { await hook(HTTPResponseMetadata(status: http.statusCode, headers: http.headersDictionary), model) }
        guard (200..<300).contains(http.statusCode) else { throw AIError.apiError(status: http.statusCode, body: "HTTP \(http.statusCode)") }
        var state = StreamState(model: model)
        var buffer = ""
        for try await byte in bytes {
            buffer += String(decoding: [byte], as: UTF8.self)
            while let range = buffer.range(of: "\n\n") ?? buffer.range(of: "\r\n\r\n") {
                let frame = String(buffer[..<range.lowerBound])
                buffer.removeSubrange(..<range.upperBound)
                processSSEFrame(frame, model: model, state: &state, continuation: continuation)
            }
        }
        finishStream(state: &state, continuation: continuation)
    }

    private static func request(model: Model, context: AIContext, options: StreamOptions?) async throws -> Message {
        let request = try await makeRequest(model: model, context: context, options: options, stream: false)
        let (data, response) = try await HTTPRetry.data(for: request, policy: RetryPolicy(options: options))
        guard let http = response as? HTTPURLResponse else { throw AIError.invalidResponse("non-HTTP response") }
        if let hook = options?.onResponse { await hook(HTTPResponseMetadata(status: http.statusCode, headers: http.headersDictionary), model) }
        guard (200..<300).contains(http.statusCode) else { throw AIError.apiError(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "") }
        let raw = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        var message = Message(role: .assistant, content: [.text(raw.choices.first?.message.content ?? "")])
        message.api = model.api; message.provider = model.provider; message.model = model.id; message.responseId = raw.id; message.responseModel = raw.model; message.stopReason = raw.choices.first?.finishReason == "length" ? .length : .stop
        if let usage = raw.usage { var u = Usage(); u.input = usage.promptTokens ?? 0; u.output = usage.completionTokens ?? 0; u.totalTokens = usage.totalTokens ?? (u.input + u.output); AIUtilities.applyCost(model: model, usage: &u); message.usage = u }
        return message
    }
    public static func processSSEText(_ text: String, model: Model) -> [AIEvent] {
        var events: [AIEvent] = []
        var state = StreamState(model: model)
        for event in SSEParser().parse(text) {
            processSSEData(event.data, model: model, state: &state) { events.append($0) }
        }
        finishStream(state: &state) { events.append($0) }
        return events
    }

    private static func processSSEFrame(_ frame: String, model: Model, state: inout StreamState, continuation: AsyncStream<AIEvent>.Continuation) {
        for event in SSEParser().parse(frame + "\n\n") {
            processSSEData(event.data, model: model, state: &state) { continuation.yield($0) }
        }
    }

    private static func processSSEData(_ data: String, model: Model, state: inout StreamState, yield: (AIEvent) -> Void) {
        if !state.started { state.started = true; yield(.start(partial: state.partial)) }
        if data == "[DONE]" { state.doneSeen = true; return }
        guard let raw = data.data(using: .utf8), let chunk = try? JSONDecoder().decode(SSEChunk.self, from: raw) else { return }
        if let id = chunk.id { state.partial.responseId = id }
        if let responseModel = chunk.model, responseModel != model.id, state.partial.responseModel == nil { state.partial.responseModel = responseModel }
        if let usage = chunk.usage { state.applyUsage(usage) }
        guard let choice = chunk.choices.first else { return }
        if let usage = choice.usage { state.applyUsage(usage) }
        if let finish = choice.finishReason { state.finishReason = finish }
        let delta = choice.delta
        if let text = delta.content, !text.isEmpty {
            if state.partial.content.last?.type != "text" { state.partial.content.append(ContentBlock(type: "text")); yield(.textStart(contentIndex: state.partial.content.count - 1, partial: state.partial)) }
            let idx = state.partial.content.count - 1
            state.partial.content[idx].text = (state.partial.content[idx].text ?? "") + text
            yield(.textDelta(contentIndex: idx, delta: text, partial: state.partial))
        }
        let reasoning = delta.reasoningContent ?? delta.reasoning ?? delta.reasoningText
        if let reasoning, !reasoning.isEmpty {
            if state.partial.content.last?.type != "thinking" { state.partial.content.append(ContentBlock(type: "thinking")); yield(.thinkingStart(contentIndex: state.partial.content.count - 1, partial: state.partial)) }
            let idx = state.partial.content.count - 1
            state.partial.content[idx].thinking = (state.partial.content[idx].thinking ?? "") + reasoning
            yield(.thinkingDelta(contentIndex: idx, delta: reasoning, partial: state.partial))
        }
        for tool in delta.toolCalls ?? [] {
            let key = tool.index
            if state.activeTools[key] == nil {
                let idx = state.partial.content.count
                state.partial.content.append(ContentBlock(type: "toolCall", id: tool.id, name: tool.function?.name))
                state.activeTools[key] = ActiveTool(index: key, id: tool.id, name: tool.function?.name, args: "", contentIndex: idx)
                yield(.toolCallStart(contentIndex: idx, partial: state.partial))
            }
            guard var active = state.activeTools[key] else { continue }
            if let id = tool.id { active.id = id; state.partial.content[active.contentIndex].id = id }
            if let name = tool.function?.name { active.name = name; state.partial.content[active.contentIndex].name = name }
            if let args = tool.function?.arguments, !args.isEmpty { active.args += args; yield(.toolCallDelta(contentIndex: active.contentIndex, delta: args, partial: state.partial)) }
            state.activeTools[key] = active
        }
    }

    private static func finishStream(state: inout StreamState, continuation: AsyncStream<AIEvent>.Continuation) { finishStream(state: &state) { continuation.yield($0) } }

    private static func finishStream(state: inout StreamState, yield: (AIEvent) -> Void) {
        if !state.started { state.started = true; yield(.start(partial: state.partial)) }
        for (idx, block) in state.partial.content.enumerated() {
            if block.type == "text" { yield(.textEnd(contentIndex: idx, content: block.text ?? "", partial: state.partial)) }
            if block.type == "thinking" { yield(.thinkingEnd(contentIndex: idx, content: block.thinking ?? "", partial: state.partial)) }
        }
        for key in state.activeTools.keys.sorted() {
            guard let active = state.activeTools[key] else { continue }
            let args = parseJSONObject(active.args)
            state.partial.content[active.contentIndex].arguments = args
            let call = ContentBlock(type: "toolCall", id: active.id, name: active.name, arguments: args)
            yield(.toolCallEnd(contentIndex: active.contentIndex, toolCall: call, partial: state.partial))
        }
        state.partial.timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        let reason = stopReason(from: state.finishReason)
        state.partial.stopReason = reason
        if reason == .error, let finish = state.finishReason {
            state.partial.errorMessage = "Provider finish_reason: \(finish)"
            yield(.error(reason: .error, message: state.partial, error: AIError.provider(state.partial.errorMessage ?? "provider error")))
        } else {
            yield(.done(reason: reason, message: state.partial))
        }
    }

    private static func parseJSONObject(_ text: String) -> [String: JSONValue] { PartialJSONParser.parseObject(text) ?? [:] }

    private static func stopReason(from finish: String?) -> StopReason {
        switch finish {
        case nil, "stop", "end": return .stop
        case "length": return .length
        case "tool_calls", "function_call": return .toolUse
        default: return .error
        }
    }
}

private struct StreamState {
    var model: Model
    var partial: Message
    var started = false
    var doneSeen = false
    var finishReason: String?
    var activeTools: [Int: ActiveTool] = [:]
    init(model: Model) { self.model = model; var msg = Message(role: .assistant, content: []); msg.api = model.api; msg.provider = model.provider; msg.model = model.id; msg.usage = Usage(); partial = msg }
    mutating func applyUsage(_ raw: SSEUsage) { var u = partial.usage ?? Usage(); u.input = raw.promptTokens ?? 0; u.output = raw.completionTokens ?? 0; u.totalTokens = raw.totalTokens ?? (u.input + u.output); if let cached = raw.promptTokensDetails?.cachedTokens ?? raw.promptCacheHitTokens { u.cacheRead = cached; u.input = max(0, u.input - cached) }; if let written = raw.promptTokensDetails?.cacheWriteTokens { u.cacheWrite = written; u.input = max(0, u.input - written) }; AIUtilities.applyCost(model: model, usage: &u); partial.usage = u }
}

private struct ActiveTool { var index: Int; var id: String?; var name: String?; var args: String; var contentIndex: Int }

private struct ChatCompletionResponse: Decodable { var id: String?; var model: String?; var choices: [Choice]; var usage: ChatUsage?; struct Choice: Decodable { var message: ChatMessage; var finishReason: String?; enum CodingKeys: String, CodingKey { case message; case finishReason = "finish_reason" } }; struct ChatMessage: Decodable { var content: String? } }
private struct ChatUsage: Decodable { var promptTokens: Int?; var completionTokens: Int?; var totalTokens: Int?; enum CodingKeys: String, CodingKey { case promptTokens = "prompt_tokens"; case completionTokens = "completion_tokens"; case totalTokens = "total_tokens" } }

private struct SSEChunk: Decodable { var id: String?; var model: String?; var choices: [SSEChoice]; var usage: SSEUsage? }
private struct SSEChoice: Decodable { var index: Int?; var delta: SSEDelta; var finishReason: String?; var usage: SSEUsage?; enum CodingKeys: String, CodingKey { case index, delta, usage; case finishReason = "finish_reason" } }
private struct SSEDelta: Decodable { var role: String?; var content: String?; var toolCalls: [SSEToolCall]?; var reasoning: String?; var reasoningContent: String?; var reasoningText: String?; enum CodingKeys: String, CodingKey { case role, content, reasoning; case toolCalls = "tool_calls"; case reasoningContent = "reasoning_content"; case reasoningText = "reasoning_text" } }
private struct SSEToolCall: Decodable { var index: Int; var id: String?; var type: String?; var function: SSEToolFunction? }
private struct SSEToolFunction: Decodable { var name: String?; var arguments: String? }
private struct SSEUsage: Decodable { var promptTokens: Int?; var completionTokens: Int?; var totalTokens: Int?; var promptCacheHitTokens: Int?; var promptTokensDetails: PromptTokensDetails?; enum CodingKeys: String, CodingKey { case promptTokens = "prompt_tokens"; case completionTokens = "completion_tokens"; case totalTokens = "total_tokens"; case promptCacheHitTokens = "prompt_cache_hit_tokens"; case promptTokensDetails = "prompt_tokens_details" }; struct PromptTokensDetails: Decodable { var cachedTokens: Int?; var cacheWriteTokens: Int?; enum CodingKeys: String, CodingKey { case cachedTokens = "cached_tokens"; case cacheWriteTokens = "cache_write_tokens" } } }
