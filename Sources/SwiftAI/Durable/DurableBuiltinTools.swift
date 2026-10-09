import Foundation

public enum DurableBuiltinTools {
    public static func register(in registry: DurableToolRegistry, environment: any DurableExecutionEnvironment) async throws {
        func schema(_ properties: [String: JSONValue], required: [String]) -> JSONValue {
            .object(["type": .string("object"), "properties": .object(properties), "required": .array(required.map { .string($0) }), "additionalProperties": .bool(false)])
        }
        let string: JSONValue = .object(["type": .string("string")])
        let integer: JSONValue = .object(["type": .string("integer")])
        try await registry.register(DurableToolRegistration(definition: Tool(name: "read", description: "Read UTF-8 text in the configured environment; bounded to 2000 lines or 50KB.", parameters: schema(["path": string, "offset": integer, "limit": integer], required: ["path"])), implementationID: "swift-ai.read", implementationVersion: "1", replayPolicy: .safe, execute: { invocation in
            guard let path = invocation.arguments["path"]?.stringValue else { throw DurableError.invalidRecord("missing path") }
            let offset = invocation.arguments["offset"]?.doubleValue.flatMap(Int.init(exactly:)) ?? 1
            let limit = invocation.arguments["limit"]?.doubleValue.flatMap(Int.init(exactly:))
            let result = try await environment.read(path: path, offset: offset, limit: limit, cancellation: invocation.cancellation)
            return DurableToolResult(content: result.text + (result.truncated ? "\n[truncated; use offset/limit for another range]" : ""))
        }))
        try await registry.register(DurableToolRegistration(definition: Tool(name: "write", description: "Write UTF-8 content; creates parent directories in the configured environment.", parameters: schema(["path": string, "content": string], required: ["path", "content"])), implementationID: "swift-ai.write", implementationVersion: "1", replayPolicy: .safe, execute: { invocation in
            guard let path = invocation.arguments["path"]?.stringValue, let content = invocation.arguments["content"]?.stringValue else { throw DurableError.invalidRecord("missing write arguments") }
            try await environment.write(path: path, content: content, cancellation: invocation.cancellation)
            return DurableToolResult(content: "Successfully wrote to \(path)")
        }))
        let editItem: JSONValue = .object(["type": .string("object"), "properties": .object(["oldText": string, "newText": string]), "required": .array([.string("oldText"), .string("newText")]), "additionalProperties": .bool(false)])
        try await registry.register(DurableToolRegistration(definition: Tool(name: "edit", description: "Apply unique non-overlapping exact replacements against the original UTF-8 file.", parameters: schema(["path": string, "edits": .object(["type": .string("array"), "items": editItem])], required: ["path", "edits"])), implementationID: "swift-ai.edit", implementationVersion: "1", replayPolicy: .unsafe, execute: { invocation in
            guard let path = invocation.arguments["path"]?.stringValue, let values = invocation.arguments["edits"]?.arrayValue else { throw DurableError.invalidRecord("missing edit arguments") }
            let edits = try values.map { value -> DurableTextEdit in
                guard let item = value.objectValue, let old = item["oldText"]?.stringValue, let new = item["newText"]?.stringValue else { throw DurableError.invalidRecord("invalid edit") }
                return DurableTextEdit(oldText: old, newText: new)
            }
            try await environment.edit(path: path, edits: edits, cancellation: invocation.cancellation)
            return DurableToolResult(content: "Successfully replaced \(edits.count) block(s) in \(path)")
        }))
        try await registry.register(DurableToolRegistration(definition: Tool(name: "bash", description: "Execute a trusted bash script in the configured environment. Retains a bounded output tail and spills large output.", parameters: schema(["command": string, "timeout": .object(["type": .string("number")])], required: ["command"])), implementationID: "swift-ai.bash", implementationVersion: "1", replayPolicy: .unsafe, execute: { invocation in
            guard let command = invocation.arguments["command"]?.stringValue else { throw DurableError.invalidRecord("missing command") }
            let result = try await environment.execute(command: command, timeoutSeconds: invocation.arguments["timeout"]?.doubleValue, cancellation: invocation.cancellation)
            return DurableToolResult(content: result.output + (result.spillPath.map { "\nFull output: " + $0 } ?? "") + (result.exitCode == 0 ? "" : "\nCommand exited with code \(result.exitCode)"), isError: result.exitCode != 0)
        }))
    }
}
