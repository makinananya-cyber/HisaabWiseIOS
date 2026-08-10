
/// Why a request did not produce a decoded value.
///
/// The distinction between ``offline`` and the other two cases is load-bearing: a network failure
/// must not read as a fault (ADR-0016) and must not cost the user their session (ADR-0007).
enum APIError: Error, Equatable, Sendable {
    /// The network did not answer. The session survives; the screen shows offline, not failed.
    case offline

    /// The server answered definitively and unsuccessfully. Carries the status and the envelope's
    /// `code` — never its `message` (ADR-0016).
    case server(status: Int, code: ErrorCode)

    /// The server answered successfully with a body the client could not decode. Distinct from
    /// ``server`` because it is our bug, not the user's problem, and it is the failure a drifted
    /// fixture produces.
    case malformedResponse

    /// The code a screen maps to copy, or `nil` when there is nothing to map.
    ///
    /// `offline` has no error code by design: it is a supported mode, not a failure, and handing a
    /// screen a plausible-looking code would invite it to render generic-failure copy for it.
    var errorCode: ErrorCode? {
        switch self {
        case .offline: nil
        case .server(_, let code): code
        case .malformedResponse: .malformedResponse
        }
    }
}
