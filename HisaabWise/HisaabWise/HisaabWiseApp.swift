import SwiftUI

/// The composition root.
///
/// This is the only place that decides which `Transport` the app runs on and what base URL it points
/// at. Nothing below here knows what an environment is (ADR-0010): the URL comes out of the build
/// configuration through ``AppConfig``, `APIClient` takes it as an argument, and
/// ``URLSessionTransport`` takes nothing at all.
///
/// One transport, in every configuration. There is no debug branch: a Debug build points at the local
/// backend on `localhost:8080` and talks to it over the real transport, which is the only way the client's
/// behaviour against a real server is something anyone finds out about before staging. Fixtures still exist
/// and are still the seam tests and previews swap — they are just no longer what the app itself runs on.
///
/// Everything the decision produces is handed to ``AppEnvironment``, which is the graph. The root
/// makes one graph and one view model per screen, and injects them once.
@main
struct HisaabWiseApp: App {
    private let environment: AppEnvironment

    /// The five tab view models, made here rather than by the shell: a view that made its own would make a new
    /// set on every re-render, and a tab would lose its place every time the user switched away and back
    /// (issue #5).
    ///
    /// **`@State`, and replaced when the session ends** — see `discardScreenState()`. A `let` would outlive the
    /// user it belongs to.
    @State private var tabViewModels: TabViewModels

    /// **The app's one reader of `scenePhase`, with two consumers.** ADR-0008's foreground sequence needs it,
    /// and so does ADR-0014's privacy overlay — and the phase belongs to the *scene*, so this is where it is
    /// legible. `SessionCoordinator.onForeground()` is a plain awaitable method for exactly this reason: the
    /// ordering inside it is testable without an observer.
    ///
    /// The earlier note here said the shell would take both over. It does not, and the reason is better than
    /// the tidiness would have been: ``RootView`` reading the phase itself would make the session branch
    /// untestable, because a renderer's phase is not something a test can set. So the phase is read once and
    /// **passed** — `hwPrivacyOverlay(covering:)` takes it as an argument.
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let configuration = Self.configuration()
        let environment = AppEnvironment(
            baseURL: configuration.apiBaseURL,
            legal: configuration.legal,
            transport: URLSessionTransport()
        )
        self.environment = environment
        _tabViewModels = State(initialValue: environment.makeTabViewModels())
    }

    var body: some Scene {
        WindowGroup {
            RootView(
                makeRegistrationViewModel: environment.makeRegistrationViewModel,
                makeForgotPasswordViewModel: environment.makeForgotPasswordViewModel
            )
                .environment(tabViewModels)
                // Over everything, both worlds included: Landing carries no figures, but a rule with an
                // exception in it is a rule somebody has to remember (ADR-0014).
                .hwPrivacyOverlay(covering: scenePhase)
                .hwEnvironment(environment)
                .task { await environment.session.restore() }
                .onChange(of: scenePhase) { previous, phase in
                    // A launch that arrives `.inactive` and then `.active` can put this alongside the
                    // restore above rather than after it. That is safe rather than co-ordinated:
                    // `onForeground()` returns immediately while `isSignedIn` is still false, and if the
                    // restore has already set it, both do the same idempotent revalidation. Serialising
                    // them would be machinery for the shell (#5) to inherit and then rewrite.
                    guard phase == .active, previous != .active else { return }
                    Task { await environment.session.onForeground() }
                }
                // **The session's end is the screens' end.** A view model holds the last response it got, and
                // a signed-out `HomeViewModel` is still holding a salary — so the next sign-in would paint the
                // previous user's figures for the frame between the shell appearing and its `.task` running
                // `load()`. Invariant 8's reasoning about caches applies to objects too: per-user data that
                // outlives the user is a leak, not a warm start.
                //
                // Here rather than in `SessionCoordinator`, which owns who is signed in and has no business
                // knowing that screens exist, and rather than in ``RootView``, which owns no lifetimes.
                .onChange(of: environment.session.isSignedIn) { _, isSignedIn in
                    guard !isSignedIn else { return }
                    tabViewModels = environment.makeTabViewModels()
                }
        }
    }

    /// Reads the build configuration. `Bundle.main` is named here and nowhere else in the app.
    ///
    /// A failure traps, deliberately. An unusable base URL is not a runtime condition a user can be
    /// in and out of — it is a build that was assembled wrong, it reproduces on every launch of that
    /// configuration, and no rebuild-free recovery exists. The alternative is a client pointed at
    /// nothing, which renders as the offline state on every screen and hides the actual cause behind
    /// the one message that means "not our fault". Rule 7 rules out the third option of falling back
    /// to a hardcoded host.
    private static func configuration() -> AppConfig {
        do {
            return try AppConfig(infoDictionary: Bundle.main.infoDictionary ?? [:])
        } catch {
            preconditionFailure(
                """
                This build has no usable API base URL: \(error).
                Check HW_API_BASE_URL in Configuration/{Debug,Staging,Release}.xcconfig and the \
                \(AppConfig.apiBaseURLKey) key in the configuration's Info.plist.
                """
            )
        }
    }
}
