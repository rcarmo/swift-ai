import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum GoogleGeminiCLIProvider {
    public static func stream(model: Model, context: AIContext, options: StreamOptions?) -> AsyncStream<AIEvent> {
        AsyncStream { continuation in
            Task {
                do { try await streamRequest(model: model, context: context, options: options, continuation: continuation) }
                catch { continuation.yield(.error(reason: .error, message: nil, error: error)) }
                continuation.finish()
            }
        }
    }

    public static func buildRequestBody(model: Model, context: AIContext, projectId: String, options: StreamOptions?) -> [String: JSONValue] {
        var inner: [String: JSONValue] = [:]
        if let system = context.systemPrompt, !system.isEmpty { inner["systemInstruction"] = .object(["role": .string("user"), "parts": .array([.object(["text": .string(AIUtilities.sanitizeSurrogates(system))])])]) }
        if let session = options?.sessionId, !session.isEmpty { inner["sessionId"] = .string(session) }
        inner["contents"] = .array(convertMessages(model: model, messages: AIUtilities.transformMessages(context.messages, for: model)))
        var gen: [String: JSONValue] = [:]
        if let temp = options?.temperature { gen["temperature"] = .number(temp) }
        if let max = options?.maxTokens { gen["maxOutputTokens"] = .number(Double(max)) }
        if let reasoning = options?.reasoning, model.reasoning { gen["thinkingConfig"] = .object(["includeThoughts": .bool(true), "thinkingLevel": .string((AIUtilities.mapThinkingLevel(model: model, level: ModelThinkingLevel(rawValue: reasoning.rawValue) ?? .high) ?? "high").uppercased())]) }
        if !gen.isEmpty { inner["generationConfig"] = .object(gen) }
        if let tools = context.tools, !tools.isEmpty { inner["tools"] = .array([.object(["functionDeclarations": .array(tools.map(toolJSON))])]) }
        return ["project": .string(projectId), "model": .string(model.id), "request": .object(inner)]
    }

    private static func streamRequest(model: Model, context: AIContext, options: StreamOptions?, continuation: AsyncStream<AIEvent>.Continuation) async throws {
        guard let raw = ProviderEnvironment.resolveAPIKey(model: model, options: options), let data = raw.data(using: .utf8), let creds = try? JSONDecoder().decode([String: JSONValue].self, from: data), let token = creds["token"]?.stringValue, let project = creds["projectId"]?.stringValue, !token.isEmpty, !project.isEmpty else { throw AIError.provider("invalid Google Cloud credentials (expected {token,projectId} JSON)") }
        let endpoint = (model.baseUrl.isEmpty ? "https://cloudcode-pa.googleapis.com" : model.baseUrl).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var request = URLRequest(url: URL(string: endpoint + "/v1internal:streamGenerateContent?alt=sse")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("cloud-code-assist/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("cl/head cloud-code-assist/1.0", forHTTPHeaderField: "X-Goog-Api-Client")
        for (k, v) in options?.headers ?? [:] { request.setValue(v, forHTTPHeaderField: k) }
        var payload = buildRequestBody(model: model, context: context, projectId: project, options: options)
        if let hook = options?.onPayload { payload = try await hook(payload, model) }
        request.httpBody = try JSONEncoder().encode(payload)
        let (bytes, response) = try await HTTPRetry.bytes(for: request, policy: RetryPolicy(options: options))
        guard let http = response as? HTTPURLResponse else { throw AIError.invalidResponse("non-HTTP response") }
        if let hook = options?.onResponse { await hook(HTTPResponseMetadata(status: http.statusCode, headers: http.headersDictionary), model) }
        guard (200..<300).contains(http.statusCode) else { throw AIError.apiError(status: http.statusCode, body: "HTTP \(http.statusCode)") }
        var buffer = ""
        var sseText = ""
        for try await byte in bytes {
            buffer += String(decoding: [byte], as: UTF8.self)
            while let range = buffer.range(of: "\n\n") ?? buffer.range(of: "\r\n\r\n") {
                let frame = String(buffer[..<range.lowerBound]); buffer.removeSubrange(..<range.upperBound)
                sseText += unwrapCCAFrame(frame) + "\n\n"
            }
        }
        for event in GoogleGenerativeAIProvider.processSSEText(sseText, model: model) { continuation.yield(event) }
    }

    public static func processSSEText(_ text: String, model: Model) -> [AIEvent] {
        let converted = SSEParser().parse(text).map { event in unwrapCCAData(event.data) }.filter { !$0.isEmpty }.map { "data: \($0)\n\n" }.joined()
        return GoogleGenerativeAIProvider.processSSEText(converted, model: model)
    }

    private static func unwrapCCAFrame(_ frame: String) -> String { SSEParser().parse(frame + "\n\n").map { unwrapCCAData($0.data) }.filter { !$0.isEmpty }.map { "data: \($0)" }.joined(separator: "\n\n") }
    private static func unwrapCCAData(_ data: String) -> String { guard data != "[DONE]", let raw = data.data(using: .utf8), let wrapped = try? JSONDecoder().decode(CCAStreamChunk.self, from: raw), let response = wrapped.response, let encoded = try? JSONEncoder().encode(response) else { return data == "[DONE]" ? data : "" }; return String(data: encoded, encoding: .utf8) ?? "" }

    private static func convertMessages(model: Model, messages: [Message]) -> [JSONValue] { messages.compactMap { msg in var parts: [JSONValue] = []; for b in msg.content { if b.type == "text" { parts.append(.object(["text": .string(AIUtilities.sanitizeSurrogates(b.text ?? ""))])) } else if b.type == "image" { parts.append(.object(["inlineData": .object(["mimeType": .string(b.mimeType ?? "application/octet-stream"), "data": .string(b.data ?? "")])])) } else if b.type == "thinking" { parts.append(.object(["thought": .bool(true), "text": .string(AIUtilities.sanitizeSurrogates(b.thinking ?? ""))])) } else if b.type == "toolCall" { parts.append(.object(["functionCall": .object(["name": .string(b.name ?? ""), "args": .object(b.arguments ?? [:])])])) } }; guard !parts.isEmpty else { return nil }; return .object(["role": .string(msg.role == .assistant ? "model" : "user"), "parts": .array(parts)]) } }
    private static func toolJSON(_ tool: Tool) -> JSONValue { .object(["name": .string(tool.name), "description": .string(tool.description), "parameters": tool.parameters]) }
}

private struct CCAStreamChunk: Decodable { var response: JSONValue? }
