import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum GoogleGenerativeAIProvider {
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
        var body: [String: JSONValue] = [:]
        if let system = context.systemPrompt, !system.isEmpty { body["systemInstruction"] = .object(["parts": .array([.object(["text": .string(AIUtilities.sanitizeSurrogates(system))])])]) }
        body["contents"] = .array(convertMessages(model: model, messages: AIUtilities.transformMessages(context.messages, for: model)))
        var gen: [String: JSONValue] = [:]
        if let t = options?.temperature { gen["temperature"] = .number(t) }
        if let max = AIUtilities.effectiveMaxTokens(model: model, context: context, options: options, defaultToModel: true) { gen["maxOutputTokens"] = .number(Double(max)) }
        if model.reasoning {
            if let reasoning = options?.reasoning {
                let mapped = mappedThinkingEffort(model: model, effort: reasoning.rawValue)
                if usesThinkingLevel(model) { gen["thinkingConfig"] = .object(["includeThoughts": .bool(true), "thinkingLevel": .string(googleThinkingLevel(mapped, model: model))]) }
                else { gen["thinkingConfig"] = .object(["includeThoughts": .bool(true), "thinkingBudget": .number(Double(googleBudget(mapped)))]) }
            } else {
                gen["thinkingConfig"] = disabledThinkingConfig(model: model)
            }
        }
        if !gen.isEmpty { body["generationConfig"] = .object(gen) }
        if let tools = context.tools, let converted = convertTools(tools) { body["tools"] = converted }
        return body
    }

    public static func buildStreamURL(model: Model, apiKey: String, options: StreamOptions?) throws -> String {
        if model.api == .googleVertex {
            let project = options?.project ?? options?.env?["GOOGLE_CLOUD_PROJECT"] ?? options?.env?["GCLOUD_PROJECT"] ?? ProcessInfo.processInfo.environment["GOOGLE_CLOUD_PROJECT"] ?? ProcessInfo.processInfo.environment["GCLOUD_PROJECT"]
            let location = options?.location ?? options?.env?["GOOGLE_CLOUD_LOCATION"] ?? ProcessInfo.processInfo.environment["GOOGLE_CLOUD_LOCATION"]
            guard let project, !project.isEmpty else { throw AIError.provider("Vertex AI requires a project ID") }
            guard let location, !location.isEmpty else { throw AIError.provider("Vertex AI requires a location") }
            let base = (model.baseUrl.isEmpty ? "https://{location}-aiplatform.googleapis.com" : model.baseUrl).replacingOccurrences(of: "{location}", with: location).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let resourcePath = base.contains("/v1/projects/") ? "" : "/v1/projects/\(escapePathSegment(project))/locations/\(escapePathSegment(location))"
            var url = "\(base)\(resourcePath)/publishers/google/models/\(escapePathSegment(model.id)):streamGenerateContent?alt=sse"
            if !isVertexADCMarker(apiKey) { url += "&key=\(apiKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? apiKey)" }
            return url
        }
        let base = (model.baseUrl.isEmpty ? "https://generativelanguage.googleapis.com/v1beta" : model.baseUrl).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return "\(base)/models/\(escapePathSegment(model.id)):streamGenerateContent?alt=sse&key=\(apiKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? apiKey)"
    }

    private static func streamRequest(model: Model, context: AIContext, options: StreamOptions?, continuation: AsyncStream<AIEvent>.Continuation) async throws {
        guard let key = ProviderEnvironment.resolveAPIKey(model: model, options: options), !key.isEmpty else { throw AIError.provider("missing API key for \(model.provider.rawValue)") }
        var request = URLRequest(url: URL(string: try buildStreamURL(model: model, apiKey: key, options: options))!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (k, v) in model.headers ?? [:] { request.setValue(v, forHTTPHeaderField: k) }
        for (k, v) in options?.headers ?? [:] { request.setValue(v, forHTTPHeaderField: k) }
        var payload = buildRequestBody(model: model, context: context, options: options)
        if let hook = options?.onPayload { payload = try await hook(payload, model) }
        request.httpBody = try JSONEncoder().encode(payload)
        let (bytes, response) = try await HTTPRetry.bytes(for: request, policy: RetryPolicy(options: options))
        guard let http = response as? HTTPURLResponse else { throw AIError.invalidResponse("non-HTTP response") }
        if let hook = options?.onResponse { await hook(HTTPResponseMetadata(status: http.statusCode, headers: http.headersDictionary), model) }
        guard (200..<300).contains(http.statusCode) else { throw AIError.apiError(status: http.statusCode, body: "HTTP \(http.statusCode)") }
        var state = GoogleStreamState(model: model)
        var buffer = ""
        for try await byte in bytes {
            buffer += String(decoding: [byte], as: UTF8.self)
            while let range = buffer.range(of: "\n\n") ?? buffer.range(of: "\r\n\r\n") {
                let frame = String(buffer[..<range.lowerBound])
                buffer.removeSubrange(..<range.upperBound)
                for event in SSEParser().parse(frame + "\n\n") { process(data: event.data, state: &state) { continuation.yield($0) } }
            }
        }
        finish(state: &state) { continuation.yield($0) }
    }

    public static func processSSEText(_ text: String, model: Model) -> [AIEvent] {
        var events: [AIEvent] = []
        var state = GoogleStreamState(model: model)
        for event in SSEParser().parse(text) where !event.data.isEmpty { process(data: event.data, state: &state) { events.append($0) } }
        finish(state: &state) { events.append($0) }
        return events
    }

    private static func process(data: String, state: inout GoogleStreamState, yield: (AIEvent) -> Void) {
        if !state.started { state.started = true; yield(.start(partial: state.partial)) }
        if data == "[DONE]" { return }
        guard let raw = data.data(using: .utf8), let chunk = try? JSONDecoder().decode(GeminiChunk.self, from: raw) else { return }
        if let id = chunk.responseId { state.partial.responseId = id }
        if let usage = chunk.usageMetadata { var u = Usage(); u.input = max(0, (usage.promptTokenCount ?? 0) - (usage.cachedContentTokenCount ?? 0)); u.output = (usage.candidatesTokenCount ?? 0) + (usage.thoughtsTokenCount ?? 0); u.reasoning = usage.thoughtsTokenCount ?? 0; u.cacheRead = usage.cachedContentTokenCount ?? 0; u.totalTokens = usage.totalTokenCount ?? (u.input + u.output + u.cacheRead); AIUtilities.applyCost(model: state.model, usage: &u); state.partial.usage = u }
        guard let candidate = chunk.candidates?.first else { return }
        for part in candidate.content?.parts ?? [] {
            if let text = part.text, !text.isEmpty {
                let isThinking = part.thought == true
                if state.current?.type != (isThinking ? "thinking" : "text") { closeCurrent(state: &state, yield: yield); state.partial.content.append(ContentBlock(type: isThinking ? "thinking" : "text")); state.current = (isThinking ? "thinking" : "text", state.partial.content.count - 1); if isThinking { yield(.thinkingStart(contentIndex: state.partial.content.count - 1, partial: state.partial)) } else { yield(.textStart(contentIndex: state.partial.content.count - 1, partial: state.partial)) } }
                guard let current = state.current else { continue }
                if isThinking { state.partial.content[current.index].thinking = (state.partial.content[current.index].thinking ?? "") + text; state.partial.content[current.index].thinkingSignature = retainThoughtSignature(existing: state.partial.content[current.index].thinkingSignature, incoming: part.thoughtSignature); yield(.thinkingDelta(contentIndex: current.index, delta: text, partial: state.partial)) }
                else { state.partial.content[current.index].text = (state.partial.content[current.index].text ?? "") + text; state.partial.content[current.index].textSignature = retainThoughtSignature(existing: state.partial.content[current.index].textSignature, incoming: part.thoughtSignature); yield(.textDelta(contentIndex: current.index, delta: text, partial: state.partial)) }
            }
            if let call = part.functionCall { closeCurrent(state: &state, yield: yield); let id = call.id ?? "\(call.name)_\(Int(Date().timeIntervalSince1970 * 1000))"; let block = ContentBlock(type: "toolCall", id: id, name: call.name, arguments: call.args, thoughtSignature: part.thoughtSignature); state.partial.content.append(block); let idx = state.partial.content.count - 1; yield(.toolCallStart(contentIndex: idx, partial: state.partial)); yield(.toolCallDelta(contentIndex: idx, delta: jsonString(call.args ?? [:]), partial: state.partial)); yield(.toolCallEnd(contentIndex: idx, toolCall: block, partial: state.partial)) }
        }
        if let finish = candidate.finishReason { state.partial.stopReason = mapFinishReason(finish); if state.partial.content.contains(where: { $0.type == "toolCall" }) { state.partial.stopReason = .toolUse } }
    }

    private static func closeCurrent(state: inout GoogleStreamState, yield: (AIEvent) -> Void) { guard let current = state.current else { return }; let block = state.partial.content[current.index]; if current.type == "text" { yield(.textEnd(contentIndex: current.index, content: block.text ?? "", partial: state.partial)) } else { yield(.thinkingEnd(contentIndex: current.index, content: block.thinking ?? "", partial: state.partial)) }; state.current = nil }
    private static func finish(state: inout GoogleStreamState, yield: (AIEvent) -> Void) { if !state.started { state.started = true; yield(.start(partial: state.partial)) }; closeCurrent(state: &state, yield: yield); state.partial.timestamp = Int64(Date().timeIntervalSince1970 * 1000); if state.partial.stopReason == nil { state.partial.stopReason = .stop }; yield(.done(reason: state.partial.stopReason ?? .stop, message: state.partial)) }

    public static func convertMessages(model: Model, messages: [Message]) -> [JSONValue] {
        var out: [JSONValue] = []
        var pendingFunctionResponses: [JSONValue] = []
        func flushFunctionResponses() {
            if pendingFunctionResponses.isEmpty { return }
            out.append(.object(["role": .string("user"), "parts": .array(pendingFunctionResponses)]))
            pendingFunctionResponses.removeAll()
        }
        for msg in messages {
            let sameModel = msg.provider == model.provider && msg.api == model.api && msg.model == model.id
            if msg.role == .toolResult {
                let text = AIUtilities.sanitizeSurrogates(msg.content.compactMap(\.text).joined(separator: "\n"))
                let imageParts = msg.content.compactMap { block -> JSONValue? in
                    guard block.type == "image", let data = block.data, let mime = block.mimeType else { return nil }
                    return .object(["inlineData": .object(["mimeType": .string(mime), "data": .string(data)])])
                }
                if !imageParts.isEmpty && !supportsMultimodalFunctionResponse(model.id) {
                    flushFunctionResponses()
                    out.append(.object(["role": .string("user"), "parts": .array([.object(["text": .string("Tool result image:")])] + imageParts)]))
                    continue
                }
                let response: [String: JSONValue]
                if msg.isError == true { response = ["error": .string(text)] }
                else if !text.isEmpty { response = ["output": .string(text)] }
                else if !imageParts.isEmpty { response = ["output": .string("(see attached image)")] }
                else { response = [:] }
                var functionResponse: [String: JSONValue] = ["name": .string(msg.toolName ?? ""), "response": .object(response), "id": .string(normalizeToolCallID(msg.toolCallId ?? ""))]
                if !imageParts.isEmpty { functionResponse["parts"] = .array(imageParts) }
                pendingFunctionResponses.append(.object(["functionResponse": .object(functionResponse)]))
                continue
            }
            flushFunctionResponses()
            var parts: [JSONValue] = []
            for block in msg.content {
                if block.type == "text" {
                    var part: [String: JSONValue] = ["text": .string(AIUtilities.sanitizeSurrogates(block.text ?? ""))]
                    if sameModel, let sig = block.textSignature, isValidBase64Signature(sig) { part["thoughtSignature"] = .string(sig) }
                    parts.append(.object(part))
                } else if block.type == "thinking" {
                    var part: [String: JSONValue] = ["text": .string(AIUtilities.sanitizeSurrogates(block.thinking ?? "")), "thought": .bool(true)]
                    if sameModel, let sig = block.thinkingSignature, isValidBase64Signature(sig) { part["thoughtSignature"] = .string(sig) }
                    parts.append(.object(part))
                } else if block.type == "image" {
                    parts.append(.object(["inlineData": .object(["mimeType": .string(block.mimeType ?? "application/octet-stream"), "data": .string(block.data ?? "")])]))
                } else if block.type == "toolCall" {
                    let fc: [String: JSONValue] = ["name": .string(block.name ?? ""), "args": .object(block.arguments ?? [:]), "id": .string(normalizeToolCallID(block.id ?? ""))]
                    var part: [String: JSONValue] = ["functionCall": .object(fc)]
                    if sameModel, let sig = block.thoughtSignature, isValidBase64Signature(sig) { part["thoughtSignature"] = .string(sig) }
                    parts.append(.object(part))
                }
            }
            if !parts.isEmpty { out.append(.object(["role": .string(msg.role == .assistant ? "model" : "user"), "parts": .array(parts)])) }
        }
        flushFunctionResponses()
        return out
    }
    private static func escapePathSegment(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
    public static func isThinkingPart(thought: Bool?, thoughtSignature _: String?) -> Bool { thought == true }
    public static func retainThoughtSignature(existing: String?, incoming: String?) -> String? { guard let incoming, !incoming.isEmpty else { return existing }; return incoming }
    public static func isVertexADCMarker(_ apiKey: String) -> Bool { apiKey == "<authenticated>" || apiKey == "gcp-vertex-credentials" }
    private static func mappedThinkingEffort(model: Model, effort: String) -> String { AIUtilities.mapThinkingLevel(model: model, level: ModelThinkingLevel(rawValue: effort) ?? .high) ?? effort }
    private static func usesThinkingLevel(_ model: Model) -> Bool { model.id.lowercased().contains("gemini-3") || model.id.lowercased().contains("gemma-4") || model.id == "gemini-flash-latest" || model.id == "gemini-flash-lite-latest" }
    private static func supportsMultimodalFunctionResponse(_ modelID: String) -> Bool { let lower = modelID.lowercased(); if lower.hasPrefix("gemini-") { return lower.contains("gemini-3") }; return true }
    private static func googleThinkingLevel(_ effort: String, model: Model) -> String { switch effort { case "minimal": return "MINIMAL"; case "low": return model.id.lowercased().contains("gemini-3") && model.id.lowercased().contains("pro") ? "LOW" : "LOW"; case "medium": return "MEDIUM"; case "high": return "HIGH"; default: return effort.uppercased() } }
    private static func googleBudget(_ effort: String) -> Int { switch effort { case "minimal": return 1024; case "low": return 2048; case "medium": return 8192; case "high": return 24576; default: return 8192 } }
    private static func disabledThinkingConfig(model: Model) -> JSONValue { usesThinkingLevel(model) ? .object(["thinkingLevel": .string(model.id.lowercased().contains("pro") ? "LOW" : "MINIMAL")]) : .object(["thinkingBudget": .number(0)]) }
    public static func convertTools(_ tools: [Tool], useParameters: Bool = false) -> JSONValue? {
        guard !tools.isEmpty else { return nil }
        let declarations = tools.map { tool -> JSONValue in
            var object: [String: JSONValue] = ["name": .string(tool.name), "description": .string(tool.description)]
            if useParameters { object["parameters"] = stripSchemaMeta(tool.parameters) }
            else { object["parametersJsonSchema"] = tool.parameters }
            return .object(object)
        }
        return .array([.object(["functionDeclarations": .array(declarations)])])
    }

    private static func stripSchemaMeta(_ value: JSONValue) -> JSONValue {
        switch value {
        case .object(let obj):
            var out: [String: JSONValue] = [:]
            for (key, val) in obj where key != "$schema" && key != "$id" && key != "$comment" && key != "$defs" && key != "definitions" { out[key] = stripSchemaMeta(val) }
            return .object(out)
        case .array(let arr): return .array(arr.map(stripSchemaMeta))
        default: return value
        }
    }
    private static func normalizeToolCallID(_ id: String) -> String { let out = String(id.map { ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") ? $0 : "_" }); return String(out.prefix(64)) }
    private static func isValidBase64Signature(_ sig: String) -> Bool {
        if sig.isEmpty || sig.count % 4 != 0 { return false }
        return sig.allSatisfy { $0.isLetter || $0.isNumber || $0 == "+" || $0 == "/" || $0 == "=" }
    }
    private static func jsonString(_ object: [String: JSONValue]) -> String { guard let data = try? JSONEncoder().encode(object) else { return "{}" }; return String(data: data, encoding: .utf8) ?? "{}" }
    private static func mapFinishReason(_ raw: String) -> StopReason { raw == "MAX_TOKENS" ? .length : (raw == "STOP" ? .stop : .error) }
}

private struct GoogleStreamState { var model: Model; var partial: Message; var started = false; var current: (type: String, index: Int)?; init(model: Model) { self.model = model; var msg = Message(role: .assistant, content: []); msg.api = model.api; msg.provider = model.provider; msg.model = model.id; msg.usage = Usage(); partial = msg } }
private struct GeminiChunk: Decodable { var candidates: [Candidate]?; var usageMetadata: UsageMetadata?; var responseId: String?; struct Candidate: Decodable { var content: Content?; var finishReason: String? }; struct Content: Decodable { var parts: [Part] }; struct Part: Decodable { var text: String?; var thought: Bool?; var thoughtSignature: String?; var functionCall: FunctionCall? }; struct FunctionCall: Decodable { var name: String; var args: [String: JSONValue]?; var id: String? }; struct UsageMetadata: Decodable { var promptTokenCount: Int?; var candidatesTokenCount: Int?; var totalTokenCount: Int?; var thoughtsTokenCount: Int?; var cachedContentTokenCount: Int? } }
