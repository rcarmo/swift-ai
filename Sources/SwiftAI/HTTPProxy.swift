import Foundation

public enum HTTPProxyResolver {
    public static let unsupportedProxyProtocolMessage = "Unsupported proxy protocol. Only http:// and https:// proxy URLs are supported."

    public static func resolveProxyURL(forTarget target: String, env scopedEnv: ProviderEnv? = nil) throws -> URL? {
        guard let targetURL = URL(string: target), let scheme = targetURL.scheme?.lowercased(), let host = targetURL.host?.lowercased() else { return nil }
        if isNoProxy(host: host, env: scopedEnv) { return nil }
        let keyCandidates = scheme == "https"
            ? ["HTTPS_PROXY", "https_proxy", "npm_config_https_proxy", "ALL_PROXY", "all_proxy", "npm_config_proxy"]
            : ["HTTP_PROXY", "http_proxy", "npm_config_http_proxy", "ALL_PROXY", "all_proxy", "npm_config_proxy"]
        for key in keyCandidates {
            guard let raw = value(key, env: scopedEnv), !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            guard let url = URL(string: raw) else { continue }
            guard let proxyScheme = url.scheme?.lowercased(), proxyScheme == "http" || proxyScheme == "https" else { throw AIError.provider(unsupportedProxyProtocolMessage) }
            return url
        }
        return nil
    }

    private static func isNoProxy(host: String, env: ProviderEnv?) -> Bool {
        guard let raw = value("NO_PROXY", env: env) ?? value("no_proxy", env: env) ?? value("npm_config_no_proxy", env: env) else { return false }
        return raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.contains { entry in
            if entry == "*" { return true }
            if entry.hasPrefix(".") { return host.hasSuffix(entry) || host == String(entry.dropFirst()) }
            return host == entry || host.hasSuffix("." + entry)
        }
    }

    private static func value(_ key: String, env: ProviderEnv?) -> String? {
        if let scoped = env?[key] { return scoped }
        return ProcessInfo.processInfo.environment[key]
    }
}
