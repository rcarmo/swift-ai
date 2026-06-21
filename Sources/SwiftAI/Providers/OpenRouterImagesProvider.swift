import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum OpenRouterImagesProvider {
    public static func generateImages(model: ImagesModel, context: ImagesContext, options: ImagesOptions?) async -> AssistantImages {
        var out = AssistantImages(api: model.api, provider: model.provider, model: model.id, stopReason: .stop, timestamp: Int64(Date().timeIntervalSince1970 * 1000))
        guard let apiKey = ProviderEnvironment.apiKey(for: .openRouter, env: options?.env), !apiKey.isEmpty else {
            out.stopReason = .error
            out.errorMessage = "No API key available for provider: \(model.provider.rawValue)"
            return out
        }
        do {
            let payload = buildImagesPayload(model: model, context: context)
            let base = (model.baseUrl ?? "https://openrouter.ai/api/v1").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            var request = URLRequest(url: URL(string: base + "/chat/completions")!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            for (k, v) in model.headers ?? [:] { request.setValue(v, forHTTPHeaderField: k) }
            for (k, v) in options?.headers ?? [:] { request.setValue(v, forHTTPHeaderField: k) }
            request.httpBody = try JSONEncoder().encode(payload)
            let (data, response) = try await HTTPRetry.data(for: request, policy: RetryPolicy(options: options))
            guard let http = response as? HTTPURLResponse else {
                out.stopReason = .error; out.errorMessage = "non-HTTP response"; return out
            }
            if http.statusCode >= 300 {
                out.stopReason = .error
                out.errorMessage = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
                return out
            }
            let decoded = try JSONDecoder().decode(OpenRouterImageResponse.self, from: data)
            out.responseId = decoded.id
            if let usage = decoded.usage { var u = Usage(); u.input = usage.promptTokens ?? 0; u.output = usage.completionTokens ?? 0; u.totalTokens = usage.totalTokens ?? (u.input + u.output); out.usage = u }
            if let text = decoded.choices.first?.message.content, !text.isEmpty { out.output.append(ImageOutput(type: "text", text: text)) }
            for image in decoded.choices.first?.message.images ?? [] {
                guard let url = image.urlValue, url.hasPrefix("data:") else { continue }
                let stripped = String(url.dropFirst("data:".count))
                let parts = stripped.components(separatedBy: ";base64,")
                if parts.count == 2 { out.output.append(ImageOutput(type: "image", data: parts[1], mimeType: parts[0])) }
            }
            return out
        } catch {
            out.stopReason = .error
            out.errorMessage = error.localizedDescription
            return out
        }
    }

    public static func buildImagesPayload(model: ImagesModel, context: ImagesContext) -> JSONValue {
        let content: [JSONValue] = context.input.map { input in
            if input.type == "text" { return .object(["type": .string("text"), "text": .string(input.text ?? "")]) }
            return .object(["type": .string("image_url"), "image_url": .object(["url": .string("data:\(input.mimeType ?? "application/octet-stream");base64,\(input.data ?? "")")])])
        }
        var modalities = [JSONValue.string("image")]
        if model.output?.contains("text") == true { modalities.append(.string("text")) }
        return .object([
            "model": .string(model.id),
            "messages": .array([.object(["role": .string("user"), "content": .array(content)])]),
            "stream": .bool(false),
            "modalities": .array(modalities)
        ])
    }
}

private struct OpenRouterImageResponse: Decodable {
    var id: String?
    var choices: [Choice]
    var usage: OpenRouterUsage?
    struct Choice: Decodable { var message: Message }
    struct Message: Decodable { var content: String?; var images: [Image]? }
    struct Image: Decodable {
        var imageUrlObject: ImageURLObject?
        var imageUrlString: String?
        var urlValue: String? { imageUrlObject?.url ?? imageUrlString }
        struct ImageURLObject: Decodable { var url: String? }
        enum CodingKeys: String, CodingKey { case imageUrl = "image_url" }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            imageUrlObject = try? c.decode(ImageURLObject.self, forKey: .imageUrl)
            imageUrlString = try? c.decode(String.self, forKey: .imageUrl)
        }
    }
}

private struct OpenRouterUsage: Decodable { var promptTokens: Int?; var completionTokens: Int?; var totalTokens: Int?; enum CodingKeys: String, CodingKey { case promptTokens = "prompt_tokens"; case completionTokens = "completion_tokens"; case totalTokens = "total_tokens" } }
