import XCTest
@testable import SwiftAI

final class EnvironmentTests: XCTestCase {
    func testEnvApiKeyAuthHelper() async {
        let auth = AuthHelpers.envApiKeyAuth("Test key", ["FIRST_KEY", "SECOND_KEY"])
        let model = Model(id: "m", name: "M", api: .openAICompletions, provider: .openAI)
        let ctx = FakeAuthContext(env: ["FIRST_KEY": "env", "SECOND_KEY": "second"])
        let stored = await auth.resolve(model, ctx, .apiKey(key: "stored", env: nil))
        XCTAssertEqual(stored?.auth.apiKey, "stored")
        XCTAssertEqual(stored?.source, "stored credential")
        let env = await auth.resolve(model, FakeAuthContext(env: ["SECOND_KEY": "second"]), nil)
        XCTAssertEqual(env?.auth.apiKey, "second")
        XCTAssertEqual(env?.source, "SECOND_KEY")
        let missing = await auth.resolve(model, FakeAuthContext(env: [:]), nil)
        XCTAssertNil(missing)
    }

    func testEnvAPIKeysCopilotAndZAICodingCNMappings() {
        XCTAssertNil(ProviderEnvironment.apiKey(for: .githubCopilot, env: ["GH_TOKEN": "gh-token", "GITHUB_TOKEN": "github-token"]))
        XCTAssertEqual(ProviderEnvironment.apiKey(for: .githubCopilot, env: ["COPILOT_GITHUB_TOKEN": "copilot-token", "GH_TOKEN": "gh-token", "GITHUB_TOKEN": "github-token"]), "copilot-token")
        XCTAssertEqual(ProviderEnvironment.apiKey(for: .zaiCodingCN, env: ["ZAI_CODING_CN_API_KEY": "zai-coding-cn-token"]), "zai-coding-cn-token")
    }

    func testGetEnvAPIKeyProviderMappings() {
        XCTAssertEqual(ProviderEnvironment.apiKey(for: .openAI, env: ["OPENAI_API_KEY": "openai-key"]), "openai-key")
        XCTAssertEqual(ProviderEnvironment.apiKey(for: .anthropic, env: ["ANTHROPIC_OAUTH_TOKEN": "oauth", "ANTHROPIC_API_KEY": "api"]), "oauth")
        XCTAssertEqual(ProviderEnvironment.apiKey(for: .anthropic, env: ["ANTHROPIC_API_KEY": "api"]), "api")
        XCTAssertEqual(ProviderEnvironment.apiKey(for: .mistral, env: ["MISTRAL_API_KEY": "mistral"]), "mistral")
        XCTAssertEqual(ProviderEnvironment.apiKey(for: .deepSeek, env: ["DEEPSEEK_API_KEY": "deepseek"]), "deepseek")
    }

    func testGetEnvAPIKeyWithEnvBedrockAuthenticated() {
        XCTAssertEqual(ProviderEnvironment.apiKey(for: .amazonBedrock, env: ["AWS_PROFILE": "default"]), "<authenticated>")
        XCTAssertEqual(ProviderEnvironment.apiKey(for: .amazonBedrock, env: ["AWS_ACCESS_KEY_ID": "a", "AWS_SECRET_ACCESS_KEY": "s"]), "<authenticated>")
        XCTAssertEqual(ProviderEnvironment.apiKey(for: .amazonBedrock, env: ["AWS_CONTAINER_CREDENTIALS_RELATIVE_URI": "/v2/creds"]), "<authenticated>")
        XCTAssertEqual(ProviderEnvironment.apiKey(for: .amazonBedrock, env: ["AWS_WEB_IDENTITY_TOKEN_FILE": "/tmp/token"]), "<authenticated>")
    }

    func testResolveAPIKeyExplicitOptionPrecedence() {
        let model = Model(id: "m", name: "M", api: .openAICompletions, provider: .openAI)
        var options = StreamOptions()
        options.apiKey = "explicit"
        options.env = ["OPENAI_API_KEY": "env"]
        XCTAssertEqual(ProviderEnvironment.resolveAPIKey(model: model, options: options), "explicit")
    }

    func testEnvFallbackNameAndCacheRetention() {
        XCTAssertEqual(ProviderEnvironment.envFallbackName(.zaiCodingCN), "ZAI_CODING_CN_API_KEY")
        XCTAssertEqual(ProviderEnvironment.resolveCacheRetention(nil, env: ["PI_CACHE_RETENTION": "long"]), .long)
        XCTAssertEqual(ProviderEnvironment.resolveCacheRetention(.none, env: ["PI_CACHE_RETENTION": "long"]), .none)
        XCTAssertEqual(ProviderEnvironment.resolveCacheRetention(nil, env: [:]), .short)
    }
}

private struct FakeAuthContext: AuthContext {
    var envValues: [String: String]
    init(env: [String: String]) { self.envValues = env }
    func env(_ name: String) async -> String? { envValues[name] }
    func fileExists(_ path: String) async -> Bool { false }
}
