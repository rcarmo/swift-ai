import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

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

    static func wireRequest(_ context: ClassificationContext) throws -> [String: JSONValue] {
        guard case .object = context.state else { throw AIError.provider("System One classifier state must be a JSON object") }
        var questions: [String: JSONValue] = [:]
        for (id, question) in context.questions {
            try validateQuestion(question, id: id)
            let object: [String: JSONValue] = [
                "type": .string(question.type == "bool" ? "noul" : question.type),
                "instructions": .string(question.instructions),
                "criteria": question.criteria
            ]
            questions[id] = .object(object)
        }
        return ["state": context.state, "questions": .object(questions)]
    }

    private static func validateQuestion(_ question: ClassifierQuestion, id: String) throws {
        switch question.type {
        case "choice":
            guard case .object(let criteria) = question.criteria, !criteria.isEmpty, criteria.values.allSatisfy({ if case .string = $0 { return true }; return false }) else {
                throw AIError.provider("System One choice question \"\(id)\" requires string criteria")
            }
        case "score":
            guard case .array(let criteria) = question.criteria, !criteria.isEmpty, criteria.allSatisfy({ if case .string = $0 { return true }; return false }) else {
                throw AIError.provider("System One score question \"\(id)\" requires string criteria")
            }
        case "bool":
            guard case .object(let criteria) = question.criteria, case .string? = criteria["true"], case .string? = criteria["false"] else {
                throw AIError.provider("System One bool question \"\(id)\" requires true and false criteria")
            }
        default:
            throw AIError.provider("System One question \"\(id)\" has unsupported type \"\(question.type)\"")
        }
    }

    static func payload(model: ClassifierModel, context: ClassificationContext, transport: Transport) throws -> [String: JSONValue] {
        let request = try wireRequest(context)
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
        let base: ProviderHeaders = ["authorization": "Bearer \(apiKey)", "content-type": "application/json"]
        let withModel = AIUtilities.mergeProviderHeaders(base, override: model.headers)?.mapValues { Optional($0) }
        return AIUtilities.mergeProviderHeaders(withModel, override: options?.headers) ?? [:]
    }

    static func parseTransportOutput(_ body: JSONValue, transport: Transport) throws -> [String: JSONValue] {
        guard case .object(let object) = body else { throw AIError.invalidResponse("System One API returned an unexpected response") }
        switch transport {
        case .typeSafe:
            return object
        case .cloudflareWorkersAI:
            if object["success"] == .bool(false) { throw AIError.provider(cloudflareErrorMessage(object["errors"])) }
            guard case .object(let result)? = object["result"] else { throw AIError.invalidResponse("Cloudflare Workers AI returned an unexpected response") }
            if result["answers"] != nil { return result }
            guard result["state"] == .string("Completed"), case .object(let nested)? = result["result"] else { throw AIError.invalidResponse("Cloudflare Workers AI returned an unexpected response") }
            return nested
        }
    }

    static func parseResult(_ body: JSONValue, model: ClassifierModel, context: ClassificationContext, transport: Transport) throws -> ClassificationResult {
        let output = try parseTransportOutput(body, transport: transport)
        var result = ClassificationResult(api: model.api, provider: model.provider, model: model.id, stopReason: .stop, timestamp: nowMs())
        if case .object(let usage)? = output["usage"] { result.usage = parseUsage(usage, model: model) }
        result.answers = try parseAnswers(output["answers"], context: context)
        return result
    }

    static func parseResultPreservingUsage(_ body: JSONValue, model: ClassifierModel, context: ClassificationContext, transport: Transport) -> ClassificationResult {
        var result = ClassificationResult(api: model.api, provider: model.provider, model: model.id, stopReason: .stop, timestamp: nowMs())
        do {
            let output = try parseTransportOutput(body, transport: transport)
            if case .object(let usage)? = output["usage"] { result.usage = parseUsage(usage, model: model) }
            result.answers = try parseAnswers(output["answers"], context: context)
            return result
        } catch {
            result.stopReason = .error
            result.errorMessage = String(describing: error)
            return result
        }
    }

    private static func parseAnswers(_ value: JSONValue?, context: ClassificationContext) throws -> [String: ClassificationAnswer] {
        guard case .object(let answersObject)? = value else { throw AIError.invalidResponse("System One API returned an unexpected response") }
        var answers: [String: ClassificationAnswer] = [:]
        for (id, question) in context.questions {
            guard case .object(let answer)? = answersObject[id] else { throw AIError.invalidResponse("System One API did not return an answer for \(id)") }
            answers[id] = try parseAnswer(answer, question: question, id: id)
        }
        return answers
    }

    private static func requiredFiniteNumber(_ value: JSONValue?, field: String) throws -> Double {
        guard case .number(let number)? = value, number.isFinite else { throw AIError.invalidResponse("System One API returned invalid \(field)") }
        return number
    }

    private static func parseAnswer(_ answer: [String: JSONValue], question: ClassifierQuestion, id: String) throws -> ClassificationAnswer {
        switch question.type {
        case "choice":
            guard answer["type"] == .string("choice"), case .string(let choice)? = answer["choice"] else { throw AIError.invalidResponse("System One API did not return a choice answer for \(id)") }
            guard case .object(let raw)? = answer["probabilities"] else { throw AIError.invalidResponse("System One API returned invalid probabilities for \(id)") }
            var probs: [String: Double] = [:]
            for (key, value) in raw { probs[key] = try requiredFiniteNumber(value, field: "probability for \(id).\(key)") }
            let confidence = try requiredFiniteNumber(answer["confidence"], field: "confidence for \(id)")
            return ClassificationAnswer(type: "choice", choice: choice, probabilities: probs, confidence: confidence)
        case "score":
            guard answer["type"] == .string("score") else { throw AIError.invalidResponse("System One API did not return a score answer for \(id)") }
            let score = try requiredFiniteNumber(answer["score"], field: "score for \(id)")
            let confidence = try requiredFiniteNumber(answer["confidence"], field: "confidence for \(id)")
            return ClassificationAnswer(type: "score", confidence: confidence, score: score)
        case "bool":
            guard answer["type"] == .string("noul") || answer["type"] == .string("bool") else { throw AIError.invalidResponse("System One API did not return a bool answer for \(id)") }
            let probability = try requiredFiniteNumber(answer["noul"] ?? answer["probability"], field: "probability for \(id)")
            return ClassificationAnswer(type: "bool", probability: probability)
        default:
            throw AIError.invalidResponse("System One API cannot parse unsupported question type \(question.type) for \(id)")
        }
    }

    private static func parseUsage(_ usage: [String: JSONValue], model: ClassifierModel) -> Usage? {
        guard let inputValue = usageInt(usage["input_tokens"]), let outputValue = usageInt(usage["output_tokens"]) else { return nil }
        let input = inputValue
        let output = outputValue
        guard input > 0 || output > 0 else { return nil }
        let sum = input.addingReportingOverflow(output)
        guard !sum.overflow else { return nil }
        let total = sum.partialValue
        var result = Usage()
        result.input = input
        result.output = output
        result.totalTokens = total
        result.cost = AIUtilities.calculateCost(cost: model.cost, usage: result)
        return result
    }

    private static func usageInt(_ value: JSONValue?) -> Int? {
        guard let value else { return 0 }
        guard case .number(let number) = value, number.isFinite, number.rounded(.towardZero) == number else { return nil }
        if number <= 0 { return 0 }
        return Int(exactly: number)
    }

    private static func nowMs() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    private static func cloudflareErrorMessage(_ errors: JSONValue?) -> String {
        guard case .array(let array)? = errors else { return "Cloudflare Workers AI request failed" }
        let messages = array.compactMap { item -> String? in
            guard case .object(let object) = item, case .string(let message)? = object["message"] else { return nil }
            return message
        }
        return messages.isEmpty ? "Cloudflare Workers AI request failed" : "Cloudflare Workers AI error: \(messages.joined(separator: "; "))"
    }

    static func classify(model: ClassifierModel, context: ClassificationContext, options: ClassifierOptions?, transport: Transport) async -> ClassificationResult {
        var output = ClassificationResult(api: model.api, provider: model.provider, model: model.id, stopReason: .stop, timestamp: nowMs())
        do {
            let expectedAPI: ClassifierAPI = transport == .typeSafe ? .typeSafeSystemOne : .cloudflareWorkersAISystemOne
            guard model.api == expectedAPI else { throw AIError.unsupported("Unsupported classifier API: \(model.api.rawValue)") }
            guard context.images?.isEmpty != false else { throw AIError.unsupported("System One classification does not support image input") }
            guard let apiKey = options?.apiKey, !apiKey.isEmpty else { throw AIError.provider("No API key for provider: \(model.provider.rawValue)") }
            var body = try payload(model: model, context: context, transport: transport)
            if let transformed = try await options?.onPayload?(body, model) { body = transformed }
            let requestURLString = url(model: model, transport: transport)
            guard let requestURL = URL(string: requestURLString), ["http", "https"].contains(requestURL.scheme?.lowercased() ?? ""), requestURL.host?.isEmpty == false else { throw AIError.provider("Invalid System One URL: \(requestURLString)") }
            var nextRequest = URLRequest(url: requestURL)
            nextRequest.httpMethod = "POST"
            for (key, value) in requestHeaders(model: model, apiKey: apiKey, options: options) { nextRequest.setValue(value, forHTTPHeaderField: key) }
            if let timeoutMs = options?.timeoutMs, timeoutMs > 0 { nextRequest.timeoutInterval = Double(timeoutMs) / 1000.0 }
            nextRequest.httpBody = try JSONEncoder().encode(body)
            let request = nextRequest
            let requestTransport = options?.requestTransport
            let onResponse = options?.onResponse
            let policy = RetryPolicy(maxRetries: options?.maxRetries ?? 2, maxRetryDelayMs: options?.maxRetryDelayMs ?? 60_000)
            let (data, response): (Data, URLResponse) = try await ProviderRetry.run(maxRetries: policy.maxRetries, maxRetryDelayMs: policy.maxRetryDelayMs) {
                try Task.checkCancellation()
                let pair: (Data, URLResponse)
                if let requestTransport { pair = try await requestTransport(request, policy) }
                else { pair = try await HTTPRetry.providerData(for: request, maxRetryDelayMs: policy.maxRetryDelayMs) }
                guard let http = pair.1 as? HTTPURLResponse else { throw ProviderRetryError(status: nil, message: "non-HTTP response") }
                guard (200..<300).contains(http.statusCode) else {
                    let text = String(data: pair.0, encoding: .utf8) ?? ""
                    let headers = Dictionary(uniqueKeysWithValues: http.allHeaderFields.map { (String(describing: $0.key), String(describing: $0.value)) })
                    throw ProviderRetryError(status: http.statusCode, headers: headers, message: text.isEmpty ? "HTTP \(http.statusCode)" : text)
                }
                return pair
            }
            let decoded: JSONValue
            do { decoded = try JSONDecoder().decode(JSONValue.self, from: data) }
            catch {
                output.stopReason = .error
                output.errorMessage = "System One API returned invalid JSON"
                return output
            }
            if let http = response as? HTTPURLResponse { await onResponse?(ClassifierResponseMetadata(status: http.statusCode, headers: http.headersDictionary), model) }
            return parseResultPreservingUsage(decoded, model: model, context: context, transport: transport)
        } catch is CancellationError {
            output.stopReason = .aborted
            return output
        } catch {
            output.stopReason = .error
            output.errorMessage = String(describing: error)
            return output
        }
    }
}
