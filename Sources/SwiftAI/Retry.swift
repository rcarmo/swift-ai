import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct RetryPolicy: Equatable, Sendable {
    public var maxRetries: Int
    public var maxDelayMs: Int
    public var baseDelayMs: Int
    public var backoffMultiplier: Double
    public var jitterFraction: Double
    public var maxRetryDelayMs: Int
    public var retryableStatuses: [Int]?

    public init(maxRetries: Int = 0, maxDelayMs: Int = 60_000, baseDelayMs: Int = 1_000, backoffMultiplier: Double = 2.0, jitterFraction: Double = 0.25, maxRetryDelayMs: Int = 60_000, retryableStatuses: [Int]? = nil) {
        self.maxRetries = max(0, maxRetries)
        self.maxDelayMs = maxDelayMs
        self.baseDelayMs = baseDelayMs
        self.backoffMultiplier = backoffMultiplier
        self.jitterFraction = max(0, jitterFraction)
        self.maxRetryDelayMs = maxRetryDelayMs
        self.retryableStatuses = retryableStatuses
    }

    public static func `default`() -> RetryPolicy { RetryPolicy(maxRetries: 3) }
    public static func noRetry() -> RetryPolicy { RetryPolicy(maxRetries: 0) }

    public init(options: StreamOptions?) {
        if let maxRetries = options?.maxRetries, maxRetries > 0 {
            self.init(maxRetries: maxRetries, maxRetryDelayMs: options?.maxRetryDelayMs ?? 60_000)
        } else if let cfg = options?.retryConfig {
            self.init(maxRetries: cfg.maxRetries ?? 3, maxRetryDelayMs: options?.maxRetryDelayMs ?? cfg.maxDelayMs ?? 60_000)
        } else if let maxRetryDelayMs = options?.maxRetryDelayMs {
            self.init(maxRetries: 3, maxRetryDelayMs: maxRetryDelayMs)
        } else {
            self = .noRetry()
        }
    }

    public init(options: ImagesOptions?) {
        if let maxRetries = options?.maxRetries, maxRetries > 0 { self.init(maxRetries: maxRetries, maxRetryDelayMs: options?.maxRetryDelayMs ?? 60_000) }
        else if let maxRetryDelayMs = options?.maxRetryDelayMs { self.init(maxRetries: 3, maxRetryDelayMs: maxRetryDelayMs) }
        else { self = .noRetry() }
    }

    public func delayMilliseconds(attempt: Int, retryAfterMs: Int? = nil) throws -> Int {
        if let retryAfterMs, retryAfterMs > 0 {
            if maxRetryDelayMs > 0, retryAfterMs > maxRetryDelayMs { throw AIError.provider("server requested retry delay of \(retryAfterMs)ms exceeds cap of \(maxRetryDelayMs)ms") }
            return retryAfterMs
        }
        let exponential = Double(baseDelayMs) * pow(backoffMultiplier <= 0 ? 2.0 : backoffMultiplier, Double(max(0, attempt - 1)))
        let jittered = exponential * (1.0 + (jitterFraction > 0 ? Double.random(in: -jitterFraction...jitterFraction) : 0))
        return min(maxDelayMs, max(0, Int(jittered)))
    }

    public func delayNanoseconds(attempt: Int, retryAfterMs: Int? = nil) throws -> UInt64 { UInt64(try delayMilliseconds(attempt: attempt, retryAfterMs: retryAfterMs)) * 1_000_000 }
}

public enum AssistantErrorRetryClassifier {
    private static let nonRetryablePattern = try! NSRegularExpression(pattern: "GoUsageLimitError|FreeUsageLimitError|Monthly usage limit reached|available balance|insufficient_quota|out of budget|quota exceeded|billing", options: [.caseInsensitive])
    private static let retryablePattern = try! NSRegularExpression(pattern: "overloaded|rate.?limit|too many requests|429|500|502|503|504|service.?unavailable|server.?error|internal.?error|provider.?returned.?error|network.?error|connection.?error|connection.?refused|connection.?lost|other side closed|fetch failed|upstream.?connect|reset before headers|socket hang up|timed? out|timeout|terminated|websocket.?closed|websocket.?error|ended without|stream ended before message_stop|http2 request did not get a response|retry delay|you can retry your request|try your request again|please retry your request", options: [.caseInsensitive])
    public static func isRetryableAssistantError(_ message: Message) -> Bool {
        guard message.stopReason == .error, let errorMessage = message.errorMessage, !errorMessage.isEmpty else { return false }
        let range = NSRange(errorMessage.startIndex..<errorMessage.endIndex, in: errorMessage)
        if nonRetryablePattern.firstMatch(in: errorMessage, range: range) != nil { return false }
        return retryablePattern.firstMatch(in: errorMessage, range: range) != nil
    }
}

public enum RetryRunner {
    public static func run<T>(policy: RetryPolicy, sleep: @Sendable (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }, onRetry: (@Sendable (Int, Error) async -> Void)? = nil, operation: @Sendable (Int) async throws -> T) async throws -> T {
        var lastError: Error?
        for attempt in 0...policy.maxRetries {
            do { return try await operation(attempt) }
            catch {
                lastError = error
                guard attempt < policy.maxRetries else { break }
                if let onRetry { await onRetry(attempt + 1, error) }
                try await sleep(try policy.delayNanoseconds(attempt: attempt + 1))
            }
        }
        throw lastError ?? AIError.provider("retry exhausted")
    }
}

public enum HTTPRetry {
    public static func shouldRetry(statusCode: Int, policy: RetryPolicy = .default()) -> Bool {
        if let statuses = policy.retryableStatuses { return statuses.contains(statusCode) }
        return [429, 500, 502, 503, 504].contains(statusCode)
    }

    public static func retryAfterMs(headers: [AnyHashable: Any]) -> Int? {
        let value = header(headers, "Retry-After") ?? header(headers, "retry-after")
        guard let value else { return nil }
        if let seconds = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)) { return Int(seconds * 1000) }
        if let date = HTTPDateParser.parse(value) { return max(0, Int(date.timeIntervalSinceNow * 1000)) }
        return nil
    }

    public static func parseDurationMilliseconds(_ raw: String) -> Int? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let pattern = #"^([0-9]+(?:\.[0-9]+)?)(ms|s|m|h)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern), let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), let valueRange = Range(match.range(at: 1), in: text), let unitRange = Range(match.range(at: 2), in: text), let value = Double(text[valueRange]) else { return nil }
        let multiplier: Double
        switch String(text[unitRange]) { case "ms": multiplier = 1; case "s": multiplier = 1_000; case "m": multiplier = 60_000; case "h": multiplier = 3_600_000; default: return nil }
        return Int(value * multiplier)
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
                if let http = response as? HTTPURLResponse, shouldRetry(statusCode: http.statusCode, policy: policy), attempt < policy.maxRetries {
                    let retryAfter = retryAfterMs(headers: http.allHeaderFields)
                    try await Task.sleep(nanoseconds: try policy.delayNanoseconds(attempt: attempt + 1, retryAfterMs: retryAfter))
                    continue
                }
                return (data, response)
            } catch {
                lastError = error
                if attempt >= policy.maxRetries { throw error }
                try await Task.sleep(nanoseconds: try policy.delayNanoseconds(attempt: attempt + 1))
            }
        }
        throw lastError ?? AIError.provider("retry failed")
    }

    public static func bytes(for request: URLRequest, policy: RetryPolicy) async throws -> (AsyncThrowingStream<UInt8, Error>, URLResponse) {
        let (data, response) = try await data(for: request, policy: policy)
        let stream = AsyncThrowingStream<UInt8, Error> { continuation in
            for byte in data { continuation.yield(byte) }
            continuation.finish()
        }
        return (stream, response)
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
