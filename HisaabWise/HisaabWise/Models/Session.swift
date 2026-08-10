import Foundation

/// What `POST /v1/auth/login` and `POST /v1/auth/refresh` answer with.
///
/// One type for both, because rotation means a refresh returns exactly what a login does: a new access
/// token *and* a new refresh token, with the presented one revoked (backend ADR-0005). A refresh
/// response modelled as "access token only" is how a client ends up presenting a revoked token and
/// having the whole family revoked under it.
struct SessionTokens: Decodable, Sendable, Equatable {
    let accessToken: AccessToken
    /// Opaque. The client stores it and presents it; it has no readable structure and no expiry the
    /// client can see, which is why ``AccessToken`` is the one that carries the clock.
    let refreshToken: String
}

/// What the client sends to sign in.
///
/// **`timeZone` is not telemetry.** Invariant 6 makes day boundaries server-owned and computed in the
/// user's *stored* IANA timezone, captured from the device at login and at refresh — so this field and
/// ``RefreshRequest/timeZone`` are the only two places that capture happens. Sending it from the device
/// clock's *offset* instead, or letting the server infer a zone from an IP address, is what makes a
/// streak move when a user flies.
struct SignInRequest: Encodable, Sendable {
    let email: String
    let password: String
    let timeZone: String

    init(email: String, password: String, timeZone: String = TimeZone.current.identifier) {
        self.email = email
        self.password = password
        self.timeZone = timeZone
    }
}

/// What the client sends to rotate its tokens.
struct RefreshRequest: Encodable, Sendable {
    let refreshToken: String
    let timeZone: String

    init(refreshToken: String, timeZone: String = TimeZone.current.identifier) {
        self.refreshToken = refreshToken
        self.timeZone = timeZone
    }
}

/// What the client sends to end a session server-side.
struct SignOutRequest: Encodable, Sendable {
    /// The token to revoke, named explicitly rather than inferred from the access token, so the server
    /// revokes the family the client actually holds.
    let refreshToken: String
}

/// A body the client sends a request for and has nothing to read in.
///
/// `DELETE` and the write verbs return a screen payload (ADR-0020), but `POST /v1/auth/logout` has no
/// screen behind it — the next thing the user sees is Landing.
struct Acknowledgement: Decodable, Sendable, Equatable {}

/// The identity half of `GET /v1/me` — what ADR-0008's foreground revalidation exists to pick up.
///
/// Deliberately **not** the user's figures. Salary, display currency, and every derived percentage
/// reach a screen through that screen's own endpoint (ADR-0020); duplicating them here would give
/// invariant 2's single owner a second copy that a stale revalidation could disagree with.
///
/// What it does carry is what changes *outside* the app and has no screen of its own to arrive
/// through: `emailVerified` flips when the user taps a link in Mail and verifies in Safari (ADR-0010),
/// and this response is what clears the banner on return.
struct SessionUser: Decodable, Sendable, Equatable {
    /// The identity (invariant 4). Locked after registration.
    let email: String
    /// Surfaced in the UI as "Username". Not an identifier.
    let displayName: String
    let emailVerified: Bool
}
