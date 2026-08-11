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

    /// The cacheable content, and the ETags it was fetched with (ADR-0009). Registration is its first caller —
    /// three reference lists it cannot ask a user to type instead.
    let content: ContentLoader

    /// The two hosted pages the registration consent links to, from build configuration (ADR-0010).
    let legal: LegalLinks

    /// - Parameters:
    ///   - language: the app's language choice, over the store that **persists** it — `UserDefaults`, so
    ///     that a chosen language survives a relaunch. `LanguageManager`'s own default store is in-memory,
    ///     for the same reason `keptTokens` is substituted below: constructing one in a test or a preview
    ///     must not write a preference to the machine it runs on. The real store is chosen here, once.
    ///   - keptTokens: where a session the user asked to keep is stored. The Keychain in the app; a test
    ///     substitutes an in-memory store so that running the suite does not write a credential to the
    ///     machine it runs on.
    ///   - transientTokens: where an unkept session lives — memory, ending with the process (ADR-0007).
    ///   - contentStore: where the cacheable lists are kept between launches. On disk in the app; a test
    ///     substitutes an in-memory store, for the same reason `keptTokens` is substituted — running the suite
    ///     must not leave files in the Caches directory of the machine it runs on.
    init(
        baseURL: URL,
        legal: LegalLinks,
        transport: any Transport,
        theme: ThemeManager = ThemeManager(),
        language: LanguageManager = LanguageManager(store: UserDefaultsLanguageStore()),
        keptTokens: any TokenStore = KeychainTokenStore(),
        transientTokens: any TokenStore = InMemoryTokenStore(),
        contentStore: any ContentStore = FileContentStore()
    ) {
        self.theme = theme
        self.language = language
        self.legal = legal
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
        content = ContentLoader(client: client, store: contentStore)
    }

    func makeHomeViewModel() -> HomeViewModel {
        HomeViewModel(client: client, content: content)
    }

    /// Expenses' view model (#18). It needs the content loader as well as the client, for the two server-served
    /// pick lists its entry form picks from (ADR-0009).
    func makeExpensesViewModel() -> ExpensesViewModel {
        ExpensesViewModel(client: client, content: content)
    }

    /// One view model per tab, made once for the shell to be handed (issue #5).
    ///
    /// **Made here and held by the composition root**, not held here: the graph is the app's lifetime and a
    /// tab's view model is the shell's, which today are the same span and will not be once Landing and Auth can
    /// come and go. What this method owns is the one thing a view model needs and a view may not have — the
    /// client.
    func makeTabViewModels() -> TabViewModels {
        TabViewModels(home: makeHomeViewModel(), expenses: makeExpensesViewModel())
    }

    /// A registration form, made **fresh each time the screen is pushed** (#15).
    ///
    /// Not held, and that is a security property rather than a lifetime preference: this object holds a
    /// password, two security answers, a date of birth, and a salary. Popping the screen is what frees them, so
    /// a stored instance would keep an abandoned registration in memory for the life of the app.
    func makeRegistrationViewModel() -> RegistrationViewModel {
        RegistrationViewModel(session: session, content: content, language: language, legal: legal)
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
