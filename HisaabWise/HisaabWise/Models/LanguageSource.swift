/// Where a request's `Accept-Language` comes from.
///
/// Not a nicety. ADR-0003 puts money formatting on the server, honouring `Accept-Language`, so this
/// header is what makes a display string arrive already formatted instead of leaving the client to do
/// it — and the client has no formatter to do it with. Every request carries it.
///
/// It is a protocol in `Models` for the reason `TokenStore` will be: `APIClient` needs the value, the
/// type that owns the choice is `LanguageManager` in `DesignSystem`, and the dependency has to point
/// downwards.
///
/// **This is not a second seam.** `Transport` is still the only one (ADR-0013): nothing conforms to
/// this but the real manager, in the app and in the tests alike, and no double conforms to it. It
/// exists to point a dependency the right way, not to be swapped out.
///
/// `get async` because the owner is `@MainActor` and `APIClient` is an actor. One hop per request,
/// and it buys the guarantee that the header cannot disagree with the language on screen.
protocol LanguageSource: Sendable {
    /// The BCP-47 language tag for the header, as the app's language choice stands right now.
    var acceptLanguage: String { get async }
}
