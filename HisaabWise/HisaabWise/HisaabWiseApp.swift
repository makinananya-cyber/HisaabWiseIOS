import SwiftUI

/// The composition root.
///
/// This is the only place that decides which `Transport` the app runs on and what base URL it points
/// at. Nothing below here knows what an environment is (ADR-0010): the URL comes out of the build
/// configuration through ``AppConfig``, `APIClient` takes it as an argument, and
/// ``URLSessionTransport`` takes nothing at all.
///
/// One transport, in every configuration. There is no debug branch: a Debug build points at
/// `wrangler dev` on `localhost:8787` and talks to it over the real transport, which is the only way
/// the client's behaviour against a real server is something anyone finds out about before staging.
/// Fixtures still exist and are still the seam tests and previews swap — they are just no longer what
/// the app itself runs on.
///
/// Everything the decision produces is handed to ``AppEnvironment``, which is the graph. The root
/// makes one graph and one view model per screen, and injects them once.
@main
struct HisaabWiseApp: App {
    private let environment: AppEnvironment
    private let homeViewModel: HomeViewModel

    /// The lifecycle observer ADR-0008's sequence needs, and the one place it may live: a `scenePhase`
    /// observer is a *view* concern, and the reason `SessionCoordinator.onForeground()` is a plain
    /// awaitable method is so that the ordering inside it can be tested without one.
    ///
    /// The five-tab shell (#5) takes this over along with the privacy overlay it also needs `scenePhase`
    /// for. Until then it sits here, because a foreground sequence nobody calls is a sequence that is
    /// wrong by the time somebody does.
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let environment = AppEnvironment(
            baseURL: Self.configuration().apiBaseURL,
            transport: URLSessionTransport()
        )
        self.environment = environment
        homeViewModel = environment.makeHomeViewModel()
    }

    var body: some Scene {
        WindowGroup {
            HomeView(viewModel: homeViewModel)
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
