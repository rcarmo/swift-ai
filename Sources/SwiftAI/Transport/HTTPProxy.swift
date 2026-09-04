import Foundation

public enum HTTPProxyResolver {
    public static let unsupportedProxyProtocolMessage = "Unsupported proxy protocol. Only http:// and https:// proxy URLs are supported."

    public static func resolveProxyURL(forTarget target: String, env scopedEnv: ProviderEnv? = nil) throws -> URL? {
        guard let targetURL = URL(string: target), let scheme = targetURL.scheme?.lowercased(), let host = targetURL.host?.lowercased() else { return nil }
        if isNoProxy(host: host, port: targetURL.port, env: scopedEnv) { return nil }
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

    private static func isNoProxy(host: String, port: Int?, env: ProviderEnv?) -> Bool {
        guard let raw = value("NO_PROXY", env: env) ?? value("no_proxy", env: env) ?? value("npm_config_no_proxy", env: env) else { return false }
        return raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.contains { rawEntry in
            if rawEntry == "*" { return true }
            let entry = normalizedNoProxyEntry(rawEntry)
            if entry.port != nil, entry.port != port { return false }
            if entry.host == host { return true }
            if entry.host.hasPrefix("*.") { let suffix = String(entry.host.dropFirst(2)); return host == suffix || host.hasSuffix("." + suffix) }
            if entry.host.hasPrefix(".") { let suffix = String(entry.host.dropFirst()); return host == suffix || host.hasSuffix("." + suffix) }
            return entry.port == nil && host.hasSuffix("." + entry.host)
        }
    }

    private static func normalizedNoProxyEntry(_ raw: String) -> (host: String, port: Int?) {
        var entry = raw
        if entry.hasPrefix("[") {
            guard let close = entry.firstIndex(of: "]") else { return (entry, nil) }
            let host = String(entry[entry.index(after: entry.startIndex)..<close])
            let rest = entry[entry.index(after: close)...]
            if rest.hasPrefix(":"), let port = Int(rest.dropFirst()) { return (host, port) }
            return (host, nil)
        }
        if entry.filter({ $0 == ":" }).count == 1, let colon = entry.lastIndex(of: ":"), let port = Int(entry[entry.index(after: colon)...]) {
            entry = String(entry[..<colon])
            return (entry, port)
        }
        return (entry, nil)
    }

    private static func value(_ key: String, env: ProviderEnv?) -> String? {
        if let scoped = env?[key] { return scoped }
        return ProcessInfo.processInfo.environment[key]
    }
}
