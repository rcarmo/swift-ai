import Foundation

public enum ContextUtilities {
    private static let overflowPatterns = [
        "prompt is too long", "request_too_large", "input is too long for requested model",
        "exceeds the context window", "exceeds maximum context length", "maximum context length",
        "maximum context length of", "exceeds model's maximum context length", "longer than the model's context length",
        "input token count", "maximum prompt length", "reduce the length of the messages",
        "maximum allowed input length", "exceeds the maximum allowed input length", "exceeds the available context size", "greater than the context length",
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
            if texts.contains(where: { text in text.contains("prompt has") && text.contains("tokens") && text.contains("configured context size") }) { return true }
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
        var coerced = arguments
        if case .object(let properties)? = schema["properties"] {
            for (name, value) in arguments {
                if case .object(let propertySchema)? = properties[name] { coerced[name] = try validateAndCoerce(name: name, value: value, schema: propertySchema, toolName: tool.name) }
            }
        }
        return coerced
    }

    private static func validateAndCoerce(name: String, value: JSONValue, schema: [String: JSONValue], toolName: String) throws -> JSONValue {
        let expectedTypes: [String]
        switch schema["type"] {
        case .string(let expected)?: expectedTypes = [expected]
        case .array(let values)?: expectedTypes = values.compactMap(\.stringValue)
        default: return value
        }
        if let actual = jsonType(value), expectedTypes.contains(actual) {
            return try coerce(name: name, value: value, expected: actual, schema: schema, toolName: toolName)
        }
        var lastError: Error?
        for expected in expectedTypes {
            do { return try coerce(name: name, value: value, expected: expected, schema: schema, toolName: toolName) } catch { lastError = error }
        }
        throw lastError ?? typeError(toolName: toolName, field: name, expected: expectedTypes.joined(separator: "/"), actual: value)
    }

    private static func jsonType(_ value: JSONValue) -> String? {
        switch value { case .string: return "string"; case .number(let n): return n.rounded() == n ? "integer" : "number"; case .bool: return "boolean"; case .array: return "array"; case .object: return "object"; case .null: return "null" }
    }

    private static func coerce(name: String, value: JSONValue, expected: String, schema: [String: JSONValue], toolName: String) throws -> JSONValue {
        switch expected {
        case "string":
            let stringValue: String
            switch value { case .string(let v): stringValue = v; case .null: stringValue = ""; case .bool(let v): stringValue = v ? "true" : "false"; case .number(let v): stringValue = String(v); default: throw typeError(toolName: toolName, field: name, expected: "string", actual: value) }
            if case .array(let allowed)? = schema["enum"] {
                let allowedStrings = allowed.compactMap { item -> String? in if case .string(let v) = item { return v }; return nil }
                if !allowedStrings.isEmpty, !allowedStrings.contains(stringValue) { throw AIError.provider("validation failed for tool \(toolName): field \(name): value \(stringValue) not in enum") }
            }
            return .string(stringValue)
        case "number":
            switch value { case .number: return value; case .string(let s): if let n = Double(s) { return .number(n) }; case .bool(let b): return .number(b ? 1 : 0); case .null: return .number(0); default: break }
            throw typeError(toolName: toolName, field: name, expected: "number", actual: value)
        case "integer":
            let numeric: Double
            switch value { case .number(let n): numeric = n; case .string(let s): guard let n = Double(s) else { throw typeError(toolName: toolName, field: name, expected: "integer", actual: value) }; numeric = n; default: throw typeError(toolName: toolName, field: name, expected: "integer", actual: value) }
            guard numeric.rounded() == numeric else { throw typeError(toolName: toolName, field: name, expected: "integer", actual: value) }
            return .number(numeric)
        case "boolean":
            switch value { case .bool: return value; case .string("true"): return .bool(true); case .string("false"): return .bool(false); case .number(1): return .bool(true); case .number(0): return .bool(false); default: break }
            throw typeError(toolName: toolName, field: name, expected: "boolean", actual: value)
        case "array":
            guard case .array = value else { throw typeError(toolName: toolName, field: name, expected: "array", actual: value) }
            return value
        case "object":
            guard case .object = value else { throw typeError(toolName: toolName, field: name, expected: "object", actual: value) }
            return value
        case "null":
            switch value { case .null, .string(""), .number(0), .bool(false): return .null; default: throw typeError(toolName: toolName, field: name, expected: "null", actual: value) }
        default:
            return value
        }
    }

    private static func typeError(toolName: String, field: String, expected: String, actual: JSONValue) -> AIError {
        AIError.provider("validation failed for tool \(toolName): field \(field): expected \(expected), got \(actual)")
    }
}
