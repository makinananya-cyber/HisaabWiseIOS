/// Everything the app keeps on the device.
///
/// What is here now. The first two are behind `Models`' `TokenStore` protocol (ADR-0007), the second two
/// behind its ``LanguageStore`` (ADR-0024):
///
/// - ``KeychainTokenStore`` — the refresh token, with
///   `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` so a session does not travel with an iCloud
///   backup restore.
/// - ``InMemoryTokenStore`` — the same seam with no device footprint, which is what leaving
///   "Keep me signed in" unchecked means.
/// - ``UserDefaultsLanguageStore`` — the chosen language, as its BCP-47 tag. `UserDefaults` rather than the
///   Keychain because a preference is not a credential, and **synchronously** readable because the choice
///   has to be in force before the first frame rather than swapped in after it.
/// - ``InMemoryLanguageStore`` — the same seam with no footprint. Here for one of `InMemoryTokenStore`'s two
///   reasons rather than both: a language preference has no "keep me signed in", but a test or a preview
///   still must not configure the machine it runs on.
///
/// What is still to arrive:
///
/// - The on-disk curriculum PDF the user downloads (ADR-0019).
/// - The on-disk content store with a persisted ETag per resource, distinct from `URLCache`
///   (ADR-0009).
///
/// There is deliberately **no** write queue and no SwiftData: every write needs a connection
/// (ADR-0019, superseding ADR-0005).
///
/// It depends on `Models` alone: persistence stores DTOs, and never reaches the network itself. The
/// access token is not stored here and has no store to put it in — it lives in memory on the client
/// actor and is never persisted (ADR-0007).
///
/// The namespace stays as the folder's overview. Nothing is nested inside it: the types above are
/// top-level, like every other type in the app.
enum Persistence {}
