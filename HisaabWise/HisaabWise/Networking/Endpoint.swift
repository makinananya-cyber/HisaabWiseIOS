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

    /// Everything the three registration steps collected, in **one** request (#15). Unauthenticated, and it
    /// answers with a token pair: a new account is signed in.
    static let register = "/v1/auth/register"

    /// The identity revalidation ADR-0008 performs on foreground. Not a screen endpoint (ADR-0020): it
    /// carries who the user is, not what any screen draws.
    static let me = "/v1/me"

    // MARK: - Content

    /// The 251 countries with their dial codes (#15).
    ///
    /// **Cacheable, and the only kind of route that is** (invariant 8): the same bytes for everybody, fetched
    /// anonymously because registration needs them before there is a session. Every per-user route bypasses
    /// every cache; these three are why the distinction exists.
    static let contentCountries = "/v1/content/reference/countries"

    /// The 160 ISO-4217 currencies (#15).
    static let contentCurrencies = "/v1/content/reference/currencies"

    /// The 14-question security bank (#15). Under `/v1/content` rather than `/v1/auth` for the reason above —
    /// the *questions* are public content; the *answers* are verified server-side and never leave it
    /// (invariant 5).
    static let contentSecurityQuestions = "/v1/content/security-questions"

    /// The path a cacheable resource is fetched from.
    ///
    /// Here rather than on `ContentResource` itself, which lives in `Models` and must not know what a route is
    /// (`LayeringTests`). The resource is an identity — a file name and a cache key; the path is this layer's.
    static func path(for resource: ContentResource) -> String {
        switch resource {
        case .countries: contentCountries
        case .currencies: contentCurrencies
        case .securityQuestions: contentSecurityQuestions
        }
    }

    // MARK: - Preferences

    /// The stored language preference. `PUT`, because the request replaces a value rather than adding one
    /// — which is also why it carries no `Idempotency-Key`.
    ///
    /// A route the client invented, recorded in `CONTEXT.md`'s table of changes this repo requires
    /// elsewhere. Its reason for existing is email: the header tells the server what to format *this*
    /// response in, and nothing about a message composed six hours later (ADR-0024).
    static let language = "/v1/me/language"
}
