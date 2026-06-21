import Foundation

public enum ContextUtilities {
    private static let overflowPatterns = [
        "prompt is too long", "request_too_large", "input is too long for requested model",
        "exceeds the context window", "exceeds maximum context length", "maximum context length",
        "input token count", "maximum prompt length", "reduce the length of the messages",
        "maximum allowed input length", "exceeds the available context size", "greater than the context length",
        "context window exceeds limit", "exceeded model token limit", "model_context_window_exceeded",
        "prompt too long", "context_length_exceeded", "context length exceeded", "too many tokens",
        "token limit exceeded", "400 (no body)", "413 (no body)"
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
        for diagnostic in message.diagnostics ?? [] {
            texts.append(diagnostic.error.message)
            if let code = diagnostic.error.code { texts.append(String(describing: code)) }
        }
        return texts
    }

    public static func validateToolCall(tools: [Tool], toolCall: ContentBlock) throws -> [String: JSONValue] {
        guard let name = toolCall.name, let tool = tools.first(where: { $0.name == name }) else { throw AIError.provider("tool \(toolCall.name ?? "") not found") }
        return try validateToolArguments(tool: tool, arguments: toolCall.arguments ?? [:])
    }

    public static func validateToolArguments(tool: Tool, arguments: [String: JSONValue]) throws -> [String: JSONValue] {
        guard case .object(let schema) = tool.parameters else { return arguments }
        if case .array(let required)? = schema["required"] {
            for item in required {
                if case .string(let name) = item, arguments[name] == nil { throw AIError.provider("validation failed for tool \(tool.name): missing required field \(name)") }
            }
        }
        if case .object(let properties)? = schema["properties"] {
            for (name, value) in arguments {
                if case .object(let propertySchema)? = properties[name] { try validateType(name: name, value: value, schema: propertySchema, toolName: tool.name) }
            }
        }
        return arguments
    }

    private static func validateType(name: String, value: JSONValue, schema: [String: JSONValue], toolName: String) throws {
        guard case .string(let expected)? = schema["type"] else { return }
        switch expected {
        case "string":
            guard case .string(let stringValue) = value else { throw typeError(toolName: toolName, field: name, expected: "string", actual: value) }
            if case .array(let allowed)? = schema["enum"] {
                let allowedStrings = allowed.compactMap { item -> String? in if case .string(let v) = item { return v }; return nil }
                if !allowedStrings.isEmpty, !allowedStrings.contains(stringValue) { throw AIError.provider("validation failed for tool \(toolName): field \(name): value \(stringValue) not in enum") }
            }
        case "number":
            guard case .number = value else { throw typeError(toolName: toolName, field: name, expected: "number", actual: value) }
        case "integer":
            guard case .number(let n) = value, n.rounded() == n else { throw typeError(toolName: toolName, field: name, expected: "integer", actual: value) }
        case "boolean":
            guard case .bool = value else { throw typeError(toolName: toolName, field: name, expected: "boolean", actual: value) }
        case "array":
            guard case .array = value else { throw typeError(toolName: toolName, field: name, expected: "array", actual: value) }
        case "object":
            guard case .object = value else { throw typeError(toolName: toolName, field: name, expected: "object", actual: value) }
        default:
            return
        }
    }

    private static func typeError(toolName: String, field: String, expected: String, actual: JSONValue) -> AIError {
        AIError.provider("validation failed for tool \(toolName): field \(field): expected \(expected), got \(actual)")
    }
}
