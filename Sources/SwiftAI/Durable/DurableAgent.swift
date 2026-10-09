import Foundation

public struct DurableAgentSettings: Codable, Equatable, Sendable {
    public var model: Model
    public var instructions: String?
    public var thinkingLevel: ModelThinkingLevel
    public var extensions: [String]
    public var steeringMode: DurableQueueMode
    public var followUpMode: DurableQueueMode
    public init(model: Model, instructions: String? = nil, thinkingLevel: ModelThinkingLevel = .off, extensions: [String] = [], steeringMode: DurableQueueMode = .oneAtATime, followUpMode: DurableQueueMode = .oneAtATime) {
        self.model = model; self.instructions = instructions; self.thinkingLevel = thinkingLevel; self.extensions = extensions; self.steeringMode = steeringMode; self.followUpMode = followUpMode
    }
}

public struct DurablePromptSection: Sendable {
    public var key: String
    public var tagged: Bool
    public var render: @Sendable (DurableConversationView) async throws -> String?
    public init(key: String, tagged: Bool = true, render: @escaping @Sendable (DurableConversationView) async throws -> String?) { self.key = key; self.tagged = tagged; self.render = render }
}

public struct DurableGenerationHooks: Sendable {
    public var beforeRequest: (@Sendable (AIContext) async throws -> AIContext)?
    public var afterResponse: (@Sendable (Message) async throws -> Void)?
    public init(beforeRequest: (@Sendable (AIContext) async throws -> AIContext)? = nil, afterResponse: (@Sendable (Message) async throws -> Void)? = nil) { self.beforeRequest = beforeRequest; self.afterResponse = afterResponse }
}

public struct DurableExtension: Sendable {
    public var name: String
    public var sections: [DurablePromptSection]
    public var hooks: DurableGenerationHooks
    public init(name: String, sections: [DurablePromptSection] = [], hooks: DurableGenerationHooks = DurableGenerationHooks()) { self.name = name; self.sections = sections; self.hooks = hooks }
}

public actor DurableExtensionRegistry {
    private var installed: [DurableExtension] = []
    public init() {}
    public func install(_ value: DurableExtension) throws {
        guard !value.name.isEmpty, value.name.utf8.count <= 128, Set(value.sections.map(\.key)).count == value.sections.count else { throw DurableError.invalidRecord("invalid extension") }
        let valid = try NSRegularExpression(pattern: "^[a-z][a-z0-9_-]*$")
        for section in value.sections { guard section.key != "instructions", valid.firstMatch(in: section.key, range: NSRange(section.key.startIndex..., in: section.key)) != nil else { throw DurableError.invalidRecord("invalid prompt section") } }
        if let index = installed.firstIndex(where: { $0.name == value.name }) { installed[index] = value }
        else { installed.append(value) }
    }
    public func uninstall(_ name: String) { installed.removeAll { $0.name == name } }
    public func snapshot(names: [String]) throws -> [DurableExtension] {
        guard Set(names).count == names.count else { throw DurableError.invalidRecord("duplicate selected extension") }
        return try names.map { name in guard let value = installed.first(where: { $0.name == name }) else { throw DurableError.invalidRecord("missing selected extension") }; return value }
    }
}

struct DurablePromptState: Codable, Sendable { var sections: [String]; var text: [String: String] }

public extension DurableSession {
    func configureAgent(conversationID: Int64, settings: DurableAgentSettings) async throws {
        var stored = settings; stored.model.baseUrl = ""; stored.model.headers = nil
        guard Set(stored.extensions).count == stored.extensions.count else { throw DurableError.invalidRecord("duplicate selected extension") }
        _ = try await writeDocument(scope: "conversation", ownerID: conversationID, kind: "pi.agent", value: DurableGenerationPlanner.encodeJSON(stored), fork: .current)
    }

    func agent(conversationID: Int64) async throws -> DurableAgentSettings? {
        guard let value = try await document(scope: "conversation", ownerID: conversationID, kind: "pi.agent") else { return nil }
        return try JSONDecoder().decode(DurableAgentSettings.self, from: JSONEncoder().encode(value))
    }

    func generate(conversationID: Int64, input: [Message], requestID: String? = nil) async throws -> DurableGenerationResult {
        guard let settings = try await agent(conversationID: conversationID) else { throw DurableError.invalidRecord("agent is not configured") }
        var options = StreamOptions()
        if settings.thinkingLevel != .off { options.reasoning = ThinkingLevel(rawValue: settings.thinkingLevel.rawValue) }
        var request = DurableGenerationRequest(conversationID: conversationID, model: settings.model, systemPrompt: settings.instructions, transcript: input, requestID: requestID, options: options)
        request.extensions = settings.extensions
        return try await submit(request)
    }

    func renderPrompt(conversationID: Int64, instructions: String?, extensions: [String]) async throws -> String? {
        let selected = try await extensionRegistry.snapshot(names: extensions)
        let currentView = try await view(conversationID: conversationID)
        let previousValue = try await document(scope: "conversation", ownerID: conversationID, kind: "pi.prompt")
        let previous = try previousValue.map { try JSONDecoder().decode(DurablePromptState.self, from: JSONEncoder().encode($0)) }
        var order: [String] = [], text: [String: String] = [:]
        if let instructions { order.append("instructions"); text["instructions"] = instructions }
        for value in selected {
            for section in value.sections {
                let rendered: String?
                do { rendered = try await section.render(currentView) }
                catch is CancellationError { throw CancellationError() }
                catch {
                    if let kept = previous?.text[section.key] {
                        if text[section.key] == nil { order.append(section.key) }; text[section.key] = kept
                    }
                    continue
                }
                guard let rendered else { continue }
                if text[section.key] == nil { order.append(section.key) }
                text[section.key] = section.tagged ? "<\(section.key)>\n\(rendered)\n</\(section.key)>" : rendered
            }
        }
        let state = DurablePromptState(sections: order, text: text)
        _ = try await writeDocument(scope: "conversation", ownerID: conversationID, kind: "pi.prompt", value: DurableGenerationPlanner.encodeJSON(state), fork: .current)
        let combined = order.compactMap { text[$0] }.joined(separator: "\n\n")
        return combined.isEmpty ? nil : combined
    }
}
