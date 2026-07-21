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
        let providers = await ImagesRegistry.shared.listProviders()
        let imageModels = await ImagesRegistry.shared.listModels(provider: .openRouter).map(\.id)
        let foundM2 = await ImagesRegistry.shared.model(provider: .openRouter, id: "m2")
        XCTAssertEqual(providers, [.openRouter])
        XCTAssertEqual(imageModels, ["m1", "m2"])
        XCTAssertEqual(foundM2, m2)
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
        XCTAssertEqual(models.count, 39)
        XCTAssertTrue(models.allSatisfy { $0.api == .openRouterImages && $0.provider == .openRouter })
        XCTAssertNotNil(models.first { $0.id == "black-forest-labs/flux.2-flex" })
        XCTAssertNotNil(models.first { $0.id == "krea/krea-2-large" })
        XCTAssertNotNil(models.first { $0.id == "openrouter/auto-beta" })
        XCTAssertEqual(ProviderEnvironment.apiKey(for: .openRouter, env: ["OPENROUTER_API_KEY": "or-key"]), "or-key")
    }

    func testGenerateImagesErrorPathsAndHookError() async {
        let nilResult = await SwiftAI.generateImages(model: nil, context: ImagesContext(input: [.text("x")]))
        XCTAssertEqual(nilResult.stopReason, .error)
        XCTAssertEqual(nilResult.errorMessage, "nil model")
        await ImagesRegistry.shared.clearProviders()
        let model = ImagesModel(id: "m", name: "m", api: .openRouterImages, provider: .openRouter)
        let result = await SwiftAI.generateImages(model: model, context: ImagesContext(input: [.text("x")]))
        XCTAssertEqual(result.stopReason, .error)
        XCTAssertTrue(result.errorMessage?.contains("no image provider registered") == true)
        await ImagesRegistry.shared.register(ImagesAPIProvider(api: .openRouterImages) { model, _, options in
            var out = AssistantImages(api: model.api, provider: model.provider, model: model.id, stopReason: .stop)
            do { _ = try await options?.onPayload?([:], model) } catch { out.stopReason = .error; out.errorMessage = String(describing: error) }
            return out
        })
        var options = ImagesOptions()
        options.onPayload = { _, _ in throw AIError.provider("hook boom") }
        let hookResult = await SwiftAI.generateImages(model: model, context: ImagesContext(input: [.text("x")]), options: options)
        XCTAssertEqual(hookResult.stopReason, .error)
        XCTAssertTrue(hookResult.errorMessage?.contains("hook boom") == true)
        await SwiftAI.bootstrap()
    }
}
