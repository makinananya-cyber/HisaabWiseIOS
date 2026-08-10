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
