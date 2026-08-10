import SwiftUI

/// The object graph, assembled once.
///
/// Everything long-lived the app needs is held here and handed down: the HTTP client, the theme, the
/// language manager, and the session. **No singletons and no globals** — nothing in the app reaches for a
/// `.shared`, which is what makes a test able to stand up a whole app's worth of objects over a
/// fixture transport without touching a build configuration.
///
/// It is *not* the composition root. `HisaabWiseApp` still is, and still owns the one decision that
/// belongs there — which `Transport` and which base URL (ADR-0010). This type owns the wiring on the
/// other side of that decision, so the root stays about environments and this stays about objects.
///
/// **It builds the client rather than being handed one.** The client sets `Accept-Language` from a
/// ``LanguageManager`` (ADR-0003), and it has to be the *same* manager the UI shows — two of them
/// would mean an Arabic screen quietly asking the server for English money strings. Assembling both
/// here makes that structural instead of something the root has to remember.
///
/// **View models are made here, not held here.** A screen's view model is per-screen state; the
/// five-tab shell (issue #5) decides how long each lives. What the graph supplies is the client one
/// needs.
@MainActor
final class AppEnvironment {
    let client: APIClient
    let theme: ThemeManager
    let language: LanguageManager
    let session: SessionCoordinator

    /// - Parameters:
    ///   - keptTokens: where a session the user asked to keep is stored. The Keychain in the app; a test
    ///     substitutes an in-memory store so that running the suite does not write a credential to the
    ///     machine it runs on.
    ///   - transientTokens: where an unkept session lives — memory, ending with the process (ADR-0007).
    init(
        baseURL: URL,
        transport: any Transport,
        theme: ThemeManager = ThemeManager(),
        language: LanguageManager = LanguageManager(),
        keptTokens: any TokenStore = KeychainTokenStore(),
        transientTokens: any TokenStore = InMemoryTokenStore()
    ) {
        self.theme = theme
        self.language = language
        let client = APIClient(
            baseURL: baseURL,
            transport: transport,
            language: language,
            refreshTokens: keptTokens
        )
        self.client = client
        // The client is built with the *kept* store, because that is the one a launch has to consult to
        // find a session at all. Which store a new session goes to is the checkbox's decision and is made
        // at sign-in, by the coordinator.
        session = SessionCoordinator(
            client: client,
            keptStore: keptTokens,
            transientStore: transientTokens
        )
    }

    func makeHomeViewModel() -> HomeViewModel {
        HomeViewModel(client: client)
    }
}

extension View {
    /// Injects everything screens read from `@Environment`.
    ///
    /// One call site, so that the list of injected objects grows in one place rather than in each new
    /// tab's `body`.
    ///
    /// The language manager is **not** injected yet: issue #7 owns that, along with the `Locale` and
    /// `LayoutDirection` a view would read it for. Injecting it now would mean guessing at the shape
    /// of an object no view has asked for.
    func hwEnvironment(_ environment: AppEnvironment) -> some View {
        hwTheme(environment.theme)
    }
}
