import XCTest
@testable import SwiftAI
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class V110ParityTests: XCTestCase {
    private func model() -> ClassifierModel { ClassifierModel(id: "gpt-5.4-decisions", name: "Decisions", api: .openAIDecisions, provider: .openAIClassifier, baseUrl: "https://example.invalid/v1", input: ["text", "image"], cost: ModelCost(input: 2, output: 8)) }
    private func context() -> ClassificationContext { ClassificationContext(stateObject: ["x": .number(1)], questions: ["c": .choice(instructions: "Choose", criteria: ["yes": "Yes", "no": ""]), "s": .score(instructions: "Score", criteria: ["low", "high"]), "b": .bool(instructions: "Judge", trueCriteria: "Good", falseCriteria: "Bad")]) }

    func testDecisionsWireQuestionsAndImages() throws {
        var context = context(); context.images = [.image(data: "aGk=", mimeType: "image/png")]
        let body = try OpenAIDecisionsProvider.buildRequestBody(model: model(), context: context)
        let questions = body["questions"]!.arrayValue!.compactMap(\.objectValue)
        XCTAssertEqual(questions.first { $0["name"] == .string("b") }?["instructions"], .string("Judge\n\nTrue means: Good\nFalse means: Bad"))
        XCTAssertEqual(questions.first { $0["name"] == .string("b") }?["type"], .string("predicate"))
        XCTAssertEqual(questions.first { $0["name"] == .string("s") }?["levels"], .array([.object(["label": .string("low")]), .object(["label": .string("high")])]))
        let input = body["input"]!.arrayValue![0].objectValue!["content"]!.arrayValue!
        XCTAssertEqual(input[1], .object(["type": .string("input_image"), "image_url": .string("data:image/png;base64,aGk=")]))
        context.images = Array(repeating: .image(data: "aGk=", mimeType: "image/png"), count: 129)
        XCTAssertThrowsError(try OpenAIDecisionsProvider.buildRequestBody(model: model(), context: context))
        context.images = nil
        XCTAssertNotNil(try OpenAIDecisionsProvider.buildRequestBody(model: model(), context: context)["input"]?.stringValue)
    }

    func testDecisionsAnswersAndBilledRefusal() throws {
        let body: JSONValue = .object(["usage": .object(["input_tokens": .number(100), "output_tokens": .number(20)]), "answers": .array([
            .object(["name": .string("c"), "type": .string("choice"), "choice": .string("yes"), "confidence": .number(0.9), "probabilities": .array([.object(["value": .string("yes"), "probability": .number(0.9)])])]),
            .object(["name": .string("s"), "type": .string("score"), "score": .number(0.7), "confidence": .number(0.8)]),
            .object(["name": .string("b"), "type": .string("predicate"), "probability": .number(0.6)])
        ])])
        let result = OpenAIDecisionsProvider.parseResult(body, model: model(), context: context())
        XCTAssertEqual(result.stopReason, .stop); XCTAssertEqual(result.answers["c"]?.choice, "yes"); XCTAssertEqual(result.answers["s"]?.score, 0.7); XCTAssertEqual(result.answers["b"]?.probability, 0.6)
        XCTAssertEqual(result.usage?.totalTokens, 120); XCTAssertEqual(result.usage!.cost.total, 0.00036, accuracy: 1e-12)
        let refusal: JSONValue = .object(["usage": .object(["input_tokens": .number(100)]), "answers": .array([.object(["name": .string("c"), "type": .string("refusal")])])])
        let failed = OpenAIDecisionsProvider.parseResult(refusal, model: model(), context: context())
        XCTAssertEqual(failed.stopReason, .error); XCTAssertTrue(failed.answers.isEmpty); XCTAssertEqual(failed.usage?.input, 100)
        let malformed = OpenAIDecisionsProvider.parseResult(.object(["answers": .array([])]), model: model(), context: context())
        XCTAssertEqual(malformed.stopReason, .error)
    }

    func testPublicClassifierDispatchAndGatewayNoRetry() async {
        await SwiftAI.bootstrap()
        let calls = V110Counter()
        var options = ClassifierOptions(); options.apiKey = "sk-fixture"
        options.requestTransport = { request, policy in
            await calls.increment()
            XCTAssertEqual(request.url?.path, "/v1/decisions"); XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-fixture"); XCTAssertEqual(policy.maxRetries, 2)
            return (Data("gateway".utf8), HTTPURLResponse(url: request.url!, statusCode: 504, httpVersion: nil, headerFields: ["x-should-retry": "true"])!)
        }
        let result = await SwiftAI.classify(model: model(), context: context(), options: options)
        XCTAssertEqual(result.stopReason, .error); XCTAssertTrue(result.errorMessage?.contains("504") == true)
        let count = await calls.count; XCTAssertEqual(count, 1)
        var textOnly = model(); textOnly.input = ["text"]
        var images = context(); images.images = [.image(data: "x", mimeType: "image/png")]
        let unsupported = await SwiftAI.classify(model: textOnly, context: images, options: options)
        XCTAssertEqual(unsupported.stopReason, .error)
        let after = await calls.count; XCTAssertEqual(after, 1)
        let system = await SystemOneClassifierProvider.classify(model: ClassifierModel(id: "s", name: "s", api: .typeSafeSystemOne, provider: .typesafe), context: images, options: options, transport: .typeSafe)
        XCTAssertEqual(system.stopReason, .error)
    }

    func testSamplingByClampedLevelAndRequestPrecedence() throws {
        var model = Model(id: "m", name: "m", api: .openAICompletions, provider: .openAI, reasoning: true, contextWindow: 10000, maxTokens: 1000, samplingParams: ["temperature": .number(0.8), "top_p": .number(0.9)])
        model.samplingParamsByThinkingLevel = [.off: ["temperature": .number(0.7)], .high: ["temperature": .number(0.3), "top_p": .number(0.6)]]
        var options = StreamOptions(); options.reasoning = .max; options.temperature = 0.1; options.samplingParams = ["top_p": .number(0.4)]
        let body = OpenAICompletionsProvider.buildRequestBody(model: model, context: AIContext(), options: options)
        XCTAssertEqual(body["temperature"], .number(0.3)); XCTAssertEqual(body["top_p"], .number(0.4))
        XCTAssertEqual(OpenAIResponsesProvider.buildRequestBody(model: model, context: AIContext(), options: options)["temperature"], .number(0.3))
        let decoded = try JSONDecoder().decode(Model.self, from: JSONEncoder().encode(model))
        XCTAssertEqual(decoded.samplingParamsByThinkingLevel, model.samplingParamsByThinkingLevel)
        XCTAssertEqual(AIUtilities.resolveSamplingParams(model: model, level: .off)["temperature"], .number(0.7))
    }

    func testTierBoundaryAndRetryPhrases() {
        let tier: JSONValue = .object(["inputTokensAbove": .number(100), "input": .number(4), "output": .number(8), "cacheRead": .number(1), "cacheWrite": .number(5)])
        let cost = ModelCost(input: 2, output: 4, cacheRead: 0.5, cacheWrite: 2.5, tiers: [tier])
        var usage = Usage(); usage.input = 100; usage.output = 2
        XCTAssertEqual(AIUtilities.calculateCost(cost: cost, usage: usage).input, 0.0002, accuracy: 1e-12)
        usage.cacheRead = 1
        XCTAssertEqual(AIUtilities.calculateCost(cost: cost, usage: usage).input, 0.0004, accuracy: 1e-12)
        XCTAssertEqual(AIUtilities.calculateCost(cost: cost, usage: usage).cacheRead, 0.000001, accuracy: 1e-12)
        for phrase in ["server_busy", "servers are currently busy", "pending stream has been canceled"] {
            var message = Message(role: .assistant, content: []); message.stopReason = .error; message.errorMessage = phrase
            XCTAssertTrue(AssistantErrorRetryClassifier.isRetryableAssistantError(message))
        }
        var quota = Message(role: .assistant, content: []); quota.stopReason = .error; quota.errorMessage = "insufficient_quota: servers are currently busy"
        XCTAssertFalse(AssistantErrorRetryClassifier.isRetryableAssistantError(quota))
    }

    func testBedrockGptEffortAndHaikuBinding() {
        var options = StreamOptions(); options.reasoning = .max
        let oss = Model(id: "openai.gpt-oss-120b", name: "GPT OSS", api: .bedrockConverseStream, provider: .amazonBedrock, reasoning: true)
        XCTAssertEqual(BedrockProvider.additionalModelRequestFields(model: oss, options: options), ["reasoning_effort": .string("high")])
        options.reasoning = .minimal
        let gpt = Model(id: "openai.gpt-5", name: "GPT", api: .bedrockConverseStream, provider: .amazonBedrock, reasoning: true)
        XCTAssertEqual(BedrockProvider.additionalModelRequestFields(model: gpt, options: options), ["reasoning": .object(["effort": .string("low")])])
        options.reasoning = .xhigh
        let haiku = Model(id: "anthropic.claude-haiku-5", name: "Haiku 5", api: .bedrockConverseStream, provider: .amazonBedrock, reasoning: true)
        XCTAssertNotNil(BedrockProvider.additionalModelRequestFields(model: haiku, options: options)?["thinking"]?.objectValue?["block_binding"])
        XCTAssertEqual(ProviderEnvironment.apiKey(for: Provider.azure, env: ["AZURE_OPENAI_API_KEY": "fixture"]), "fixture")
    }

    func testPublicResponseTimingAndLegacyPreservation() async throws {
        let model = Model(id: "timed", name: "timed", api: .faux, provider: .faux)
        await AIRegistry.shared.register(APIProvider(api: .faux, stream: { model, _, _ in AsyncStream { continuation in
            var message = Message(role: .assistant, content: [.text("done")]); message.api = model.api; message.provider = model.provider; message.model = model.id; message.timestamp = Int64(Date().timeIntervalSince1970 * 1000); message.stopReason = .stop
            continuation.yield(.done(reason: .stop, message: message)); continuation.finish()
        } }))
        let result = try await SwiftAI.complete(model: model)
        XCTAssertNotNil(result.durationMs); XCTAssertGreaterThanOrEqual(result.durationMs ?? -1, 0)
        var legacy = Message(role: .toolResult, content: [.text("result")]); legacy.durationMs = 12
        XCTAssertEqual(try JSONDecoder().decode(Message.self, from: JSONEncoder().encode(legacy)).durationMs, 12)
    }
}

private actor V110Counter {
    var count = 0
    func increment() { count += 1 }
}
