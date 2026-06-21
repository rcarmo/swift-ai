import Foundation

public enum ContextUtilities {
    private static let overflowPatterns = [
        "prompt is too long", "request_too_large", "input is too long for requested model",
        "exceeds the context window", "maximum context length", "too many tokens",
        "token limit exceeded", "model_context_window_exceeded", "context length exceeded"
    ]
    private static let nonOverflowPatterns = ["rate limit", "too many requests", "service unavailable", "throttling error"]

    public static func isContextOverflow(_ message: Message?, contextWindow: Int) -> Bool {
        guard let message else { return false }
        if message.stopReason == .error {
            let texts = overflowCandidateTexts(message).map { $0.lowercased() }
            if texts.contains(where: { text in nonOverflowPatterns.contains(where: { text.contains($0) }) }) { return false }
            if texts.contains(where: { text in overflowPatterns.contains(where: { text.contains($0) }) }) { return true }
        }
        if contextWindow > 0, message.stopReason == .stop, let usage = message.usage, usage.input + usage.cacheRead > contextWindow { return true }
        if contextWindow > 0, message.stopReason == .length, let usage = message.usage, usage.output == 0, Double(usage.input + usage.cacheRead) >= Double(contextWindow) * 0.99 { return true }
        return false
    }

    private static func overflowCandidateTexts(_ message: Message) -> [String] {
        var texts: [String] = []
        if let error = message.errorMessage { texts.append(error) }
        for diagnostic in message.diagnostics ?? [] { texts.append(diagnostic.error.message) }
        return texts
    }

    public static func validateToolCall(tools: [Tool], toolCall: ContentBlock) throws -> [String: JSONValue] {
        guard let name = toolCall.name, let tool = tools.first(where: { $0.name == name }) else { throw AIError.provider("tool \(toolCall.name ?? "") not found") }
        return try validateToolArguments(tool: tool, arguments: toolCall.arguments ?? [:])
    }

    public static func validateToolArguments(tool: Tool, arguments: [String: JSONValue]) throws -> [String: JSONValue] {
        guard case .object(let schema) = tool.parameters else { return arguments }
        if case .array(let required)? = schema["required"] {
            for item in required { if case .string(let name) = item, arguments[name] == nil { throw AIError.provider("validation failed for tool \(tool.name): missing required field \(name)") } }
        }
        return arguments
    }
}
