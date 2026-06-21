import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum OpenAIResponsesProvider {
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
        var body: [String: JSONValue] = ["model": .string(model.id), "input": .array(convertInput(model: model, context: context)), "stream": .bool(true), "store": .bool(false)]
        if let tools = context.tools, !tools.isEmpty { body["tools"] = .array(tools.map(toolJSON)) }
        if let t = options?.temperature { body["temperature"] = .number(t) }
        if let max = options?.maxTokens { body["max_output_tokens"] = .number(Double(max)) }
        if let reasoning = options?.reasoning, model.reasoning { body["reasoning"] = .object(["effort": .string(mappedThinkingEffort(model: model, effort: reasoning.rawValue)), "summary": .string(options?.reasoningSummary ?? "auto")]); body["include"] = .array([.string("reasoning.encrypted_content")]) }
        if let tier = options?.serviceTier, !tier.isEmpty { body["service_tier"] = .string(tier) }
        if let session = options?.sessionId, !session.isEmpty, options?.cacheRetention != .none { body["prompt_cache_key"] = .string(String(session.prefix(64))) }
        if options?.cacheRetention == .long, model.responsesCompat?.supportsLongCacheRetention != false { body["prompt_cache_retention"] = .string("24h") }
        return body
    }

    public static func resolveAzureConfig(model: Model, options: StreamOptions?) throws -> (baseURL: String, deployment: String, apiVersion: String) {
        let env = options?.env ?? [:]
        let apiVersion = options?.azureApiVersion ?? env["AZURE_OPENAI_API_VERSION"] ?? "v1"
        let deployment = options?.azureDeploymentName ?? model.id
        var base = options?.azureBaseUrl ?? env["AZURE_OPENAI_BASE_URL"] ?? model.baseUrl
        if base.isEmpty, let resource = options?.azureResourceName ?? env["AZURE_OPENAI_RESOURCE_NAME"], !resource.isEmpty { base = "https://\(resource).openai.azure.com/openai/v1" }
        guard !base.isEmpty else { throw AIError.provider("Azure OpenAI base URL is required") }
        base = base.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !base.contains("/openai") { base += "/openai/v1" }
        return (base + "/deployments/\(deployment.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? deployment)", deployment, apiVersion)
    }

    private static func streamRequest(model: Model, context: AIContext, options: StreamOptions?, continuation: AsyncStream<AIEvent>.Continuation) async throws {
        guard let key = ProviderEnvironment.apiKey(for: model.provider, env: options?.env), !key.isEmpty else { throw AIError.provider("missing API key for \(model.provider.rawValue)") }
        var requestModel = model
        var base = model.baseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var suffix = "/responses"
        if model.api == .azureOpenAIResponses { let cfg = try resolveAzureConfig(model: model, options: options); base = cfg.baseURL; suffix = "/responses?api-version=\(cfg.apiVersion.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? cfg.apiVersion)"; requestModel.id = cfg.deployment }
        var body = buildRequestBody(model: requestModel, context: context, options: options)
        var request = URLRequest(url: URL(string: base + suffix)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        if let session = options?.sessionId, !session.isEmpty { if model.responsesCompat?.sendSessionIdHeader != false { request.setValue(session, forHTTPHeaderField: "session_id") }; request.setValue(session, forHTTPHeaderField: "x-client-request-id") }
        for (k, v) in model.headers ?? [:] { request.setValue(v, forHTTPHeaderField: k) }
        for (k, v) in options?.headers ?? [:] { request.setValue(v, forHTTPHeaderField: k) }
        request.httpBody = try JSONEncoder().encode(body)
        let (bytes, response) = try await HTTPRetry.bytes(for: request, policy: RetryPolicy(options: options))
        guard let http = response as? HTTPURLResponse else { throw AIError.invalidResponse("non-HTTP response") }
        guard (200..<300).contains(http.statusCode) else { throw AIError.apiError(status: http.statusCode, body: "HTTP \(http.statusCode)") }
        var state = ResponsesStreamState(model: model)
        var buffer = ""
        for try await byte in bytes {
            buffer += String(decoding: [byte], as: UTF8.self)
            while let range = buffer.range(of: "\n\n") ?? buffer.range(of: "\r\n\r\n") {
                let frame = String(buffer[..<range.lowerBound]); buffer.removeSubrange(..<range.upperBound)
                for event in SSEParser().parse(frame + "\n\n") { process(event: event, state: &state) { continuation.yield($0) } }
            }
        }
        finish(state: &state) { continuation.yield($0) }
    }

    public static func processSSEText(_ text: String, model: Model) -> [AIEvent] {
        var events: [AIEvent] = []; var state = ResponsesStreamState(model: model)
        for event in SSEParser().parse(text) { process(event: event, state: &state) { events.append($0) } }
        finish(state: &state) { events.append($0) }
        return events
    }

    private static func process(event: SSEEvent, state: inout ResponsesStreamState, yield: (AIEvent) -> Void) {
        if !state.started { state.started = true; yield(.start(partial: state.partial)) }
        guard let data = event.data.data(using: .utf8) else { return }
        switch event.event {
        case "response.created": if let raw = try? JSONDecoder().decode(ResponseCreated.self, from: data) { state.partial.responseId = raw.response?.id }
        case "response.output_item.added":
            guard let item = try? JSONDecoder().decode(ResponseOutputItemAdded.self, from: data) else { return }
            switch item.item.type {
            case "message": state.partial.content.append(ContentBlock(type: "text")); state.current = ("message", state.partial.content.count - 1); yield(.textStart(contentIndex: state.partial.content.count - 1, partial: state.partial))
            case "reasoning": state.partial.content.append(ContentBlock(type: "thinking")); state.current = ("reasoning", state.partial.content.count - 1); yield(.thinkingStart(contentIndex: state.partial.content.count - 1, partial: state.partial))
            case "function_call": let block = ContentBlock(type: "toolCall", id: item.item.callId ?? item.item.id, name: item.item.name); state.partial.content.append(block); state.current = ("function_call", state.partial.content.count - 1); state.toolArgs[state.partial.content.count - 1] = ""; yield(.toolCallStart(contentIndex: state.partial.content.count - 1, partial: state.partial))
            default: break
            }
        case "response.output_text.delta": if let idx = state.current?.index { let raw = (try? JSONDecoder().decode(ResponseDelta.self, from: data))?.delta ?? ""; state.partial.content[idx].text = (state.partial.content[idx].text ?? "") + raw; yield(.textDelta(contentIndex: idx, delta: raw, partial: state.partial)) }
        case "response.reasoning_summary_text.delta": if let idx = state.current?.index { let raw = (try? JSONDecoder().decode(ResponseDelta.self, from: data))?.delta ?? ""; state.partial.content[idx].thinking = (state.partial.content[idx].thinking ?? "") + raw; yield(.thinkingDelta(contentIndex: idx, delta: raw, partial: state.partial)) }
        case "response.function_call_arguments.delta": if let idx = state.current?.index { let raw = (try? JSONDecoder().decode(ResponseDelta.self, from: data))?.delta ?? ""; state.toolArgs[idx, default: ""] += raw; yield(.toolCallDelta(contentIndex: idx, delta: raw, partial: state.partial)) }
        case "response.output_item.done": closeCurrent(state: &state, yield: yield)
        case "response.completed": if let raw = try? JSONDecoder().decode(ResponseCompleted.self, from: data) { state.partial.responseId = raw.response?.id ?? state.partial.responseId; applyUsage(raw.response?.usage, state: &state); state.partial.stopReason = .stop }
        case "response.failed": if let raw = try? JSONDecoder().decode(ResponseFailed.self, from: data) { state.partial.stopReason = .error; state.partial.errorMessage = raw.response?.error?.message ?? raw.error?.message ?? "response failed" }
        default: break
        }
    }

    private static func closeCurrent(state: inout ResponsesStreamState, yield: (AIEvent) -> Void) { guard let current = state.current else { return }; let block = state.partial.content[current.index]; switch current.type { case "message": yield(.textEnd(contentIndex: current.index, content: block.text ?? "", partial: state.partial)); case "reasoning": yield(.thinkingEnd(contentIndex: current.index, content: block.thinking ?? "", partial: state.partial)); case "function_call": let args = parseJSONObject(state.toolArgs[current.index] ?? ""); state.partial.content[current.index].arguments = args; yield(.toolCallEnd(contentIndex: current.index, toolCall: state.partial.content[current.index], partial: state.partial)); default: break }; state.current = nil }
    private static func finish(state: inout ResponsesStreamState, yield: (AIEvent) -> Void) { if !state.started { state.started = true; yield(.start(partial: state.partial)) }; closeCurrent(state: &state, yield: yield); state.partial.timestamp = Int64(Date().timeIntervalSince1970 * 1000); if state.partial.stopReason == nil { state.partial.stopReason = .stop }; yield(.done(reason: state.partial.stopReason ?? .stop, message: state.partial)) }
    private static func applyUsage(_ raw: ResponseUsage?, state: inout ResponsesStreamState) { guard let raw else { return }; var u = Usage(); u.input = raw.inputTokens ?? 0; u.output = raw.outputTokens ?? 0; u.totalTokens = raw.totalTokens ?? (u.input + u.output); AIUtilities.applyCost(model: state.model, usage: &u); state.partial.usage = u }

    private static func convertInput(model: Model, context: AIContext) -> [JSONValue] { var out: [JSONValue] = []; if let system = context.systemPrompt, !system.isEmpty { out.append(.object(["role": .string(model.reasoning ? "developer" : "system"), "content": .string(system)])) }; for msg in AIUtilities.transformMessages(context.messages, for: model) { if msg.role == .user { out.append(.object(["role": .string("user"), "content": .array(msg.content.compactMap(userContent))])) } else if msg.role == .assistant { out.append(.object(["type": .string("message"), "role": .string("assistant"), "content": .array(msg.content.filter { $0.type == "text" }.map { .object(["type": .string("output_text"), "text": .string($0.text ?? "")]) })])) } else { out.append(.object(["type": .string("function_call_output"), "call_id": .string(msg.toolCallId ?? ""), "output": .string(msg.content.compactMap(\.text).joined(separator: "\n"))])) } }; return out }
    private static func userContent(_ block: ContentBlock) -> JSONValue? { if block.type == "text" { return .object(["type": .string("input_text"), "text": .string(block.text ?? "")]) }; if block.type == "image" { return .object(["type": .string("input_image"), "detail": .string("auto"), "image_url": .string("data:\(block.mimeType ?? "application/octet-stream");base64,\(block.data ?? "")")]) }; return nil }
    private static func toolJSON(_ tool: Tool) -> JSONValue { .object(["type": .string("function"), "name": .string(tool.name), "description": .string(tool.description), "parameters": tool.parameters]) }
    private static func mappedThinkingEffort(model: Model, effort: String) -> String { guard let level = ModelThinkingLevel(rawValue: effort), let map = model.thinkingLevelMap, let maybe = map[level], let value = maybe else { return effort }; return value }
    private static func parseJSONObject(_ text: String) -> [String: JSONValue] { guard let data = text.data(using: .utf8), let object = try? JSONDecoder().decode([String: JSONValue].self, from: data) else { return [:] }; return object }
}

private struct ResponsesStreamState { var model: Model; var partial: Message; var started = false; var current: (type: String, index: Int)?; var toolArgs: [Int: String] = [:]; init(model: Model) { self.model = model; var msg = Message(role: .assistant, content: []); msg.api = model.api; msg.provider = model.provider; msg.model = model.id; msg.usage = Usage(); partial = msg } }
private struct ResponseCreated: Decodable { var response: Inner?; struct Inner: Decodable { var id: String? } }
private struct ResponseOutputItemAdded: Decodable { var item: Item; struct Item: Decodable { var type: String; var id: String?; var callId: String?; var name: String?; enum CodingKeys: String, CodingKey { case type, id, name; case callId = "call_id" } } }
private struct ResponseDelta: Decodable { var delta: String? }
private struct ResponseCompleted: Decodable { var response: Response?; struct Response: Decodable { var id: String?; var usage: ResponseUsage? } }
private struct ResponseUsage: Decodable { var inputTokens: Int?; var outputTokens: Int?; var totalTokens: Int?; enum CodingKeys: String, CodingKey { case inputTokens = "input_tokens"; case outputTokens = "output_tokens"; case totalTokens = "total_tokens" } }
private struct ResponseFailed: Decodable { var response: FailedResponse?; var error: Failure?; struct FailedResponse: Decodable { var error: Failure? }; struct Failure: Decodable { var message: String?; var code: String? } }
