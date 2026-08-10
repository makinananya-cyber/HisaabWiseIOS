import Foundation

/// The short-lived access token, with the two claims the client has a use for read off it.
///
/// **The expiry comes out of the JWT rather than out of a sibling `expiresIn` field.** The client has
/// to open the payload anyway — ADR-0007's proactive refresh needs to know when the token dies, and the
/// `sec` claim is what makes a `securityEpoch` bump a prompt sign-out rather than a fifteen-minute
/// window of failures. Reading `exp` from the same place removes the second copy of one fact, and with
/// it the failure mode where a server that changes its token lifetime forgets to change the field
/// beside it.
///
/// **Nothing here is a security check.** The signature is not verified and cannot be: the client holds
/// no key, and a client that trusted its own reading of a token would be the wrong place to decide
/// anything. The claims are read to schedule a refresh, and the server rejects a token it does not
/// like whatever this type believes about it (invariant 10).
///
/// The parse is `throws` and reaches a screen as ``APIError/malformedResponse``, because
/// ``SessionTokens`` decodes through it: a token the client cannot read is a token it cannot schedule a
/// refresh for, and carrying it as an opaque string would trade a loud failure at sign-in for a silent
/// logout fifteen minutes later.
struct AccessToken: Sendable, Equatable {
    /// The token exactly as the server issued it. **This is what goes on the wire** — never a
    /// re-encoding of the claims below, which would drop the signature and the claims this build has
    /// never heard of.
    let raw: String

    /// The `exp` claim.
    let expiresAt: Date

    /// The `sec` claim — the user's `securityEpoch` at the moment the token was minted (backend
    /// ADR-0005). Optional because the client must not refuse a token over a claim it only reads for
    /// diagnosis; the server is the one that compares it.
    let securityEpoch: Int?

    /// How much life left counts as "nearly expired" (ADR-0007: "under roughly 60 s").
    ///
    /// It is the window, not a timer. Refresh happens on the next request that needs a token, so a
    /// backgrounded app does not wake up to fire one.
    static let refreshWindow: TimeInterval = 60

    /// - Parameter now: injected only so a test can pin the moment. Nothing in the app passes it.
    func isNearExpiry(at now: Date = Date()) -> Bool {
        expiresAt.timeIntervalSince(now) < Self.refreshWindow
    }

    init(raw: String) throws {
        let segments = raw.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3, let payload = Self.decodeSegment(String(segments[1])) else {
            throw AccessTokenError.notAJWT
        }
        guard let claims = try? JSONDecoder().decode(Claims.self, from: payload) else {
            throw AccessTokenError.noExpiry
        }
        self.raw = raw
        expiresAt = Date(timeIntervalSince1970: TimeInterval(claims.exp))
        securityEpoch = claims.sec
    }

    /// The claims this build reads. Everything else in the payload is the server's business and is left
    /// alone rather than mirrored into a model that would then need updating in step with it.
    private struct Claims: Decodable {
        let exp: Int
        let sec: Int?
    }

    /// base64url → bytes. JWT segments are unpadded and use the URL alphabet, so `Data(base64Encoded:)`
    /// rejects them as-is.
    private static func decodeSegment(_ segment: String) -> Data? {
        var encoded = segment
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = encoded.count % 4
        if remainder > 0 {
            encoded += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: encoded)
    }
}

extension AccessToken: Decodable {
    /// Decoded from the bare string the server sends, so a malformed token fails at the same boundary
    /// as any other malformed response rather than at the first request that tries to use it.
    init(from decoder: any Decoder) throws {
        try self.init(raw: decoder.singleValueContainer().decode(String.self))
    }
}

/// Why a token string could not be read.
///
/// Two cases rather than one because they fail differently in practice: `notAJWT` is a wiring mistake —
/// an opaque token, an error body, a field read from the wrong key — and `noExpiry` is a real JWT whose
/// claims are not the ones agreed.
enum AccessTokenError: Error, Equatable, Sendable {
    case notAJWT
    case noExpiry
}
