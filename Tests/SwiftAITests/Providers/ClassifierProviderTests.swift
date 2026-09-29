import XCTest
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
        let payload = SystemOneClassifierProvider.payload(model: model, context: context(), transport: .typeSafe)
        XCTAssertEqual(payload["model"], .string("jev-latest"))
        guard case .object(let questions)? = payload["questions"], case .object(let safe)? = questions["safe"] else { return XCTFail("missing questions") }
        XCTAssertEqual(safe["type"], .string("noul"))
        XCTAssertEqual(SystemOneClassifierProvider.url(model: model, transport: .typeSafe), "https://api.typesafe.ai/v1/systemone")
        XCTAssertEqual(SystemOneClassifierProvider.requestHeaders(model: model, apiKey: "key", options: nil)["authorization"], "Bearer key")

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
        let model = ClassifierModel(id: "@cf/typesafe/jev", name: "Jev", api: .cloudflareWorkersAISystemOne, provider: .cloudflareWorkersAI, baseUrl: "https://api.cloudflare.com/client/v4/accounts/acct/ai")
        let payload = SystemOneClassifierProvider.payload(model: model, context: context(), transport: .cloudflareWorkersAI)
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

        let errorBody: JSONValue = .object(["success": .bool(false), "errors": .array([.object(["message": .string("bad account")])])])
        XCTAssertThrowsError(try SystemOneClassifierProvider.parseResult(errorBody, model: model, context: context(), transport: .cloudflareWorkersAI)) { error in
            XCTAssertTrue(String(describing: error).contains("bad account"))
        }
    }
}
