import Foundation
@testable import HisaabWise
import Testing

/// The graph, and the reason it is a graph rather than a set of `.shared` accessors.
@Suite("AppEnvironment")
@MainActor
struct AppEnvironmentTests {
    @Test("hands the client it was built with to the view models it makes")
    func viewModelsGetTheComposedClient() async throws {
        let transport = FixtureTransport(stubs: [Endpoint.budget: try .ok(.budgetINR)])
        let environment = AppEnvironment(client: TestBench.client(transport))

        try await environment.makeHomeViewModel().load()

        // The request reached *this* transport, so the view model is on the graph's client and not one it
        // built for itself.
        #expect(await transport.recordedRequests.map(\.path) == [Endpoint.budget])
    }

    @Test("composes a theme, so a screen is not left to find one")
    func composesATheme() {
        let theme = ThemeManager()
        let environment = AppEnvironment(
            client: TestBench.client(FixtureTransport()),
            theme: theme
        )

        #expect(environment.theme === theme)
    }

    @Test("two environments share nothing")
    func environmentsAreIndependent() {
        let first = AppEnvironment(client: TestBench.client(FixtureTransport()))
        let second = AppEnvironment(client: TestBench.client(FixtureTransport()))

        // The property that makes a test able to stand up a whole app's worth of objects: there is no
        // process-wide state to reset between them.
        #expect(first.theme !== second.theme)
        #expect(first.client !== second.client)
    }
}
