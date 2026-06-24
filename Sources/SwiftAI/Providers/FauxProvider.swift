import Foundation

public typealias FauxResponseFactory = @Sendable (AIContext, StreamOptions?, FauxState) -> Message

public enum FauxResponseStep: Sendable {
    case message(Message)
    case factory(FauxResponseFactory)
}

public struct FauxState: Equatable, Sendable { public var callCount: Int64; public init(callCount: Int64 = 0) { self.callCount = callCount } }
public struct FauxModelDef: Equatable, Sendable { public var id: String; public var name: String; public var reasoning: Bool; public var input: [String]; public var cost: ModelCost; public var contextWindow: Int; public var maxTokens: Int; public init(id: String = "faux-model", name: String = "Faux Model", reasoning: Bool = false, input: [String] = ["text"], cost: ModelCost = ModelCost(), contextWindow: Int = 128_000, maxTokens: Int = 4096) { self.id = id; self.name = name; self.reasoning = reasoning; self.input = input; self.cost = cost; self.contextWindow = contextWindow; self.maxTokens = maxTokens } }
public struct FauxOptions: Equatable, Sendable { public var models: [FauxModelDef]; public var tokensPerSecond: Int; public init(models: [FauxModelDef] = [FauxModelDef()], tokensPerSecond: Int = 1000) { self.models = models; self.tokensPerSecond = tokensPerSecond } }

public actor FauxRegistration {
    public nonisolated let models: [Model]
    public private(set) var state = FauxState()
    private var responses: [FauxResponseStep] = []
    private var promptCache: [String: Int] = [:]
    private let tokensPerSecond: Int

    public init(options: FauxOptions = FauxOptions()) {
        self.tokensPerSecond = options.tokensPerSecond
        self.models = options.models.map { def in Model(id: def.id, name: def.name.isEmpty ? def.id : def.name, api: .faux, provider: .faux, reasoning: def.reasoning, input: def.input.isEmpty ? ["text"] : def.input, cost: def.cost, contextWindow: def.contextWindow, maxTokens: def.maxTokens) }
    }

    public func setResponses(_ responses: [FauxResponseStep]) { self.responses = responses }
    public func appendResponses(_ responses: [FauxResponseStep]) { self.responses.append(contentsOf: responses) }
    public func pendingResponseCount() -> Int { responses.count }
    public func model(id: String? = nil) -> Model? { guard let id, !id.isEmpty else { return models.first }; return models.first { $0.id == id } }

    fileprivate func nextResponse(context: AIContext, options: StreamOptions?) -> Message {
        state.callCount += 1
        let callState = state
        let step = responses.isEmpty ? nil : responses.removeFirst()
        var msg: Message
        switch step {
        case .message(let message): msg = message
        case .factory(let factory): msg = factory(context, options, callState)
        case nil: msg = FauxProvider.errorMessage("No more faux responses queued")
        }
        msg.usage = usage(for: msg, context: context, options: options)
        if msg.timestamp == 0 { msg.timestamp = Int64(Date().timeIntervalSince1970 * 1000) }
        return msg
    }

    private func usage(for message: Message, context: AIContext, options: StreamOptions?) -> Usage {
        let promptTokens = estimateTokens(promptText(context))
        let outputTokens = estimateTokens(outputText(message))
        var usage = message.usage ?? Usage()
        usage.input = promptTokens
        usage.output = outputTokens
        usage.cacheRead = 0
        usage.cacheWrite = 0
        if let session = options?.sessionId, !session.isEmpty, ProviderEnvironment.resolveCacheRetention(options?.cacheRetention, env: options?.env) != .none {
            if let cached = promptCache[session] { usage.cacheRead = min(cached, promptTokens); usage.input = max(0, promptTokens - usage.cacheRead) }
            usage.cacheWrite = promptTokens
            promptCache[session] = max(promptCache[session] ?? 0, promptTokens)
        }
        usage.totalTokens = usage.input + usage.output + usage.cacheRead + usage.cacheWrite
        return usage
    }

    private func promptText(_ context: AIContext) -> String {
        var parts: [String] = []
        if let system = context.systemPrompt, !system.isEmpty { parts.append("system:\(system)") }
        for message in context.messages { parts.append(messageText(message)) }
        if let tools = context.tools, !tools.isEmpty, let data = try? JSONEncoder().encode(tools), let text = String(data: data, encoding: .utf8) { parts.append("tools:\(text)") }
        return parts.joined(separator: "\n\n")
    }

    private func messageText(_ message: Message) -> String {
        let body = message.content.map { block -> String in
            switch block.type {
            case "text": return block.text ?? ""
            case "thinking": return block.thinking ?? ""
            case "image": return "[image:\(block.mimeType ?? "application/octet-stream"):\((block.data ?? "").count)]"
            case "toolCall": return "\(block.name ?? "")\n\(jsonString(block.arguments ?? [:]))"
            default: return ""
            }
        }.filter { !$0.isEmpty }.joined(separator: "\n")
        return "\(message.role.rawValue):\(message.role == .toolResult ? "\(message.toolName ?? "")\n" : "")\(body)"
    }

    private func outputText(_ message: Message) -> String {
        message.content.map { block -> String in
            switch block.type {
            case "text": return block.text ?? ""
            case "thinking": return block.thinking ?? ""
            case "toolCall": return jsonString(block.arguments ?? [:])
            default: return ""
            }
        }.joined(separator: "")
    }

    private func estimateTokens(_ text: String) -> Int { text.isEmpty ? 0 : Int(ceil(Double(text.count) / 4.0)) }
    private func jsonString(_ object: [String: JSONValue]) -> String { guard let data = try? JSONEncoder().encode(object) else { return "{}" }; return String(data: data, encoding: .utf8) ?? "{}" }

    fileprivate func delayNanoseconds(for text: String) -> UInt64 {
        guard tokensPerSecond > 0, !text.isEmpty else { return 0 }
        let tokens = max(1, text.count / 4)
        let chunks = max(1, text.count / 10)
        return UInt64(Double(1_000_000_000 * tokens) / Double(tokensPerSecond * chunks))
    }
}

public enum FauxProvider {
    public static func register(options: FauxOptions = FauxOptions()) async -> FauxRegistration {
        let registration = FauxRegistration(options: options)
        for model in registration.models { await AIRegistry.shared.register(model) }
        await AIRegistry.shared.register(APIProvider(api: .faux, stream: { model, context, options in stream(registration: registration, model: model, context: context, options: options) }))
        return registration
    }

    public static func textMessage(_ text: String) -> Message {
        var msg = Message(role: .assistant, content: [.text(text)])
        msg.stopReason = .stop
        var usage = Usage(); usage.input = 100; usage.output = text.count / 4; usage.totalTokens = usage.input + usage.output; msg.usage = usage
        msg.timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        return msg
    }

    public static func thinkingMessage(thinking: String, text: String) -> Message {
        var msg = Message(role: .assistant, content: [.thinking(thinking), .text(text)])
        msg.stopReason = .stop
        var usage = Usage(); usage.input = 100; usage.output = (thinking.count + text.count) / 4; usage.totalTokens = usage.input + usage.output; msg.usage = usage
        msg.timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        return msg
    }

    public static func toolCallMessage(name: String, arguments: [String: JSONValue]) -> Message {
        var msg = Message(role: .assistant, content: [.toolCall(id: "call_\(name)_\(Int(Date().timeIntervalSince1970 * 1_000_000_000))", name: name, arguments: arguments)])
        msg.stopReason = .toolUse
        var usage = Usage(); usage.input = 100; usage.output = 50; usage.totalTokens = 150; msg.usage = usage
        msg.timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        return msg
    }

    public static func errorMessage(_ error: String) -> Message { var msg = Message(role: .assistant, content: []); msg.stopReason = .error; msg.errorMessage = error; msg.usage = Usage(); msg.timestamp = Int64(Date().timeIntervalSince1970 * 1000); return msg }

    private static func stream(registration: FauxRegistration, model: Model, context: AIContext, options: StreamOptions?) -> AsyncStream<AIEvent> {
        AsyncStream { continuation in
            Task {
                var msg = await registration.nextResponse(context: context, options: options)
                msg.api = model.api; msg.provider = model.provider; msg.model = model.id
                continuation.yield(.start(partial: msg))
                for (idx, block) in msg.content.enumerated() {
                    switch block.type {
                    case "text":
                        continuation.yield(.textStart(contentIndex: idx, partial: msg))
                        for chunk in chunks(block.text ?? "", size: 10) { continuation.yield(.textDelta(contentIndex: idx, delta: chunk, partial: msg)); let delay = await registration.delayNanoseconds(for: block.text ?? ""); if delay > 0 { try? await Task.sleep(nanoseconds: delay) } }
                        continuation.yield(.textEnd(contentIndex: idx, content: block.text ?? "", partial: msg))
                    case "thinking":
                        continuation.yield(.thinkingStart(contentIndex: idx, partial: msg))
                        for chunk in chunks(block.thinking ?? "", size: 10) { continuation.yield(.thinkingDelta(contentIndex: idx, delta: chunk, partial: msg)); let delay = await registration.delayNanoseconds(for: block.thinking ?? ""); if delay > 0 { try? await Task.sleep(nanoseconds: delay) } }
                        continuation.yield(.thinkingEnd(contentIndex: idx, content: block.thinking ?? "", partial: msg))
                    case "toolCall":
                        continuation.yield(.toolCallStart(contentIndex: idx, partial: msg))
                        for chunk in chunks(jsonString(block.arguments ?? [:]), size: 10) { continuation.yield(.toolCallDelta(contentIndex: idx, delta: chunk, partial: msg)); let delay = await registration.delayNanoseconds(for: chunk); if delay > 0 { try? await Task.sleep(nanoseconds: delay) } }
                        continuation.yield(.toolCallEnd(contentIndex: idx, toolCall: block, partial: msg))
                    default: break
                    }
                }
                if msg.stopReason == .error { continuation.yield(.error(reason: .error, message: msg, error: AIError.provider(msg.errorMessage ?? "faux error"))) }
                else { continuation.yield(.done(reason: msg.stopReason ?? .stop, message: msg)) }
                continuation.finish()
            }
        }
    }

    private static func jsonString(_ object: [String: JSONValue]) -> String { guard let data = try? JSONEncoder().encode(object) else { return "{}" }; return String(data: data, encoding: .utf8) ?? "{}" }
    private static func chunks(_ text: String, size: Int) -> [String] { var out: [String] = []; var start = text.startIndex; while start < text.endIndex { let end = text.index(start, offsetBy: size, limitedBy: text.endIndex) ?? text.endIndex; out.append(String(text[start..<end])); start = end }; return out }
}
