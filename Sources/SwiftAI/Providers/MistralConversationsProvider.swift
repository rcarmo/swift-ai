import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum MistralConversationsProvider {
    public typealias StreamingTransport = @Sendable (URLRequest) async throws -> (AsyncThrowingStream<UInt8, Error>, URLResponse)
    nonisolated(unsafe) public static var requestTransport: StreamingTransport?
    nonisolated(unsafe) public static var urlSessionConfiguration: @Sendable () -> URLSessionConfiguration = { .default }

    public static func stream(model: Model, context: AIContext, options: StreamOptions?) -> AsyncStream<AIEvent> {
        AsyncStream { continuation in
            let task = Task {
                do { try await streamRequest(model: model, context: context, options: options, continuation: continuation) }
                catch is CancellationError { continuation.yield(.error(reason: .aborted, message: errorMessage(model: model, stopReason: .aborted, message: nil), error: CancellationError())) }
                catch { continuation.yield(.error(reason: .error, message: errorMessage(model: model, stopReason: .error, message: String(describing: error)), error: error)) }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public static func buildRequestBody(model: Model, context: AIContext, options: StreamOptions?) -> [String: JSONValue] {
        var body: [String: JSONValue] = ["model": .string(model.id), "stream": .bool(true), "messages": .array(convertMessages(context, model: model))]
        if let temperature = options?.temperature { body["temperature"] = .number(temperature) }
        if let maxTokens = AIUtilities.effectiveMaxTokens(model: model, context: context, options: options, defaultToModel: true) { body["max_tokens"] = .number(Double(maxTokens)) }
        if let reasoning = options?.reasoning, model.reasoning {
            let mapped = mappedThinkingEffort(model: model, effort: reasoning.rawValue)
            if usesReasoningEffort(model) { body["reasoning_effort"] = .string(mapped) } else { body["prompt_mode"] = .string("reasoning") }
        }
        if let session = options?.sessionId, !session.isEmpty, options?.cacheRetention != CacheRetention.none { body["prompt_cache_key"] = .string(session) }
        if let tools = context.tools, !tools.isEmpty { body["tools"] = .array(tools.map(toolJSON)) }
        return body
    }

    private static func streamRequest(model: Model, context: AIContext, options: StreamOptions?, continuation: AsyncStream<AIEvent>.Continuation) async throws {
        guard let key = ProviderEnvironment.resolveAPIKey(model: model, options: options), !key.isEmpty else { throw AIError.provider("missing API key for \(model.provider.rawValue)") }
        let base = (model.baseUrl.isEmpty ? "https://api.mistral.ai/v1" : model.baseUrl).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var request = URLRequest(url: URL(string: base + "/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue(AIUtilities.piUserAgent(), forHTTPHeaderField: "User-Agent")
        if let session = options?.sessionId, !session.isEmpty, options?.cacheRetention != CacheRetention.none { request.setValue(session, forHTTPHeaderField: "x-affinity") }
        if let timeoutMs = options?.timeoutMs, timeoutMs > 0 { request.timeoutInterval = Double(timeoutMs) / 1000.0 }
        AIUtilities.applyProviderHeaders(model.headers, options?.headers, to: &request)
        if let affinityOverride = options?.headers?.first(where: { $0.key.lowercased() == "x-affinity" }) {
            request.setValue(affinityOverride.value, forHTTPHeaderField: "x-affinity")
        }
        var payload = buildRequestBody(model: model, context: context, options: options)
        if let hook = options?.onPayload { payload = try await hook(payload, model) }
        request.httpBody = try JSONEncoder().encode(payload)
        let (bytes, response) = try await streamingBytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIError.invalidResponse("non-HTTP response") }
        if let hook = options?.onResponse { await hook(HTTPResponseMetadata(status: http.statusCode, headers: http.headersDictionary), model) }
        guard (200..<300).contains(http.statusCode) else { throw AIError.apiError(status: http.statusCode, body: try await boundedBody(bytes: bytes)) }
        var state = MistralStreamState(model: model)
        var buffer = Data()
        for try await byte in bytes {
            buffer.append(byte)
            while let match = firstSSEFrameDelimiter(in: buffer) {
                let frameData = buffer[..<match.lowerBound]
                buffer.removeSubrange(..<match.upperBound)
                guard let frame = String(data: frameData, encoding: .utf8) else { continue }
                for event in SSEParser().parse(frame + "\n\n") { process(data: event.data, state: &state) { continuation.yield($0) } }
            }
        }
        finish(state: &state) { continuation.yield($0) }
    }

    private static func streamingBytes(for request: URLRequest) async throws -> (AsyncThrowingStream<UInt8, Error>, URLResponse) {
        if let requestTransport { return try await requestTransport(request) }
        let transport = MistralURLSessionStreamingTransport(configuration: urlSessionConfiguration())
        return try await transport.stream(request: request)
    }

    private static func boundedBody(bytes: AsyncThrowingStream<UInt8, Error>) async throws -> String {
        var data = Data()
        for try await byte in bytes {
            if data.count < AIUtilities.maxProviderErrorBodyChars { data.append(byte) }
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func firstSSEFrameDelimiter(in data: Data) -> Range<Data.Index>? {
        if let range = data.range(of: Data([10, 10])) { return range }
        if let range = data.range(of: Data([13, 10, 13, 10])) { return range }
        return nil
    }

    public static func processSSEText(_ text: String, model: Model) -> [AIEvent] {
        var events: [AIEvent] = []
        var state = MistralStreamState(model: model)
        for event in SSEParser().parse(text) { process(data: event.data, state: &state) { events.append($0) } }
        finish(state: &state) { events.append($0) }
        return events
    }

    private static func process(data: String, state: inout MistralStreamState, yield: (AIEvent) -> Void) {
        if !state.started { state.started = true; yield(.start(partial: state.partial)) }
        if data == "[DONE]" { return }
        guard let raw = data.data(using: .utf8), let chunk = try? JSONDecoder().decode(MistralChunk.self, from: raw) else { return }
        if let id = chunk.id, !id.isEmpty { state.partial.responseId = id }
        if let model = chunk.model, !model.isEmpty, model != state.model.id, state.partial.responseModel == nil { state.partial.responseModel = model }
        if let usage = chunk.usage { var u = state.partial.usage ?? Usage(); let cached = usage.promptTokensDetails?.cachedTokens ?? 0; u.cacheRead = cached; u.input = max(0, (usage.promptTokens ?? 0) - cached); u.output = usage.completionTokens ?? 0; u.totalTokens = usage.totalTokens ?? (u.input + u.output + u.cacheRead); AIUtilities.applyCost(model: state.model, usage: &u); state.partial.usage = u }
        guard let choice = chunk.choices.first else { return }
        if let finish = choice.finishReason { state.finishReason = finish; state.partial.rawStopReason = finish }
        if let content = choice.delta.content, !content.isEmpty {
            if state.partial.content.last?.type != "text" { state.partial.content.append(ContentBlock(type: "text")); yield(.textStart(contentIndex: state.partial.content.count - 1, partial: state.partial)) }
            let idx = state.partial.content.count - 1
            state.partial.content[idx].text = (state.partial.content[idx].text ?? "") + content
            yield(.textDelta(contentIndex: idx, delta: content, partial: state.partial))
        }
        if let reasoning = choice.delta.reasoning, !reasoning.isEmpty {
            if state.partial.content.last?.type != "thinking" { state.partial.content.append(ContentBlock(type: "thinking")); yield(.thinkingStart(contentIndex: state.partial.content.count - 1, partial: state.partial)) }
            let idx = state.partial.content.count - 1
            state.partial.content[idx].thinking = (state.partial.content[idx].thinking ?? "") + reasoning
            yield(.thinkingDelta(contentIndex: idx, delta: reasoning, partial: state.partial))
        }
        for tool in choice.delta.toolCalls ?? [] {
            if state.activeTools[tool.index] == nil {
                let idx = state.partial.content.count
                state.partial.content.append(ContentBlock(type: "toolCall", id: tool.id, name: tool.function?.name))
                state.activeTools[tool.index] = MistralActiveTool(id: tool.id, name: tool.function?.name, args: "", contentIndex: idx)
                yield(.toolCallStart(contentIndex: idx, partial: state.partial))
            }
            guard var active = state.activeTools[tool.index] else { continue }
            if let id = tool.id { active.id = id; state.partial.content[active.contentIndex].id = id }
            if let name = tool.function?.name, !name.isEmpty { active.name = name; state.partial.content[active.contentIndex].name = name }
            if let args = tool.function?.arguments, !args.isEmpty { active.args += args; yield(.toolCallDelta(contentIndex: active.contentIndex, delta: args, partial: state.partial)) }
            state.activeTools[tool.index] = active
        }
    }

    private static func finish(state: inout MistralStreamState, yield: (AIEvent) -> Void) {
        if !state.started { state.started = true; yield(.start(partial: state.partial)) }
        for (idx, block) in state.partial.content.enumerated() {
            if block.type == "text" { yield(.textEnd(contentIndex: idx, content: block.text ?? "", partial: state.partial)) }
            if block.type == "thinking" { yield(.thinkingEnd(contentIndex: idx, content: block.thinking ?? "", partial: state.partial)) }
        }
        for key in state.activeTools.keys.sorted() {
            guard let active = state.activeTools[key] else { continue }
            let args = parseJSONObject(active.args)
            state.partial.content[active.contentIndex].arguments = args
            yield(.toolCallEnd(contentIndex: active.contentIndex, toolCall: ContentBlock(type: "toolCall", id: active.id, name: active.name, arguments: args), partial: state.partial))
        }
        state.partial.timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        let reason = stopReason(state.finishReason)
        state.partial.stopReason = reason
        if reason == .error {
            state.partial.errorMessage = "Provider stopped with: \(state.finishReason ?? "error")"
            yield(.error(reason: .error, message: state.partial, error: AIError.provider(state.partial.errorMessage ?? "mistral error")))
        } else {
            yield(.done(reason: reason, message: state.partial))
        }
    }

    private static func convertMessages(_ context: AIContext, model: Model) -> [JSONValue] {
        var out: [JSONValue] = []
        if let system = context.systemPrompt, !system.isEmpty { out.append(.object(["role": .string("system"), "content": .string(AIUtilities.sanitizeSurrogates(system))])) }
        for msg in AIUtilities.transformMessages(context.messages, for: model) {
            switch msg.role {
            case .user: out.append(.object(["role": .string("user"), "content": .string(AIUtilities.sanitizeSurrogates(msg.content.compactMap(\.text).joined()))]))
            case .assistant:
                var obj: [String: JSONValue] = ["role": .string("assistant"), "content": .string(msg.content.compactMap { $0.text ?? $0.thinking }.joined())]
                let calls = msg.content.filter { $0.type == "toolCall" }.map { block in JSONValue.object(["id": .string(normalizeToolCallID(block.id ?? "")), "type": .string("function"), "function": .object(["name": .string(block.name ?? ""), "arguments": .string(jsonString(block.arguments ?? [:]))])]) }
                if !calls.isEmpty { obj["tool_calls"] = .array(calls) }
                out.append(.object(obj))
            case .toolResult: out.append(.object(["role": .string("tool"), "content": .string(AIUtilities.sanitizeSurrogates(msg.content.compactMap(\.text).joined())), "tool_call_id": .string(normalizeToolCallID(msg.toolCallId ?? "")), "name": .string(msg.toolName ?? "")]))
            }
        }
        return out
    }

    private static func mappedThinkingEffort(model: Model, effort: String) -> String { AIUtilities.mapThinkingLevel(model: model, level: ModelThinkingLevel(rawValue: effort) ?? .high) ?? effort }
    private static func usesReasoningEffort(_ model: Model) -> Bool { ["mistral-small-2603", "mistral-small-latest", "mistral-medium-3.5"].contains(model.id) }
    private static func toolJSON(_ tool: Tool) -> JSONValue { .object(["type": .string("function"), "function": .object(["name": .string(tool.name), "description": .string(tool.description), "parameters": tool.parameters])]) }
    private static func parseJSONObject(_ text: String) -> [String: JSONValue] { PartialJSONParser.parseObject(text) ?? [:] }
    private static func jsonString(_ object: [String: JSONValue]) -> String { guard let data = try? JSONEncoder().encode(object) else { return "{}" }; return String(data: data, encoding: .utf8) ?? "{}" }
    private static func stopReason(_ raw: String?) -> StopReason { switch raw { case "stop", "end": return .stop; case "length", "model_length": return .length; case "tool_calls": return .toolUse; case "error": return .error; case nil: return .error; default: return .error } }
    private static func normalizeToolCallID(_ id: String) -> String { let filtered = id.filter { $0.isLetter || $0.isNumber }; if filtered.count == 9 { return String(filtered) }; return String(AIUtilities.shortHash(id).filter { $0.isLetter || $0.isNumber }.prefix(9)).padding(toLength: 9, withPad: "0", startingAt: 0) }
    private static func errorMessage(model: Model, stopReason: StopReason, message: String?) -> Message { var out = Message(role: .assistant, content: []); out.api = model.api; out.provider = model.provider; out.model = model.id; out.stopReason = stopReason; out.errorMessage = message; return out }
}

private struct MistralStreamState { var model: Model; var partial: Message; var started = false; var finishReason: String?; var activeTools: [Int: MistralActiveTool] = [:]; init(model: Model) { self.model = model; var msg = Message(role: .assistant, content: []); msg.api = model.api; msg.provider = model.provider; msg.model = model.id; msg.usage = Usage(); partial = msg } }
private struct MistralActiveTool { var id: String?; var name: String?; var args: String; var contentIndex: Int }
private struct MistralChunk: Decodable { var id: String?; var model: String?; var choices: [Choice]; var usage: UsagePayload?; struct Choice: Decodable { var delta: Delta; var finishReason: String?; enum CodingKeys: String, CodingKey { case delta; case finishReason = "finish_reason" } }; struct Delta: Decodable { var content: String?; var reasoning: String?; var toolCalls: [ToolCall]?; enum CodingKeys: String, CodingKey { case content; case reasoning = "reasoning_content"; case toolCalls = "tool_calls" } }; struct ToolCall: Decodable { var index: Int; var id: String?; var function: Function? }; struct Function: Decodable { var name: String?; var arguments: String? }; struct UsagePayload: Decodable { var promptTokens: Int?; var completionTokens: Int?; var totalTokens: Int?; var promptTokensDetails: PromptTokensDetails?; enum CodingKeys: String, CodingKey { case promptTokens = "prompt_tokens"; case completionTokens = "completion_tokens"; case totalTokens = "total_tokens"; case promptTokensDetails = "prompt_tokens_details" }; struct PromptTokensDetails: Decodable { var cachedTokens: Int?; enum CodingKeys: String, CodingKey { case cachedTokens = "cached_tokens" } } } }

private final class MistralURLSessionStreamingTransport: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var responseContinuation: CheckedContinuation<URLResponse, Error>?
    private var streamContinuation: AsyncThrowingStream<UInt8, Error>.Continuation?
    private var task: URLSessionDataTask?
    private var session: URLSession?
    private let configuration: URLSessionConfiguration

    init(configuration: URLSessionConfiguration = .default) { self.configuration = configuration }

    func stream(request: URLRequest) async throws -> (AsyncThrowingStream<UInt8, Error>, URLResponse) {
        let stream = AsyncThrowingStream<UInt8, Error> { continuation in
            lock.lock(); streamContinuation = continuation; lock.unlock()
            continuation.onTermination = { [weak self] _ in self?.cancel() }
        }
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        let task = session.dataTask(with: request)
        set(session: session, task: task)
        task.resume()
        let response = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URLResponse, Error>) in
            lock.lock(); responseContinuation = continuation; lock.unlock()
        }
        return (stream, response)
    }

    private func set(session: URLSession, task: URLSessionDataTask) { lock.lock(); self.session = session; self.task = task; lock.unlock() }
    private func cancel() { lock.lock(); let task = task; let session = session; lock.unlock(); task?.cancel(); session?.invalidateAndCancel() }
    private func resumeResponse(_ result: Result<URLResponse, Error>) { lock.lock(); let cont = responseContinuation; responseContinuation = nil; lock.unlock(); cont?.resume(with: result) }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) { resumeResponse(.success(response)); completionHandler(.allow) }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) { lock.lock(); let cont = streamContinuation; lock.unlock(); for byte in data { cont?.yield(byte) } }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) { if let error { resumeResponse(.failure(error)); streamContinuation?.finish(throwing: error) } else { streamContinuation?.finish() }; session.invalidateAndCancel() }
}
