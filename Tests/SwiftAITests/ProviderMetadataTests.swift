import XCTest
@testable import SwiftAI

final class ProviderMetadataTests: XCTestCase {
    private func model(_ provider: Provider, _ id: String) throws -> Model {
        try XCTUnwrap(try BuiltinModels.all().first { $0.provider == provider && $0.id == id }, "missing \(provider.rawValue)/\(id)")
    }

    func testFireworksKimiK26ModelMetadataAndCompat() throws {
        let model = try model(.fireworks, "accounts/fireworks/models/kimi-k2p6")
        XCTAssertEqual(model.api, .anthropicMessages)
        XCTAssertEqual(model.provider, .fireworks)
        XCTAssertEqual(model.baseUrl, "https://api.fireworks.ai/inference")
        XCTAssertTrue(model.reasoning)
        XCTAssertEqual(model.input, ["text", "image"])
        XCTAssertEqual(model.contextWindow, 262_000)
        XCTAssertEqual(model.maxTokens, 262_000)
        XCTAssertEqual(model.cost, ModelCost(input: 0.95, output: 4, cacheRead: 0.16, cacheWrite: 0))
        XCTAssertEqual(model.anthropicCompat?.sendSessionAffinityHeaders, true)
        XCTAssertEqual(model.anthropicCompat?.supportsEagerToolInputStreaming, false)
        XCTAssertEqual(model.anthropicCompat?.supportsCacheControlOnTools, false)
        XCTAssertEqual(model.anthropicCompat?.supportsLongCacheRetention, false)
        XCTAssertNotNil(try BuiltinModels.all().first { $0.provider == .fireworks && $0.id.hasPrefix("accounts/fireworks/routers/") && $0.id.hasSuffix("-turbo") })
        XCTAssertEqual(ProviderEnvironment.apiKey(for: .fireworks, env: ["FIREWORKS_API_KEY": "test-fireworks-key"]), "test-fireworks-key")
    }

    func testFireworksAnthropicToolCompatRequestShape() {
        let model = Model(id: "accounts/fireworks/models/kimi-k2p6", name: "Kimi", api: .anthropicMessages, provider: .fireworks, anthropicCompat: AnthropicMessagesCompat(supportsEagerToolInputStreaming: false, supportsLongCacheRetention: false, sendSessionAffinityHeaders: true, supportsCacheControlOnTools: false))
        let tool = Tool(name: "lookup", description: "lookup", parameters: .object(["type": .string("object")]))
        let body = AnthropicMessagesProvider.buildRequestBody(model: model, context: AIContext(messages: [.user("hi")], tools: [tool]), options: nil)
        guard case .array(let tools)? = body["tools"], case .object(let first) = tools[0] else { return XCTFail("missing fireworks tool") }
        XCTAssertNil(first["cache_control"])
        XCTAssertNil(first["eager_input_streaming"])
        let native = Model(id: "claude", name: "Claude", api: .anthropicMessages, provider: .anthropic)
        let nativeBody = AnthropicMessagesProvider.buildRequestBody(model: native, context: AIContext(messages: [.user("hi")], tools: [tool]), options: nil)
        guard case .array(let nativeTools)? = nativeBody["tools"], case .object(let nativeTool) = nativeTools[0] else { return XCTFail("missing native tool") }
        XCTAssertNotNil(nativeTool["cache_control"])
        XCTAssertEqual(nativeTool["eager_input_streaming"], .bool(true))
    }

    func testTogetherKimiK26ModelMetadata() throws {
        let model = try model(.together, "moonshotai/Kimi-K2.6")
        XCTAssertEqual(model.api, .openAICompletions)
        XCTAssertEqual(model.provider, .together)
        XCTAssertEqual(model.baseUrl, "https://api.together.ai/v1")
        XCTAssertTrue(model.reasoning)
        XCTAssertNil(model.thinkingLevelMap?[.minimal]!)
        XCTAssertNil(model.thinkingLevelMap?[.low]!)
        XCTAssertNil(model.thinkingLevelMap?[.medium]!)
        XCTAssertEqual(model.input, ["text", "image"])
        XCTAssertEqual(model.contextWindow, 262_144)
        XCTAssertEqual(model.maxTokens, 131_000)
        XCTAssertEqual(model.cost, ModelCost(input: 1.2, output: 4.5, cacheRead: 0.2, cacheWrite: 0))
        XCTAssertEqual(model.completionsCompat?.supportsStore, false)
        XCTAssertEqual(model.completionsCompat?.supportsDeveloperRole, false)
        XCTAssertEqual(model.completionsCompat?.supportsReasoningEffort, false)
        XCTAssertEqual(model.completionsCompat?.maxTokensField, "max_tokens")
        XCTAssertEqual(model.completionsCompat?.thinkingFormat, "together")
        XCTAssertEqual(model.completionsCompat?.supportsStrictMode, false)
        XCTAssertEqual(model.completionsCompat?.supportsLongCacheRetention, false)
    }

    func testTogetherReasoningControls() throws {
        let gptOss = try model(.together, "openai/gpt-oss-120b")
        XCTAssertNil(gptOss.thinkingLevelMap?[.off]!)
        XCTAssertNil(gptOss.thinkingLevelMap?[.minimal]!)
        XCTAssertEqual(gptOss.completionsCompat?.supportsReasoningEffort, true)
        XCTAssertEqual(gptOss.completionsCompat?.thinkingFormat, "openai")

        let deepSeek = try model(.together, "deepseek-ai/DeepSeek-V4-Pro")
        XCTAssertNil(deepSeek.thinkingLevelMap?[.minimal]!)
        XCTAssertNil(deepSeek.thinkingLevelMap?[.low]!)
        XCTAssertNil(deepSeek.thinkingLevelMap?[.medium]!)
        XCTAssertEqual(deepSeek.thinkingLevelMap?[.high]!, "high")
        XCTAssertNil(deepSeek.thinkingLevelMap?[.xhigh]!)
        XCTAssertEqual(deepSeek.completionsCompat?.supportsReasoningEffort, true)
        XCTAssertEqual(deepSeek.completionsCompat?.thinkingFormat, "together")

        let minimax = try model(.together, "MiniMaxAI/MiniMax-M2.7")
        XCTAssertNil(minimax.thinkingLevelMap?[.off]!)
        XCTAssertNil(minimax.thinkingLevelMap?[.minimal]!)
        XCTAssertNil(minimax.thinkingLevelMap?[.low]!)
        XCTAssertNil(minimax.thinkingLevelMap?[.medium]!)
        XCTAssertNil(minimax.completionsCompat?.thinkingFormat)
        XCTAssertEqual(minimax.completionsCompat?.supportsReasoningEffort, false)
    }

    func testTogetherAPIKeyEnvironment() {
        XCTAssertEqual(ProviderEnvironment.apiKey(for: .together, env: ["TOGETHER_API_KEY": "test-together-key"]), "test-together-key")
    }
}
