import Foundation

public enum ProviderEnvironment {
    private static let providerEnvMap: [Provider: [String]] = [
        .openAI: ["OPENAI_API_KEY"],
        .anthropic: ["ANTHROPIC_OAUTH_TOKEN", "ANTHROPIC_API_KEY"],
        .google: ["GEMINI_API_KEY"],
        .googleVertex: ["GOOGLE_CLOUD_API_KEY"],
        .azureOpenAI: ["AZURE_OPENAI_API_KEY"],
        .githubCopilot: ["COPILOT_GITHUB_TOKEN"],
        .mistral: ["MISTRAL_API_KEY"],
        .xai: ["XAI_API_KEY"],
        .groq: ["GROQ_API_KEY"],
        .cerebras: ["CEREBRAS_API_KEY"],
        .openRouter: ["OPENROUTER_API_KEY"],
        .vercelAIGateway: ["AI_GATEWAY_API_KEY"],
        .zai: ["ZAI_API_KEY"],
        .miniMax: ["MINIMAX_API_KEY"],
        .miniMaxCN: ["MINIMAX_CN_API_KEY"],
        .huggingFace: ["HF_TOKEN"],
        .fireworks: ["FIREWORKS_API_KEY"],
        .openCode: ["OPENCODE_API_KEY"],
        .openCodeGo: ["OPENCODE_API_KEY"],
        .kimiCoding: ["KIMI_API_KEY"],
        .deepSeek: ["DEEPSEEK_API_KEY"],
        .moonshotAI: ["MOONSHOT_API_KEY"],
        .moonshotAICN: ["MOONSHOT_API_KEY"],
        .cloudflareAIGateway: ["CLOUDFLARE_API_KEY"],
        .cloudflareWorkersAI: ["CLOUDFLARE_API_KEY"],
        .xiaomi: ["XIAOMI_API_KEY"],
        .xiaomiTokenPlanCN: ["XIAOMI_TOKEN_PLAN_CN_API_KEY"],
        .xiaomiTokenPlanAMS: ["XIAOMI_TOKEN_PLAN_AMS_API_KEY"],
        .xiaomiTokenPlanSGP: ["XIAOMI_TOKEN_PLAN_SGP_API_KEY"],
        .together: ["TOGETHER_API_KEY"],
        .antLing: ["ANT_LING_API_KEY"],
        .nvidia: ["NVIDIA_API_KEY"],
        .zaiCodingCN: ["ZAI_CODING_CN_API_KEY"]
    ]

    public static func value(_ name: String, env: ProviderEnv? = nil) -> String? {
        if let value = env?[name] { return value }
        return ProcessInfo.processInfo.environment[name]
    }

    public static func resolveCacheRetention(_ cacheRetention: CacheRetention?, env: ProviderEnv? = nil) -> CacheRetention {
        if let cacheRetention { return cacheRetention }
        return value("PI_CACHE_RETENTION", env: env) == "long" ? .long : .short
    }

    public static func apiKey(for provider: Provider, env: ProviderEnv? = nil) -> String? {
        if let names = providerEnvMap[provider] {
            for name in names { if let key = value(name, env: env), !key.isEmpty { return key } }
            if provider == .googleVertex, hasVertexADCCredentials(env: env), !(value("GOOGLE_CLOUD_PROJECT", env: env) ?? value("GCLOUD_PROJECT", env: env) ?? "").isEmpty, !(value("GOOGLE_CLOUD_LOCATION", env: env) ?? "").isEmpty { return "<authenticated>" }
            return nil
        }
        if provider == .amazonBedrock, hasBedrockCredentials(env: env) { return "<authenticated>" }
        return value(envFallbackName(provider), env: env)
    }

    public static func resolveAPIKey(model: Model?, options: StreamOptions?) -> String? {
        if let key = options?.apiKey, !key.isEmpty { return key }
        guard let model else { return nil }
        return apiKey(for: model.provider, env: options?.env)
    }

    public static func envFallbackName(_ provider: Provider) -> String {
        provider.rawValue.map { ch in ch == "-" || ch == "." ? "_" : String(ch).uppercased() }.joined() + "_API_KEY"
    }

    private static func hasVertexADCCredentials(env: ProviderEnv?) -> Bool {
        if let path = value("GOOGLE_APPLICATION_CREDENTIALS", env: env), FileManager.default.fileExists(atPath: path) { return true }
        if let home = FileManager.default.homeDirectoryForCurrentUser.path.removingPercentEncoding {
            return FileManager.default.fileExists(atPath: home + "/.config/gcloud/application_default_credentials.json")
        }
        return false
    }

    private static func hasBedrockCredentials(env: ProviderEnv?) -> Bool {
        if !(value("AWS_PROFILE", env: env) ?? "").isEmpty || !(value("AWS_BEARER_TOKEN_BEDROCK", env: env) ?? "").isEmpty { return true }
        if !(value("AWS_ACCESS_KEY_ID", env: env) ?? "").isEmpty && !(value("AWS_SECRET_ACCESS_KEY", env: env) ?? "").isEmpty { return true }
        if !(value("AWS_CONTAINER_CREDENTIALS_RELATIVE_URI", env: env) ?? "").isEmpty || !(value("AWS_CONTAINER_CREDENTIALS_FULL_URI", env: env) ?? "").isEmpty { return true }
        return !(value("AWS_WEB_IDENTITY_TOKEN_FILE", env: env) ?? "").isEmpty
    }
}
