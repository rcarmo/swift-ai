import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct RetryPolicy: Equatable, Sendable {
    public var maxRetries: Int
    public var maxDelayMs: Int
    public var baseDelayMs: Int

    public init(maxRetries: Int = 0, maxDelayMs: Int = 30_000, baseDelayMs: Int = 250) {
        self.maxRetries = maxRetries
        self.maxDelayMs = maxDelayMs
        self.baseDelayMs = baseDelayMs
    }

    public init(options: StreamOptions?) {
        self.maxRetries = options?.maxRetries ?? 0
        self.maxDelayMs = options?.maxRetryDelayMs ?? 30_000
        self.baseDelayMs = 250
    }

    public init(options: ImagesOptions?) {
        self.maxRetries = options?.maxRetries ?? 0
        self.maxDelayMs = options?.maxRetryDelayMs ?? 30_000
        self.baseDelayMs = 250
    }

    public func delayNanoseconds(attempt: Int, retryAfterMs: Int? = nil) -> UInt64 {
        let exponential = min(maxDelayMs, baseDelayMs * (1 << max(0, attempt - 1)))
        let chosen = min(maxDelayMs, max(exponential, retryAfterMs ?? 0))
        return UInt64(chosen) * 1_000_000
    }
}

public enum HTTPRetry {
    public static func shouldRetry(statusCode: Int) -> Bool { statusCode == 429 || statusCode >= 500 }

    public static func retryAfterMs(headers: [AnyHashable: Any]) -> Int? {
        let value = header(headers, "Retry-After") ?? header(headers, "retry-after")
        guard let value else { return nil }
        if let seconds = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)) { return Int(seconds * 1000) }
        if let date = HTTPDateParser.parse(value) { return max(0, Int(date.timeIntervalSinceNow * 1000)) }
        return nil
    }

    private static func header(_ headers: [AnyHashable: Any], _ key: String) -> String? {
        for (k, v) in headers where String(describing: k).lowercased() == key.lowercased() { return String(describing: v) }
        return nil
    }

    public static func data(for request: URLRequest, policy: RetryPolicy) async throws -> (Data, URLResponse) {
        var lastError: Error?
        for attempt in 0...policy.maxRetries {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, shouldRetry(statusCode: http.statusCode), attempt < policy.maxRetries {
                    let retryAfter = retryAfterMs(headers: http.allHeaderFields)
                    try await Task.sleep(nanoseconds: policy.delayNanoseconds(attempt: attempt + 1, retryAfterMs: retryAfter))
                    continue
                }
                return (data, response)
            } catch {
                lastError = error
                if attempt >= policy.maxRetries { throw error }
                try await Task.sleep(nanoseconds: policy.delayNanoseconds(attempt: attempt + 1))
            }
        }
        throw lastError ?? AIError.provider("retry failed")
    }

    public static func bytes(for request: URLRequest, policy: RetryPolicy) async throws -> (URLSession.AsyncBytes, URLResponse) {
        var lastError: Error?
        for attempt in 0...policy.maxRetries {
            do {
                let (bytes, response) = try await URLSession.shared.bytes(for: request)
                if let http = response as? HTTPURLResponse, shouldRetry(statusCode: http.statusCode), attempt < policy.maxRetries {
                    let retryAfter = retryAfterMs(headers: http.allHeaderFields)
                    try await Task.sleep(nanoseconds: policy.delayNanoseconds(attempt: attempt + 1, retryAfterMs: retryAfter))
                    continue
                }
                return (bytes, response)
            } catch {
                lastError = error
                if attempt >= policy.maxRetries { throw error }
                try await Task.sleep(nanoseconds: policy.delayNanoseconds(attempt: attempt + 1))
            }
        }
        throw lastError ?? AIError.provider("retry failed")
    }
}

private enum HTTPDateParser {
    static func parse(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        for format in ["EEE, dd MMM yyyy HH:mm:ss zzz", "EEEE, dd-MMM-yy HH:mm:ss zzz", "EEE MMM d HH:mm:ss yyyy"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }
}
