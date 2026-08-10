import Foundation
@testable import HisaabWise
import Testing

/// The graph, and the reason it is a graph rather than a set of `.shared` accessors.
@Suite("AppEnvironment")
@MainActor
struct AppEnvironmentTests {
    @Test("hands the client it built to the view models it makes")
    func viewModelsGetTheComposedClient() async throws {
        let transport = FixtureTransport(stubs: [Endpoint.budget: try .ok(.budgetINR)])
        let environment = AppEnvironment(baseURL: TestBench.baseURL, transport: transport)

        try await environment.makeHomeViewModel().load()

        // The request reached *this* transport, so the view model is on the graph's client and not one it
        // built for itself.
        #expect(await transport.recordedRequests.map(\.path) == [Endpoint.budget])
    }

    @Test("composes a theme, so a screen is not left to find one")
    func composesATheme() {
        let theme = ThemeManager()
        let environment = AppEnvironment(
            baseURL: TestBench.baseURL,
            transport: FixtureTransport(),
            theme: theme
        )

        #expect(environment.theme === theme)
    }

    @Test("the client speaks the language the graph composed")
    func theClientSpeaksTheGraphsLanguage() async throws {
        // The reason the graph builds the client rather than being handed one. Two language managers —
        // one for the UI, one the client happened to be constructed with — would mean an Arabic screen
        // asking the server for English money strings, and ADR-0003 leaves the client no formatter to
        // put that right.
        let language = LanguageManager(selected: .arabic)
        let transport = FixtureTransport(stubs: [Endpoint.budget: try .ok(.budgetINR)])
        let environment = AppEnvironment(
            baseURL: TestBench.baseURL,
            transport: transport,
            language: language
        )

        try await environment.makeHomeViewModel().load()

        let request = try #require(await transport.recordedRequests.first)
        #expect(request.headers["Accept-Language"] == "ar")
        #expect(environment.language === language)
    }

    @Test("two environments share nothing")
    func environmentsAreIndependent() {
        let first = AppEnvironment(baseURL: TestBench.baseURL, transport: FixtureTransport())
        let second = AppEnvironment(baseURL: TestBench.baseURL, transport: FixtureTransport())

        // The property that makes a test able to stand up a whole app's worth of objects: there is no
        // process-wide state to reset between them.
        #expect(first.theme !== second.theme)
        #expect(first.client !== second.client)
        #expect(first.language !== second.language)
    }
}
