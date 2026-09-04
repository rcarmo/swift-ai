import Foundation

public enum AssistantMessageFrame: Codable, Equatable, Sendable {
    case start(partial: Message)
    case textStart(contentIndex: Int, content: ContentBlock)
    case textDelta(contentIndex: Int, delta: String)
    case textEnd(contentIndex: Int, content: String, textSignature: String? = nil)
    case thinkingStart(contentIndex: Int, content: ContentBlock)
    case thinkingDelta(contentIndex: Int, delta: String)
    case thinkingEnd(contentIndex: Int, content: String, thinkingSignature: String? = nil, redacted: Bool? = nil)
    case toolCallStart(contentIndex: Int, toolCall: ContentBlock)
    case toolCallCheckpoint(contentIndex: Int, json: String)
    case toolCallDelta(contentIndex: Int, delta: String)
    case toolCallEnd(contentIndex: Int, id: String, name: String, arguments: [String: JSONValue], thoughtSignature: String? = nil, namespace: String? = nil)

    private enum CodingKeys: String, CodingKey { case type, partial, contentIndex, content, delta, textSignature, thinkingSignature, redacted, toolCall, json, id, name, arguments, thoughtSignature, namespace }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "start": try Self.requireTopLevelKeys(decoder, ["type", "partial"]); self = .start(partial: try Self.decodeStartPartial(c))
        case "text_start": try Self.requireTopLevelKeys(decoder, ["type", "contentIndex", "content"]); self = .textStart(contentIndex: try Self.decodeContentIndex(c), content: try Self.decodeContentBlock(c, key: .content, expected: "text"))
        case "text_delta": try Self.requireTopLevelKeys(decoder, ["type", "contentIndex", "delta"]); self = .textDelta(contentIndex: try Self.decodeContentIndex(c), delta: try c.decode(String.self, forKey: .delta))
        case "text_end": try Self.requireTopLevelKeys(decoder, ["type", "contentIndex", "content", "textSignature"]); self = .textEnd(contentIndex: try Self.decodeContentIndex(c), content: try c.decode(String.self, forKey: .content), textSignature: try Self.decodeOptionalString(c, .textSignature))
        case "thinking_start": try Self.requireTopLevelKeys(decoder, ["type", "contentIndex", "content"]); self = .thinkingStart(contentIndex: try Self.decodeContentIndex(c), content: try Self.decodeContentBlock(c, key: .content, expected: "thinking"))
        case "thinking_delta": try Self.requireTopLevelKeys(decoder, ["type", "contentIndex", "delta"]); self = .thinkingDelta(contentIndex: try Self.decodeContentIndex(c), delta: try c.decode(String.self, forKey: .delta))
        case "thinking_end": try Self.requireTopLevelKeys(decoder, ["type", "contentIndex", "content", "thinkingSignature", "redacted"]); self = .thinkingEnd(contentIndex: try Self.decodeContentIndex(c), content: try c.decode(String.self, forKey: .content), thinkingSignature: try Self.decodeOptionalString(c, .thinkingSignature), redacted: try Self.decodeOptionalBool(c, .redacted))
        case "toolcall_start": try Self.requireTopLevelKeys(decoder, ["type", "contentIndex", "toolCall"]); self = .toolCallStart(contentIndex: try Self.decodeContentIndex(c), toolCall: try Self.decodeContentBlock(c, key: .toolCall, expected: "toolCall"))
        case "toolcall_checkpoint": try Self.requireTopLevelKeys(decoder, ["type", "contentIndex", "json"]); self = .toolCallCheckpoint(contentIndex: try Self.decodeContentIndex(c), json: try c.decode(String.self, forKey: .json))
        case "toolcall_delta": try Self.requireTopLevelKeys(decoder, ["type", "contentIndex", "delta"]); self = .toolCallDelta(contentIndex: try Self.decodeContentIndex(c), delta: try c.decode(String.self, forKey: .delta))
        case "toolcall_end": try Self.requireTopLevelKeys(decoder, ["type", "contentIndex", "id", "name", "arguments", "thoughtSignature", "namespace"]); self = .toolCallEnd(contentIndex: try Self.decodeContentIndex(c), id: try c.decode(String.self, forKey: .id), name: try c.decode(String.self, forKey: .name), arguments: try c.decode([String: JSONValue].self, forKey: .arguments), thoughtSignature: try Self.decodeOptionalString(c, .thoughtSignature), namespace: try Self.decodeOptionalString(c, .namespace))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown assistant message frame type: \(type)")
        }
    }

    private struct AnyCodingKey: CodingKey {
        var stringValue: String
        var intValue: Int?
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { self.stringValue = String(intValue); self.intValue = intValue }
    }

    private static func requireTopLevelKeys(_ decoder: Decoder, _ allowed: Set<String>) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        let keys = Set(c.allKeys.map(\.stringValue))
        let unsupported = keys.subtracting(allowed)
        guard unsupported.isEmpty else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unsupported assistant message frame keys: \(unsupported.sorted().joined(separator: ", "))"))
        }
    }

    private static func decodeStartPartial(_ c: KeyedDecodingContainer<CodingKeys>) throws -> Message {
        let partialKeys = Set((try c.nestedContainer(keyedBy: AnyCodingKey.self, forKey: .partial)).allKeys.map(\.stringValue))
        let allowed: Set<String> = ["role", "content", "timestamp", "api", "provider", "model", "responseId", "responseModel", "providerThinkingLevel", "diagnostics", "usage", "stopReason"]
        let unsupported = partialKeys.subtracting(allowed)
        guard unsupported.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .partial, in: c, debugDescription: "start.partial contains unsupported fields: \(unsupported.sorted().joined(separator: ", "))")
        }
        let required: Set<String> = ["role", "content", "timestamp", "api", "provider", "model", "usage", "stopReason"]
        let missing = required.subtracting(partialKeys)
        guard missing.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .partial, in: c, debugDescription: "start.partial missing required fields: \(missing.sorted().joined(separator: ", "))")
        }
        let nested = try c.nestedContainer(keyedBy: AnyCodingKey.self, forKey: .partial)
        let role = try nested.decode(Role.self, forKey: requiredKey("role"))
        let content = try nested.decode([ContentBlock].self, forKey: requiredKey("content"))
        _ = try nested.decode(Int64.self, forKey: requiredKey("timestamp"))
        _ = try nested.decode(API.self, forKey: requiredKey("api"))
        _ = try nested.decode(Provider.self, forKey: requiredKey("provider"))
        let model = try nested.decode(String.self, forKey: requiredKey("model"))
        _ = try nested.decode(Usage.self, forKey: requiredKey("usage"))
        let stopReason = try nested.decode(StopReason.self, forKey: requiredKey("stopReason"))
        guard role == .assistant, content.isEmpty, stopReason == .pending, !model.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .partial, in: c, debugDescription: "start.partial must be an assistant message with empty content, non-empty model, and pending stopReason")
        }
        return try c.decode(Message.self, forKey: .partial)
    }

    private static func requiredKey(_ value: String) -> AnyCodingKey { AnyCodingKey(stringValue: value)! }

    private static func decodeContentIndex(_ c: KeyedDecodingContainer<CodingKeys>) throws -> Int {
        let index = try c.decode(Int.self, forKey: .contentIndex)
        guard index >= 0 else { throw DecodingError.dataCorruptedError(forKey: .contentIndex, in: c, debugDescription: "Invalid assistant message frame contentIndex: \(index)") }
        return index
    }

    private static func decodeContentBlock(_ c: KeyedDecodingContainer<CodingKeys>, key: CodingKeys, expected: String) throws -> ContentBlock {
        let nested = try c.nestedContainer(keyedBy: AnyCodingKey.self, forKey: key)
        let keys = Set(nested.allKeys.map(\.stringValue))
        let allowed: Set<String>
        switch expected {
        case "text": allowed = ["type", "text", "textSignature"]
        case "thinking": allowed = ["type", "thinking", "thinkingSignature", "redacted"]
        case "toolCall": allowed = ["type", "id", "name", "arguments", "thoughtSignature", "namespace"]
        default: allowed = ["type"]
        }
        let unsupported = keys.subtracting(allowed)
        guard unsupported.isEmpty else { throw DecodingError.dataCorruptedError(forKey: key, in: c, debugDescription: "assistant message frame content contains unsupported fields: \(unsupported.sorted().joined(separator: ", "))") }
        let block = try c.decode(ContentBlock.self, forKey: key)
        guard block.type == expected else { throw DecodingError.dataCorruptedError(forKey: key, in: c, debugDescription: "assistant message frame contains \(block.type) content, expected \(expected)") }
        switch expected {
        case "text":
            guard keys.contains("text"), block.text != nil else { throw DecodingError.dataCorruptedError(forKey: key, in: c, debugDescription: "text_start content requires text") }
            try rejectNull(nested, "textSignature", key: key, outer: c)
        case "thinking":
            guard keys.contains("thinking"), block.thinking != nil else { throw DecodingError.dataCorruptedError(forKey: key, in: c, debugDescription: "thinking_start content requires thinking") }
            try rejectNull(nested, "thinkingSignature", key: key, outer: c)
            try rejectNull(nested, "redacted", key: key, outer: c)
        case "toolCall":
            guard keys.contains("id"), keys.contains("name"), keys.contains("arguments"), block.id != nil, block.name != nil, block.arguments != nil else { throw DecodingError.dataCorruptedError(forKey: key, in: c, debugDescription: "toolcall_start content requires id, name, and arguments") }
            try rejectNull(nested, "thoughtSignature", key: key, outer: c)
            try rejectNull(nested, "namespace", key: key, outer: c)
        default: break
        }
        return block
    }

    private static func decodeOptionalString(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) throws -> String? {
        guard c.contains(key) else { return nil }
        if try c.decodeNil(forKey: key) { throw DecodingError.dataCorruptedError(forKey: key, in: c, debugDescription: "\(key.stringValue) cannot be null") }
        return try c.decode(String.self, forKey: key)
    }

    private static func decodeOptionalBool(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) throws -> Bool? {
        guard c.contains(key) else { return nil }
        if try c.decodeNil(forKey: key) { throw DecodingError.dataCorruptedError(forKey: key, in: c, debugDescription: "\(key.stringValue) cannot be null") }
        return try c.decode(Bool.self, forKey: key)
    }

    private static func rejectNull(_ c: KeyedDecodingContainer<AnyCodingKey>, _ key: String, key outerKey: CodingKeys, outer: KeyedDecodingContainer<CodingKeys>) throws {
        guard let codingKey = AnyCodingKey(stringValue: key), c.contains(codingKey), (try? c.decodeNil(forKey: codingKey)) == true else { return }
        throw DecodingError.dataCorruptedError(forKey: outerKey, in: outer, debugDescription: "\(key) cannot be null")
    }

    private static func startPartial(_ partial: Message) throws -> Message {
        guard partial.role == .assistant else { throw EncodingError.invalidValue(partial, .init(codingPath: [], debugDescription: "start.partial must be an assistant message")) }
        guard partial.api != nil, partial.provider != nil, partial.model?.isEmpty == false, partial.usage != nil else { throw EncodingError.invalidValue(partial, .init(codingPath: [], debugDescription: "start.partial missing required api/provider/model/usage")) }
        var message = partial
        message.content = []
        message.stopReason = .pending
        message.errorMessage = nil
        message.deferred = nil
        message.rawStopReason = nil
        message.toolCallId = nil
        message.toolName = nil
        message.isError = nil
        message.details = nil
        message.addedToolNames = nil
        message.endTurn = nil
        return message
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .start(let partial): try c.encode("start", forKey: .type); try c.encode(try Self.startPartial(partial), forKey: .partial)
        case .textStart(let contentIndex, let content): try c.encode("text_start", forKey: .type); try c.encode(contentIndex, forKey: .contentIndex); try c.encode(content, forKey: .content)
        case .textDelta(let contentIndex, let delta): try c.encode("text_delta", forKey: .type); try c.encode(contentIndex, forKey: .contentIndex); try c.encode(delta, forKey: .delta)
        case .textEnd(let contentIndex, let content, let textSignature): try c.encode("text_end", forKey: .type); try c.encode(contentIndex, forKey: .contentIndex); try c.encode(content, forKey: .content); try c.encodeIfPresent(textSignature, forKey: .textSignature)
        case .thinkingStart(let contentIndex, let content): try c.encode("thinking_start", forKey: .type); try c.encode(contentIndex, forKey: .contentIndex); try c.encode(content, forKey: .content)
        case .thinkingDelta(let contentIndex, let delta): try c.encode("thinking_delta", forKey: .type); try c.encode(contentIndex, forKey: .contentIndex); try c.encode(delta, forKey: .delta)
        case .thinkingEnd(let contentIndex, let content, let thinkingSignature, let redacted): try c.encode("thinking_end", forKey: .type); try c.encode(contentIndex, forKey: .contentIndex); try c.encode(content, forKey: .content); try c.encodeIfPresent(thinkingSignature, forKey: .thinkingSignature); try c.encodeIfPresent(redacted, forKey: .redacted)
        case .toolCallStart(let contentIndex, let toolCall): try c.encode("toolcall_start", forKey: .type); try c.encode(contentIndex, forKey: .contentIndex); try c.encode(toolCall, forKey: .toolCall)
        case .toolCallCheckpoint(let contentIndex, let json): try c.encode("toolcall_checkpoint", forKey: .type); try c.encode(contentIndex, forKey: .contentIndex); try c.encode(json, forKey: .json)
        case .toolCallDelta(let contentIndex, let delta): try c.encode("toolcall_delta", forKey: .type); try c.encode(contentIndex, forKey: .contentIndex); try c.encode(delta, forKey: .delta)
        case .toolCallEnd(let contentIndex, let id, let name, let arguments, let thoughtSignature, let namespace): try c.encode("toolcall_end", forKey: .type); try c.encode(contentIndex, forKey: .contentIndex); try c.encode(id, forKey: .id); try c.encode(name, forKey: .name); try c.encode(arguments, forKey: .arguments); try c.encodeIfPresent(thoughtSignature, forKey: .thoughtSignature); try c.encodeIfPresent(namespace, forKey: .namespace)
        }
    }
}

public final class AssistantMessageFrameEncoder: @unchecked Sendable {
    private enum BlockState {
        case text(coveredChars: Int, deltaChars: Int)
        case thinking(coveredChars: Int, deltaChars: Int)
        case toolCall(caughtUp: Bool, catchupJSON: String, snapshotArguments: String)
    }

    private var started = false
    private var terminal = false
    private var blocks: [Int: BlockState] = [:]

    public init() {}

    public func encode(_ event: AIEvent) throws -> AssistantMessageFrame? {
        if terminal { throw AIError.provider("Assistant message event \(eventType(event)) follows a terminal event") }
        switch event {
        case .start(let partial):
            if started { throw AIError.provider("Assistant message stream contains more than one start event") }
            started = true
            var message = partial ?? Message(role: .assistant, content: [])
            message.content = []
            message.stopReason = .pending
            return .start(partial: message)
        case .done:
            guard started else { throw AIError.provider("Assistant message done event appears before start") }
            terminal = true
            return nil
        case .error:
            terminal = true
            return nil
        default:
            guard started else { throw AIError.provider("Assistant message \(eventType(event)) event appears before start") }
        }

        switch event {
        case .textStart(let index, let partial):
            let content = try eventBlock(partial: partial, index: index, expected: "text", type: eventType(event))
            try start(index: index, state: .text(coveredChars: (content.text ?? "").count, deltaChars: 0))
            return .textStart(contentIndex: index, content: content)
        case .textDelta(let index, let delta, _):
            return try encodeTextDelta(index: index, delta: delta, kind: "text")
        case .textEnd(let index, let content, let partial):
            let block = try eventBlock(partial: partial, index: index, expected: "text", type: eventType(event))
            try end(index: index, expected: "text")
            return .textEnd(contentIndex: index, content: content, textSignature: block.textSignature)
        case .thinkingStart(let index, let partial):
            let content = try eventBlock(partial: partial, index: index, expected: "thinking", type: eventType(event))
            try start(index: index, state: .thinking(coveredChars: (content.thinking ?? "").count, deltaChars: 0))
            return .thinkingStart(contentIndex: index, content: content)
        case .thinkingDelta(let index, let delta, _):
            return try encodeTextDelta(index: index, delta: delta, kind: "thinking")
        case .thinkingEnd(let index, let content, let partial):
            let block = try eventBlock(partial: partial, index: index, expected: "thinking", type: eventType(event))
            try end(index: index, expected: "thinking")
            return .thinkingEnd(contentIndex: index, content: content, thinkingSignature: block.thinkingSignature, redacted: block.redacted)
        case .toolCallStart(let index, let partial):
            let tool = try eventBlock(partial: partial, index: index, expected: "toolCall", type: eventType(event))
            let snapshot = Self.jsonString(tool.arguments ?? [:])
            try start(index: index, state: .toolCall(caughtUp: snapshot == "{}", catchupJSON: "", snapshotArguments: snapshot == "{}" ? "" : snapshot))
            return .toolCallStart(contentIndex: index, toolCall: tool)
        case .toolCallDelta(let index, let delta, _):
            guard case .toolCall(let caughtUp, var catchup, let snapshot)? = blocks[index] else { throw AIError.provider("Assistant message toolCall block \(index) has not started") }
            if caughtUp { return delta.isEmpty ? nil : .toolCallDelta(contentIndex: index, delta: delta) }
            catchup += delta
            if let parsed = PartialJSONParser.parseObject(catchup) {
                let matchesSnapshot = Self.jsonString(parsed) == snapshot
                let extendsLegacySnapshot = PartialJSONParser.parseObject(snapshot).map { Self.isJSONPrefix(snapshot: $0, current: parsed) } ?? false
                if matchesSnapshot || extendsLegacySnapshot {
                    blocks[index] = .toolCall(caughtUp: true, catchupJSON: "", snapshotArguments: "")
                    return catchup.isEmpty ? nil : .toolCallCheckpoint(contentIndex: index, json: catchup)
                }
            }
            blocks[index] = .toolCall(caughtUp: false, catchupJSON: catchup, snapshotArguments: snapshot)
            return nil
        case .toolCallEnd(let index, let toolCall, _):
            guard toolCall.type == "toolCall" else { throw AIError.provider("toolcall_end event has invalid tool call at index \(index)") }
            try end(index: index, expected: "toolCall")
            return .toolCallEnd(contentIndex: index, id: toolCall.id ?? "", name: toolCall.name ?? "", arguments: toolCall.arguments ?? [:], thoughtSignature: toolCall.thoughtSignature, namespace: toolCall.namespace)
        case .start, .done, .error:
            return nil
        }
    }

    private func encodeTextDelta(index: Int, delta: String, kind: String) throws -> AssistantMessageFrame? {
        let state = blocks[index]
        let coveredChars: Int
        let deltaChars: Int
        switch (kind, state) {
        case ("text", .text(let covered, let deltas)?), ("thinking", .thinking(let covered, let deltas)?):
            coveredChars = covered; deltaChars = deltas
        default:
            throw AIError.provider("Assistant message \(kind) block \(index) has not started")
        }
        let deltaStart = deltaChars
        let newDeltaChars = deltaChars + delta.count
        let covered = max(0, coveredChars - deltaStart)
        if kind == "text" { blocks[index] = .text(coveredChars: coveredChars, deltaChars: newDeltaChars) }
        else { blocks[index] = .thinking(coveredChars: coveredChars, deltaChars: newDeltaChars) }
        if covered >= delta.count { return nil }
        let start = delta.index(delta.startIndex, offsetBy: covered)
        let uncovered = String(delta[start...])
        return kind == "text" ? .textDelta(contentIndex: index, delta: uncovered) : .thinkingDelta(contentIndex: index, delta: uncovered)
    }

    private func start(index: Int, state: BlockState) throws {
        guard index >= 0 else { throw AIError.provider("Invalid assistant message frame contentIndex: \(index)") }
        if blocks[index] != nil { throw AIError.provider("Assistant message block \(index) starts more than once") }
        blocks[index] = state
    }

    private func end(index: Int, expected: String) throws {
        guard let state = blocks[index] else { throw AIError.provider("Assistant message \(expected) block \(index) has not started") }
        switch (expected, state) {
        case ("text", .text), ("thinking", .thinking), ("toolCall", .toolCall): blocks.removeValue(forKey: index)
        default: throw AIError.provider("Assistant message block \(index) is not \(expected)")
        }
    }

    private func eventBlock(partial: Message?, index: Int, expected: String, type: String) throws -> ContentBlock {
        guard index >= 0 else { throw AIError.provider("Invalid assistant message frame contentIndex: \(index)") }
        guard let block = partial?.content[safe: index] else { throw AIError.provider("\(type) event has no content block at index \(index)") }
        guard block.type == expected else { throw AIError.provider("\(type) event points to \(block.type) block at index \(index)") }
        return block
    }

    private static func jsonString(_ object: [String: JSONValue]) -> String { guard let data = try? JSONEncoder().encode(object) else { return "{}" }; return String(data: data, encoding: .utf8) ?? "{}" }

    private static func isJSONPrefix(snapshot: [String: JSONValue], current: [String: JSONValue]) -> Bool {
        snapshot.allSatisfy { key, value in current[key].map { isJSONPrefix(snapshot: value, current: $0) } ?? false }
    }

    private static func isJSONPrefix(snapshot: JSONValue, current: JSONValue) -> Bool {
        switch (snapshot, current) {
        case (.string(let prefix), .string(let value)): return value.hasPrefix(prefix)
        case (.array(let prefix), .array(let value)):
            guard prefix.count <= value.count else { return false }
            return zip(prefix, value).allSatisfy { isJSONPrefix(snapshot: $0, current: $1) }
        case (.object(let prefix), .object(let value)): return isJSONPrefix(snapshot: prefix, current: value)
        case (.null, .null): return true
        case (.bool(let left), .bool(let right)): return left == right
        case (.number(let left), .number(let right)): return left == right
        default: return false
        }
    }

    private func eventType(_ event: AIEvent) -> String {
        switch event {
        case .start: return "start"
        case .textStart: return "text_start"
        case .textDelta: return "text_delta"
        case .textEnd: return "text_end"
        case .thinkingStart: return "thinking_start"
        case .thinkingDelta: return "thinking_delta"
        case .thinkingEnd: return "thinking_end"
        case .toolCallStart: return "toolcall_start"
        case .toolCallDelta: return "toolcall_delta"
        case .toolCallEnd: return "toolcall_end"
        case .done: return "done"
        case .error: return "error"
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

public struct AssistantMessageFrameReducer {
    private enum BlockState { case text(ended: Bool), thinking(ended: Bool), toolCall(ended: Bool, json: String) }

    public static func reduce(_ frames: [AssistantMessageFrame]) throws -> Message? {
        var message: Message?
        var beforeStart: String?
        var states: [Int: BlockState] = [:]
        for frame in frames {
            if case .start(let partial) = frame {
                if message != nil { throw AIError.provider("Assistant message frame sequence contains more than one start frame") }
                if let beforeStart { throw AIError.provider("\(beforeStart) frame appears before the start frame") }
                var clone = partial
                clone.content = []
                clone.stopReason = .pending
                message = clone
                continue
            }
            guard message != nil else { beforeStart = beforeStart ?? frameType(frame); continue }
            switch frame {
            case .start: break
            case .textStart(let index, let content):
                try append(index: index, content: content, expected: "text", message: &message!, states: &states, state: .text(ended: false))
            case .textDelta(let index, let delta):
                let block = try active(index: index, expected: "text", frame: frame, message: &message!, states: &states)
                message!.content[block].text = (message!.content[block].text ?? "") + delta
            case .textEnd(let index, let content, let signature):
                let block = try active(index: index, expected: "text", frame: frame, message: &message!, states: &states)
                message!.content[block].text = content
                message!.content[block].textSignature = signature
                states[index] = .text(ended: true)
            case .thinkingStart(let index, let content):
                try append(index: index, content: content, expected: "thinking", message: &message!, states: &states, state: .thinking(ended: false))
            case .thinkingDelta(let index, let delta):
                let block = try active(index: index, expected: "thinking", frame: frame, message: &message!, states: &states)
                message!.content[block].thinking = (message!.content[block].thinking ?? "") + delta
            case .thinkingEnd(let index, let content, let signature, let redacted):
                let block = try active(index: index, expected: "thinking", frame: frame, message: &message!, states: &states)
                message!.content[block].thinking = content
                message!.content[block].thinkingSignature = signature
                message!.content[block].redacted = redacted
                states[index] = .thinking(ended: true)
            case .toolCallStart(let index, let toolCall):
                try append(index: index, content: toolCall, expected: "toolCall", message: &message!, states: &states, state: .toolCall(ended: false, json: ""))
            case .toolCallCheckpoint(let index, let json):
                let block = try active(index: index, expected: "toolCall", frame: frame, message: &message!, states: &states)
                message!.content[block].arguments = PartialJSONParser.parseObject(json) ?? [:]
                states[index] = .toolCall(ended: false, json: json)
            case .toolCallDelta(let index, let delta):
                _ = try active(index: index, expected: "toolCall", frame: frame, message: &message!, states: &states)
                if case .toolCall(let ended, let json)? = states[index] { states[index] = .toolCall(ended: ended, json: json + delta) }
            case .toolCallEnd(let index, let id, let name, let arguments, let thoughtSignature, let namespace):
                let block = try active(index: index, expected: "toolCall", frame: frame, message: &message!, states: &states)
                message!.content[block].id = id
                message!.content[block].name = name
                message!.content[block].arguments = arguments
                message!.content[block].thoughtSignature = thoughtSignature
                message!.content[block].namespace = namespace
                states[index] = .toolCall(ended: true, json: "")
            }
        }
        guard var result = message else { return nil }
        for (index, state) in states {
            if case .toolCall(let ended, let json) = state, !ended, !json.isEmpty, result.content.indices.contains(index), result.content[index].type == "toolCall" {
                result.content[index].arguments = PartialJSONParser.parseObject(json) ?? [:]
            }
        }
        return result
    }

    private static func append(index: Int, content: ContentBlock, expected: String, message: inout Message, states: inout [Int: BlockState], state: BlockState) throws {
        guard index >= 0 else { throw AIError.provider("Invalid assistant message frame contentIndex: \(index)") }
        guard index == message.content.count else { throw AIError.provider("Cannot start assistant message block at index \(index)") }
        guard content.type == expected else { throw AIError.provider("assistant message frame contains \(content.type) content, expected \(expected)") }
        message.content.append(content)
        states[index] = state
    }

    private static func active(index: Int, expected: String, frame: AssistantMessageFrame, message: inout Message, states: inout [Int: BlockState]) throws -> Int {
        guard index >= 0, message.content.indices.contains(index), states[index] != nil else { throw AIError.provider("\(frameType(frame)) frame has no started block at index \(index)") }
        guard message.content[index].type == expected else { throw AIError.provider("\(frameType(frame)) frame expected \(expected) block at index \(index)") }
        switch states[index] {
        case .text(let ended)?, .thinking(let ended)?, .toolCall(let ended, _)?:
            if ended { throw AIError.provider("\(frameType(frame)) frame follows the end of block at index \(index)") }
        case nil: break
        }
        return index
    }

    private static func frameType(_ frame: AssistantMessageFrame) -> String {
        switch frame {
        case .start: return "start"
        case .textStart: return "text_start"
        case .textDelta: return "text_delta"
        case .textEnd: return "text_end"
        case .thinkingStart: return "thinking_start"
        case .thinkingDelta: return "thinking_delta"
        case .thinkingEnd: return "thinking_end"
        case .toolCallStart: return "toolcall_start"
        case .toolCallCheckpoint: return "toolcall_checkpoint"
        case .toolCallDelta: return "toolcall_delta"
        case .toolCallEnd: return "toolcall_end"
        }
    }
}
