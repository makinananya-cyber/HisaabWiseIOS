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
    ///   - language: the app's language choice, over the store that **persists** it — `UserDefaults`, so
    ///     that a chosen language survives a relaunch. `LanguageManager`'s own default store is in-memory,
    ///     for the same reason `keptTokens` is substituted below: constructing one in a test or a preview
    ///     must not write a preference to the machine it runs on. The real store is chosen here, once.
    ///   - keptTokens: where a session the user asked to keep is stored. The Keychain in the app; a test
    ///     substitutes an in-memory store so that running the suite does not write a credential to the
    ///     machine it runs on.
    ///   - transientTokens: where an unkept session lives — memory, ending with the process (ADR-0007).
    init(
        baseURL: URL,
        transport: any Transport,
        theme: ThemeManager = ThemeManager(),
        language: LanguageManager = LanguageManager(store: UserDefaultsLanguageStore()),
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
        // The one genuine cycle in the graph, closed here: the client reads the language on every request,
        // and a language change is recorded *through* the client. One of the two has to be connected
        // rather than injected, and the manager is the cheaper half to leave half-built — until this line
        // runs, `select(_:)` throws rather than switching the language on this device alone (ADR-0024).
        language.connect(to: client)
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

    /// One view model per tab, made once for the shell to be handed (issue #5).
    ///
    /// **Made here and held by the composition root**, not held here: the graph is the app's lifetime and a
    /// tab's view model is the shell's, which today are the same span and will not be once Landing and Auth can
    /// come and go. What this method owns is the one thing a view model needs and a view may not have — the
    /// client.
    func makeTabViewModels() -> TabViewModels {
        TabViewModels(home: makeHomeViewModel())
    }
}

extension View {
    /// Injects everything screens read from `@Environment`.
    ///
    /// One call site, so that the list of injected objects grows in one place rather than in each new
    /// tab's `body`. Three entries: the theme, the language — the latter bringing the `Locale` and the
    /// `LayoutDirection` with it, so that no screen has to remember to set either — and the session, which
    /// ``RootView`` branches on and ``LogoutControl`` ends.
    ///
    /// **The tab view models are not here**, and cannot be: they are *made* rather than held (see
    /// ``AppEnvironment/makeTabViewModels()``), so injecting them from a `View` extension would make a fresh
    /// set every time a `body` ran and reset every screen on every re-render. The composition root makes them
    /// once and injects them itself.
    func hwEnvironment(_ environment: AppEnvironment) -> some View {
        hwTheme(environment.theme)
            .hwLanguage(environment.language)
            .environment(environment.session)
    }
}
