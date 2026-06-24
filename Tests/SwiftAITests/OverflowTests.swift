import XCTest
@testable import SwiftAI

final class OverflowTests: XCTestCase {
    private func errorMessage(_ text: String) -> Message {
        var message = Message(role: .assistant, content: [])
        message.api = .openAICompletions
        message.provider = .openAI
        message.model = "model"
        message.stopReason = .error
        message.errorMessage = text
        message.usage = Usage()
        return message
    }

    private func lengthMessage(input: Int, cacheRead: Int, output: Int) -> Message {
        var message = Message(role: .assistant, content: [])
        message.stopReason = .length
        var usage = Usage()
        usage.input = input
        usage.cacheRead = cacheRead
        usage.output = output
        usage.totalTokens = input + cacheRead + output
        message.usage = usage
        return message
    }

    func testSimulatedProviderContextOverflowFixtures() {
        let fixtures: [(String, Int)] = [
            ("prompt is too long: 211337 tokens > 200000 maximum", 200000),
            ("This model's maximum context length is 128000 tokens. However, your messages resulted in 139024 tokens.", 128000),
            ("input token count (1048577) exceeds the maximum number of tokens allowed (1048576)", 1_048_576),
            ("exceeds the context window of 1048576 tokens", 1_048_576),
            ("input is too long for requested model", 200000)
        ]
        for (text, window) in fixtures { XCTAssertTrue(ContextUtilities.isContextOverflow(errorMessage(text), contextWindow: window), text) }

        var zAIStyleSuccess = Message(role: .assistant, content: [.text("ok")])
        zAIStyleSuccess.stopReason = .stop
        var usage = Usage(); usage.input = 140_000; usage.output = 3; usage.totalTokens = 140_003
        zAIStyleSuccess.usage = usage
        XCTAssertTrue(ContextUtilities.isContextOverflow(zAIStyleSuccess, contextWindow: 128_000))
    }

    func testUpstreamOverflowPatterns() {
        XCTAssertTrue(ContextUtilities.isContextOverflow(errorMessage("400 `prompt too long; exceeded max context length by 100918 tokens`"), contextWindow: 32768))
        XCTAssertTrue(ContextUtilities.isContextOverflow(errorMessage("400 The input (516368 tokens) is longer than the model's context length (262144 tokens)."), contextWindow: 262144))
        XCTAssertTrue(ContextUtilities.isContextOverflow(errorMessage("Requested token count exceeds the model's maximum context length of 131072 tokens."), contextWindow: 131072))
        XCTAssertTrue(ContextUtilities.isContextOverflow(errorMessage("Error: 400 Input length (265330) exceeds model's maximum context length (262144)."), contextWindow: 262144))
        XCTAssertTrue(ContextUtilities.isContextOverflow(errorMessage("Provider returned error: Input length 131393 exceeds the maximum allowed input length of 131040 tokens."), contextWindow: 131072))
    }

    func testUpstreamNonOverflowPatterns() {
        XCTAssertFalse(ContextUtilities.isContextOverflow(errorMessage("500 `model runner crashed unexpectedly`"), contextWindow: 32768))
        XCTAssertFalse(ContextUtilities.isContextOverflow(errorMessage("Throttling error: Too many tokens, please wait before trying again."), contextWindow: 200000))
        XCTAssertFalse(ContextUtilities.isContextOverflow(errorMessage("Service unavailable: The service is temporarily unavailable."), contextWindow: 200000))
        XCTAssertFalse(ContextUtilities.isContextOverflow(errorMessage("Rate limit exceeded, please retry after 30 seconds."), contextWindow: 200000))
        XCTAssertFalse(ContextUtilities.isContextOverflow(errorMessage("Too many requests. Please slow down."), contextWindow: 200000))
    }

    func testUpstreamLengthStopOverflowHeuristics() {
        XCTAssertTrue(ContextUtilities.isContextOverflow(lengthMessage(input: 58, cacheRead: 1_048_512, output: 0), contextWindow: 1_048_576))
        XCTAssertFalse(ContextUtilities.isContextOverflow(lengthMessage(input: 1000, cacheRead: 0, output: 4096), contextWindow: 200000))
        XCTAssertFalse(ContextUtilities.isContextOverflow(lengthMessage(input: 100, cacheRead: 0, output: 0), contextWindow: 200000))
    }
}
