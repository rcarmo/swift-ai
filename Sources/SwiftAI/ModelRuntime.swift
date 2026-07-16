import Foundation

public struct StoredModelsEntry: Codable, Equatable, Sendable {
    public var models: [Model]
    public var fetchedAt: Date
    public init(models: [Model], fetchedAt: Date = Date()) { self.models = models; self.fetchedAt = fetchedAt }
}

public protocol ProviderModelsStore: Sendable {
    func read(providerId: String) async throws -> StoredModelsEntry?
    func write(providerId: String, entry: StoredModelsEntry) async throws
    func delete(providerId: String) async throws
}

public actor InMemoryProviderModelsStore: ProviderModelsStore {
    private var entries: [String: StoredModelsEntry] = [:]
    public init() {}
    public func read(providerId: String) async throws -> StoredModelsEntry? { entries[providerId] }
    public func write(providerId: String, entry: StoredModelsEntry) async throws { entries[providerId] = entry }
    public func delete(providerId: String) async throws { entries.removeValue(forKey: providerId) }
}

public struct ModelRefreshContext: Sendable {
    public var providerId: String
    public var apiKey: String?
    public var store: any ProviderModelsStore
    public var allowNetwork: Bool
    public var force: Bool
    public init(providerId: String, apiKey: String? = nil, store: any ProviderModelsStore, allowNetwork: Bool, force: Bool = false) {
        self.providerId = providerId; self.apiKey = apiKey; self.store = store; self.allowNetwork = allowNetwork; self.force = force
    }
}

public struct ModelRefreshResult: Sendable {
    public var aborted: Bool
    public var errors: [String: String]
    public init(aborted: Bool = false, errors: [String: String] = [:]) { self.aborted = aborted; self.errors = errors }
}

public typealias ModelRefreshHandler = @Sendable (ModelRefreshContext) async throws -> [Model]

public struct RuntimeProvider: Sendable {
    public var id: Provider
    public var name: String
    public var fallbackModels: [Model]
    public var refresh: ModelRefreshHandler?
    public init(id: Provider, name: String, fallbackModels: [Model] = [], refresh: ModelRefreshHandler? = nil) {
        self.id = id; self.name = name; self.fallbackModels = fallbackModels; self.refresh = refresh
    }
}

public actor ModelRuntime {
    public static let shared = ModelRuntime()
    private var providers: [Provider: RuntimeProvider] = [:]
    private var cachedModels: [Provider: [Model]] = [:]
    private var store: any ProviderModelsStore
    private var inFlight: [Provider: Task<[Model], Error>] = [:]

    public init(store: any ProviderModelsStore = InMemoryProviderModelsStore()) { self.store = store }

    public func setStore(_ store: any ProviderModelsStore) { self.store = store }
    public func register(_ provider: RuntimeProvider) { providers[provider.id] = provider; cachedModels[provider.id] = provider.fallbackModels }
    public func removeProvider(_ provider: Provider) { providers.removeValue(forKey: provider); cachedModels.removeValue(forKey: provider); inFlight[provider]?.cancel(); inFlight.removeValue(forKey: provider) }
    public func clear() { providers.removeAll(); cachedModels.removeAll(); inFlight.values.forEach { $0.cancel() }; inFlight.removeAll() }
    public func provider(_ id: Provider) -> RuntimeProvider? { providers[id] }

    public func listModels(provider: Provider? = nil) -> [Model] {
        if let provider { return cachedModels[provider] ?? providers[provider]?.fallbackModels ?? [] }
        return providers.keys.sorted { $0.rawValue < $1.rawValue }.flatMap { cachedModels[$0] ?? providers[$0]?.fallbackModels ?? [] }
    }

    public func model(provider: Provider, id: String) -> Model? { listModels(provider: provider).first { $0.id == id } }

    public func replaceModels(provider: Provider, models: [Model]) async {
        cachedModels[provider] = models
        for model in models { await AIRegistry.shared.register(model) }
    }

    public func removeModel(provider: Provider, id: String) async {
        cachedModels[provider] = (cachedModels[provider] ?? []).filter { $0.id != id }
        await AIRegistry.shared.unregisterModel(provider: provider, id: id)
    }

    public func refresh(provider providerId: Provider, apiKey: String? = nil, allowNetwork: Bool = true, force: Bool = false) async -> ModelRefreshResult {
        guard let provider = providers[providerId] else { return ModelRefreshResult(errors: [providerId.rawValue: "unknown provider"]) }
        if let task = inFlight[providerId], !force {
            do { let models = try await task.value; await replaceModels(provider: providerId, models: models); return ModelRefreshResult() }
            catch is CancellationError { return ModelRefreshResult(aborted: true) }
            catch { return ModelRefreshResult(errors: [providerId.rawValue: String(describing: error)]) }
        }
        let store = self.store
        let task = Task<[Model], Error> {
            if let entry = try await store.read(providerId: providerId.rawValue) { await self.replaceModels(provider: providerId, models: entry.models) }
            guard allowNetwork, let refresh = provider.refresh else { return (try await store.read(providerId: providerId.rawValue))?.models ?? provider.fallbackModels }
            try Task.checkCancellation()
            let models = try await refresh(ModelRefreshContext(providerId: providerId.rawValue, apiKey: apiKey, store: store, allowNetwork: allowNetwork, force: force))
            try await store.write(providerId: providerId.rawValue, entry: StoredModelsEntry(models: models))
            return models
        }
        inFlight[providerId] = task
        defer { inFlight.removeValue(forKey: providerId) }
        do { let models = try await task.value; await replaceModels(provider: providerId, models: models); return ModelRefreshResult() }
        catch is CancellationError { return ModelRefreshResult(aborted: true) }
        catch {
            if let entry = try? await store.read(providerId: providerId.rawValue) { await replaceModels(provider: providerId, models: entry.models) }
            else { cachedModels[providerId] = provider.fallbackModels }
            return ModelRefreshResult(errors: [providerId.rawValue: String(describing: error)])
        }
    }

    public func refreshAll(apiKeys: [Provider: String] = [:], allowNetwork: Bool = true, force: Bool = false) async -> ModelRefreshResult {
        var result = ModelRefreshResult()
        await withTaskGroup(of: (Provider, ModelRefreshResult).self) { group in
            for id in providers.keys { group.addTask { (id, await self.refresh(provider: id, apiKey: apiKeys[id], allowNetwork: allowNetwork, force: force)) } }
            for await (id, partial) in group {
                result.aborted = result.aborted || partial.aborted
                for (k, v) in partial.errors { result.errors[k] = v }
                if partial.aborted { result.errors[id.rawValue] = "aborted" }
            }
        }
        return result
    }
}
