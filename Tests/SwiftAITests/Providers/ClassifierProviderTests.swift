import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import SwiftAI

final class ClassifierProviderTests: XCTestCase {
    private func context() -> ClassificationContext {
        ClassificationContext(state: .object(["text": .string("hello world")]), questions: [
            "tone": .choice(instructions: "What tone is this?", criteria: ["friendly": "Friendly", "hostile": "Hostile"]),
            "quality": .score(instructions: "How good is it?", criteria: ["bad", "ok", "great"]),
            "safe": .bool(instructions: "Is it safe?", trueCriteria: "Safe", falseCriteria: "Unsafe")
        ])
    }

    func testTypeSafeSystemOnePayloadMapsBoolToNoulAndParsesAnswers() throws {
        let model = ClassifierModel(id: "jev-latest", name: "Jev", api: .typeSafeSystemOne, provider: .typesafe, baseUrl: "https://api.typesafe.ai/v1/", cost: ModelCost(input: 1, output: 2), contextWindow: 64_000)
        let payload = try SystemOneClassifierProvider.payload(model: model, context: context(), transport: .typeSafe)
        XCTAssertEqual(payload["model"], .string("jev-latest"))
        guard case .object(let questions)? = payload["questions"], case .object(let safe)? = questions["safe"] else { return XCTFail("missing questions") }
        XCTAssertEqual(safe["type"], .string("noul"))
        XCTAssertEqual(SystemOneClassifierProvider.url(model: model, transport: .typeSafe), "https://api.typesafe.ai/v1/systemone")
        XCTAssertEqual(SystemOneClassifierProvider.requestHeaders(model: model, apiKey: "key", options: nil)["authorization"], "Bearer key")
        var suppress = ClassifierOptions(); suppress.headers = ["AUTHORIZATION": nil, "Content-Type": nil, "x-extra": "1"]
        let suppressed = SystemOneClassifierProvider.requestHeaders(model: ClassifierModel(id: "jev", name: "Jev", api: .typeSafeSystemOne, provider: .typesafe, headers: ["Authorization": "Bearer model", "content-type": "application/json"]), apiKey: "key", options: suppress)
        XCTAssertNil(suppressed.first { $0.key.lowercased() == "authorization" })
        XCTAssertNil(suppressed.first { $0.key.lowercased() == "content-type" })
        XCTAssertEqual(suppressed["x-extra"], "1")

        let body: JSONValue = .object([
            "usage": .object(["input_tokens": .number(100), "output_tokens": .number(50)]),
            "answers": .object([
                "tone": .object(["type": .string("choice"), "choice": .string("friendly"), "probabilities": .object(["friendly": .number(0.8), "hostile": .number(0.2)]), "confidence": .number(0.6)]),
                "quality": .object(["type": .string("score"), "score": .number(1.8), "confidence": .number(0.7)]),
                "safe": .object(["type": .string("noul"), "noul": .number(0.93)])
            ])
        ])
        let result = try SystemOneClassifierProvider.parseResult(body, model: model, context: context(), transport: .typeSafe)
        XCTAssertEqual(result.stopReason, .stop)
        XCTAssertEqual(result.answers["tone"]?.choice, "friendly")
        XCTAssertEqual(result.answers["quality"]?.score, 1.8)
        XCTAssertEqual(result.answers["safe"]?.type, "bool")
        XCTAssertEqual(result.answers["safe"]?.probability, 0.93)
        XCTAssertEqual(result.usage?.input, 100)
        XCTAssertEqual(result.usage?.output, 50)
        XCTAssertEqual(result.usage?.cost.input, 0.0001)
        XCTAssertEqual(result.usage?.cost.output, 0.0001)
    }

    func testCloudflareSystemOnePayloadEnvelopeAndErrors() throws {
        let model = ClassifierModel(id: "@cf/typesafe/jev", name: "Jev", api: .cloudflareWorkersAISystemOne, provider: .cloudflareWorkersAI, baseUrl: "https://api.cloudflare.com/client/v4/accounts/acct/ai", cost: ModelCost(input: 0.24, output: 0))
        let payload = try SystemOneClassifierProvider.payload(model: model, context: context(), transport: .cloudflareWorkersAI)
        XCTAssertEqual(payload["model"], .string("@cf/typesafe/jev"))
        guard case .object(let input)? = payload["input"], case .object(let questions)? = input["questions"], case .object(let safe)? = questions["safe"] else { return XCTFail("missing Cloudflare input") }
        XCTAssertEqual(safe["type"], .string("noul"))
        XCTAssertEqual(SystemOneClassifierProvider.url(model: model, transport: .cloudflareWorkersAI), "https://api.cloudflare.com/client/v4/accounts/acct/ai/run")

        let body: JSONValue = .object([
            "success": .bool(true),
            "result": .object([
                "state": .string("Completed"),
                "result": .object(["answers": .object(["safe": .object(["type": .string("noul"), "noul": .number(0.5)]), "tone": .object(["type": .string("choice"), "choice": .string("friendly"), "probabilities": .object(["friendly": .number(1), "hostile": .number(0)]), "confidence": .number(1)]), "quality": .object(["type": .string("score"), "score": .number(2), "confidence": .number(1)])])])
            ])
        ])
        let result = try SystemOneClassifierProvider.parseResult(body, model: model, context: context(), transport: .cloudflareWorkersAI)
        XCTAssertEqual(result.answers["safe"]?.probability, 0.5)

        let direct: JSONValue = .object([
            "success": .bool(true),
            "result": .object([
                "model": .string("clef"),
                "usage": .object(["input_tokens": .number(222), "output_tokens": .number(0)]),
                "answers": .object([
                    "safe": .object(["type": .string("noul"), "noul": .number(0.9912)]),
                    "tone": .object(["type": .string("choice"), "choice": .string("friendly"), "probabilities": .object(["friendly": .number(0.8368), "hostile": .number(0.1632)]), "confidence": .number(0.4538)]),
                    "quality": .object(["type": .string("score"), "score": .number(2), "confidence": .number(1)])
                ])
            ])
        ])
        let directResult = try SystemOneClassifierProvider.parseResult(direct, model: model, context: context(), transport: .cloudflareWorkersAI)
        XCTAssertEqual(directResult.answers["safe"]?.probability, 0.9912)
        XCTAssertEqual(directResult.answers["tone"]?.choice, "friendly")
        XCTAssertEqual(directResult.usage?.input, 222)
        XCTAssertEqual(directResult.usage?.output, 0)
        XCTAssertEqual(directResult.usage?.totalTokens, 222)
        XCTAssertEqual(directResult.usage?.cost.input, 222 * 0.24 / 1_000_000)

        let nullResult: JSONValue = .object(["success": .bool(true), "result": .null])
        XCTAssertThrowsError(try SystemOneClassifierProvider.parseResult(nullResult, model: model, context: context(), transport: .cloudflareWorkersAI))

        let errorBody: JSONValue = .object(["success": .bool(false), "errors": .array([.object(["message": .string("bad account")])])])
        XCTAssertThrowsError(try SystemOneClassifierProvider.parseResult(errorBody, model: model, context: context(), transport: .cloudflareWorkersAI)) { error in
            XCTAssertTrue(String(describing: error).contains("bad account"))
        }
    }

    func testSystemOneRequiresObjectStateBoolCriteriaAndStrictAnswers() throws {
        let model = ClassifierModel(id: "jev-latest", name: "Jev", api: .typeSafeSystemOne, provider: .typesafe, baseUrl: "https://api.typesafe.ai/v1/", cost: ModelCost(input: 1, output: 2))
        XCTAssertThrowsError(try SystemOneClassifierProvider.payload(model: model, context: ClassificationContext(input: "legacy", questions: ["safe": .bool(instructions: "safe?", trueCriteria: "yes", falseCriteria: "no")]), transport: .typeSafe)) { error in
            XCTAssertTrue(String(describing: error).contains("state must be a JSON object"))
        }
        XCTAssertThrowsError(try SystemOneClassifierProvider.payload(model: model, context: ClassificationContext(stateObject: ["text": .string("hello")], questions: ["safe": .bool(instructions: "safe?")]), transport: .typeSafe)) { error in
            XCTAssertTrue(String(describing: error).contains("true and false criteria"))
        }
        let missingConfidence: JSONValue = .object(["answers": .object(["tone": .object(["type": .string("choice"), "choice": .string("friendly"), "probabilities": .object(["friendly": .number(1)])]), "quality": .object(["type": .string("score"), "score": .number(2), "confidence": .number(1)]), "safe": .object(["type": .string("noul"), "noul": .number(0.5)])])])
        XCTAssertThrowsError(try SystemOneClassifierProvider.parseResult(missingConfidence, model: model, context: context(), transport: .typeSafe))
        let boolCompatibility: JSONValue = .object(["answers": .object(["tone": .object(["type": .string("choice"), "choice": .string("friendly"), "probabilities": .object(["friendly": .number(1), "hostile": .number(0)]), "confidence": .number(1)]), "quality": .object(["type": .string("score"), "score": .number(2), "confidence": .number(1)]), "safe": .object(["type": .string("bool"), "probability": .number(0.25)])])])
        XCTAssertEqual(try SystemOneClassifierProvider.parseResult(boolCompatibility, model: model, context: context(), transport: .typeSafe).answers["safe"]?.probability, 0.25)
    }

    func testSystemOneProductionTransportPreservesUsageOnMalformedAnswersAndHooks() async throws {
        let model = ClassifierModel(id: "jev-latest", name: "Jev", api: .typeSafeSystemOne, provider: .typesafe, baseUrl: "https://api.typesafe.ai/v1/", cost: ModelCost(input: 1, output: 2))
        final class Box: @unchecked Sendable { var requests: [URLRequest] = []; var sawPayload = false; var sawResponse = false }
        let box = Box()
        var options = ClassifierOptions(); options.apiKey = "key"; options.maxRetries = 0
        options.onPayload = { payload, _ in box.sawPayload = payload["model"] == .string("jev-latest"); return payload }
        options.onResponse = { response, _ in box.sawResponse = response.status == 200 }
        options.requestTransport = { request, _ in
            box.requests.append(request)
            let body = #"{"usage":{"input_tokens":10,"output_tokens":5},"answers":{"tone":{"type":"choice","choice":"friendly","probabilities":{"friendly":1}},"quality":{"type":"score","score":2,"confidence":1},"safe":{"type":"noul","noul":0.8}}}"#.data(using: .utf8)!
            return (body, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["x-test": "ok"])!)
        }
        await SwiftAI.bootstrap()
        let result = await SwiftAI.classify(model: model, context: context(), options: options)
        XCTAssertEqual(result.stopReason, .error)
        XCTAssertGreaterThan(result.timestamp, 0)
        XCTAssertEqual(result.usage?.input, 10)
        XCTAssertEqual(result.usage?.output, 5)
        XCTAssertTrue(box.sawPayload)
        XCTAssertTrue(box.sawResponse)
        XCTAssertEqual(box.requests.first?.url?.absoluteString, "https://api.typesafe.ai/v1/systemone")
        XCTAssertEqual(box.requests.first?.value(forHTTPHeaderField: "authorization"), "Bearer key")
    }

    func testSystemOnePrePostValidationAndMalformedUsageControls() async throws {
        let model = ClassifierModel(id: "jev-latest", name: "Jev", api: .typeSafeSystemOne, provider: .typesafe, baseUrl: "https://api.typesafe.ai/v1/")
        final class PostBox: @unchecked Sendable { var posts = 0 }
        let postBox = PostBox()
        var options = ClassifierOptions(); options.apiKey = "key"; options.requestTransport = { _, _ in postBox.posts += 1; throw AIError.provider("should not post") }
        let invalidURL = ClassifierModel(id: "jev-latest", name: "Jev", api: .typeSafeSystemOne, provider: .typesafe, baseUrl: "not a url")
        let invalidURLResult = await SystemOneClassifierProvider.classify(model: invalidURL, context: context(), options: options, transport: .typeSafe)
        XCTAssertEqual(invalidURLResult.stopReason, .error)
        XCTAssertTrue(invalidURLResult.errorMessage?.contains("Invalid System One URL") == true)
        let missingHostURL = ClassifierModel(id: "jev-latest", name: "Jev", api: .typeSafeSystemOne, provider: .typesafe, baseUrl: "https://")
        let missingHostResult = await SystemOneClassifierProvider.classify(model: missingHostURL, context: context(), options: options, transport: .typeSafe)
        XCTAssertEqual(missingHostResult.stopReason, .error)
        XCTAssertTrue(missingHostResult.errorMessage?.contains("Invalid System One URL") == true)
        let unknown = ClassificationContext(stateObject: ["text": .string("hello")], questions: ["q": ClassifierQuestion(type: "unknown", instructions: "x", criteria: .object([:]))])
        let unknownResult = await SystemOneClassifierProvider.classify(model: model, context: unknown, options: options, transport: .typeSafe)
        XCTAssertEqual(unknownResult.stopReason, .error)
        let wrongChoice = ClassificationContext(stateObject: ["text": .string("hello")], questions: ["q": ClassifierQuestion(type: "choice", instructions: "x", criteria: .array([.string("bad")]))])
        let wrongChoiceResult = await SystemOneClassifierProvider.classify(model: model, context: wrongChoice, options: options, transport: .typeSafe)
        XCTAssertEqual(wrongChoiceResult.stopReason, .error)
        let wrongScore = ClassificationContext(stateObject: ["text": .string("hello")], questions: ["q": ClassifierQuestion(type: "score", instructions: "x", criteria: .object(["bad": .string("bad")]))])
        let wrongScoreResult = await SystemOneClassifierProvider.classify(model: model, context: wrongScore, options: options, transport: .typeSafe)
        XCTAssertEqual(wrongScoreResult.stopReason, .error)
        XCTAssertEqual(postBox.posts, 0)

        func bodyWithUsage(input: Double, output: Double) -> JSONValue { .object(["usage": .object(["input_tokens": .number(input), "output_tokens": .number(output)]), "answers": .object(["tone": .object(["type": .string("choice"), "choice": .string("friendly"), "probabilities": .object(["friendly": .number(1), "hostile": .number(0)]), "confidence": .number(1)]), "quality": .object(["type": .string("score"), "score": .number(2), "confidence": .number(1)]), "safe": .object(["type": .string("noul"), "noul": .number(0.5)])])]) }
        XCTAssertNil(try SystemOneClassifierProvider.parseResult(bodyWithUsage(input: 1e100, output: 5), model: model, context: context(), transport: .typeSafe).usage)
        XCTAssertNil(try SystemOneClassifierProvider.parseResult(bodyWithUsage(input: 1.5, output: 5), model: model, context: context(), transport: .typeSafe).usage)
        let intMaxPlusOne = pow(2.0, 63.0)
        XCTAssertNil(try SystemOneClassifierProvider.parseResult(bodyWithUsage(input: intMaxPlusOne, output: 0), model: model, context: context(), transport: .typeSafe).usage)
        XCTAssertNil(try SystemOneClassifierProvider.parseResult(bodyWithUsage(input: pow(2.0, 62.0), output: pow(2.0, 62.0)), model: model, context: context(), transport: .typeSafe).usage)
    }

    func testSystemOneProductionTransportFaultsRetryCancelAndDecodeBoundaries() async throws {
        let model = ClassifierModel(id: "jev-latest", name: "Jev", api: .typeSafeSystemOne, provider: .typesafe, baseUrl: "https://api.typesafe.ai/v1/")
        func run(_ handler: @escaping @Sendable (URLRequest, RetryPolicy) async throws -> (Data, URLResponse), onResponse: (@Sendable (ClassifierResponseMetadata, ClassifierModel) async -> Void)? = nil, maxRetries: Int = 0) async -> ClassificationResult {
            var options = ClassifierOptions(); options.apiKey = "key"; options.maxRetries = maxRetries; options.requestTransport = handler; options.onResponse = onResponse
            return await SystemOneClassifierProvider.classify(model: model, context: context(), options: options, transport: .typeSafe)
        }
        let badStatus = await run { request, _ in (#"{"error":"bad"}"#.data(using: .utf8)!, HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!) }
        XCTAssertEqual(badStatus.stopReason, .error)
        let nonObject = await run { request, _ in (#"[]"#.data(using: .utf8)!, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!) }
        XCTAssertEqual(nonObject.stopReason, .error)
        let trailing = await run { request, _ in (#"{"answers":{}} trailing"#.data(using: .utf8)!, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!) }
        XCTAssertEqual(trailing.stopReason, .error)
        XCTAssertNil(trailing.usage)
        let overflowAnswer = await run { request, _ in (#"{"usage":{"input_tokens":10,"output_tokens":5},"answers":{"tone":{"type":"choice","choice":"friendly","probabilities":{"friendly":1e400},"confidence":1},"quality":{"type":"score","score":2,"confidence":1},"safe":{"type":"noul","noul":0.5}}}"#.data(using: .utf8)!, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!) }
        XCTAssertEqual(overflowAnswer.stopReason, .error)
        XCTAssertNil(overflowAnswer.usage)
        let semanticMalformed = await run { request, _ in (#"{"usage":{"input_tokens":10,"output_tokens":5},"answers":{"tone":{"type":"choice","choice":"friendly","probabilities":{"friendly":"bad"},"confidence":1},"quality":{"type":"score","score":2,"confidence":1},"safe":{"type":"noul","noul":0.5}}}"#.data(using: .utf8)!, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!) }
        XCTAssertEqual(semanticMalformed.stopReason, .error)
        XCTAssertEqual(semanticMalformed.usage?.input, 10)
        final class ResponseBox: @unchecked Sendable { var sawResponse = false }
        let responseBox = ResponseBox()
        let invalid = await run({ request, _ in (#"not json"#.data(using: .utf8)!, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!) }, onResponse: { _, _ in responseBox.sawResponse = true })
        XCTAssertEqual(invalid.stopReason, .error)
        XCTAssertNil(invalid.usage)
        XCTAssertFalse(responseBox.sawResponse)
        let truncated = await run { request, _ in (#"{"usage":{"input_tokens":10},"answers":"#.data(using: .utf8)!, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!) }
        XCTAssertEqual(truncated.stopReason, .error)
        XCTAssertNil(truncated.usage)
        let readThrow = await run { _, _ in throw AIError.provider("read failed") }
        XCTAssertEqual(readThrow.stopReason, .error)
        let cancelled = await run { _, _ in throw CancellationError() }
        XCTAssertEqual(cancelled.stopReason, .aborted)
        final class Counter: @unchecked Sendable { var attempts = 0 }
        let counter = Counter()
        let retried = await run({ request, _ in
            counter.attempts += 1
            if counter.attempts == 1 { throw ProviderRetryError(status: 503, message: "retry") }
            let body = #"{"answers":{"tone":{"type":"choice","choice":"friendly","probabilities":{"friendly":1,"hostile":0},"confidence":1},"quality":{"type":"score","score":2,"confidence":1},"safe":{"type":"noul","noul":0.7}}}"#.data(using: .utf8)!
            return (body, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }, maxRetries: 1)
        XCTAssertEqual(retried.stopReason, .stop)
        XCTAssertEqual(counter.attempts, 2)
    }

    func testCloudflareSystemOneProductionTransportEnvelopeAndUsage() async throws {
        let model = ClassifierModel(id: "@cf/typesafe/jev", name: "Jev", api: .cloudflareWorkersAISystemOne, provider: .cloudflareWorkersAI, baseUrl: "https://api.cloudflare.com/client/v4/accounts/acct/ai", cost: ModelCost(input: 1, output: 2))
        final class BodyBox: @unchecked Sendable { var capturedBody: [String: JSONValue] = [:] }
        let box = BodyBox()
        var options = ClassifierOptions(); options.apiKey = "cf-key"; options.maxRetries = 0
        options.requestTransport = { request, _ in
            box.capturedBody = try JSONDecoder().decode([String: JSONValue].self, from: request.httpBody ?? Data())
            let body = #"{"success":true,"result":{"state":"Completed","result":{"usage":{"input_tokens":4,"output_tokens":3},"answers":{"tone":{"type":"choice","choice":"friendly","probabilities":{"friendly":1,"hostile":0},"confidence":1},"quality":{"type":"score","score":2,"confidence":1},"safe":{"type":"noul","noul":0.6}}}}}"#.data(using: .utf8)!
            return (body, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        await SwiftAI.bootstrap()
        let result = await SwiftAI.classify(model: model, context: context(), options: options)
        XCTAssertEqual(result.stopReason, .stop)
        XCTAssertEqual(result.usage?.input, 4)
        XCTAssertEqual(result.usage?.output, 3)
        XCTAssertEqual(box.capturedBody["model"], .string("@cf/typesafe/jev"))
        guard case .object(let input)? = box.capturedBody["input"] else { return XCTFail("missing input envelope") }
        XCTAssertNotNil(input["state"])
        XCTAssertNotNil(input["questions"])
    }
}
