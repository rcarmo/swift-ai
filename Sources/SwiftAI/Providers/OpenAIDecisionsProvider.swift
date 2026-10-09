import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// OpenAI Decisions uses API-key authentication; ChatGPT OAuth tokens are unsupported.
public enum OpenAIDecisionsProvider {
    public static func buildRequestBody(model: ClassifierModel, context: ClassificationContext) throws -> [String: JSONValue] {
        guard model.api == .openAIDecisions else { throw AIError.unsupported("Unsupported classifier API: \(model.api.rawValue)") }
        guard context.state.objectValue != nil else { throw AIError.invalidResponse("Classifier state must be an object") }
        let data = try JSONEncoder().encode(context.state)
        guard let state = String(data: data, encoding: .utf8) else { throw AIError.invalidResponse("Invalid classifier state") }
        var input: JSONValue = .string(state)
        if let images = context.images, !images.isEmpty {
            guard model.input.contains("image"), images.count <= 128 else { throw AIError.unsupported("OpenAI Decisions accepts at most 128 images on image-capable models") }
            var content: [JSONValue] = [.object(["type": .string("input_text"), "text": .string(state)])]
            for image in images {
                guard image.type == "image", let mime = image.mimeType, let data = image.data else { throw AIError.invalidResponse("Invalid classifier image") }
                content.append(.object(["type": .string("input_image"), "image_url": .string("data:\(mime);base64,\(data)")]))
            }
            input = .array([.object(["role": .string("user"), "content": .array(content)])])
        }
        let questions = try context.questions.sorted { $0.key < $1.key }.map { id, question -> JSONValue in
            var wire: [String: JSONValue] = ["name": .string(id), "instructions": .string(question.instructions)]
            switch question.type {
            case "choice":
                guard let criteria = question.criteria.objectValue else { throw AIError.invalidResponse("Invalid choice criteria") }
                wire["type"] = .string("choice")
                wire["choices"] = .array(try criteria.sorted { $0.key < $1.key }.map { value, description in
                    guard let text = description.stringValue else { throw AIError.invalidResponse("Invalid choice description") }
                    var choice: [String: JSONValue] = ["value": .string(value)]
                    if !text.isEmpty { choice["description"] = .string(text) }
                    return .object(choice)
                })
            case "score":
                guard let criteria = question.criteria.arrayValue else { throw AIError.invalidResponse("Invalid score criteria") }
                wire["type"] = .string("score")
                wire["levels"] = .array(try criteria.map { label in
                    guard let text = label.stringValue else { throw AIError.invalidResponse("Invalid score label") }
                    return .object(["label": .string(text)])
                })
            case "bool":
                guard let criteria = question.criteria.objectValue else { throw AIError.invalidResponse("Invalid predicate criteria") }
                wire["type"] = .string("predicate")
                var meanings: [String] = []
                if let text = criteria["true"]?.stringValue, !text.isEmpty { meanings.append("True means: \(text)") }
                if let text = criteria["false"]?.stringValue, !text.isEmpty { meanings.append("False means: \(text)") }
                if !meanings.isEmpty { wire["instructions"] = .string(question.instructions + "\n\n" + meanings.joined(separator: "\n")) }
            default: throw AIError.unsupported("Unsupported classifier question type: \(question.type)")
            }
            return .object(wire)
        }
        return ["model": .string(model.id), "input": input, "questions": .array(questions)]
    }

    public static func parseResult(_ body: JSONValue, model: ClassifierModel, context: ClassificationContext) -> ClassificationResult {
        var output = ClassificationResult(api: model.api, provider: model.provider, model: model.id, stopReason: .stop, timestamp: Int64(Date().timeIntervalSince1970 * 1000))
        do {
            guard let object = body.objectValue else { throw AIError.invalidResponse("OpenAI Decisions returned an unexpected response") }
            if let usage = object["usage"]?.objectValue, usage["input_tokens"] != nil || usage["output_tokens"] != nil {
                func tokens(_ value: JSONValue?) -> Int {
                    guard let number = value?.doubleValue, number.isFinite, number > 0, let count = Int(exactly: number) else { return 0 }
                    return count
                }
                var result = Usage()
                result.input = tokens(usage["input_tokens"]); result.output = tokens(usage["output_tokens"])
                let total = result.input.addingReportingOverflow(result.output)
                guard !total.overflow else { throw AIError.invalidResponse("Classifier token total overflow") }
                result.totalTokens = total.partialValue
                result.cost = AIUtilities.calculateCost(cost: model.cost, usage: result)
                output.usage = result
            }
            guard let answers = object["answers"]?.arrayValue else { throw AIError.invalidResponse("OpenAI Decisions returned invalid answers") }
            var byName: [String: [String: JSONValue]] = [:]
            for value in answers { if let answer = value.objectValue, let name = answer["name"]?.stringValue { byName[name] = answer } }
            func number(_ value: JSONValue?, _ field: String) throws -> Double {
                guard let n = value?.doubleValue, n.isFinite else { throw AIError.invalidResponse("OpenAI Decisions returned invalid \(field)") }
                return n
            }
            var parsed: [String: ClassificationAnswer] = [:]
            for (id, question) in context.questions {
                guard let answer = byName[id] else { throw AIError.invalidResponse("OpenAI Decisions did not return an answer for \(id)") }
                if answer["type"] == .string("refusal") { throw AIError.provider("OpenAI Decisions refused to answer \(id)") }
                switch question.type {
                case "choice":
                    guard answer["type"] == .string("choice"), let choice = answer["choice"]?.stringValue, let raw = answer["probabilities"]?.arrayValue else { throw AIError.invalidResponse("Invalid choice answer for \(id)") }
                    var probabilities: [String: Double] = [:]
                    for entry in raw {
                        guard let value = entry.objectValue, let key = value["value"]?.stringValue else { throw AIError.invalidResponse("Invalid choice probabilities") }
                        probabilities[key] = try number(value["probability"], "probability")
                    }
                    parsed[id] = ClassificationAnswer(type: "choice", choice: choice, probabilities: probabilities, confidence: try number(answer["confidence"], "confidence"))
                case "score":
                    guard answer["type"] == .string("score") else { throw AIError.invalidResponse("Invalid score answer") }
                    parsed[id] = ClassificationAnswer(type: "score", confidence: try number(answer["confidence"], "confidence"), score: try number(answer["score"], "score"))
                case "bool":
                    guard answer["type"] == .string("predicate") else { throw AIError.invalidResponse("Invalid predicate answer") }
                    parsed[id] = ClassificationAnswer(type: "bool", probability: try number(answer["probability"], "probability"))
                default: throw AIError.unsupported("Unsupported question type")
                }
            }
            output.answers = parsed
        } catch { output.answers = [:]; output.stopReason = .error; output.errorMessage = String(describing: error) }
        return output
    }

    public static func classify(model: ClassifierModel, context: ClassificationContext, options: ClassifierOptions?) async -> ClassificationResult {
        do {
            let key = options?.apiKey ?? ProviderEnvironment.apiKey(for: model.provider, env: options?.env)
            guard let key, !key.isEmpty else { throw AIError.provider("No API key for provider: \(model.provider.rawValue)") }
            guard key.hasPrefix("sk-") || model.provider != .openAIClassifier else { throw AIError.unsupported("OpenAI Decisions requires an OpenAI API key; ChatGPT OAuth is unsupported") }
            var body = try buildRequestBody(model: model, context: context)
            if let hook = options?.onPayload { body = try await hook(body, model) }
            guard let url = URL(string: model.baseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/decisions"), ["http", "https"].contains(url.scheme ?? ""), url.host != nil else { throw AIError.invalidResponse("Invalid classifier URL") }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            AIUtilities.applyProviderHeaders(model.headers, options?.headers, to: &request)
            if let timeout = options?.timeoutMs, timeout > 0 { request.timeoutInterval = Double(timeout) / 1000 }
            request.httpBody = try JSONEncoder().encode(body)
            let fixedRequest = request
            let transport = options?.requestTransport
            let policy = RetryPolicy(maxRetries: options?.maxRetries ?? 2, maxRetryDelayMs: options?.maxRetryDelayMs ?? 60_000)
            let (data, response) = try await ProviderRetry.run(maxRetries: policy.maxRetries, maxRetryDelayMs: policy.maxRetryDelayMs, noRetryStatuses: [504]) {
                try Task.checkCancellation()
                let pair: (Data, URLResponse)
                if let transport { pair = try await transport(fixedRequest, policy) }
                else { pair = try await HTTPRetry.providerData(for: fixedRequest, maxRetryDelayMs: policy.maxRetryDelayMs) }
                guard let http = pair.1 as? HTTPURLResponse else { throw AIError.invalidResponse("Non-HTTP classifier response") }
                guard (200..<300).contains(http.statusCode) else { throw ProviderRetryError(status: http.statusCode, headers: http.headersDictionary, message: String(data: pair.0, encoding: .utf8) ?? "HTTP error") }
                return pair
            }
            if let http = response as? HTTPURLResponse { await options?.onResponse?(ClassifierResponseMetadata(status: http.statusCode, headers: http.headersDictionary), model) }
            return parseResult(try JSONDecoder().decode(JSONValue.self, from: data), model: model, context: context)
        } catch {
            let gateway = (error as? ProviderRetryError)?.status == 504
            return ClassificationResult(api: model.api, provider: model.provider, model: model.id, stopReason: Task.isCancelled ? .aborted : .error, timestamp: Int64(Date().timeIntervalSince1970 * 1000), errorMessage: gateway ? "OpenAI Decisions error (504): the request timed out at the gateway. Very large inputs (above roughly 600K tokens) currently exceed its time limit." : String(describing: error))
        }
    }
}
