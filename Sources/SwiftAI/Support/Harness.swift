import Foundation

public enum Harness {
    public static func cloneContext(_ context: AIContext?) -> AIContext? {
        guard let context else { return nil }
        // JSON round-trip gives a deep copy across value graphs and JSONValue maps.
        guard let data = try? JSONEncoder().encode(context), let clone = try? JSONDecoder().decode(AIContext.self, from: data) else { return context }
        return clone
    }

    public static func saveContext(_ context: AIContext, to url: URL) throws {
        let data = try JSONEncoder.pretty.encode(context)
        try data.write(to: url)
    }

    public static func loadContext(from url: URL) throws -> AIContext {
        try JSONDecoder().decode(AIContext.self, from: Data(contentsOf: url))
    }

    public static func estimateTokens(_ context: AIContext?) -> Int {
        guard let context else { return 0 }
        var total = (context.systemPrompt ?? "").count / 4
        for message in context.messages {
            total += 4
            for block in message.content {
                switch block.type {
                case "text": total += (block.text ?? "").count / 4
                case "thinking": total += (block.thinking ?? "").count / 4
                case "toolCall": total += (block.name ?? "").count / 4 + ((try? JSONEncoder().encode(block.arguments ?? [:]).count) ?? 0) / 4
                case "image": total += 1000
                default: break
                }
            }
        }
        for tool in context.tools ?? [] { total += tool.name.count / 4 + tool.description.count / 4 + ((try? JSONEncoder().encode(tool.parameters).count) ?? 0) / 4 }
        return total
    }

    public static func fitsInContextWindow(_ context: AIContext?, model: Model?) -> (fits: Bool, estimatedTokens: Int) {
        let tokens = estimateTokens(context)
        guard let model, model.contextWindow > 0 else { return (true, tokens) }
        return (tokens < model.contextWindow, tokens)
    }

    public static func compactContext(_ context: AIContext?, model: Model?, keepRecent: Int = 10) -> AIContext? {
        guard let context else { return nil }
        let fits = fitsInContextWindow(context, model: model).fits
        if fits { return context }
        var clone = cloneContext(context) ?? context
        let keep = max(1, keepRecent)
        if clone.messages.count > keep { clone.messages = Array(clone.messages.suffix(keep)) }
        return clone
    }

    public static func appendUserMessage(_ text: String, to context: inout AIContext) { context.messages.append(.user(text)) }

    public static func appendToolResult(toolCallId: String, toolName: String, text: String, isError: Bool, to context: inout AIContext) {
        var message = Message(role: .toolResult, content: [.text(text)])
        message.toolCallId = toolCallId
        message.toolName = toolName
        message.isError = isError
        context.messages.append(message)
    }

    public static func appendAssistantMessage(_ message: Message?, to context: inout AIContext) { if let message { context.messages.append(message) } }

    public static func toolCalls(in message: Message?) -> [ContentBlock] { message?.content.filter { $0.type == "toolCall" } ?? [] }
    public static func textContent(in message: Message?) -> String { message?.content.compactMap(\.text).joined() ?? "" }
    public static func hasToolCalls(_ message: Message?) -> Bool { !toolCalls(in: message).isEmpty }
    public static func needsToolExecution(_ message: Message?) -> Bool { message?.role == .assistant && message?.stopReason == .toolUse && hasToolCalls(message) }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; return encoder }
}
