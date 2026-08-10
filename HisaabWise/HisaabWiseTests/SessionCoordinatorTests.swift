import Foundation
@testable import HisaabWise
import Testing

/// Who is signed in, and the four moments that change the answer.
///
/// The refresh mechanics are `SessionTests`' subject; this suite is about the decisions layered on top of
/// them — which store the checkbox chooses, and ADR-0008's foreground *ordering*, which is the whole
/// reason `onForeground()` is an awaitable method rather than a `scenePhase` observer.
@Suite("SessionCoordinator")
@MainActor
struct SessionCoordinatorTests {
    private static let refresh = "/v1/auth/refresh"
    private static let login = "/v1/auth/login"
    private static let logout = "/v1/auth/logout"
    private static let me = "/v1/me"

    private static let unverified = Data(
        #"{"email":"a@b.com","displayName":"Neeraj","emailVerified":false}"#.utf8
    )
    private static let verified = Data(
        #"{"email":"a@b.com","displayName":"Neeraj","emailVerified":true}"#.utf8
    )
    private static let acknowledged = Data("{}".utf8)

    /// The three objects the graph composes, kept together so a test can reach the stores it is asserting
    /// about. Both stores are in-memory: which one is the *Keychain* is `AppEnvironment`'s decision and is
    /// asserted there, not here.
    private struct Harness {
        let coordinator: SessionCoordinator
        let kept: InMemoryTokenStore
        let transient: InMemoryTokenStore
        let transport: FixtureTransport
    }

    private func harness(
        _ stubs: [String: FixtureTransport.Outcome],
        sequences: [String: [FixtureTransport.Outcome]] = [:],
        keptRefreshToken: String? = nil
    ) -> Harness {
        let kept = InMemoryTokenStore(refreshToken: keptRefreshToken)
        let transient = InMemoryTokenStore()
        let transport = FixtureTransport(sequences: sequences, stubs: stubs)
        let client = TestBench.client(transport, refreshTokens: kept)
        return Harness(
            coordinator: SessionCoordinator(client: client, keptStore: kept, transientStore: transient),
            kept: kept,
            transient: transient,
            transport: transport
        )
    }

    /// A token pair from the refresh or login route.
    ///
    /// - Parameter accessExpiresIn: the life of the access token it hands back. Under
    ///   `AccessToken.refreshWindow` produces a client that will refresh again on its next request, which
    ///   is how the foreground tests below reach step 1 at all.
    private static func rotation(
        accessExpiresIn: TimeInterval = 900,
        refresh: String = "refresh-2"
    ) -> FixtureTransport.Outcome {
        .response(
            status: 200,
            body: TestBench.tokenPair(
                access: TestBench.accessToken(expiresIn: accessExpiresIn),
                refresh: refresh
            )
        )
    }

    // MARK: - Launch

    @Test("restores a session the Keychain kept across launches")
    func restoresAKeptSession() async throws {
        let harness = harness(
            [Self.refresh: Self.rotation(), Self.me: .response(status: 200, body: Self.unverified)],
            keptRefreshToken: "refresh-1"
        )

        await harness.coordinator.restore()

        #expect(harness.coordinator.isSignedIn)
        #expect(harness.coordinator.user?.email == "a@b.com")
    }

    @Test("restores nothing on a fresh install, and sends no request doing it")
    func restoresNothingWithoutAStoredToken() async throws {
        let harness = harness([Self.me: .response(status: 200, body: Self.unverified)])

        await harness.coordinator.restore()

        #expect(!harness.coordinator.isSignedIn)
        #expect(await harness.transport.recordedRequests.isEmpty)
    }

    @Test("a restored session survives having no network")
    func aRestoredSessionSurvivesBeingOffline() async throws {
        // The token is still good; the app simply cannot check right now. Signing the user out here would
        // be ADR-0007's bug arriving through the front door.
        let harness = harness(
            [Self.refresh: .notConnected, Self.me: .notConnected],
            keptRefreshToken: "refresh-1"
        )

        await harness.coordinator.restore()

        #expect(harness.coordinator.isSignedIn)
        #expect(harness.coordinator.user == nil)
        #expect(try await harness.kept.refreshToken() == "refresh-1")
    }

    @Test("a restored session ends when the server refuses the refresh token")
    func aRefusedRefreshSignsTheUserOut() async throws {
        // The family was revoked while the app was closed — a password change on another device, or
        // "sign out other devices". The user lands on Landing rather than on a screen full of failures.
        let harness = harness(
            [
                Self.refresh: .response(status: 401, body: Data(#"{"error":{"code":"TOKEN_REUSED"}}"#.utf8)),
                Self.me: .response(status: 401, body: Data(#"{"error":{"code":"TOKEN_EXPIRED"}}"#.utf8)),
            ],
            keptRefreshToken: "refresh-1"
        )

        await harness.coordinator.restore()

        #expect(!harness.coordinator.isSignedIn)
        #expect(harness.coordinator.user == nil)
        #expect(try await harness.kept.refreshToken() == nil)
    }

    // MARK: - Signing in

    @Test("checked, Keep me signed in persists the refresh token")
    func keepMeSignedInPersists() async throws {
        let harness = harness([
            Self.login: Self.rotation(refresh: "refresh-1"),
            Self.me: .response(status: 200, body: Self.unverified),
        ])

        try await harness.coordinator.signIn(email: "a@b.com", password: "password1", keepMeSignedIn: true)

        #expect(try await harness.kept.refreshToken() == "refresh-1")
        #expect(try await harness.transient.refreshToken() == nil)
        #expect(harness.coordinator.isSignedIn)
    }

    @Test("unchecked, the session is memory-only and leaves nothing behind")
    func unkeptSessionsAreMemoryOnly() async throws {
        // The off-state Product Spec §3.2 never defined (ADR-0007): the session works exactly as a kept
        // one for as long as the app runs, and ends when the process does, because nothing was written.
        let harness = harness([
            Self.login: Self.rotation(refresh: "refresh-1"),
            Self.me: .response(status: 200, body: Self.unverified),
        ])

        try await harness.coordinator.signIn(email: "a@b.com", password: "password1", keepMeSignedIn: false)

        #expect(try await harness.transient.refreshToken() == "refresh-1")
        #expect(try await harness.kept.refreshToken() == nil)
        #expect(harness.coordinator.isSignedIn)
    }

    @Test("unchecked, an earlier kept session's token is removed rather than left behind")
    func unkeptSignInClearsAPreviouslyKeptToken() async throws {
        // A live 60-day credential for a session the user has just asked not to keep.
        let harness = harness(
            [
                Self.login: Self.rotation(refresh: "refresh-new"),
                Self.me: .response(status: 200, body: Self.unverified),
            ],
            keptRefreshToken: "refresh-old"
        )

        try await harness.coordinator.signIn(email: "a@b.com", password: "password1", keepMeSignedIn: false)

        #expect(try await harness.kept.refreshToken() == nil)
        #expect(try await harness.transient.refreshToken() == "refresh-new")
    }

    @Test("sign-in presents no token and sends the credentials with the device timezone")
    func signInIsAnonymousAndCarriesTheTimeZone() async throws {
        // Invariant 6 — the user's stored IANA timezone is captured from the device at login. Day
        // boundaries are computed in it server-side, so a missing field here is a streak that moves when
        // the device clock does.
        let harness = harness([
            Self.login: Self.rotation(),
            Self.me: .response(status: 200, body: Self.unverified),
        ])

        try await harness.coordinator.signIn(email: "a@b.com", password: "password1", keepMeSignedIn: true)

        let request = try #require(await harness.transport.recordedRequests.first { $0.path == Self.login })
        #expect(request.headers["Authorization"] == nil)
        let body = try JSONDecoder().decode([String: String].self, from: try #require(request.body))
        #expect(body["email"] == "a@b.com")
        #expect(body["password"] == "password1")
        #expect(body["timeZone"] == TimeZone.current.identifier)
    }

    @Test("a refused sign-in leaves nobody signed in and nothing stored")
    func aRefusedSignInChangesNothing() async throws {
        let harness = harness([
            Self.login: .response(status: 401, body: Data(#"{"error":{"code":"INVALID_CREDENTIALS"}}"#.utf8))
        ])

        await #expect(throws: APIError.server(status: 401, code: ErrorCode(rawValue: "INVALID_CREDENTIALS"))) {
            try await harness.coordinator.signIn(
                email: "a@b.com",
                password: "wrong-password",
                keepMeSignedIn: true
            )
        }

        #expect(!harness.coordinator.isSignedIn)
        #expect(try await harness.kept.refreshToken() == nil)
        // The refusal reaches the auth screen unchanged (#14 turns it into copy) — and, crucially, sign-in
        // does not go through the refresh machinery, so a wrong password does not spend a refresh attempt.
        #expect(await harness.transport.requestCount(for: Self.refresh) == 0)
    }

    // MARK: - Foreground

    @Test("onForeground refreshes if near expiry, then revalidates — in that order")
    func onForegroundOrdersItsTwoSteps() async throws {
        // ADR-0008's ordering, and the reason it is an awaitable method rather than an observer:
        // revalidating first would spend the request discovering an expired token.
        //
        // The launch refresh hands back a token with 30 seconds left, so the app comes to the foreground in
        // exactly the state step 1 exists for. The second hands back a normal one, so step 2 makes a single
        // request — the whole sequence is the four below, and the order is asserted across both passes
        // rather than by resetting the transport in between.
        let harness = harness(
            [Self.me: .response(status: 200, body: Self.unverified)],
            sequences: [
                Self.refresh: [Self.rotation(accessExpiresIn: 30), Self.rotation(accessExpiresIn: 900)]
            ],
            keptRefreshToken: "refresh-1"
        )
        await harness.coordinator.restore()

        await harness.coordinator.onForeground()

        #expect(
            await harness.transport.recordedRequests.map(\.path)
                == [Self.refresh, Self.me, Self.refresh, Self.me]
        )
    }

    @Test("onForeground revalidates alone when the token has life left")
    func onForegroundSkipsTheRefreshWhenFresh() async throws {
        let harness = harness(
            [Self.refresh: Self.rotation(), Self.me: .response(status: 200, body: Self.unverified)],
            keptRefreshToken: "refresh-1"
        )
        await harness.coordinator.restore()

        await harness.coordinator.onForeground()

        // The launch refresh, then two revalidations. The second foreground costs one request, not two.
        #expect(await harness.transport.recordedRequests.map(\.path) == [Self.refresh, Self.me, Self.me])
    }

    @Test("onForeground does nothing at all when nobody is signed in")
    func onForegroundIsANoOpWhenSignedOut() async throws {
        let harness = harness([Self.me: .response(status: 200, body: Self.unverified)])

        await harness.coordinator.onForeground()

        #expect(await harness.transport.recordedRequests.isEmpty)
    }

    @Test("onForeground picks up a verification that happened outside the app")
    func onForegroundClearsTheUnverifiedBanner() async throws {
        // ADR-0010's web-based verification: the user taps a link in Mail, verifies in Safari, and comes
        // back to an app that has no other way to notice. Step 2 of the sequence is what notices.
        let harness = harness(
            [Self.refresh: Self.rotation()],
            sequences: [
                Self.me: [
                    .response(status: 200, body: Self.unverified),
                    .response(status: 200, body: Self.verified),
                ]
            ],
            keptRefreshToken: "refresh-1"
        )
        await harness.coordinator.restore()
        #expect(harness.coordinator.user?.emailVerified == false)

        await harness.coordinator.onForeground()

        #expect(harness.coordinator.user?.emailVerified == true)
    }

    @Test("onForeground on a dead network keeps the session and the last identity it had")
    func onForegroundOfflineKeepsEverything() async throws {
        let harness = harness(
            [Self.refresh: Self.rotation()],
            sequences: [Self.me: [.response(status: 200, body: Self.unverified), .notConnected]],
            keptRefreshToken: "refresh-1"
        )
        await harness.coordinator.restore()

        await harness.coordinator.onForeground()

        #expect(harness.coordinator.isSignedIn)
        #expect(harness.coordinator.user?.email == "a@b.com")
    }

    // MARK: - Signing out

    @Test("signing out ends the session and clears the store")
    func signOutEndsTheSession() async throws {
        let harness = harness(
            [
                Self.refresh: Self.rotation(),
                Self.me: .response(status: 200, body: Self.unverified),
                Self.logout: .response(status: 200, body: Self.acknowledged),
            ],
            keptRefreshToken: "refresh-1"
        )
        await harness.coordinator.restore()

        await harness.coordinator.signOut()

        #expect(!harness.coordinator.isSignedIn)
        #expect(harness.coordinator.user == nil)
        #expect(try await harness.kept.refreshToken() == nil)
        #expect(await harness.transport.requestCount(for: Self.logout) == 1)
    }

    @Test("signing out an unkept session clears the store that actually held the token")
    func signOutClearsTheTransientStore() async throws {
        let harness = harness([
            Self.login: Self.rotation(refresh: "refresh-1"),
            Self.me: .response(status: 200, body: Self.unverified),
            Self.logout: .response(status: 200, body: Self.acknowledged),
        ])
        try await harness.coordinator.signIn(email: "a@b.com", password: "password1", keepMeSignedIn: false)

        await harness.coordinator.signOut()

        #expect(try await harness.transient.refreshToken() == nil)
        #expect(!harness.coordinator.isSignedIn)
    }
}
