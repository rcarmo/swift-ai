import XCTest
@testable import SwiftAI

final class ImageRegistryTests: XCTestCase {
    func testImageRegistryRegistersProvidersAndModels() async {
        await ImagesRegistry.shared.clearModels()
        await ImagesRegistry.shared.clearProviders()
        let m1 = ImagesModel(id: "m1", name: "m1", api: .openRouterImages, provider: .openRouter)
        let m2 = ImagesModel(id: "m2", name: "m2", api: .openRouterImages, provider: .openRouter)
        await ImagesRegistry.shared.register(m1)
        await ImagesRegistry.shared.register(m2)
        await ImagesRegistry.shared.register(ImagesAPIProvider(api: .openRouterImages) { model, _, _ in
            AssistantImages(api: model.api, provider: model.provider, model: model.id, output: [ImageOutput(type: "image", data: "aGk=", mimeType: "image/png")], stopReason: .stop)
        })
        XCTAssertEqual(await ImagesRegistry.shared.listProviders(), [.openRouter])
        XCTAssertEqual(await ImagesRegistry.shared.listModels(provider: .openRouter).map(\.id), ["m1", "m2"])
        XCTAssertEqual(await ImagesRegistry.shared.model(provider: .openRouter, id: "m2"), m2)
        let result = await SwiftAI.generateImages(model: m1, context: ImagesContext(input: [.text("a red circle")]))
        XCTAssertEqual(result.stopReason, .stop)
        XCTAssertEqual(result.output.first?.mimeType, "image/png")
        await ImagesRegistry.shared.clearModels()
        await ImagesRegistry.shared.clearProviders()
        await SwiftAI.bootstrap()
    }

    func testBuiltinImageRegistryOpenRouterCatalog() throws {
        XCTAssertEqual(BuiltinImageModels.providerCount, 1)
        let models = try BuiltinImageModels.all()
        XCTAssertEqual(models.count, 34)
        XCTAssertTrue(models.allSatisfy { $0.api == .openRouterImages && $0.provider == .openRouter })
        XCTAssertNotNil(models.first { $0.id == "black-forest-labs/flux.2-flex" })
        XCTAssertEqual(ProviderEnvironment.apiKey(for: .openRouter, env: ["OPENROUTER_API_KEY": "or-key"]), "or-key")
    }

    func testGenerateImagesUnknownProviderError() async {
        await ImagesRegistry.shared.clearProviders()
        let model = ImagesModel(id: "m", name: "m", api: .openRouterImages, provider: .openRouter)
        let result = await SwiftAI.generateImages(model: model, context: ImagesContext(input: [.text("x")]))
        XCTAssertEqual(result.stopReason, .error)
        XCTAssertTrue(result.errorMessage?.contains("no image provider registered") == true)
        await SwiftAI.bootstrap()
    }
}
