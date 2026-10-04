import Foundation
import Crypto

public enum DurableToolReplayPolicy: String, Codable, Sendable { case safe, unsafe }

public struct DurableToolBinding: Codable, Equatable, Sendable {
    public var definition: Tool
    public var implementationID: String
    public var implementationVersion: String
    public var replayPolicy: DurableToolReplayPolicy
    public var schemaIdentity: String

    public init(definition: Tool, implementationID: String, implementationVersion: String, replayPolicy: DurableToolReplayPolicy) throws {
        try DurableToolSchema.validateDefinition(definition)
        guard !implementationID.isEmpty, implementationID.utf8.count <= 256, !implementationVersion.isEmpty, implementationVersion.utf8.count <= 128 else { throw DurableError.invalidRecord("invalid tool implementation identity") }
        self.definition = definition
        self.implementationID = implementationID
        self.implementationVersion = implementationVersion
        self.replayPolicy = replayPolicy
        self.schemaIdentity = try DurableToolSchema.identity(definition.parameters)
    }
}

public final class DurableCancellationSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    public init() {}
    public var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func cancel() { lock.lock(); value = true; lock.unlock() }
}

public struct DurableToolExecution: Sendable {
    public let durableToolID: String
    public let idempotencyKey: String
    public let providerCallID: String
    public let arguments: [String: JSONValue]
    public let logicalAttempt: Int
    public let cancellation: DurableCancellationSignal
    public init(durableToolID: String, idempotencyKey: String, providerCallID: String, arguments: [String: JSONValue], logicalAttempt: Int, cancellation: DurableCancellationSignal = DurableCancellationSignal()) {
        self.durableToolID = durableToolID; self.idempotencyKey = idempotencyKey; self.providerCallID = providerCallID; self.arguments = arguments; self.logicalAttempt = logicalAttempt; self.cancellation = cancellation
    }
}

public struct DurableToolApplicationDocument: Codable, Equatable, Sendable {
    public enum Target: String, Codable, Sendable { case conversation, toolTask }
    public var target: Target
    public var suffix: String
    public var value: JSONValue
    public init(target: Target, suffix: String, value: JSONValue) { self.target = target; self.suffix = suffix; self.value = value }
}

public struct DurableToolResult: Sendable, Equatable {
    public var content: String
    public var isError: Bool
    public var usage: Usage?
    public var documents: [DurableToolApplicationDocument]
    public init(content: String, isError: Bool = false, usage: Usage? = nil, documents: [DurableToolApplicationDocument] = []) {
        self.content = content; self.isError = isError; self.usage = usage; self.documents = documents
    }
}

public struct DurableLiveConnection: Sendable, Equatable {
    public var endpoint: String?
    public var headers: ProviderHeaders?
    public var apiKey: String?
    public var bearerToken: String?
    public init(endpoint: String? = nil, headers: ProviderHeaders? = nil, apiKey: String? = nil, bearerToken: String? = nil) {
        self.endpoint = endpoint; self.headers = headers; self.apiKey = apiKey; self.bearerToken = bearerToken
    }
}

public typealias DurableLiveConnectionResolver = @Sendable (Model) async throws -> DurableLiveConnection
public typealias DurableToolExecutor = @Sendable (DurableToolExecution) async throws -> DurableToolResult

public struct DurableToolRegistration: Sendable {
    public var binding: DurableToolBinding
    public var execute: DurableToolExecutor
    public init(definition: Tool, implementationID: String, implementationVersion: String, replayPolicy: DurableToolReplayPolicy = .unsafe, execute: @escaping DurableToolExecutor) throws {
        self.binding = try DurableToolBinding(definition: definition, implementationID: implementationID, implementationVersion: implementationVersion, replayPolicy: replayPolicy)
        self.execute = execute
    }
}

struct DurableRegisteredTool: Sendable { var binding: DurableToolBinding; var execute: DurableToolExecutor }

public actor DurableToolRegistry {
    public static let maxTools = 16
    private var registrations: [String: DurableRegisteredTool] = [:]
    private var sealed = false
    public init() {}

    public func register(_ registration: DurableToolRegistration) throws {
        guard !sealed else { throw DurableError.closed }
        let source = registration.binding
        let binding = try DurableToolBinding(definition: source.definition, implementationID: source.implementationID, implementationVersion: source.implementationVersion, replayPolicy: source.replayPolicy)
        guard binding.schemaIdentity == source.schemaIdentity else { throw DurableError.invalidRecord("tool schema identity mismatch") }
        if registrations[binding.definition.name] == nil, registrations.count >= Self.maxTools { throw DurableError.queueFull }
        registrations[binding.definition.name] = DurableRegisteredTool(binding: binding, execute: registration.execute)
    }
    public func remove(_ name: String) { if !sealed { registrations.removeValue(forKey: name) } }
    public func seal() { sealed = true }
    func snapshot() -> [DurableToolBinding] { registrations.values.map(\.binding).sorted { $0.definition.name < $1.definition.name } }
    func resolve(_ binding: DurableToolBinding) -> DurableRegisteredTool? {
        guard let value = registrations[binding.definition.name], value.binding == binding else { return nil }
        return value
    }
}

struct DurableToolIntent: Codable, Equatable, Sendable {
    var parentTaskID: Int64
    var providerCallID: String
    var durableToolID: String
    var idempotencyKey: String
    var binding: DurableToolBinding
    var originalArguments: [String: JSONValue]
    var executionArguments: [String: JSONValue]
    var logicalAttempt: Int
}

struct DurableStagedToolResult: Codable, Equatable, Sendable {
    var content: String
    var isError: Bool
    var usage: Usage?
    var documents: [DurableToolApplicationDocument]
    var code: String?
    var billingUnknown: Bool
}

enum DurableToolOutputValidation: Error { case outputLimit, invalidUsage, invalidDocuments }

enum DurableToolSchema {
    private static let maxDepth = 32
    private static let maxNodes = 4_096
    private static let allowedName = try! NSRegularExpression(pattern: "^[A-Za-z0-9_.-]+$")

    static func validateDefinition(_ tool: Tool) throws {
        guard !tool.name.isEmpty, tool.name.utf8.count <= 128, validKindPart(tool.name), tool.description.utf8.count <= DurableLimits.maxStringBytes, tool.constrainedSampling == nil else { throw DurableError.invalidRecord("invalid durable tool definition") }
        guard tool.parameters.objectValue?["type"]?.stringValue == "object" else { throw DurableError.invalidRecord("tool schema root must be object") }
        try DurableNativePreflight.validate(tool, maxBytes: DurableLimits.maxDocumentBytes)
        var nodes = 0
        try validateSchema(tool.parameters, depth: 0, nodes: &nodes)
    }

    static func identity(_ schema: JSONValue) throws -> String {
        var nodes = 0; try validateSchema(schema, depth: 0, nodes: &nodes)
        let data = try DurableValidation.encoder.encode(schema)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func validate(arguments: [String: JSONValue], against schema: JSONValue) throws {
        try DurableNativePreflight.validate(arguments, maxBytes: DurableLimits.maxArgumentsBytes)
        var nodes = 0
        try validateValue(.object(arguments), schema: schema, depth: 0, nodes: &nodes)
    }

    static func validateOutput(_ output: DurableToolResult) throws {
        guard output.content.utf8.count <= 32 * 1024 else { throw DurableToolOutputValidation.outputLimit }
        do { try DurableGenerationPlanner.validateUsage(output.usage) } catch { throw DurableToolOutputValidation.invalidUsage }
        guard output.documents.count <= 16 else { throw DurableToolOutputValidation.invalidDocuments }
        do {
            for document in output.documents { try DurableNativePreflight.validate(document, maxBytes: DurableLimits.maxDocumentBytes) }
            try DurableNativePreflight.validate(output.documents, maxBytes: DurableLimits.maxCheckpointBytes / 2)
        } catch { throw DurableToolOutputValidation.invalidDocuments }
    }

    static func validKindPart(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 128 else { return false }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return allowedName.firstMatch(in: value, range: range)?.range == range
    }

    private static func validateSchema(_ schema: JSONValue, depth: Int, nodes: inout Int) throws {
        try bump(depth, &nodes)
        guard let object = schema.objectValue, let type = object["type"]?.stringValue else { throw DurableError.invalidRecord("tool schema object/type required") }
        let common: Set<String> = ["type", "description", "enum"]
        let specific: Set<String>
        switch type {
        case "object": specific = ["properties", "required", "additionalProperties"]
        case "array": specific = ["items", "minItems", "maxItems"]
        case "string": specific = ["minLength", "maxLength", "pattern"]
        case "number", "integer": specific = ["minimum", "maximum"]
        case "boolean", "null": specific = []
        default: throw DurableError.invalidRecord("unsupported tool schema type")
        }
        guard Set(object.keys).isSubset(of: common.union(specific)) else { throw DurableError.invalidRecord("unsupported tool schema keyword") }
        if let description = object["description"], description.stringValue == nil { throw DurableError.invalidRecord("tool schema description must be string") }
        if let values = object["enum"]?.arrayValue {
            guard !values.isEmpty else { throw DurableError.invalidRecord("tool schema enum empty") }
            for value in values { guard matchesType(value, type) else { throw DurableError.invalidRecord("tool schema enum type mismatch") } }
        } else if object["enum"] != nil { throw DurableError.invalidRecord("tool schema enum must be array") }
        switch type {
        case "object":
            let properties = object["properties"]?.objectValue ?? [:]
            guard properties.keys.allSatisfy({ !$0.isEmpty && $0.utf8.count <= DurableLimits.maxStringBytes }) else { throw DurableError.invalidRecord("tool schema property name exceeds limit") }
            if object["properties"] != nil, object["properties"]?.objectValue == nil { throw DurableError.invalidRecord("tool schema properties must be object") }
            for child in properties.values { try validateSchema(child, depth: depth + 1, nodes: &nodes) }
            let required = object["required"]?.arrayValue ?? []
            if object["required"] != nil, object["required"]?.arrayValue == nil { throw DurableError.invalidRecord("tool schema required must be array") }
            var seen = Set<String>()
            for item in required { guard let name = item.stringValue, properties[name] != nil, seen.insert(name).inserted else { throw DurableError.invalidRecord("invalid tool schema required") } }
            if let additional = object["additionalProperties"], additional.boolValue == nil { throw DurableError.invalidRecord("additionalProperties must be boolean") }
        case "array":
            guard let items = object["items"] else { throw DurableError.invalidRecord("tool schema items required") }
            try validateSchema(items, depth: depth + 1, nodes: &nodes)
            try validateBounds(object, minimum: "minItems", maximum: "maxItems", integral: true)
        case "string":
            try validateBounds(object, minimum: "minLength", maximum: "maxLength", integral: true)
            if let pattern = object["pattern"] { guard let text = pattern.stringValue, text.utf8.count <= 4_096, (try? NSRegularExpression(pattern: text)) != nil else { throw DurableError.invalidRecord("invalid tool schema pattern") } }
        case "number", "integer": try validateBounds(object, minimum: "minimum", maximum: "maximum", integral: false)
        default: break
        }
    }

    private static func validateValue(_ value: JSONValue, schema: JSONValue, depth: Int, nodes: inout Int) throws {
        try bump(depth, &nodes)
        guard let object = schema.objectValue, let type = object["type"]?.stringValue, matchesType(value, type) else { throw DurableError.invalidRecord("tool argument type mismatch") }
        if let values = object["enum"]?.arrayValue, !values.contains(value) { throw DurableError.invalidRecord("tool argument enum mismatch") }
        switch type {
        case "object":
            let values = value.objectValue!, properties = object["properties"]?.objectValue ?? [:]
            let required = Set((object["required"]?.arrayValue ?? []).compactMap(\.stringValue))
            guard required.isSubset(of: Set(values.keys)) else { throw DurableError.invalidRecord("missing required tool argument") }
            let allowUnknown = object["additionalProperties"]?.boolValue ?? false
            for (name, child) in values { if let childSchema = properties[name] { try validateValue(child, schema: childSchema, depth: depth + 1, nodes: &nodes) } else if !allowUnknown { throw DurableError.invalidRecord("unknown tool argument") } else { try validateArbitrary(child, depth: depth + 1, nodes: &nodes) } }
        case "array":
            let values = value.arrayValue!; try enforceCount(values.count, object, "minItems", "maxItems")
            for child in values { try validateValue(child, schema: object["items"]!, depth: depth + 1, nodes: &nodes) }
        case "string":
            let text = value.stringValue!; try enforceCount(text.count, object, "minLength", "maxLength")
            if let pattern = object["pattern"]?.stringValue { let regex = try NSRegularExpression(pattern: pattern); let range = NSRange(text.startIndex..<text.endIndex, in: text); guard regex.firstMatch(in: text, range: range) != nil else { throw DurableError.invalidRecord("tool argument pattern mismatch") } }
        case "number", "integer":
            let number = value.doubleValue!; if let minimum = object["minimum"]?.doubleValue, number < minimum { throw DurableError.invalidRecord("tool argument below minimum") }; if let maximum = object["maximum"]?.doubleValue, number > maximum { throw DurableError.invalidRecord("tool argument above maximum") }
        default: break
        }
    }

    private static func validateArbitrary(_ value: JSONValue, depth: Int, nodes: inout Int) throws {
        try bump(depth, &nodes)
        switch value { case .number(let n): guard n.isFinite else { throw DurableError.invalidRecord("non-finite tool argument") }; case .array(let a): for v in a { try validateArbitrary(v, depth: depth + 1, nodes: &nodes) }; case .object(let o): for v in o.values { try validateArbitrary(v, depth: depth + 1, nodes: &nodes) }; default: break }
    }
    private static func bump(_ depth: Int, _ nodes: inout Int) throws { guard depth <= maxDepth else { throw DurableError.invalidRecord("tool schema depth limit") }; nodes += 1; guard nodes <= maxNodes else { throw DurableError.invalidRecord("tool schema node limit") } }
    private static func matchesType(_ value: JSONValue, _ type: String) -> Bool { switch (type, value) { case ("object", .object), ("array", .array), ("string", .string), ("boolean", .bool), ("null", .null): return true; case ("number", .number(let n)): return n.isFinite; case ("integer", .number(let n)): return n.isFinite && n.rounded(.towardZero) == n && abs(n) <= Double(DurableLimits.maxExactInteger); default: return false } }
    private static func validateBounds(_ object: [String: JSONValue], minimum: String, maximum: String, integral: Bool) throws { func get(_ key: String) throws -> Double? { guard let value = object[key] else { return nil }; guard let number = value.doubleValue, number.isFinite, (!integral || (number >= 0 && number.rounded(.towardZero) == number && number <= Double(DurableLimits.maxJSONNodes))) else { throw DurableError.invalidRecord("invalid tool schema bound") }; return number }; let lo = try get(minimum), hi = try get(maximum); if let lo, let hi, lo > hi { throw DurableError.invalidRecord("incoherent tool schema bounds") } }
    private static func enforceCount(_ count: Int, _ object: [String: JSONValue], _ minimum: String, _ maximum: String) throws { if let lo = object[minimum]?.doubleValue, Double(count) < lo { throw DurableError.invalidRecord("tool argument below size minimum") }; if let hi = object[maximum]?.doubleValue, Double(count) > hi { throw DurableError.invalidRecord("tool argument above size maximum") } }
}
