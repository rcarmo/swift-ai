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
