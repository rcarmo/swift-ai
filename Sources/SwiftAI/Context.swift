import Foundation

public enum ContextUtilities {
    private static let overflowPatterns = [
        "prompt is too long", "request_too_large", "input is too long for requested model",
        "exceeds the context window", "exceeds maximum context length", "maximum context length",
        "maximum context length of", "exceeds model's maximum context length", "longer than the model's context length",
        "input token count", "maximum prompt length", "reduce the length of the messages",
        "maximum allowed input length", "exceeds the maximum allowed input length", "exceeds the available context size", "greater than the context length",
        "context window exceeds limit", "exceeded model token limit", "model_context_window_exceeded",
        "prompt too long", "range of input length should be", "context_length_exceeded", "context length exceeded", "too many tokens",
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

    public static func makeStrictJSONSchema(_ schema: JSONValue) throws -> JSONValue {
        guard case .object(var root) = schema else { throw AIError.provider("root schema must have type object") }
        try makeStrictJSONSchemaNode(&root)
        guard root["type"] == .string("object") else { throw AIError.provider("root schema must have type object") }
        return .object(root)
    }

    private static func makeStrictJSONSchemaNode(_ schema: inout [String: JSONValue]) throws {
        let unsupported = ["$ref", "$defs", "definitions", "allOf", "oneOf", "patternProperties", "dependentSchemas", "dependencies", "unevaluatedProperties", "propertyNames", "contains", "prefixItems", "not", "if", "then", "else"]
        for key in unsupported where schema[key] != nil { throw AIError.provider("") }
        if case .array(var anyOf)? = schema["anyOf"] {
            guard !anyOf.isEmpty else { throw AIError.provider("anyOf must contain at least one schema") }
            for index in anyOf.indices {
                guard case .object(var variant) = anyOf[index] else { throw AIError.provider("boolean schemas are unsupported") }
                if isStructuredSchema(variant) { throw AIError.provider("object and array unions are unsupported") }
                try makeStrictJSONSchemaNode(&variant)
                anyOf[index] = .object(variant)
            }
            schema["anyOf"] = .array(anyOf)
        }
        if case .array = schema["items"] { throw AIError.provider("tuple schemas are unsupported") }
        if case .object(var items)? = schema["items"] { try makeStrictJSONSchemaNode(&items); schema["items"] = .object(items) }
        guard schema["type"] == .string("object") else {
            if schema["properties"] != nil { throw AIError.provider("properties require type object") }
            return
        }
        if let additional = schema["additionalProperties"], additional != .bool(false) { throw AIError.provider("schema-valued or true additionalProperties is unsupported") }
        guard schema["properties"] == nil || schema["properties"]?.objectValue != nil else { throw AIError.provider("object properties must be a schema map") }
        let required = Set(schema["required"]?.arrayValue?.compactMap(\.stringValue) ?? [])
        guard schema["required"] == nil || schema["required"]?.arrayValue?.count == required.count else { throw AIError.provider("object required must be a string array") }
        var properties = schema["properties"]?.objectValue ?? [:]
        let names = Set(properties.keys)
        if !required.isSubset(of: names) { throw AIError.provider("required contains an unknown property") }
        for name in properties.keys.sorted() {
            guard case .object(var property) = properties[name] else { throw AIError.provider("boolean schemas are unsupported") }
            try makeStrictJSONSchemaNode(&property)
            if !required.contains(name), !schemaAllowsNull(.object(property)) { property = ["anyOf": .array([.object(property), .object(["type": .string("null")])])] }
            properties[name] = .object(property)
        }
        schema["properties"] = .object(properties)
        schema["required"] = .array(properties.keys.sorted().map { .string($0) })
        schema["additionalProperties"] = .bool(false)
    }

    private static func isStructuredSchema(_ schema: [String: JSONValue]) -> Bool { schemaTypes(schema).contains { $0 == "object" || $0 == "array" } || schema["properties"] != nil || schema["items"] != nil }
    private static func schemaAllowsNull(_ schema: JSONValue) -> Bool {
        guard case .object(let object) = schema else { return false }
        if schemaTypes(object).contains("null") { return true }
        if object["const"] == .null { return true }
        if object["enum"]?.arrayValue?.contains(.null) == true { return true }
        return object["anyOf"]?.arrayValue?.contains(where: schemaAllowsNull) == true
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
        normalizeOptionalNulls(value: &coerced, schema: schema)
        if case .object(let properties)? = schema["properties"] {
            for (name, value) in coerced {
                if case .object(let propertySchema)? = properties[name] { coerced[name] = try validateAndCoerce(name: name, value: value, schema: propertySchema, toolName: tool.name) }
            }
        }
        return coerced
    }

    private static func normalizeOptionalNulls(value: inout [String: JSONValue], schema: [String: JSONValue]) {
        guard case .object(let properties)? = schema["properties"] else { return }
        let required = Set(schema["required"]?.arrayValue?.compactMap(\.stringValue) ?? [])
        for (key, propertySchemaValue) in properties {
            guard var current = value[key], case .object(let propertySchema) = propertySchemaValue else { continue }
            if current == .null, !required.contains(key), !matchesSchema(.null, schema: propertySchema) { value.removeValue(forKey: key); continue }
            if case .object(var nested) = current { normalizeOptionalNulls(value: &nested, schema: propertySchema); current = .object(nested); value[key] = current }
        }
    }

    private static func validateAndCoerce(name: String, value: JSONValue, schema: [String: JSONValue], toolName: String) throws -> JSONValue {
        var next = value
        if case .array(let allOf)? = schema["allOf"] {
            for item in allOf {
                if case .object(let nested) = item { next = try validateAndCoerce(name: name, value: next, schema: nested, toolName: toolName) }
            }
        }
        if case .array(let anyOf)? = schema["anyOf"] { next = try coerceUnion(name: name, value: next, schemas: anyOf, toolName: toolName) }
        if case .array(let oneOf)? = schema["oneOf"] { next = try coerceUnion(name: name, value: next, schemas: oneOf, toolName: toolName) }
        let expectedTypes = schemaTypes(schema)
        guard !expectedTypes.isEmpty else { return next }
        if let actual = jsonType(next), expectedTypes.contains(actual) { return try coerce(name: name, value: next, expected: actual, schema: schema, toolName: toolName) }
        var lastError: Error?
        for expected in expectedTypes {
            do { return try coerce(name: name, value: next, expected: expected, schema: schema, toolName: toolName) } catch { lastError = error }
        }
        throw lastError ?? typeError(toolName: toolName, field: name, expected: expectedTypes.joined(separator: "/"), actual: next)
    }

    private static func schemaTypes(_ schema: [String: JSONValue]) -> [String] {
        switch schema["type"] {
        case .string(let expected)?: return [expected]
        case .array(let values)?: return values.compactMap(\.stringValue)
        default: return []
        }
    }

    private static func coerceUnion(name: String, value: JSONValue, schemas: [JSONValue], toolName: String) throws -> JSONValue {
        let schemaObjects = schemas.compactMap { item -> [String: JSONValue]? in if case .object(let schema) = item { return schema }; return nil }
        for schema in schemaObjects where matchesSchema(value, schema: schema) { return value }
        var lastError: Error?
        for schema in schemaObjects {
            do {
                let candidate = try validateAndCoerce(name: name, value: value, schema: schema, toolName: toolName)
                if matchesSchema(candidate, schema: schema) { return candidate }
            } catch { lastError = error }
        }
        throw lastError ?? typeError(toolName: toolName, field: name, expected: "union", actual: value)
    }

    private static func matchesSchema(_ value: JSONValue, schema: [String: JSONValue]) -> Bool {
        let expectedTypes = schemaTypes(schema)
        if !expectedTypes.isEmpty { return jsonTypes(value).contains { expectedTypes.contains($0) } }
        if case .array(let anyOf)? = schema["anyOf"] {
            return anyOf.contains { item in if case .object(let nested) = item { return matchesSchema(value, schema: nested) }; return false }
        }
        if case .array(let oneOf)? = schema["oneOf"] {
            return oneOf.contains { item in if case .object(let nested) = item { return matchesSchema(value, schema: nested) }; return false }
        }
        if case .array(let allOf)? = schema["allOf"] {
            return allOf.allSatisfy { item in if case .object(let nested) = item { return matchesSchema(value, schema: nested) }; return true }
        }
        return true
    }

    private static func jsonType(_ value: JSONValue) -> String? { jsonTypes(value).first }

    private static func jsonTypes(_ value: JSONValue) -> [String] {
        switch value { case .string: return ["string"]; case .number(let n): return n.rounded() == n ? ["integer", "number"] : ["number"]; case .bool: return ["boolean"]; case .array: return ["array"]; case .object: return ["object"]; case .null: return ["null"] }
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
