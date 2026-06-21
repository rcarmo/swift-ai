import Foundation

public enum ProviderEnvironment {
    public static func value(_ name: String, env: ProviderEnv? = nil) -> String? { env?[name] ?? ProcessInfo.processInfo.environment[name] }

    public static func apiKey(for provider: Provider, env: ProviderEnv? = nil) -> String? {
        switch provider {
        case .openAI: return value("OPENAI_API_KEY", env: env)
        case .anthropic: return value("ANTHROPIC_API_KEY", env: env)
        case .google, .googleVertex: return value("GOOGLE_API_KEY", env: env) ?? value("GEMINI_API_KEY", env: env)
        case .mistral: return value("MISTRAL_API_KEY", env: env)
        case .openRouter: return value("OPENROUTER_API_KEY", env: env)
        case .groq: return value("GROQ_API_KEY", env: env)
        case .xai: return value("XAI_API_KEY", env: env)
        case .deepSeek: return value("DEEPSEEK_API_KEY", env: env)
        case .zai: return value("ZAI_API_KEY", env: env)
        case .githubCopilot: return value("GITHUB_COPILOT_API_KEY", env: env)
        default: return nil
        }
    }
}
