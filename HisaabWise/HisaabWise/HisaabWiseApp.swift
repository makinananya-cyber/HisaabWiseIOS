import SwiftUI

/// The composition root.
///
/// This is the only place that decides which `Transport` the app runs on and what base URL it points at.
/// Nothing below here knows what an environment is (ADR-0010): `APIClient` takes a URL, and
/// `URLSessionTransport` plus the three `.xcconfig` files arrive with the real-transport work. Until then
/// the app runs on the fixture transport, which is why it builds and runs today with no backend.
///
/// Everything the decision produces is handed to ``AppEnvironment``, which is the graph. The root makes
/// one client, one theme, and one view model per screen, and injects them once.
@main
struct HisaabWiseApp: App {
    private let environment: AppEnvironment
    private let homeViewModel: HomeViewModel

    init() {
        let environment = AppEnvironment(client: Self.makeClient())
        self.environment = environment
        homeViewModel = environment.makeHomeViewModel()
    }

    var body: some Scene {
        WindowGroup {
            HomeView(viewModel: homeViewModel)
                .hwEnvironment(environment)
        }
    }

    private static func makeClient() -> APIClient {
        // TODO(#3): read the base URL from `Info.plist` and use `URLSessionTransport` against
        // `wrangler dev`. Swapping the transport is the only change that needs making.
        APIClient(baseURL: URL(string: "https://fixtures.invalid")!, transport: makeTransport())
    }

    private static func makeTransport() -> any Transport {
        #if DEBUG
        // Fixtures compile only into a debug build, so this branch cannot survive into release.
        return FixtureTransport(
            stubs: [Endpoint.budget: .response(status: 200, body: (try? Fixture.budgetINR.data()) ?? Data())]
        )
        #else
        return UnconfiguredTransport()
        #endif
    }
}
