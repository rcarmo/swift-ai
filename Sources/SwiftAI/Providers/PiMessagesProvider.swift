import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum PiMessagesProvider {
    public static func stream(model: Model, context: AIContext, options: StreamOptions?) -> AsyncStream<AIEvent> {
        AsyncStream { continuation in
            Task {
                do { try await streamRequest(model: model, context: context, options: options, continuation: continuation) }
                catch { continuation.yield(errorEvent(model: model, error: error, aborted: false)); continuation.finish() }
            }
        }
    }

    public static func buildRequestBody(model: Model, context: AIContext, options: StreamOptions?) -> [String: JSONValue] {
        var opts: [String: JSONValue] = [:]
        if let temperature = options?.temperature { opts["temperature"] = .number(temperature) }
        if let maxTokens = options?.maxTokens { opts["maxTokens"] = .number(Double(maxTokens)) }
        if let reasoning = options?.reasoning { opts["reasoning"] = .string(reasoning.rawValue) }
        let retention = resolveCacheRetention(options?.cacheRetention, env: options?.env)
        if let retention { opts["cacheRetention"] = .string(retention.rawValue) }
        if let session = options?.sessionId, !session.isEmpty { opts["sessionId"] = .string(session) }
        if let toolChoice = options?.toolChoice { opts["toolChoice"] = toolChoice }
        return ["model": .string(model.id), "context": contextJSON(context), "options": .object(opts)]
    }

    public static func buildRequestURL(model: Model, options: StreamOptions?) throws -> URL {
        let base = model.baseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard var components = URLComponents(string: base + "/messages") else { throw AIError.invalidResponse("invalid pi-messages base URL") }
        if options?.debug == true { components.queryItems = [URLQueryItem(name: "debug", value: "1")] }
        guard let url = components.url else { throw AIError.invalidResponse("invalid pi-messages base URL") }
        return url
    }

    public static func responseFailureEvent(model: Model, url: String, status: Int, statusText: String, body: String) -> AIEvent {
        errorEvent(model: model, error: PiMessagesResponseError(model: model, url: url, status: status, statusText: statusText, body: body), aborted: false)
    }

    public static func processSSEText(_ text: String, model: Model) -> [AIEvent] {
        var converter = EventConverter(model: model)
        var events: [AIEvent] = []
        for event in SSEParser().parse(text) {
            guard let data = event.data.data(using: .utf8), let object = try? JSONDecoder().decode([String: JSONValue].self, from: data) else { continue }
            if let converted = converter.convert(object) { events.append(converted) }
        }
        return events
    }

    private static func streamRequest(model: Model, context: AIContext, options: StreamOptions?, continuation: AsyncStream<AIEvent>.Continuation) async throws {
        guard let key = ProviderEnvironment.resolveAPIKey(model: model, options: options), !key.isEmpty else { throw AIError.provider("No API key provided for provider \"\(model.provider.rawValue)\"") }
        let url = try buildRequestURL(model: model, options: options)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (k, v) in options?.headers ?? [:] { request.setValue(v, forHTTPHeaderField: k) }
        var payload = buildRequestBody(model: model, context: context, options: options)
        if let hook = options?.onPayload { payload = try await hook(payload, model) }
        request.httpBody = try JSONEncoder().encode(JSONValue.object(payload))
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIError.invalidResponse("missing HTTP response") }
        if let hook = options?.onResponse { await hook(HTTPResponseMetadata(status: http.statusCode, headers: http.headersDictionary), model) }
        let bodyText = String(data: data, encoding: .utf8) ?? ""
        guard (200..<300).contains(http.statusCode) else { throw PiMessagesResponseError(model: model, url: url.absoluteString, status: http.statusCode, statusText: HTTPURLResponse.localizedString(forStatusCode: http.statusCode), body: bodyText) }
        let text = bodyText
        var sawTerminal = false
        for event in processSSEText(text, model: model) {
            continuation.yield(event)
            if case .done = event { sawTerminal = true }
            if case .error = event { sawTerminal = true }
            if sawTerminal { continuation.finish(); return }
        }
        throw AIError.provider("\(model.provider.rawValue) stream ended without a terminal event")
    }

    private static func resolveCacheRetention(_ cacheRetention: CacheRetention?, env: ProviderEnv?) -> CacheRetention? {
        if let cacheRetention { return cacheRetention }
        return ProviderEnvironment.value("PI_CACHE_RETENTION", env: env) == "long" ? .long : nil
    }

    private static func errorEvent(model: Model, error: Error, aborted: Bool) -> AIEvent {
        var message = Message(role: .assistant, content: [])
        message.api = model.api; message.provider = model.provider; message.model = model.id
        message.usage = Usage(); message.stopReason = aborted ? .aborted : .error; message.errorMessage = error.localizedDescription
        if !aborted, let responseError = error as? PiMessagesResponseError {
            message.diagnostics = [AssistantMessageDiagnostic(type: "pi_messages_response_failure", timestamp: 0, error: DiagnosticError(message: responseError.localizedDescription), details: responseError.diagnosticDetails)]
        }
        return .error(reason: message.stopReason ?? .error, message: message, error: error)
    }

    private static func contextJSON(_ context: AIContext) -> JSONValue {
        guard let data = try? JSONEncoder().encode(context), let value = try? JSONDecoder().decode(JSONValue.self, from: data) else { return .object([:]) }
        return value
    }
}

private struct PiMessagesResponseError: Error, LocalizedError, Sendable {
    let model: Model
    let url: String
    let status: Int
    let statusText: String
    let body: String

    var localizedDescription: String { errorDescription ?? String(describing: self) }
    var errorDescription: String? {
        if let parsed = parseErrorBody(), let message = parsed.message {
            let codeSuffix = parsed.code.map { " (\($0))" } ?? ""
            return "\(status) \(statusText): \(message)\(codeSuffix)"
        }
        return "\(status) \(statusText): \(truncate(body))"
    }

    var diagnosticDetails: [String: JSONValue] {
        var details: [String: JSONValue] = [
            "version": .number(1),
            "provider": .string(model.provider.rawValue),
            "model": .string(model.id),
            "url": .string(url),
            "status": .number(Double(status)),
            "statusText": .string(statusText),
            "timestampMs": .number(0),
        ]
        if let parsed = parseErrorBody() {
            var error: [String: JSONValue] = [:]
            if let message = parsed.message { error["message"] = .string(message) }
            if let code = parsed.code { error["code"] = .string(code) }
            details["error"] = .object(error)
        } else {
            details["body"] = .string(truncate(body))
        }
        return details
    }

    private func parseErrorBody() -> (message: String?, code: String?)? {
        guard let data = body.data(using: .utf8), let object = try? JSONDecoder().decode([String: JSONValue].self, from: data), case .object(let error)? = object["error"] else { return nil }
        return (error["message"]?.stringValue, error["code"]?.stringValue)
    }

    private func truncate(_ value: String) -> String { value.count > 8192 ? String(value.prefix(8192)) + "…" : value }
}

private struct EventConverter {
    var model: Model
    var partial: Message
    var toolJSON: [Int: String] = [:]

    init(model: Model) {
        self.model = model
        var msg = Message(role: .assistant, content: [])
        msg.api = model.api; msg.provider = model.provider; msg.model = model.id; msg.usage = Usage(); msg.stopReason = .stop
        partial = msg
    }

    mutating func convert(_ object: [String: JSONValue]) -> AIEvent? {
        guard let type = object["type"]?.stringValue else { return nil }
        switch type {
        case "start": return .start(partial: partial)
        case "text_start": let idx = index(object); ensure(idx); partial.content[idx] = ContentBlock(type: "text", text: ""); return .textStart(contentIndex: idx, partial: partial)
        case "text_delta": let idx = index(object); let delta = object["delta"]?.stringValue ?? ""; ensure(idx); partial.content[idx].text = (partial.content[idx].text ?? "") + delta; return .textDelta(contentIndex: idx, delta: delta, partial: partial)
        case "text_end": let idx = index(object); ensure(idx); let text = object["content"]?.stringValue ?? ""; partial.content[idx].text = text; partial.content[idx].textSignature = object["contentSignature"]?.stringValue; return .textEnd(contentIndex: idx, content: text, partial: partial)
        case "thinking_start": let idx = index(object); ensure(idx); partial.content[idx] = ContentBlock(type: "thinking", thinking: ""); return .thinkingStart(contentIndex: idx, partial: partial)
        case "thinking_delta": let idx = index(object); let delta = object["delta"]?.stringValue ?? ""; ensure(idx); partial.content[idx].thinking = (partial.content[idx].thinking ?? "") + delta; return .thinkingDelta(contentIndex: idx, delta: delta, partial: partial)
        case "thinking_end": let idx = index(object); ensure(idx); let text = object["content"]?.stringValue ?? ""; partial.content[idx].thinking = text; partial.content[idx].thinkingSignature = object["contentSignature"]?.stringValue; partial.content[idx].redacted = object["redacted"]?.boolValue; return .thinkingEnd(contentIndex: idx, content: text, partial: partial)
        case "toolcall_start": let idx = index(object); ensure(idx); partial.content[idx] = ContentBlock(type: "toolCall", id: object["id"]?.stringValue, name: object["toolName"]?.stringValue, arguments: [:]); toolJSON[idx] = ""; return .toolCallStart(contentIndex: idx, partial: partial)
        case "toolcall_delta": let idx = index(object); let delta = object["delta"]?.stringValue ?? ""; toolJSON[idx, default: ""] += delta; ensure(idx); partial.content[idx].arguments = PartialJSONParser.parseObject(toolJSON[idx] ?? "") ?? [:]; return .toolCallDelta(contentIndex: idx, delta: delta, partial: partial)
        case "toolcall_end": let idx = index(object); ensure(idx); if case .object(let raw)? = object["toolCall"] { partial.content[idx].id = raw["id"]?.stringValue ?? partial.content[idx].id; partial.content[idx].name = raw["name"]?.stringValue ?? partial.content[idx].name; partial.content[idx].arguments = raw["arguments"]?.objectValue ?? partial.content[idx].arguments }; toolJSON[idx] = nil; return .toolCallEnd(contentIndex: idx, toolCall: partial.content[idx], partial: partial)
        case "done": partial.stopReason = StopReason(rawValue: object["reason"]?.stringValue ?? "stop") ?? .stop; partial.usage = decodeUsage(object["usage"]); partial.responseId = object["responseId"]?.stringValue; appendRewrite(object["rewrite"]); return .done(reason: partial.stopReason ?? .stop, message: partial)
        case "error": partial.stopReason = StopReason(rawValue: object["reason"]?.stringValue ?? "error") ?? .error; partial.usage = decodeUsage(object["usage"]); partial.errorMessage = object["errorMessage"]?.stringValue; partial.responseId = object["responseId"]?.stringValue; appendRewrite(object["rewrite"]); return .error(reason: partial.stopReason ?? .error, message: partial, error: AIError.provider(partial.errorMessage ?? "pi-messages error"))
        default: return nil
        }
    }

    mutating private func ensure(_ index: Int) { while partial.content.count <= index { partial.content.append(ContentBlock(type: "text")) } }
    private func index(_ object: [String: JSONValue]) -> Int { Int(object["contentIndex"]?.doubleValue ?? 0) }
    private func decodeUsage(_ value: JSONValue?) -> Usage {
        guard case .object(let raw)? = value else { return Usage() }
        var usage = Usage()
        usage.input = int(raw["input"])
        usage.output = int(raw["output"])
        usage.cacheRead = int(raw["cacheRead"])
        usage.cacheWrite = int(raw["cacheWrite"])
        usage.cacheWrite1h = raw["cacheWrite1h"].map(int)
        usage.reasoning = int(raw["reasoning"])
        usage.totalTokens = int(raw["totalTokens"])
        if case .object(let cost)? = raw["cost"] {
            usage.cost.input = double(cost["input"])
            usage.cost.output = double(cost["output"])
            usage.cost.cacheRead = double(cost["cacheRead"])
            usage.cost.cacheWrite = double(cost["cacheWrite"])
            usage.cost.total = double(cost["total"])
        }
        return usage
    }
    private func int(_ value: JSONValue?) -> Int { Int(double(value)) }
    private func double(_ value: JSONValue?) -> Double {
        switch value {
        case .number(let number): return number
        case .string(let string): return Double(string) ?? 0
        default: return 0
        }
    }
    mutating private func appendRewrite(_ value: JSONValue?) { guard let value else { return }; let diag = AssistantMessageDiagnostic(type: "pi_messages_rewrite", timestamp: 0, error: DiagnosticError(message: "rewrite"), details: value.objectValue); partial.diagnostics = (partial.diagnostics ?? []) + [diag] }
}
