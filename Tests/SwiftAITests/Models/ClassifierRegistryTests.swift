import XCTest
@testable import SwiftAI

final class ClassifierRegistryTests: XCTestCase {
    func testClassifierRegistryRegistersProvidersAndModels() async {
        await ClassifierRegistry.shared.clearModels()
        await ClassifierRegistry.shared.clearProviders()
        let model = ClassifierModel(id: "jev-latest", name: "Jev", api: .typeSafeSystemOne, provider: .typesafe)
        await ClassifierRegistry.shared.register(model)
        await ClassifierRegistry.shared.register(ClassifierAPIProvider(api: .typeSafeSystemOne) { model, _, _ in
            ClassificationResult(api: model.api, provider: model.provider, model: model.id, answers: ["safe": ClassificationAnswer(type: "bool", probability: 0.9)], stopReason: .stop)
        })
        let providers = await ClassifierRegistry.shared.listProviders()
        let models = await ClassifierRegistry.shared.listModels(provider: .typesafe)
        let found = await ClassifierRegistry.shared.model(provider: .typesafe, id: "jev-latest")
        XCTAssertEqual(providers, [.typesafe])
        XCTAssertEqual(models.map(\.id), ["jev-latest"])
        XCTAssertEqual(found, model)
        let result = await SwiftAI.classify(model: model, context: ClassificationContext(input: "hello", questions: ["safe": .bool(instructions: "safe?")]))
        XCTAssertEqual(result.stopReason, .stop)
        XCTAssertEqual(result.answers["safe"]?.probability, 0.9)
        await ClassifierRegistry.shared.clearModels()
        await ClassifierRegistry.shared.clearProviders()
        await SwiftAI.bootstrap()
    }

    func testBuiltinClassifierCatalogMatchesV101Oracle() throws {
        XCTAssertEqual(BuiltinClassifierModels.upstreamVersion, "1.0.1")
        XCTAssertEqual(BuiltinClassifierModels.modelCount, 20)
        XCTAssertEqual(BuiltinClassifierModels.providerCount, 5)
        let models = try BuiltinClassifierModels.all()
        XCTAssertEqual(models.count, 20)
        XCTAssertEqual(Set(models.map(\.api)), [.typeSafeSystemOne, .cloudflareWorkersAISystemOne])
        XCTAssertEqual(Set(models.map(\.provider)), [ClassifierProvider.typesafe, .cloudflareWorkersAI, .openRouter, .vercelAIGateway, .openCode])

        let direct = try XCTUnwrap(models.first { $0.provider == .typesafe && $0.id == "jev-latest" })
        XCTAssertEqual(direct.api, .typeSafeSystemOne)
        XCTAssertEqual(direct.baseUrl, "https://api.typesafe.ai/v1/")
        XCTAssertEqual(direct.contextWindow, 64_000)
        XCTAssertEqual(direct.input, ["text"])
        XCTAssertEqual(direct.type, "classifier")

        let vercel = try XCTUnwrap(models.first { $0.provider == .vercelAIGateway && $0.id == "typesafe-ai/jev" })
        XCTAssertEqual(vercel.baseUrl, "https://ai-gateway.vercel.sh/typesafe/v1")
        XCTAssertEqual(vercel.api, .typeSafeSystemOne)

        let cloudflare = try XCTUnwrap(models.first { $0.provider == .cloudflareWorkersAI && $0.id == "typesafe/jev" })
        XCTAssertEqual(cloudflare.api, .cloudflareWorkersAISystemOne)
        XCTAssertTrue(cloudflare.baseUrl.contains("{CLOUDFLARE_ACCOUNT_ID}"))

        XCTAssertNil(try BuiltinModels.all().first { $0.provider.rawValue == "typesafe" && $0.id == "jev-latest" })
        XCTAssertEqual(ProviderEnvironment.apiKey(for: ClassifierProvider.typesafe, env: ["TYPESAFE_API_KEY": "ts-key"]), "ts-key")
        XCTAssertEqual(ProviderEnvironment.apiKey(for: ClassifierProvider.cloudflareWorkersAI, env: ["CLOUDFLARE_API_KEY": "cf-key"]), "cf-key")
    }
}
