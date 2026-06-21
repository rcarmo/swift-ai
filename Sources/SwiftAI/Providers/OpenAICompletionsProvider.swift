import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum OpenAICompletionsProvider {
    public static func stream(model: Model, context: AIContext, options: StreamOptions?) -> AsyncStream<AIEvent> {
        AsyncStream { continuation in
            Task {
                do {
                    let message = try await request(model: model, context: context, options: options)
                    continuation.yield(.done(reason: message.stopReason ?? .stop, message: message))
                } catch {
                    continuation.yield(.error(reason: .error, message: nil, error: error))
                }
                continuation.finish()
            }
        }
    }

    public static func buildRequestBody(model: Model, context: AIContext, options: StreamOptions?) -> [String: JSONValue] {
        let compat = Compat.detect(for: model)
        var body: [String: JSONValue] = [
            "model": .string(model.id),
            "stream": .bool(false),
            "messages": .array(convertMessages(context: context, compat: compat))
        ]
        if compat.supportsStore != false { body["store"] = .bool(false) }
        if let temperature = options?.temperature { body["temperature"] = .number(temperature) }
        let maxTokensField = compat.maxTokensField ?? "max_tokens"
        if let maxTokens = options?.maxTokens { body[maxTokensField] = .number(Double(maxTokens)) }
        if let tools = context.tools, !tools.isEmpty { body["tools"] = .array(tools.map(toolJSON)) }
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
        guard let level = ModelThinkingLevel(rawValue: effort), let map = model.thinkingLevelMap, let maybeValue = map[level], let value = maybeValue else { return effort }
        return value
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

    private static func convertMessages(context: AIContext, compat: OpenAICompletionsCompat) -> [JSONValue] {
        var out: [JSONValue] = []
        if let system = context.systemPrompt, !system.isEmpty { out.append(.object(["role": .string("system"), "content": .string(system)])) }
        for message in context.messages {
            let role: String = message.role == .toolResult ? "tool" : message.role.rawValue
            let contentText = message.content.compactMap { block -> String? in
                if block.type == "text" { return block.text }
                if compat.requiresThinkingAsText == true, block.type == "thinking" { return block.thinking }
                return nil
            }.joined()
            var obj: [String: JSONValue] = ["role": .string(role), "content": .string(contentText)]
            if message.role == .toolResult, let id = message.toolCallId { obj["tool_call_id"] = .string(id) }
            out.append(.object(obj))
        }
        return out
    }

    private static func toolJSON(_ tool: Tool) -> JSONValue {
        .object(["type": .string("function"), "function": .object(["name": .string(tool.name), "description": .string(tool.description), "parameters": tool.parameters])])
    }

    private static func request(model: Model, context: AIContext, options: StreamOptions?) async throws -> Message {
        guard let key = ProviderEnvironment.apiKey(for: model.provider, env: options?.env), !key.isEmpty else { throw AIError.provider("missing API key for \(model.provider.rawValue)") }
        let url = URL(string: model.baseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        for (k, v) in model.headers ?? [:] { request.setValue(v, forHTTPHeaderField: k) }
        for (k, v) in options?.headers ?? [:] { request.setValue(v, forHTTPHeaderField: k) }
        request.httpBody = try JSONEncoder().encode(buildRequestBody(model: model, context: context, options: options))
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIError.invalidResponse("non-HTTP response") }
        guard (200..<300).contains(http.statusCode) else { throw AIError.apiError(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "") }
        let raw = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        var message = Message(role: .assistant, content: [.text(raw.choices.first?.message.content ?? "")])
        message.api = model.api; message.provider = model.provider; message.model = model.id; message.responseId = raw.id; message.responseModel = raw.model; message.stopReason = raw.choices.first?.finishReason == "length" ? .length : .stop
        if let usage = raw.usage { var u = Usage(); u.input = usage.promptTokens ?? 0; u.output = usage.completionTokens ?? 0; u.totalTokens = usage.totalTokens ?? (u.input + u.output); message.usage = u }
        return message
    }
}

private struct ChatCompletionResponse: Decodable { var id: String?; var model: String?; var choices: [Choice]; var usage: ChatUsage?; struct Choice: Decodable { var message: ChatMessage; var finishReason: String?; enum CodingKeys: String, CodingKey { case message; case finishReason = "finish_reason" } }; struct ChatMessage: Decodable { var content: String? } }
private struct ChatUsage: Decodable { var promptTokens: Int?; var completionTokens: Int?; var totalTokens: Int?; enum CodingKeys: String, CodingKey { case promptTokens = "prompt_tokens"; case completionTokens = "completion_tokens"; case totalTokens = "total_tokens" } }
