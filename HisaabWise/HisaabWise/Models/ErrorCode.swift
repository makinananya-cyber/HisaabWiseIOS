/// A server error's machine-readable `code`, and nothing else.
///
/// ADR-0016 — **the server's `message` field is never displayed.** English prose reaching an
/// Arabic-reading user in every failure state is the defect this prevents, so the client carries the
/// code and maps it to localised copy in one place. The envelope's `message` is not merely unused
/// here; it is never decoded, so there is nothing to display by accident.
///
/// Open-ended rather than a closed `enum`: a code the client has never heard of must still arrive
/// intact and fall through to generic copy. The code-to-copy mapping itself lands with the design
/// system.
struct ErrorCode: Sendable, Hashable, RawRepresentable, CustomStringConvertible {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    var description: String { rawValue }
}

extension ErrorCode: Decodable {
    init(from decoder: any Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }
}

/// The codes this build recognises.
///
/// Naming one here is not the same as giving it copy — that is `ErrorCopy`'s job, and a code with no
/// entry there reads as generic. A constant earns its place when code refers to the code itself.
extension ErrorCode {
    /// The fallback when a response carries no usable code, or one the client cannot recognise.
    static let unknown = ErrorCode(rawValue: "UNKNOWN")

    /// The response body did not match the shape the client decodes. Client-side: no server sends it.
    static let malformedResponse = ErrorCode(rawValue: "MALFORMED_RESPONSE")

    /// The request needed a session and there was none left to present (ADR-0007). Client-side: the
    /// server's own 401 carries whatever code it likes, and this is what the client says when it did not
    /// get as far as asking.
    static let unauthenticated = ErrorCode(rawValue: "UNAUTHENTICATED")

    /// Too many requests in the window (Technical Spec §7's rate limiting).
    static let rateLimited = ErrorCode(rawValue: "RATE_LIMITED")

    /// The write was addressed to a month the rollover has since archived. Still live with no write
    /// queue in the app: a request in flight across the boundary, or a client left open past midnight
    /// on the 1st, still hits it (Product Spec §4.5, ADR-0019).
    static let monthClosed = ErrorCode(rawValue: "MONTH_CLOSED")
}
