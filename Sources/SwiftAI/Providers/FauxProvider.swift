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
        case nil: msg = FauxProvider.textMessage("Faux response #\(callState.callCount) (no responses queued)")
        }
        if msg.timestamp == 0 { msg.timestamp = Int64(Date().timeIntervalSince1970 * 1000) }
        return msg
    }

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

    private static func chunks(_ text: String, size: Int) -> [String] { var out: [String] = []; var start = text.startIndex; while start < text.endIndex { let end = text.index(start, offsetBy: size, limitedBy: text.endIndex) ?? text.endIndex; out.append(String(text[start..<end])); start = end }; return out }
}
