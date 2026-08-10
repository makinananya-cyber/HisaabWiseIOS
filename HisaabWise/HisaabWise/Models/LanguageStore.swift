/// Where the language choice survives a relaunch.
///
/// The sibling of ``TokenStore``, and here for the same reason: `DesignSystem`'s ``LanguageManager``
/// owns the choice, the device is where it is kept, and the dependency has to point downwards.
///
/// **Synchronous and `@MainActor`, unlike `TokenStore`.** That protocol is `async throws` throughout
/// because an app-lock conformance would need to await a biometric prompt and because a Keychain read
/// can fail in a way that is not "empty". Neither applies to a two-case enum in `UserDefaults`, and the
/// cost of pretending otherwise is real: ``LanguageManager`` is constructed synchronously in
/// `AppEnvironment`, so an `async` read could only be adopted *after* the first frame — which is a
/// launch that shows English to an Arabic reader and then swaps under them.
///
/// Storing nothing is a meaningful state, not a missing one: a user who has never opened the picker gets
/// the device's language, and keeps getting it if they change the device's setting later.
@MainActor
protocol LanguageStore {
    /// The language the user chose, or `nil` when they never did.
    var language: AppLanguage? { get }

    /// Records the choice. Called only once the server has agreed to it, so a relaunch cannot resurrect
    /// a language the server never accepted (ADR-0024).
    func save(_ language: AppLanguage)
}
