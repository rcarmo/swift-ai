import XCTest
@testable import SwiftAI

final class LiveGatedTests: XCTestCase {
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
