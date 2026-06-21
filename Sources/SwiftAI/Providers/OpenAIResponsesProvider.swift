import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol CodexTransport: Sendable {
    func stream(request: [String: JSONValue], model: Model, context: AIContext, options: StreamOptions?) -> AsyncStream<AIEvent>
}

public actor CodexTransportRegistry {
    public static let shared = CodexTransportRegistry()
    private var transport: (any CodexTransport)?
    public func setTransport(_ transport: (any CodexTransport)?) { self.transport = transport }
    public func current() -> (any CodexTransport)? { transport }
}

public enum OpenAIResponsesProvider {
    public static func stream(model: Model, context: AIContext, options: StreamOptions?) -> AsyncStream<AIEvent> {
        AsyncStream { continuation in
            Task {
                do {
                    if model.api == .openAICodexResponses, let transport = await CodexTransportRegistry.shared.current() {
                        let request = buildRequestBody(model: model, context: context, options: options)
                        for await event in transport.stream(request: request, model: model, context: context, options: options) { continuation.yield(event) }
                    } else {
                        try await streamRequest(model: model, context: context, options: options, continuation: continuation)
                    }
                }
                catch { continuation.yield(.error(reason: .error, message: nil, error: error)) }
                continuation.finish()
            }
        }
    }

    public static func buildRequestBody(model: Model, context: AIContext, options: StreamOptions?) -> [String: JSONValue] {
        var input = convertInput(model: model, context: context)
        if model.api == .azureOpenAIResponses { input = AzureHelpers.applyToolCallLimit(input).messages }
        var body: [String: JSONValue] = ["model": .string(model.id), "input": .array(input), "stream": .bool(true), "store": .bool(false)]
        if let tools = context.tools, !tools.isEmpty { body["tools"] = .array(tools.map(toolJSON)) }
        if let t = options?.temperature { body["temperature"] = .number(t) }
        if let max = options?.maxTokens { body["max_output_tokens"] = .number(Double(max)) }
        if let reasoning = options?.reasoning, model.reasoning { body["reasoning"] = .object(["effort": .string(mappedThinkingEffort(model: model, effort: reasoning.rawValue)), "summary": .string(options?.reasoningSummary ?? "auto")]); body["include"] = .array([.string("reasoning.encrypted_content")]) }
        if let tier = options?.serviceTier, !tier.isEmpty { body["service_tier"] = .string(tier) }
        if let session = options?.sessionId, !session.isEmpty, options?.cacheRetention != .none { body["prompt_cache_key"] = .string(PromptCache.clampOpenAIKey(session)) }
        if options?.cacheRetention == .long, model.responsesCompat?.supportsLongCacheRetention != false { body["prompt_cache_retention"] = .string("24h") }
        return body
    }

    public static func resolveCodexURL(_ baseURL: String) -> String {
        if baseURL.isEmpty { return "https://api.openai.com/v1/codex/responses" }
        let normalized = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if normalized.hasSuffix("/codex") { return normalized + "/responses" }
        return normalized + "/codex/responses"
    }

    public static func extractCodexAccountID(_ token: String) throws -> String {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { throw AIError.provider("invalid token") }
        var payload = String(parts[1])
        while payload.count % 4 != 0 { payload += "=" }
        payload = payload.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        guard let data = Data(base64Encoded: payload), let object = try? JSONDecoder().decode([String: JSONValue].self, from: data), let auth = object["https://api.openai.com/auth"]?.objectValue, let account = auth["chatgpt_account_id"]?.stringValue, !account.isEmpty else { throw AIError.provider("no chatgpt_account_id in token") }
        return account
    }

    public static func parseAzureDeploymentNameMap(_ value: String) -> [String: String] {
        var out: [String: String] = [:]
        for entry in value.split(separator: ",") {
            let parts = entry.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            if parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty { out[parts[0]] = parts[1] }
        }
        return out
    }

    public static func normalizeAzureBaseURL(_ baseURL: String) throws -> String {
        var trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard var components = URLComponents(string: trimmed), let host = components.host, components.scheme != nil else { throw AIError.provider("invalid Azure OpenAI base URL: \(baseURL)") }
        let isAzureHost = host.hasSuffix(".openai.azure.com") || host.hasSuffix(".cognitiveservices.azure.com")
        let path = (components.path as NSString).standardizingPath
        if isAzureHost && (path.isEmpty || path == "/" || path == "/openai") {
            components.path = "/openai/v1"
            components.query = nil
        }
        guard let url = components.url?.absoluteString else { throw AIError.provider("invalid Azure OpenAI base URL: \(baseURL)") }
        return url.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    public static func resolveAzureConfig(model: Model, options: StreamOptions?) throws -> (baseURL: String, deployment: String, apiVersion: String) {
        let env = options?.env ?? [:]
        let apiVersion = options?.azureApiVersion ?? env["AZURE_OPENAI_API_VERSION"] ?? "v1"
        let mappedDeployment = parseAzureDeploymentNameMap(env["AZURE_OPENAI_DEPLOYMENT_NAME_MAP"] ?? "")[model.id]
        let deployment = options?.azureDeploymentName ?? mappedDeployment ?? model.id
        var base = options?.azureBaseUrl ?? env["AZURE_OPENAI_BASE_URL"] ?? model.baseUrl
        if base.isEmpty, let resource = options?.azureResourceName ?? env["AZURE_OPENAI_RESOURCE_NAME"], !resource.isEmpty { base = "https://\(resource).openai.azure.com/openai/v1" }
        guard !base.isEmpty else { throw AIError.provider("Azure OpenAI base URL is required") }
        base = try normalizeAzureBaseURL(base)
        return (base + "/deployments/\(deployment.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? deployment)", deployment, apiVersion)
    }

    private static func streamRequest(model: Model, context: AIContext, options: StreamOptions?, continuation: AsyncStream<AIEvent>.Continuation) async throws {
        guard let key = ProviderEnvironment.resolveAPIKey(model: model, options: options), !key.isEmpty else { throw AIError.provider("missing API key for \(model.provider.rawValue)") }
        var requestModel = model
        let resolvedModelBase = AIUtilities.isCloudflareProvider(model.provider) ? AIUtilities.resolveCloudflareBaseURL(model: model, env: options?.env) : model.baseUrl
        var base = resolvedModelBase.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var suffix = "/responses"
        if model.api == .openAICodexResponses { base = resolveCodexURL(model.baseUrl); suffix = "" }
        if model.api == .azureOpenAIResponses { let cfg = try resolveAzureConfig(model: model, options: options); base = cfg.baseURL; suffix = "/responses?api-version=\(cfg.apiVersion.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? cfg.apiVersion)"; requestModel.id = cfg.deployment }
        var body = buildRequestBody(model: requestModel, context: context, options: options)
        if let hook = options?.onPayload { body = try await hook(body, model) }
        var request = URLRequest(url: URL(string: base + suffix)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        if model.api == .openAICodexResponses {
            request.setValue(try extractCodexAccountID(key), forHTTPHeaderField: "chatgpt-account-id")
            request.setValue("pi", forHTTPHeaderField: "originator")
            request.setValue("responses=experimental", forHTTPHeaderField: "OpenAI-Beta")
        }
        if let session = options?.sessionId, !session.isEmpty {
            if model.api == .azureOpenAIResponses { for (k, v) in AIUtilities.azureSessionHeaders(session) { request.setValue(v, forHTTPHeaderField: k) } }
            else { if model.responsesCompat?.sendSessionIdHeader != false { request.setValue(session, forHTTPHeaderField: "session_id") }; request.setValue(session, forHTTPHeaderField: "x-client-request-id") }
        }
        if model.provider == .githubCopilot { for (k, v) in AIUtilities.buildCopilotDynamicHeaders(context.messages) { request.setValue(v, forHTTPHeaderField: k) } }
        for (k, v) in model.headers ?? [:] { request.setValue(v, forHTTPHeaderField: k) }
        for (k, v) in options?.headers ?? [:] { request.setValue(v, forHTTPHeaderField: k) }
        request.httpBody = try JSONEncoder().encode(body)
        let (bytes, response) = try await HTTPRetry.bytes(for: request, policy: RetryPolicy(options: options))
        guard let http = response as? HTTPURLResponse else { throw AIError.invalidResponse("non-HTTP response") }
        if let hook = options?.onResponse { await hook(HTTPResponseMetadata(status: http.statusCode, headers: http.headersDictionary), model) }
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
        var eventName = event.event
        var eventData = event.data
        if state.model.api == .azureOpenAIResponses {
            (eventName, eventData) = AzureHelpers.normalizedReasoningEventNameAndData(eventName: event.event, data: event.data)
        }
        guard let data = eventData.data(using: .utf8) else { return }
        switch eventName {
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

    private static func convertInput(model: Model, context: AIContext) -> [JSONValue] { var out: [JSONValue] = []; if let system = context.systemPrompt, !system.isEmpty { out.append(.object(["role": .string(model.reasoning ? "developer" : "system"), "content": .string(AIUtilities.sanitizeSurrogates(system))])) }; for msg in AIUtilities.transformMessages(context.messages, for: model) { if msg.role == .user { out.append(.object(["role": .string("user"), "content": .array(msg.content.compactMap(userContent))])) } else if msg.role == .assistant { out.append(.object(["type": .string("message"), "role": .string("assistant"), "content": .array(msg.content.filter { $0.type == "text" }.map { .object(["type": .string("output_text"), "text": .string($0.text ?? "")]) })])) } else { out.append(.object(["type": .string("function_call_output"), "call_id": .string(msg.toolCallId ?? ""), "output": .string(AIUtilities.sanitizeSurrogates(msg.content.compactMap(\.text).joined(separator: "\n")))])) } }; return out }
    private static func userContent(_ block: ContentBlock) -> JSONValue? { if block.type == "text" { return .object(["type": .string("input_text"), "text": .string(AIUtilities.sanitizeSurrogates(block.text ?? ""))]) }; if block.type == "image" { return .object(["type": .string("input_image"), "detail": .string("auto"), "image_url": .string("data:\(block.mimeType ?? "application/octet-stream");base64,\(block.data ?? "")")]) }; return nil }
    private static func toolJSON(_ tool: Tool) -> JSONValue { .object(["type": .string("function"), "name": .string(tool.name), "description": .string(tool.description), "parameters": tool.parameters]) }
    private static func mappedThinkingEffort(model: Model, effort: String) -> String { AIUtilities.mapThinkingLevel(model: model, level: ModelThinkingLevel(rawValue: effort) ?? .high) ?? effort }
    private static func parseJSONObject(_ text: String) -> [String: JSONValue] { PartialJSONParser.parseObject(text) ?? [:] }
}

private struct ResponsesStreamState { var model: Model; var partial: Message; var started = false; var current: (type: String, index: Int)?; var toolArgs: [Int: String] = [:]; init(model: Model) { self.model = model; var msg = Message(role: .assistant, content: []); msg.api = model.api; msg.provider = model.provider; msg.model = model.id; msg.usage = Usage(); partial = msg } }
private struct ResponseCreated: Decodable { var response: Inner?; struct Inner: Decodable { var id: String? } }
private struct ResponseOutputItemAdded: Decodable { var item: Item; struct Item: Decodable { var type: String; var id: String?; var callId: String?; var name: String?; enum CodingKeys: String, CodingKey { case type, id, name; case callId = "call_id" } } }
private struct ResponseDelta: Decodable { var delta: String? }
private struct ResponseCompleted: Decodable { var response: Response?; struct Response: Decodable { var id: String?; var usage: ResponseUsage? } }
private struct ResponseUsage: Decodable { var inputTokens: Int?; var outputTokens: Int?; var totalTokens: Int?; enum CodingKeys: String, CodingKey { case inputTokens = "input_tokens"; case outputTokens = "output_tokens"; case totalTokens = "total_tokens" } }
private struct ResponseFailed: Decodable { var response: FailedResponse?; var error: Failure?; struct FailedResponse: Decodable { var error: Failure? }; struct Failure: Decodable { var message: String?; var code: String? } }
