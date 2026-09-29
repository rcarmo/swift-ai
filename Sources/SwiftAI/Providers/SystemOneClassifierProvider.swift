import Foundation

enum SystemOneClassifierProvider {
    enum Transport {
        case typeSafe
        case cloudflareWorkersAI
    }

    static func url(model: ClassifierModel, transport: Transport) -> String {
        let trimmed = model.baseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        switch transport {
        case .typeSafe: return trimmed + "/systemone"
        case .cloudflareWorkersAI: return trimmed + "/run"
        }
    }

    static func wireRequest(_ context: ClassificationContext) -> [String: JSONValue] {
        var questions: [String: JSONValue] = [:]
        for (id, question) in context.questions {
            let object: [String: JSONValue] = [
                "type": .string(question.type == "bool" ? "noul" : question.type),
                "instructions": .string(question.instructions),
                "criteria": question.criteria
            ]
            questions[id] = .object(object)
        }
        return ["state": context.state, "questions": .object(questions)]
    }

    static func payload(model: ClassifierModel, context: ClassificationContext, transport: Transport) -> [String: JSONValue] {
        let request = wireRequest(context)
        switch transport {
        case .typeSafe:
            var payload = request
            payload["model"] = .string(model.id)
            return payload
        case .cloudflareWorkersAI:
            return ["model": .string(model.id), "input": .object(request)]
        }
    }

    static func requestHeaders(model: ClassifierModel, apiKey: String, options: ClassifierOptions?) -> [String: String] {
        var headers: [String: String] = ["authorization": "Bearer \(apiKey)", "content-type": "application/json"]
        for (key, value) in model.headers ?? [:] { if let value { headers[key.lowercased()] = value } }
        for (key, value) in options?.headers ?? [:] { if let value { headers[key.lowercased()] = value } }
        return headers
    }

    static func parseTransportOutput(_ body: JSONValue, transport: Transport) throws -> [String: JSONValue] {
        guard case .object(let object) = body else { throw AIError.invalidResponse("System One API returned an unexpected response") }
        switch transport {
        case .typeSafe:
            return object
        case .cloudflareWorkersAI:
            if object["success"] == .bool(false) { throw AIError.provider(cloudflareErrorMessage(object["errors"])) }
            guard case .object(let run)? = object["result"], run["state"] == .string("Completed"), case .object(let result)? = run["result"] else { throw AIError.invalidResponse("Cloudflare Workers AI returned an unexpected response") }
            return result
        }
    }

    static func parseResult(_ body: JSONValue, model: ClassifierModel, context: ClassificationContext, transport: Transport) throws -> ClassificationResult {
        let output = try parseTransportOutput(body, transport: transport)
        var result = ClassificationResult(api: model.api, provider: model.provider, model: model.id, stopReason: .stop)
        if case .object(let usage)? = output["usage"] { result.usage = parseUsage(usage, model: model) }
        guard case .object(let answersObject)? = output["answers"] else { throw AIError.invalidResponse("System One API returned an unexpected response") }
        var answers: [String: ClassificationAnswer] = [:]
        for (id, question) in context.questions {
            guard case .object(let answer)? = answersObject[id] else { throw AIError.invalidResponse("System One API did not return an answer for \(id)") }
            answers[id] = try parseAnswer(answer, question: question, id: id)
        }
        result.answers = answers
        return result
    }

    private static func parseAnswer(_ answer: [String: JSONValue], question: ClassifierQuestion, id: String) throws -> ClassificationAnswer {
        switch question.type {
        case "choice":
            guard answer["type"] == .string("choice"), case .string(let choice)? = answer["choice"] else { throw AIError.invalidResponse("System One API did not return a choice answer for \(id)") }
            var probs: [String: Double] = [:]
            if case .object(let raw)? = answer["probabilities"] {
                for (key, value) in raw { guard case .number(let number) = value else { throw AIError.invalidResponse("System One API returned invalid probabilities for \(id)") }; probs[key] = number }
            }
            let confidence = answer["confidence"]?.doubleValue
            return ClassificationAnswer(type: "choice", choice: choice, probabilities: probs, confidence: confidence)
        case "score":
            guard answer["type"] == .string("score"), case .number(let score)? = answer["score"] else { throw AIError.invalidResponse("System One API did not return a score answer for \(id)") }
            return ClassificationAnswer(type: "score", confidence: answer["confidence"]?.doubleValue, score: score)
        default:
            guard answer["type"] == .string("noul") || answer["type"] == .string("bool"), case .number(let probability)? = answer["noul"] ?? answer["probability"] else { throw AIError.invalidResponse("System One API did not return a bool answer for \(id)") }
            return ClassificationAnswer(type: "bool", probability: probability)
        }
    }

    private static func parseUsage(_ usage: [String: JSONValue], model: ClassifierModel) -> Usage? {
        let input = positiveInt(usage["input_tokens"])
        let output = positiveInt(usage["output_tokens"])
        guard input > 0 || output > 0 else { return nil }
        var result = Usage()
        result.input = input
        result.output = output
        result.totalTokens = input + output
        result.cost.input = Double(input) / 1_000_000.0 * model.cost.input
        result.cost.output = Double(output) / 1_000_000.0 * model.cost.output
        result.cost.total = result.cost.input + result.cost.output
        return result
    }

    private static func positiveInt(_ value: JSONValue?) -> Int {
        guard case .number(let number)? = value, number.isFinite, number > 0 else { return 0 }
        return Int(number)
    }

    private static func cloudflareErrorMessage(_ errors: JSONValue?) -> String {
        guard case .array(let array)? = errors else { return "Cloudflare Workers AI request failed" }
        let messages = array.compactMap { item -> String? in
            guard case .object(let object) = item, case .string(let message)? = object["message"] else { return nil }
            return message
        }
        return messages.isEmpty ? "Cloudflare Workers AI request failed" : "Cloudflare Workers AI error: \(messages.joined(separator: "; "))"
    }

    static func classify(model: ClassifierModel, context: ClassificationContext, options: ClassifierOptions?, transport: Transport) async -> ClassificationResult {
        var output = ClassificationResult(api: model.api, provider: model.provider, model: model.id, stopReason: .stop)
        do {
            let expectedAPI: ClassifierAPI = transport == .typeSafe ? .typeSafeSystemOne : .cloudflareWorkersAISystemOne
            guard model.api == expectedAPI else { throw AIError.unsupported("Unsupported classifier API: \(model.api.rawValue)") }
            guard let apiKey = options?.apiKey, !apiKey.isEmpty else { throw AIError.provider("No API key for provider: \(model.provider.rawValue)") }
            var body = payload(model: model, context: context, transport: transport)
            if let transformed = try await options?.onPayload?(body, model) { body = transformed }
            // Network transport is intentionally left to consuming applications; deterministic tests exercise
            // request building and response parsing through the public helpers above.
            _ = requestHeaders(model: model, apiKey: apiKey, options: options)
            output.errorMessage = "no classifier transport configured for \(url(model: model, transport: transport))"
            output.stopReason = .error
            return output
        } catch {
            output.stopReason = .error
            output.errorMessage = String(describing: error)
            return output
        }
    }
}
