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
