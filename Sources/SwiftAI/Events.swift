import Foundation

public enum AIEvent: Sendable {
    case start(partial: Message?)
    case textStart(contentIndex: Int, partial: Message?)
    case textDelta(contentIndex: Int, delta: String, partial: Message?)
    case textEnd(contentIndex: Int, content: String, partial: Message?)
    case thinkingStart(contentIndex: Int, partial: Message?)
    case thinkingDelta(contentIndex: Int, delta: String, partial: Message?)
    case thinkingEnd(contentIndex: Int, content: String, partial: Message?)
    case toolCallStart(contentIndex: Int, partial: Message?)
    case toolCallDelta(contentIndex: Int, delta: String, partial: Message?)
    case toolCallEnd(contentIndex: Int, toolCall: ContentBlock, partial: Message?)
    case done(reason: StopReason, message: Message)
    case error(reason: StopReason, message: Message?, error: Error?)
}

public enum AIError: Error, Equatable, Sendable {
    case nilModel
    case noProvider(API)
    case provider(String)
    case invalidResponse(String)
    case apiError(status: Int, body: String)
}
