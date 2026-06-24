import XCTest
@testable import SwiftAI

final class LiveGatedTests: XCTestCase {
    func testOpenAIResponsesCacheAffinityLive() async throws {
        let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]
        try XCTSkipUnless(apiKey != nil && !(apiKey ?? "").isEmpty, "requires OPENAI_API_KEY")
        await SwiftAI.bootstrap()
        let model = try XCTUnwrap(await AIRegistry.shared.model(provider: .openAI, id: "gpt-5.4-mini") ?? await AIRegistry.shared.model(provider: .openAI, id: "gpt-5-mini"))
        var options = StreamOptions()
        options.apiKey = apiKey
        options.sessionId = "swift-ai-live-cache-affinity"
        options.maxTokens = 32
        let response = try await SwiftAI.complete(model: model, context: AIContext(messages: [.user("Reply with exactly: OK")]), options: options)
        XCTAssertNotEqual(response.stopReason, .error)
        XCTAssertNil(response.errorMessage)
    }

    func testAnthropicOpus48ReasoningSmokeLive() async throws {
        let apiKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]
        try XCTSkipUnless(apiKey != nil && !(apiKey ?? "").isEmpty, "requires ANTHROPIC_API_KEY")
        await SwiftAI.bootstrap()
        let model = try XCTUnwrap(await AIRegistry.shared.model(provider: .anthropic, id: "claude-opus-4-8"))
        var options = StreamOptions()
        options.apiKey = apiKey
        options.reasoning = .high
        options.maxTokens = 256
        let response = try await SwiftAI.complete(model: model, context: AIContext(messages: [.user("Think briefly, then reply with exactly: opus-ok")]), options: options)
        XCTAssertEqual(response.stopReason, .stop)
        XCTAssertTrue(response.content.contains { $0.type == "text" })
    }

    func testOpenRouterImagesBasicLive() async throws {
        let apiKey = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"]
        try XCTSkipUnless(apiKey != nil && !(apiKey ?? "").isEmpty, "requires OPENROUTER_API_KEY")
        await SwiftAI.bootstrap()
        let model = try XCTUnwrap(await ImagesRegistry.shared.model(provider: .openRouter, id: "google/gemini-2.5-flash-image") ?? await ImagesRegistry.shared.listModels(provider: .openRouter).first)
        var options = ImagesOptions()
        options.apiKey = apiKey
        let response = await SwiftAI.generateImages(model: model, context: ImagesContext(input: [.text("Generate a simple red circle on a white background. No text.")]), options: options)
        XCTAssertEqual(response.stopReason, .stop)
        XCTAssertTrue(response.output.contains { $0.type == "image" })
    }

    func testOpenAICompletionsBasicStreamLive() async throws {
        let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]
        try XCTSkipUnless(apiKey != nil && !(apiKey ?? "").isEmpty, "requires OPENAI_API_KEY")
        await SwiftAI.bootstrap()
        var model = try XCTUnwrap(await AIRegistry.shared.model(provider: .openAI, id: "gpt-4o-mini"))
        model.api = .openAICompletions
        var options = StreamOptions()
        options.apiKey = apiKey
        options.maxTokens = 32
        let response = try await SwiftAI.complete(model: model, context: AIContext(messages: [.user("Reply with exactly: stream-ok")]), options: options)
        XCTAssertEqual(response.stopReason, .stop)
        XCTAssertTrue(response.content.contains { $0.type == "text" })
    }

    func testOpenRouterCacheWriteReproLive() async throws {
        let apiKey = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"]
        try XCTSkipUnless(apiKey != nil && !(apiKey ?? "").isEmpty, "requires OPENROUTER_API_KEY")

        await SwiftAI.bootstrap()
        let model = try XCTUnwrap(await AIRegistry.shared.model(provider: .openRouter, id: "google/gemini-2.5-flash"))
        let systemPrompt = "You are a concise assistant.\nCache nonce: \(Date().timeIntervalSince1970)\n\n" + Array(repeating: "Prompt-caching probe content. Keep this exact text stable across requests so the provider can reuse prefix tokens and report cache read and cache write usage.", count: 80).joined(separator: "\n\n")
        let context = AIContext(systemPrompt: systemPrompt, messages: [.user("Reply with exactly: OK")])
        var options = StreamOptions()
        options.apiKey = apiKey
        options.maxTokens = 32
        options.temperature = 0
        options.onPayload = { payload, _ in
            var payload = payload
            guard case .array(var messages)? = payload["messages"] else { return payload }
            for idx in messages.indices.reversed() {
                guard case .object(var msg) = messages[idx], msg["role"] == .string("user") else { continue }
                if case .string(let text)? = msg["content"] {
                    msg["content"] = .array([.object(["type": .string("text"), "text": .string(text), "cache_control": .object(["type": .string("ephemeral")])])])
                    messages[idx] = .object(msg)
                    break
                }
            }
            payload["messages"] = .array(messages)
            return payload
        }
        let first = try await SwiftAI.complete(model: model, context: context, options: options)
        XCTAssertEqual(first.stopReason, .stop)
        let second = try await SwiftAI.complete(model: model, context: context, options: options)
        XCTAssertEqual(second.stopReason, .stop)
        XCTAssertTrue(first.usage?.cacheWrite ?? 0 > 0 || second.usage?.cacheWrite ?? 0 > 0)
    }

    func testXiaomiTokenPlanAMSAnthropicEmptySignatureSmokeLive() async throws {
        let apiKey = ProcessInfo.processInfo.environment["XIAOMI_TOKEN_PLAN_AMS_API_KEY"]
        try XCTSkipUnless(apiKey != nil && !(apiKey ?? "").isEmpty, "requires XIAOMI_TOKEN_PLAN_AMS_API_KEY")

        await SwiftAI.bootstrap()
        let model = Model(
            id: "mimo-v2.5-pro",
            name: "MiMo-V2.5-Pro Anthropic smoke",
            api: .anthropicMessages,
            provider: .xiaomiTokenPlanAMS,
            baseUrl: "https://token-plan-ams.xiaomimimo.com/anthropic",
            reasoning: true,
            input: ["text"],
            cost: ModelCost(input: 1, output: 3, cacheRead: 0.2, cacheWrite: 0),
            contextWindow: 1_048_576,
            maxTokens: 1024,
            anthropicCompat: AnthropicMessagesCompat(allowEmptySignature: true)
        )
        var options = StreamOptions()
        options.apiKey = apiKey
        options.maxTokens = 512
        options.reasoning = .high

        let first = try await SwiftAI.complete(
            model: model,
            context: AIContext(systemPrompt: "You are concise. Follow the requested output format exactly.", messages: [.user("Think internally if you need to, then reply with exactly this text and nothing else: first-ok")]),
            options: options
        )
        XCTAssertEqual(first.stopReason, .stop)
        let thinkingBlocks = first.content.filter { $0.type == "thinking" }
        XCTAssertFalse(thinkingBlocks.isEmpty)
        XCTAssertTrue(thinkingBlocks.contains { ($0.thinkingSignature ?? "x") == "" })
    }
}
