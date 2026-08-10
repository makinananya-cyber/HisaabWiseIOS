import SwiftUI

/// The object graph, assembled once.
///
/// Everything long-lived the app needs is held here and handed down: the HTTP client, the theme, and
/// (issue #7) the language manager. **No singletons and no globals** — nothing in the app reaches for a
/// `.shared`, which is what makes a test able to stand up a whole app's worth of objects over a fixture
/// transport without touching a build configuration.
///
/// It is *not* the composition root. `HisaabWiseApp` still is, and still owns the one decision that
/// belongs there — which `Transport` and which base URL (ADR-0010). This type owns the wiring on the
/// other side of that decision, so the root stays about environments and this stays about objects.
///
/// **View models are made here, not held here.** A screen's view model is per-screen state; the five-tab
/// shell (issue #5) decides how long each lives. What the graph supplies is the client one needs.
@MainActor
final class AppEnvironment {
    let client: APIClient
    let theme: ThemeManager
    // TODO(#7): `let language: LanguageManager` joins these, and `hwEnvironment(_:)` injects it.

    init(client: APIClient, theme: ThemeManager = ThemeManager()) {
        self.client = client
        self.theme = theme
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
    func hwEnvironment(_ environment: AppEnvironment) -> some View {
        hwTheme(environment.theme)
    }
}
