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

extension ErrorCode {
    /// The fallback when a response carries no usable code, or one the client cannot recognise.
    static let unknown = ErrorCode(rawValue: "UNKNOWN")

    /// The response body did not match the shape the client decodes.
    static let malformedResponse = ErrorCode(rawValue: "MALFORMED_RESPONSE")
}
