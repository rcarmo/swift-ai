import XCTest
@testable import SwiftAI
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class V110TransportTests: XCTestCase {
    func testAzureCompletionsResolvesEndpointDeploymentAndPayloadHook() async throws {
        let capture = V110RequestCapture()
        let previous = OpenAICompletionsProvider.requestTransport
        defer { OpenAICompletionsProvider.requestTransport = previous }
        OpenAICompletionsProvider.requestTransport = { request, _ in
            await capture.append(request)
            let sse = "data: {\"id\":\"r\",\"choices\":[{\"delta\":{\"content\":\"answer\"},\"finish_reason\":null}]}\n\ndata: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n"
            return (Self.bytes(sse), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: [:])!)
        }
        let model = Model(id: "catalog-model", name: "Azure", api: .openAICompletions, provider: .azure, baseUrl: "https://ignored.invalid/v1")
        var options = StreamOptions(); options.apiKey = "fixture"; options.env = ["AZURE_OPENAI_RESOURCE_NAME": "resource", "AZURE_OPENAI_DEPLOYMENT_NAME_MAP": "catalog-model=deployment"]
        options.onPayload = { body, payloadModel in
            XCTAssertEqual(body["model"], .string("deployment")); XCTAssertEqual(payloadModel.id, "catalog-model")
            var body = body; body["hook"] = .bool(true); return body
        }
        var result: Message?
        for await event in OpenAICompletionsProvider.stream(model: model, context: AIContext(messages: [.user("input")]), options: options) { if case .done(_, let message) = event { result = message } }
        XCTAssertEqual(result?.content.first?.text, "answer")
        let requests = await capture.requests; let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://resource.openai.azure.com/openai/v1/chat/completions")
        let body = try JSONDecoder().decode([String: JSONValue].self, from: XCTUnwrap(request.httpBody)); XCTAssertEqual(body["model"], .string("deployment")); XCTAssertEqual(body["hook"], .bool(true))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture")
    }

    func testAzureWhitespaceFallbackAndExplicitResourcePrecedence() throws {
        let model = Model(id: "m", name: "Azure", api: .azureOpenAIResponses, provider: .azure, baseUrl: "https://fallback.invalid/v1")
        var options = StreamOptions(); options.azureBaseUrl = "   "; options.azureDeploymentName = ""; options.azureResourceName = "preferred"; options.env = ["AZURE_OPENAI_DEPLOYMENT_NAME_MAP": "m=mapped", "AZURE_OPENAI_API_VERSION": "2026-test"]
        let config = try OpenAIResponsesProvider.resolveAzureConfig(model: model, options: options)
        XCTAssertEqual(config.baseURL, "https://preferred.openai.azure.com/openai/v1/deployments/mapped"); XCTAssertEqual(config.apiVersion, "2026-test")
        options.azureBaseUrl = " https://custom.invalid/openai/v1/ "
        let explicit = try OpenAIResponsesProvider.resolveAzureConfig(model: model, options: options); XCTAssertEqual(explicit.baseURL, "https://custom.invalid/openai/v1/deployments/mapped")
    }

    func testCodexCallerDefaultsOverrideButAuthAndAccountStayMandatory() async throws {
        let capture = V110RequestCapture(), previous = OpenAIResponsesProvider.requestTransport
        defer { OpenAIResponsesProvider.requestTransport = previous }
        let payload = Data("{\"https://api.openai.com/auth\":{\"chatgpt_account_id\":\"account\"}}".utf8).base64EncodedString().replacingOccurrences(of: "=", with: "").replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        let token = "header.\(payload).signature"
        OpenAIResponsesProvider.requestTransport = { request, _ in
            await capture.append(request)
            return (Self.bytes("data: {\"type\":\"response.completed\",\"response\":{\"id\":\"r\",\"status\":\"completed\",\"output\":[],\"usage\":{\"input_tokens\":1,\"output_tokens\":0}}}\n\n"), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: [:])!)
        }
        var model = Model(id: "codex", name: "Codex", api: .openAICodexResponses, provider: .openAICodex, baseUrl: "https://example.invalid")
        model.headers = ["originator": "model-origin", "User-Agent": "model-agent"]
        var options = StreamOptions(); options.apiKey = token; options.headers = ["originator": "app-origin", "User-Agent": "app-agent", "Authorization": "wrong", "chatgpt-account-id": "wrong"]
        for await _ in OpenAIResponsesProvider.stream(model: model, context: AIContext(), options: options) {}
        let requests = await capture.requests; let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "originator"), "app-origin"); XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "app-agent")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(token)"); XCTAssertEqual(request.value(forHTTPHeaderField: "chatgpt-account-id"), "account")
    }

    private static func bytes(_ text: String) -> AsyncThrowingStream<UInt8, Error> { AsyncThrowingStream { continuation in for byte in text.utf8 { continuation.yield(byte) }; continuation.finish() } }
}
private actor V110RequestCapture { var requests: [URLRequest] = []; func append(_ request: URLRequest) { requests.append(request) } }
