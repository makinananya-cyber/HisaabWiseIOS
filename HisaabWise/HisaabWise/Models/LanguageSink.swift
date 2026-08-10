/// Where a language choice goes so that the *server* knows about it.
///
/// The write half of ``LanguageSource``. That protocol answers "what language should this response be
/// formatted in"; this one says "this is the language the user picked, keep it". Both point the same
/// direction for the same reason — `APIClient` is in `Networking`, the type that owns the choice is
/// `LanguageManager` in `DesignSystem`, and neither may import the other.
///
/// **It is not cosmetic.** The header alone would make every screen right and every *email* wrong: a
/// password reset or a streak reminder is composed by the server hours after the app was last open, from
/// the stored preference and not from a header (ADR-0024). Without this call the two disagree, and the
/// disagreement is invisible until a user receives English mail about an Arabic app.
///
/// **Not a second seam** (ADR-0013). `Transport` is still the only one: nothing conforms to this but the
/// real ``APIClient``, in the app and in the tests alike.
protocol LanguageSink: Sendable {
    /// Records the choice server-side and answers with the language the server now holds.
    ///
    /// Returning it rather than returning nothing is what lets the caller verify agreement instead of
    /// assuming it. A server that stored something else is a disagreement the user should see as a failed
    /// switch, not one that hides until the next email.
    func setLanguage(_ language: AppLanguage) async throws -> AppLanguage
}
