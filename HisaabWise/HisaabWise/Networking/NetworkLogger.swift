import Foundation

/// Debug-only tracing for every HTTP request the app makes.
///
/// Wired into ``APIClient/respond(_:_:body:idempotencyKey:bearer:ifNoneMatch:)`` — the one place a
/// request is built and sent — so a single call site covers reads, writes, refresh, logout, the
/// export stream, and the cacheable content routes.
///
/// **Compiled out of release builds.** Every method has an empty `#else` body, so in a release build
/// these are calls to functions that do nothing and the optimiser removes them. Nothing here reaches
/// a shipped binary, and no log line can leak from a user's device.
///
/// **Secrets are redacted even in debug** (invariants 1, 4, 5, and ADR-0007). The `Authorization`
/// bearer is never printed, and JSON values under credential-ish keys — anything containing
/// `password`, `token`, `answer`, or `secret` — are masked before the body is logged. A salary is a
/// `{amount, currency}` object and is *not* masked, because seeing it is usually the point of turning
/// this on; if you would rather it were hidden too, add `"amount"` to ``sensitiveKeyFragments``.
enum NetworkLogger {
    /// Logs the outgoing request: verb, full URL, headers (bearer redacted), and a redacted body.
    static func logRequest(_ request: URLRequest) {
        #if DEBUG
        let method = request.httpMethod ?? "?"
        let url = request.url?.absoluteString ?? "<no url>"
        var lines = ["⬆️  \(method) \(url)"]
        for (key, value) in (request.allHTTPHeaderFields ?? [:]).sorted(by: { $0.key < $1.key }) {
            lines.append("      \(key): \(key.caseInsensitiveCompare("Authorization") == .orderedSame ? "Bearer <redacted>" : value)")
        }
        if let body = request.httpBody {
            lines.append("      body: \(redacted(body))")
        }
        print(lines.joined(separator: "\n"))
        #endif
    }

    /// Logs the answer the server gave: status, verb, path, elapsed time, byte count, and a redacted body.
    static func logResponse(
        _ response: HTTPURLResponse,
        body: Data,
        elapsed: TimeInterval,
        for request: URLRequest
    ) {
        #if DEBUG
        let method = request.httpMethod ?? "?"
        let path = request.url?.path ?? "<no path>"
        let marker = (200..<300).contains(response.statusCode) || response.statusCode == 304 ? "✅" : "⚠️"
        print("""
        ⬇️  \(marker) \(response.statusCode) \(method) \(path)  (\(millis(elapsed)) ms, \(body.count) bytes)
              body: \(redacted(body))
        """)
        #endif
    }

    /// Logs a request that never got an answer — the transport threw. `APIClient` reads this as offline.
    static func logFailure(_ error: Error, elapsed: TimeInterval, for request: URLRequest) {
        #if DEBUG
        let method = request.httpMethod ?? "?"
        let path = request.url?.path ?? "<no path>"
        print("⬇️  ❌ (no response) \(method) \(path)  (\(millis(elapsed)) ms) — \(error)")
        #endif
    }

    /// Logs a request whose task was cancelled — the caller navigated away. Not a network condition.
    static func logCancellation(for request: URLRequest) {
        #if DEBUG
        let method = request.httpMethod ?? "?"
        let path = request.url?.path ?? "<no path>"
        print("⬇️  🚫 cancelled \(method) \(path)")
        #endif
    }

    #if DEBUG
    /// JSON key fragments whose values are masked before logging. Matched case-insensitively as substrings.
    private static let sensitiveKeyFragments = ["password", "token", "answer", "secret"]

    private static func millis(_ seconds: TimeInterval) -> Int { Int((seconds * 1000).rounded()) }

    /// Renders a body for the log with credential values masked. Falls back to a byte count for
    /// anything that is not JSON (an export stream, an empty body), so a non-JSON payload is never
    /// dumped wholesale.
    private static func redacted(_ data: Data) -> String {
        guard !data.isEmpty else { return "<empty>" }
        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            return "<\(data.count) bytes, not JSON>"
        }
        let masked = mask(json)
        guard
            let out = try? JSONSerialization.data(withJSONObject: masked, options: [.sortedKeys]),
            let string = String(data: out, encoding: .utf8)
        else {
            return "<\(data.count) bytes>"
        }
        return string
    }

    /// Walks a decoded JSON value, replacing any value under a sensitive key with `"<redacted>"`.
    private static func mask(_ value: Any) -> Any {
        switch value {
        case let dictionary as [String: Any]:
            return dictionary.reduce(into: [String: Any]()) { result, pair in
                let (key, nested) = pair
                let isSensitive = sensitiveKeyFragments.contains {
                    key.range(of: $0, options: .caseInsensitive) != nil
                }
                result[key] = isSensitive ? "<redacted>" : mask(nested)
            }
        case let array as [Any]:
            return array.map(mask)
        default:
            return value
        }
    }
    #endif
}
