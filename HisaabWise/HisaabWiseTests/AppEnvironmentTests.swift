import Foundation
@testable import HisaabWise
import Testing

/// The graph, and the reason it is a graph rather than a set of `.shared` accessors.
@Suite("AppEnvironment")
@MainActor
struct AppEnvironmentTests {
    /// An environment with no Keychain in it.
    ///
    /// The app's default for `keptTokens` is a real ``KeychainTokenStore`` — asserted below — and a suite
    /// that took the default would read and write the Keychain of the machine it runs on, leaving tests
    /// able to see each other's sessions.
    private func makeEnvironment(
        transport: any Transport,
        theme: ThemeManager = ThemeManager(),
        language: LanguageManager = LanguageManager(),
        keptTokens: any TokenStore = InMemoryTokenStore(),
        transientTokens: any TokenStore = InMemoryTokenStore()
    ) -> AppEnvironment {
        AppEnvironment(
            baseURL: TestBench.baseURL,
            transport: transport,
            theme: theme,
            language: language,
            keptTokens: keptTokens,
            transientTokens: transientTokens
        )
    }

    @Test("hands the client it built to the view models it makes")
    func viewModelsGetTheComposedClient() async throws {
        let transport = FixtureTransport(stubs: [Endpoint.budget: try .ok(.budgetINR)])
        let environment = makeEnvironment(transport: transport)

        try await environment.makeHomeViewModel().load()

        // The request reached *this* transport, so the view model is on the graph's client and not one it
        // built for itself.
        #expect(await transport.recordedRequests.map(\.path) == [Endpoint.budget])
    }

    @Test("composes a theme, so a screen is not left to find one")
    func composesATheme() {
        let theme = ThemeManager()
        let environment = makeEnvironment(transport: FixtureTransport(), theme: theme)

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
        let environment = makeEnvironment(transport: transport, language: language)

        try await environment.makeHomeViewModel().load()

        let request = try #require(await transport.recordedRequests.first)
        #expect(request.headers["Accept-Language"] == "ar")
        #expect(environment.language === language)
    }

    @Test("two environments share nothing")
    func environmentsAreIndependent() {
        let first = makeEnvironment(transport: FixtureTransport())
        let second = makeEnvironment(transport: FixtureTransport())

        // The property that makes a test able to stand up a whole app's worth of objects: there is no
        // process-wide state to reset between them.
        #expect(first.theme !== second.theme)
        #expect(first.client !== second.client)
        #expect(first.language !== second.language)
        #expect(first.session !== second.session)
    }

    // MARK: - The session

    @Test("a kept session goes to the Keychain by default, which is what ADR-0007 decided")
    func keptSessionsGoToTheKeychainInTheApp() {
        // The one place the *choice* of store is made. Every other suite substitutes in-memory stores, so
        // without this assertion the Keychain conformance could be correct and unreachable.
        let environment = AppEnvironment(baseURL: TestBench.baseURL, transport: FixtureTransport())

        #expect(environment.session.keptStore is KeychainTokenStore)
        #expect(environment.session.transientStore is InMemoryTokenStore)
    }

    @Test("the client refreshes from the same store a kept session is written to")
    func theClientAndTheCoordinatorAgreeOnTheKeptStore() async throws {
        // Two stores — one the client consults at launch, one the coordinator writes to — would mean a
        // session that persists successfully and is never found again.
        let kept = InMemoryTokenStore(refreshToken: "refresh-1")
        let transport = FixtureTransport(
            stubs: [
                Endpoint.budget: try .ok(.budgetINR),
                Endpoint.refresh: .response(
                    status: 200,
                    body: TestBench.tokenPair(access: TestBench.accessToken(), refresh: "refresh-2")
                ),
            ]
        )
        let environment = makeEnvironment(transport: transport, keptTokens: kept)

        try await environment.makeHomeViewModel().load()

        // The client found the stored token and refreshed before the read, which it could only do if it
        // was handed the store the coordinator calls `keptStore`.
        #expect(await transport.requestCount(for: Endpoint.refresh) == 1)
        #expect(environment.session.keptStore as? InMemoryTokenStore === kept)
    }
}
