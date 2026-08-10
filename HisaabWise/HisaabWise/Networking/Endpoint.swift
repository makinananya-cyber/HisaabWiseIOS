/// The `/v1` paths the app calls.
///
/// One owner per path. The literal was previously repeated by the view model, the composition root, and
/// the preview helpers, which is three places for one string to drift in. Tests deliberately keep their
/// own literals so that a path change fails a test rather than being silently agreed to.
enum Endpoint {
    /// The only place 50/30/20, `saved`, and the goal verdict are computed (invariant 3). Home,
    /// Expenses, and Reports all read it.
    static let budget = "/v1/budget"

    // MARK: - Session

    /// Email and password in, a token pair out. Unauthenticated, and a `401` here means "wrong
    /// password" rather than "expired token" — see `APIClient.Authorization`.
    static let login = "/v1/auth/login"

    /// Rotation: the presented refresh token is revoked and a new pair issued. Unauthenticated, because
    /// the refresh token *is* the credential, and because a refresh that went through the session path
    /// would recurse into itself.
    static let refresh = "/v1/auth/refresh"

    /// Revokes the family server-side. **Authenticated** — which is why the two cases of
    /// `APIClient.Authorization` are not a `/v1/auth/` prefix rule; this is the exception that would
    /// break one.
    static let logout = "/v1/auth/logout"

    /// The identity revalidation ADR-0008 performs on foreground. Not a screen endpoint (ADR-0020): it
    /// carries who the user is, not what any screen draws.
    static let me = "/v1/me"
}
