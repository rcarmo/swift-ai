import Foundation
import CZstd
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
        let plan = deferredToolPlan(model: model, context: context)
        var input = convertInput(model: model, context: context, deferredMarkers: plan.markers)
        if model.api == .azureOpenAIResponses { input = AzureHelpers.applyToolCallLimit(input).messages }
        var body: [String: JSONValue] = ["model": .string(model.id), "input": .array(input), "stream": .bool(true), "store": .bool(false)]
        if !plan.immediateTools.isEmpty { body["tools"] = .array(plan.immediateTools.map { toolJSON($0) }) }
        if let t = options?.temperature { body["temperature"] = .number(t) }
        if let max = AIUtilities.effectiveMaxTokens(model: model, context: context, options: options, defaultToModel: true) { body["max_output_tokens"] = .number(Double(max)) }
        if model.reasoning {
            let effort: String
            if let reasoning = options?.reasoning { effort = mappedThinkingEffort(model: model, effort: reasoning.rawValue) }
            else if model.provider == .githubCopilot { effort = "" }
            else if let off = model.thinkingLevelMap?[.off] { effort = off ?? "" }
            else { effort = "medium" }
            if !effort.isEmpty { body["reasoning"] = .object(["effort": .string(effort), "summary": .string(options?.reasoningSummary ?? "auto")]); body["include"] = .array([.string("reasoning.encrypted_content")]) }
        } else if let reasoning = options?.reasoning {
            body["reasoning"] = .object(["effort": .string(mappedThinkingEffort(model: model, effort: reasoning.rawValue)), "summary": .string(options?.reasoningSummary ?? "auto")]); body["include"] = .array([.string("reasoning.encrypted_content")])
        }
        if let tier = options?.serviceTier, !tier.isEmpty { body["service_tier"] = .string(tier) }
        let cacheRetention = ProviderEnvironment.resolveCacheRetention(options?.cacheRetention, env: options?.env)
        if let session = options?.sessionId, !session.isEmpty, cacheRetention != CacheRetention.none { body["prompt_cache_key"] = .string(PromptCache.clampOpenAIKey(session)) }
        if cacheRetention == .long, responsesSupportsLongCacheRetention(model) { body["prompt_cache_retention"] = .string("24h") }
        return body
    }

    public static func resolveCodexURL(_ baseURL: String) -> String {
        if baseURL.isEmpty { return "https://api.openai.com/v1/codex/responses" }
        let normalized = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if normalized.hasSuffix("/codex") { return normalized + "/responses" }
        return normalized + "/codex/responses"
    }

    public static func codexHeaders(apiKey: String) throws -> [String: String] {
        ["chatgpt-account-id": try extractCodexAccountID(apiKey), "originator": "pi", "OpenAI-Beta": "responses=experimental"]
    }

    public static func extractCodexEventError(_ value: JSONValue) -> String? {
        guard case .object(let obj) = value else { return nil }
        if let error = obj["error"]?.stringValue { return error }
        if case .object(let nested)? = obj["error"] { return nested["message"]?.stringValue ?? nested["error"]?.stringValue }
        if case .object(let event)? = obj["event"], case .object(let nested)? = event["error"] { return nested["message"]?.stringValue ?? nested["error"]?.stringValue }
        return nil
    }

    public static func codexHeaderTimeoutMessage(timeoutMs: Int) -> String {
        "Codex SSE response headers timed out after \(timeoutMs)ms"
    }

    public static let codexRequestCompressionZstdLevel: Int32 = 3
    public static let codexWebSocketSessionMaxAgeMs = 55 * 60 * 1000
    public static let codexUsesCachedWebSocketPool = false

    public static func shouldRecycleCodexWebSocketConnection(createdAtMs: Int64, nowMs: Int64) -> Bool {
        nowMs - createdAtMs >= Int64(codexWebSocketSessionMaxAgeMs)
    }

    public static func compressCodexRequestBodyZstd(_ data: Data) throws -> Data {
        let bound = ZSTD_compressBound(data.count)
        guard bound > 0 else { throw AIError.provider("zstd compression bound failed") }
        var output = Data(count: bound)
        let written = output.withUnsafeMutableBytes { dstPtr in
            data.withUnsafeBytes { srcPtr in
                ZSTD_compress(dstPtr.baseAddress, bound, srcPtr.baseAddress, data.count, codexRequestCompressionZstdLevel)
            }
        }
        if ZSTD_isError(written) != 0 {
            let message = ZSTD_getErrorName(written).map { String(cString: $0) } ?? "unknown"
            throw AIError.provider("zstd compression failed: \(message)")
        }
        output.removeSubrange(written..<output.count)
        return output
    }

    public static func encodeCodexSSERequestBody(_ body: [String: JSONValue]) throws -> (body: Data, contentEncoding: String) {
        let json = try JSONEncoder().encode(body)
        return (try compressCodexRequestBodyZstd(json), "zstd")
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
        guard var components = URLComponents(string: trimmed), let host = components.host, components.scheme != nil else { throw AIError.provider("Invalid Azure OpenAI base URL: \(baseURL)") }
        let isAzureHost = host.hasSuffix(".openai.azure.com") || host.hasSuffix(".cognitiveservices.azure.com") || host.hasSuffix(".ai.azure.com") || host.hasSuffix(".services.ai.azure.com")
        let path = (components.path as NSString).standardizingPath
        if isAzureHost && (path.isEmpty || path == "/" || path == "/openai" || path == "/openai/v1/responses") {
            components.path = "/openai/v1"
            components.query = nil
        }
        guard let url = components.url?.absoluteString else { throw AIError.provider("Invalid Azure OpenAI base URL: \(baseURL)") }
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
        if let timeoutMs = options?.timeoutMs, timeoutMs > 0 { request.timeoutInterval = Double(timeoutMs) / 1000.0 }
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        if model.api == .openAICodexResponses { for (k, v) in try codexHeaders(apiKey: key) { request.setValue(v, forHTTPHeaderField: k) } }
        let cacheRetention = ProviderEnvironment.resolveCacheRetention(options?.cacheRetention, env: options?.env)
        if let session = options?.sessionId, !session.isEmpty, cacheRetention != CacheRetention.none {
            if model.api == .azureOpenAIResponses { for (k, v) in AIUtilities.azureSessionHeaders(session) { request.setValue(v, forHTTPHeaderField: k) } }
            else { if model.responsesCompat?.sendSessionIdHeader != false { request.setValue(session, forHTTPHeaderField: "session_id") }; request.setValue(session, forHTTPHeaderField: "x-client-request-id") }
        }
        if model.provider == .githubCopilot { for (k, v) in AIUtilities.buildCopilotDynamicHeaders(context.messages) { request.setValue(v, forHTTPHeaderField: k) } }
        for (k, v) in model.headers ?? [:] { request.setValue(v, forHTTPHeaderField: k) }
        for (k, v) in options?.headers ?? [:] { request.setValue(v, forHTTPHeaderField: k) }
        if model.api == .openAICodexResponses {
            let encoded = try encodeCodexSSERequestBody(body)
            request.setValue(encoded.contentEncoding, forHTTPHeaderField: "Content-Encoding")
            request.httpBody = encoded.body
        } else {
            request.httpBody = try JSONEncoder().encode(body)
        }
        do {
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
        } catch let error as URLError where model.api == .openAICodexResponses && error.code == .timedOut {
            throw AIError.provider(codexHeaderTimeoutMessage(timeoutMs: options?.timeoutMs ?? Int(request.timeoutInterval * 1000)))
        }
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
        case "response.reasoning_summary_text.delta", "response.reasoning_text.delta": if let idx = state.current?.index { let raw = (try? JSONDecoder().decode(ResponseDelta.self, from: data))?.delta ?? ""; state.partial.content[idx].thinking = (state.partial.content[idx].thinking ?? "") + raw; yield(.thinkingDelta(contentIndex: idx, delta: raw, partial: state.partial)) }
        case "response.function_call_arguments.delta": if let idx = state.current?.index { let raw = (try? JSONDecoder().decode(ResponseDelta.self, from: data))?.delta ?? ""; state.toolArgs[idx, default: ""] += raw; yield(.toolCallDelta(contentIndex: idx, delta: raw, partial: state.partial)) }
        case "response.function_call_arguments.done": if let idx = state.current?.index, let raw = try? JSONDecoder().decode(ResponseArgumentsDone.self, from: data) { state.toolArgs[idx] = raw.arguments ?? state.toolArgs[idx] ?? "" }
        case "response.output_item.done": if let raw = try? JSONDecoder().decode(ResponseOutputItemDone.self, from: data) { applyReasoningItem(raw.item, state: &state, overwriteEncryptedContent: true) }; closeCurrent(state: &state, yield: yield)
        case "response.completed", "response.incomplete": if let raw = try? JSONDecoder().decode(ResponseCompleted.self, from: data) { state.sawTerminal = true; state.partial.responseId = raw.response?.id ?? state.partial.responseId; if let responseModel = raw.response?.model, !responseModel.isEmpty, responseModel != state.model.id { state.partial.responseModel = responseModel }; for item in raw.response?.output ?? [] { applyReasoningItem(item, state: &state, overwriteEncryptedContent: false) }; applyUsage(raw.response?.usage, serviceTier: raw.response?.serviceTier, state: &state); state.partial.stopReason = mapStatus(raw.response?.status ?? (eventName == "response.incomplete" ? "incomplete" : nil)); if state.partial.stopReason == .stop && state.partial.content.contains(where: { $0.type == "toolCall" }) { state.partial.stopReason = .toolUse } }
        case "response.failed": if let raw = try? JSONDecoder().decode(ResponseFailed.self, from: data) { state.sawTerminal = true; state.partial.responseId = raw.response?.id ?? state.partial.responseId; state.partial.stopReason = .error; let msg = raw.response?.error.map { "\($0.code ?? "unknown"): \($0.message ?? "")" } ?? raw.error.map { "\($0.code ?? "unknown"): \($0.message ?? "")" } ?? "response failed"; state.partial.errorMessage = msg; yield(.error(reason: .error, message: state.partial, error: AIError.provider(msg))) }
        case "error": if let raw = try? JSONDecoder().decode(ResponseAPIError.self, from: data) { state.sawTerminal = true; state.partial.stopReason = .error; state.partial.errorMessage = "API error \(raw.code ?? "unknown"): \(raw.message ?? "")"; yield(.error(reason: .error, message: state.partial, error: AIError.provider(state.partial.errorMessage ?? "API error"))) }
        default: break
        }
    }

    private static func closeCurrent(state: inout ResponsesStreamState, yield: (AIEvent) -> Void) { guard let current = state.current else { return }; let block = state.partial.content[current.index]; switch current.type { case "message": yield(.textEnd(contentIndex: current.index, content: block.text ?? "", partial: state.partial)); case "reasoning": yield(.thinkingEnd(contentIndex: current.index, content: block.thinking ?? "", partial: state.partial)); case "function_call": let args = parseJSONObject(state.toolArgs[current.index] ?? ""); state.partial.content[current.index].arguments = args; yield(.toolCallEnd(contentIndex: current.index, toolCall: state.partial.content[current.index], partial: state.partial)); default: break }; state.current = nil }
    private static func applyReasoningItem(_ item: ReasoningOutputItem, state: inout ResponsesStreamState, overwriteEncryptedContent: Bool) { guard item.type == "reasoning", let id = item.id else { return }; guard let idx = state.partial.content.firstIndex(where: { $0.type == "thinking" && ($0.id == id || $0.thinkingSignature == nil) }) else { return }; state.partial.content[idx].id = id; let existing = decodeReasoningSignature(state.partial.content[idx].thinkingSignature); var object = existing ?? item.asJSON(); if !overwriteEncryptedContent, existing?["encrypted_content"] != nil { return }; if let encrypted = item.encryptedContent, !encrypted.isEmpty { object["encrypted_content"] = .string(encrypted) }; if let encoded = encodeReasoningSignature(object) { state.partial.content[idx].thinkingSignature = encoded } }
    private static func decodeReasoningSignature(_ signature: String?) -> [String: JSONValue]? { guard let signature, let data = signature.data(using: .utf8) else { return nil }; return try? JSONDecoder().decode([String: JSONValue].self, from: data) }
    private static func encodeReasoningSignature(_ object: [String: JSONValue]) -> String? { guard let data = try? JSONEncoder().encode(object) else { return nil }; return String(data: data, encoding: .utf8) }
    private static func finish(state: inout ResponsesStreamState, yield: (AIEvent) -> Void) { if !state.started { state.started = true; yield(.start(partial: state.partial)) }; closeCurrent(state: &state, yield: yield); state.partial.timestamp = Int64(Date().timeIntervalSince1970 * 1000); if !state.sawTerminal { state.partial.stopReason = .error; state.partial.errorMessage = "OpenAI Responses stream ended before a terminal response event" }; if state.partial.stopReason == nil { state.partial.stopReason = .stop }; if state.partial.stopReason == .error { yield(.error(reason: .error, message: state.partial, error: AIError.provider(state.partial.errorMessage ?? "response failed"))) } else { yield(.done(reason: state.partial.stopReason ?? .stop, message: state.partial)) } }
    private static func applyUsage(_ raw: ResponseUsage?, serviceTier: String?, state: inout ResponsesStreamState) { guard let raw else { return }; let cached = raw.inputTokenDetails?.cachedTokens ?? 0; let cacheWrite = raw.inputTokenDetails?.cacheWriteTokens ?? 0; var u = Usage(); u.input = max(0, (raw.inputTokens ?? 0) - cached); u.output = raw.outputTokens ?? 0; u.reasoning = raw.outputTokenDetails?.reasoningTokens ?? 0; u.cacheRead = cached; u.cacheWrite = cacheWrite; u.totalTokens = raw.totalTokens ?? (u.input + u.output + u.cacheRead + u.cacheWrite); AIUtilities.applyCost(model: state.model, usage: &u); applyServiceTierMultiplier(serviceTier, model: state.model, usage: &u); state.partial.usage = u }
    private static func applyServiceTierMultiplier(_ serviceTier: String?, model: Model, usage: inout Usage) { guard let serviceTier else { return }; let multiplier: Double?; switch serviceTier { case "priority": multiplier = model.id.hasPrefix("gpt-5.5") ? 2.5 : 2.0; case "flex": multiplier = 0.5; default: multiplier = nil }; guard let multiplier else { return }; usage.cost.input *= multiplier; usage.cost.output *= multiplier; usage.cost.cacheRead *= multiplier; usage.cost.cacheWrite *= multiplier; usage.cost.total *= multiplier }

    private static func convertInput(model: Model, context: AIContext, deferredMarkers: [Int64: [Tool]] = [:]) -> [JSONValue] {
        var out: [JSONValue] = []
        if let system = context.systemPrompt, !system.isEmpty { out.append(.object(["role": .string(model.reasoning ? "developer" : "system"), "content": .string(AIUtilities.sanitizeSurrogates(system))])) }
        for (msgIndex, msg) in AIUtilities.transformMessages(context.messages, for: model).enumerated() {
            switch msg.role {
            case .user:
                out.append(.object(["role": .string("user"), "content": .array(msg.content.compactMap(userContent))]))
            case .assistant:
                out.append(contentsOf: assistantItems(msg, model: model, messageIndex: msgIndex))
            case .toolResult:
                if let tools = deferredMarkers[msg.timestamp], !tools.isEmpty {
                    let callID = "ts_" + AIUtilities.shortHash("\(msg.timestamp):\(tools.map(\.name).joined(separator: ","))")
                    out.append(.object(["type": .string("tool_search_call"), "call_id": .string(callID), "execution": .string("client"), "status": .string("completed")]))
                    out.append(.object(["type": .string("tool_search_output"), "call_id": .string(callID), "execution": .string("client"), "status": .string("completed"), "tools": .array(tools.map { toolJSON($0, deferred: true) })]))
                }
                let callID = (msg.toolCallId ?? "").split(separator: "|").first.map(String.init) ?? (msg.toolCallId ?? "")
                out.append(.object(["type": .string("function_call_output"), "call_id": .string(normalizeResponsesIDPart(callID)), "output": toolResultOutput(msg)]))
            }
        }
        return out
    }

    private static func assistantItems(_ msg: Message, model: Model, messageIndex: Int) -> [JSONValue] {
        var items: [JSONValue] = []
        var textIndex = 0
        for block in msg.content {
            switch block.type {
            case "thinking":
                if let sig = block.thinkingSignature, !sig.isEmpty, let data = sig.data(using: .utf8), let value = try? JSONDecoder().decode(JSONValue.self, from: data) {
                    items.append(value)
                } else {
                    let fallback = "rs_pi_\(messageIndex)_\(items.count)"
                    items.append(.object(["type": .string("reasoning"), "id": .string(fallback), "summary": .array([.object(["type": .string("summary_text"), "text": .string(AIUtilities.sanitizeSurrogates(block.thinking ?? ""))])])]))
                }
            case "text":
                let fallback = textIndex == 0 ? "msg_pi_\(messageIndex)" : "msg_pi_\(messageIndex)_\(textIndex)"
                var item: [String: JSONValue] = ["type": .string("message"), "id": .string(fallback), "role": .string("assistant"), "content": .array([.object(["type": .string("output_text"), "text": .string(AIUtilities.sanitizeSurrogates(block.text ?? ""))])]), "status": .string("completed")]
                if let sig = block.textSignature, let data = sig.data(using: .utf8), let object = try? JSONDecoder().decode([String: JSONValue].self, from: data) {
                    item["id"] = .string(object["id"]?.stringValue ?? fallback)
                    if let phase = object["phase"] { item["phase"] = phase }
                }
                textIndex += 1
                items.append(.object(item))
            case "toolCall":
                let rawID = block.id ?? ""
                let parts = rawID.split(separator: "|", maxSplits: 1).map(String.init)
                let callID = normalizeResponsesIDPart(parts.first ?? rawID)
                var item: [String: JSONValue] = ["type": .string("function_call"), "call_id": .string(callID), "name": .string(block.name ?? ""), "arguments": .string(jsonString(block.arguments ?? [:]))]
                if parts.count == 2 { item["id"] = .string(normalizeResponsesItemID(parts[1])) }
                items.append(.object(item))
            default:
                break
            }
        }
        return items
    }
    private static func userContent(_ block: ContentBlock) -> JSONValue? { if block.type == "text" { return .object(["type": .string("input_text"), "text": .string(AIUtilities.sanitizeSurrogates(block.text ?? ""))]) }; if block.type == "image" { return .object(["type": .string("input_image"), "detail": .string("auto"), "image_url": .string("data:\(block.mimeType ?? "application/octet-stream");base64,\(block.data ?? "")")]) }; return nil }
    private static func toolResultOutput(_ msg: Message) -> JSONValue {
        let parts = msg.content.compactMap(userContent)
        if parts.contains(where: { if case .object(let obj) = $0 { return obj["type"] == .string("input_image") }; return false }) { return .array(parts) }
        let text = msg.content.compactMap(\.text).joined(separator: "\n")
        return .string(AIUtilities.sanitizeSurrogates(text.isEmpty ? "(no tool output)" : text))
    }
    private static func normalizeResponsesIDPart(_ value: String) -> String { let filtered = value.map { ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") ? $0 : "_" }.reduce("", { $0 + String($1) }); return filtered.count <= 64 ? filtered : "id_" + AIUtilities.shortHash(filtered) }
    private static func normalizeResponsesItemID(_ value: String) -> String { let raw = value.hasPrefix("fc_") ? String(value.dropFirst(3)) : value; let filtered = raw.filter { $0.isLetter || $0.isNumber }; if ("fc_" + filtered).count <= 64 { return "fc_" + filtered }; return "fc_" + AIUtilities.shortHash(raw) }
    private static func jsonString(_ object: [String: JSONValue]) -> String { guard let data = try? JSONEncoder().encode(object) else { return "{}" }; return String(data: data, encoding: .utf8) ?? "{}" }
    private static func toolJSON(_ tool: Tool, deferred: Bool = false) -> JSONValue { var obj: [String: JSONValue] = ["type": .string("function"), "name": .string(tool.name), "description": .string(tool.description), "parameters": tool.parameters]; if deferred { obj["defer_loading"] = .bool(true) }; return .object(obj) }
    private static func deferredToolPlan(model: Model, context: AIContext) -> (immediateTools: [Tool], markers: [Int64: [Tool]]) {
        let tools = context.tools ?? []
        guard supportsToolSearch(model), !tools.isEmpty else { return (tools, [:]) }
        let byName = Dictionary(uniqueKeysWithValues: tools.map { ($0.name.lowercased(), $0) })
        var used = Set<String>()
        var deferred = Set<String>()
        var markers: [Int64: [Tool]] = [:]
        for message in context.messages.sorted(by: { $0.timestamp < $1.timestamp }) {
            for block in message.content where block.type == "toolCall" { used.insert((block.name ?? "").lowercased()) }
            if message.role == .toolResult {
                let marked = (message.addedToolNames ?? []).compactMap { raw -> Tool? in
                    let key = raw.lowercased(); guard let tool = byName[key], !used.contains(key) else { return nil }; deferred.insert(key); return tool
                }
                if !marked.isEmpty { markers[message.timestamp] = marked }
            }
        }
        if deferred.count == tools.count { deferred.remove(deferred.sorted().first ?? "") }
        return (tools.filter { !deferred.contains($0.name.lowercased()) }, markers)
    }
    private static func supportsToolSearch(_ model: Model) -> Bool { if let forced = model.responsesCompat?.supportsToolSearch { return forced }; guard model.api == .openAIResponses || model.api == .openAICodexResponses else { return false }; return model.id == "gpt-5.4" || model.id.hasPrefix("gpt-5.4-") == false && model.id == "gpt-5.4" }
    private static func mappedThinkingEffort(model: Model, effort: String) -> String { AIUtilities.mapThinkingLevel(model: model, level: ModelThinkingLevel(rawValue: effort) ?? .high) ?? effort }
    private static func parseJSONObject(_ text: String) -> [String: JSONValue] { PartialJSONParser.parseObject(text) ?? [:] }
    private static func mapStatus(_ status: String?) -> StopReason { switch status { case "incomplete": return .length; case "failed", "cancelled": return .error; default: return .stop } }
    private static func responsesSupportsLongCacheRetention(_ model: Model) -> Bool {
        if AIUtilities.isCloudflareProvider(model.provider) { return false }
        return model.responsesCompat?.supportsLongCacheRetention != false
    }
}

private struct ResponsesStreamState { var model: Model; var partial: Message; var started = false; var sawTerminal = false; var current: (type: String, index: Int)?; var toolArgs: [Int: String] = [:]; init(model: Model) { self.model = model; var msg = Message(role: .assistant, content: []); msg.api = model.api; msg.provider = model.provider; msg.model = model.id; msg.usage = Usage(); partial = msg } }
private struct ResponseCreated: Decodable { var response: Inner?; struct Inner: Decodable { var id: String? } }
private struct ResponseOutputItemAdded: Decodable { var item: Item; struct Item: Decodable { var type: String; var id: String?; var callId: String?; var name: String?; enum CodingKeys: String, CodingKey { case type, id, name; case callId = "call_id" } } }
private struct ResponseOutputItemDone: Decodable { var item: ReasoningOutputItem }
private struct ReasoningOutputItem: Decodable { var type: String; var id: String?; var summary: JSONValue?; var encryptedContent: String?; enum CodingKeys: String, CodingKey { case type, id, summary; case encryptedContent = "encrypted_content" }; func asJSON() -> [String: JSONValue] { var object: [String: JSONValue] = ["type": .string(type)]; if let id { object["id"] = .string(id) }; if let summary { object["summary"] = summary }; if let encryptedContent { object["encrypted_content"] = .string(encryptedContent) }; return object } }
private struct ResponseDelta: Decodable { var delta: String? }
private struct ResponseArgumentsDone: Decodable { var arguments: String? }
private struct ResponseCompleted: Decodable { var response: Response?; struct Response: Decodable { var id: String?; var status: String?; var model: String?; var serviceTier: String?; var usage: ResponseUsage?; var output: [ReasoningOutputItem]?; enum CodingKeys: String, CodingKey { case id, status, model, usage, output; case serviceTier = "service_tier" } } }
private struct ResponseUsage: Decodable { var inputTokens: Int?; var outputTokens: Int?; var totalTokens: Int?; var inputTokenDetails: InputTokenDetails?; var outputTokenDetails: OutputTokenDetails?; enum CodingKeys: String, CodingKey { case inputTokens = "input_tokens"; case outputTokens = "output_tokens"; case totalTokens = "total_tokens"; case inputTokenDetails = "input_tokens_details"; case outputTokenDetails = "output_tokens_details" }; struct InputTokenDetails: Decodable { var cachedTokens: Int?; var cacheWriteTokens: Int?; enum CodingKeys: String, CodingKey { case cachedTokens = "cached_tokens"; case cacheWriteTokens = "cache_write_tokens" } }; struct OutputTokenDetails: Decodable { var reasoningTokens: Int?; enum CodingKeys: String, CodingKey { case reasoningTokens = "reasoning_tokens" } } }
private struct ResponseFailed: Decodable { var response: FailedResponse?; var error: Failure?; struct FailedResponse: Decodable { var id: String?; var error: Failure? }; struct Failure: Decodable { var message: String?; var code: String? } }
private struct ResponseAPIError: Decodable { var code: String?; var message: String? }
