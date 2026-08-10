import Foundation
import Security
@testable import HisaabWise
import Testing

/// The session half of ``APIClient``: what a request presents, when a refresh happens, and — the reason
/// any of this is written down — that **several callers across one token expiry produce one refresh**.
///
/// ADR-0007: rotation revokes the whole family when an already-revoked token is presented, so concurrent
/// refreshes are not a wasted round trip. The losers present the token the winner just spent, the family
/// is revoked, and the user is silently logged out. It reproduces mainly on slow networks, which is this
/// app's target context, so it is the one behaviour here that is asserted from several angles.
@Suite("The session on APIClient")
struct SessionTests {
    private static let budget = "/v1/budget"
    private static let refresh = "/v1/auth/refresh"
    private static let logout = "/v1/auth/logout"

    /// A body the paths under test can answer with, so a test that is about the session is not also about
    /// decoding a screen payload.
    private struct Payload: Decodable, Sendable, Equatable { let month: String }
    private static let payload = Data(#"{"month":"2026-08"}"#.utf8)

    /// A `401` in the envelope the backend uses, so the client's `ErrorCode` path is exercised too.
    private static let unauthorized = Data(#"{"error":{"code":"TOKEN_EXPIRED","message":"expired"}}"#.utf8)

    // MARK: - Building a signed-in client

    /// A client holding a live session: `accessExpiresIn` seconds of access-token life and
    /// `refreshToken` in `store`.
    @MainActor
    private func signedIn(
        _ transport: FixtureTransport,
        accessExpiresIn: TimeInterval = 900,
        securityEpoch: Int? = 3,
        refreshToken: String = "refresh-1",
        store: any TokenStore = InMemoryTokenStore()
    ) async throws -> APIClient {
        let client = TestBench.client(transport, refreshTokens: store)
        let tokens = SessionTokens(
            accessToken: try AccessToken(
                raw: TestBench.accessToken(expiresIn: accessExpiresIn, securityEpoch: securityEpoch)
            ),
            refreshToken: refreshToken
        )
        await client.beginSession(tokens, storingRefreshTokenIn: store)
        return client
    }

    /// A `200` from the refresh route carrying a fresh pair.
    private static func rotation(access: String? = nil, refresh: String = "refresh-2") -> FixtureTransport.Outcome {
        .response(
            status: 200,
            body: TestBench.tokenPair(access: access ?? TestBench.accessToken(), refresh: refresh)
        )
    }

    // MARK: - What a request presents

    @Test("presents the access token on a per-user route")
    @MainActor
    func presentsTheAccessToken() async throws {
        let transport = FixtureTransport(stubs: [Self.budget: .response(status: 200, body: Self.payload)])
        let client = try await signedIn(transport)

        _ = try await client.get(Self.budget, as: Payload.self)

        let request = try #require(await transport.recordedRequests.first)
        let header = try #require(request.headers["Authorization"])
        #expect(header.hasPrefix("Bearer "))
    }

    @Test("presents the sec claim, because that is what makes an epoch bump visible to the server")
    @MainActor
    func presentsTheSecurityEpochClaim() async throws {
        // Backend ADR-0005 mints `securityEpoch` into the access token as `sec` and rejects a mismatch.
        // The client's part is to send the token **exactly as issued** — a re-encoding of the claims it
        // happens to read would drop this one along with the signature.
        let transport = FixtureTransport(stubs: [Self.budget: .response(status: 200, body: Self.payload)])
        let client = try await signedIn(transport, securityEpoch: 11)

        _ = try await client.get(Self.budget, as: Payload.self)

        let request = try #require(await transport.recordedRequests.first)
        let presented = try #require(request.headers["Authorization"]?.replacing("Bearer ", with: ""))
        #expect(try TestBench.claims(inJWT: presented)["sec"] == 11)
    }

    @Test("presents nothing when there is no session, and lets the server decide")
    @MainActor
    func presentsNothingWithoutASession() async throws {
        // Invariant 10 in the small: the client does not gate a request on its own belief about whether it
        // is signed in. It sends what it has, which keeps a signed-out request reaching the transport and
        // failing honestly instead of failing on a guess.
        let transport = FixtureTransport(stubs: [Self.budget: .response(status: 200, body: Self.payload)])
        let client = TestBench.client(transport)

        _ = try await client.get(Self.budget, as: Payload.self)

        let request = try #require(await transport.recordedRequests.first)
        #expect(request.headers["Authorization"] == nil)
    }

    @Test("presents nothing on an anonymous route, session or no session")
    @MainActor
    func anonymousRoutesPresentNothing() async throws {
        // Sign-in and refresh. A `401` there means "wrong password" or "this family is revoked" — never
        // "your access token expired" — so the refresh machinery has to stay out of the way.
        let transport = FixtureTransport(stubs: [Self.refresh: Self.rotation()])
        let client = try await signedIn(transport)

        _ = try await client.post(
            Self.refresh,
            body: RefreshRequest(refreshToken: "refresh-1"),
            authorization: .anonymous,
            as: SessionTokens.self
        )

        let request = try #require(await transport.recordedRequests.first)
        #expect(request.headers["Authorization"] == nil)
    }

    // MARK: - Proactive refresh

    @Test("refreshes before a request when under a minute of token life remains")
    @MainActor
    func refreshesProactively() async throws {
        // ADR-0007 — the window exists so the `401` path stays rare rather than routine.
        let transport = FixtureTransport(
            stubs: [
                Self.refresh: Self.rotation(),
                Self.budget: .response(status: 200, body: Self.payload),
            ]
        )
        let client = try await signedIn(transport, accessExpiresIn: 30)

        _ = try await client.get(Self.budget, as: Payload.self)

        #expect(await transport.recordedRequests.map(\.path) == [Self.refresh, Self.budget])
    }

    @Test("does not refresh a token with plenty of life left")
    @MainActor
    func doesNotRefreshAFreshToken() async throws {
        let transport = FixtureTransport(stubs: [Self.budget: .response(status: 200, body: Self.payload)])
        let client = try await signedIn(transport, accessExpiresIn: 900)

        _ = try await client.get(Self.budget, as: Payload.self)

        #expect(await transport.requestCount(for: Self.refresh) == 0)
    }

    @Test("refreshes on a cold start, where there is a refresh token and no access token")
    @MainActor
    func refreshesWhenThereIsNoAccessTokenAtAll() async throws {
        // The relaunch case: the Keychain kept the refresh token and the access token died with the
        // process, because it is never persisted (ADR-0007).
        let transport = FixtureTransport(
            stubs: [
                Self.refresh: Self.rotation(),
                Self.budget: .response(status: 200, body: Self.payload),
            ]
        )
        let client = TestBench.client(transport, refreshTokens: InMemoryTokenStore(refreshToken: "refresh-1"))

        _ = try await client.get(Self.budget, as: Payload.self)

        #expect(await transport.recordedRequests.map(\.path) == [Self.refresh, Self.budget])
    }

    @Test("sends the stored refresh token, and the device timezone with it")
    @MainActor
    func theRefreshRequestCarriesTheStoredTokenAndTheTimeZone() async throws {
        // Invariant 6 — day boundaries are computed in the user's *stored* IANA timezone, captured from
        // the device at login and at refresh. Without this field the capture never happens after sign-in,
        // and a user who moves countries keeps yesterday's day boundary.
        let transport = FixtureTransport(
            stubs: [
                Self.refresh: Self.rotation(),
                Self.budget: .response(status: 200, body: Self.payload),
            ]
        )
        let client = try await signedIn(transport, accessExpiresIn: 30, refreshToken: "refresh-1")

        _ = try await client.get(Self.budget, as: Payload.self)

        let refresh = try #require(await transport.recordedRequests.first { $0.path == Self.refresh })
        let body = try JSONDecoder().decode([String: String].self, from: try #require(refresh.body))
        #expect(body["refreshToken"] == "refresh-1")
        #expect(body["timeZone"] == TimeZone.current.identifier)
        // Keyed like every other `POST` (ADR-0022), and this is the `POST` the rule was written for: a
        // refresh whose response was lost, retried without a key, presents a token the server has already
        // spent — and reuse revokes the whole family. The refresh route does not go through `post()`, so
        // nothing but this assertion keeps it from being the one call that forgets.
        #expect(UUID(uuidString: refresh.headers["Idempotency-Key"] ?? "") != nil)
    }

    @Test("stores the rotated refresh token, so the spent one is never presented again")
    @MainActor
    func rotationIsStored() async throws {
        // Presenting a spent token is what revokes the family (backend ADR-0005). Keeping the old one
        // would turn every refresh into a logout on the one after it.
        let store = InMemoryTokenStore()
        let transport = FixtureTransport(
            stubs: [
                Self.refresh: Self.rotation(refresh: "refresh-2"),
                Self.budget: .response(status: 200, body: Self.payload),
            ]
        )
        let client = try await signedIn(transport, accessExpiresIn: 30, refreshToken: "refresh-1", store: store)

        _ = try await client.get(Self.budget, as: Payload.self)

        #expect(try await store.refreshToken() == "refresh-2")
    }

    // MARK: - The 401 path

    @Test("answers a 401 by refreshing and retrying once, with the new token")
    @MainActor
    func retriesOnceAfterRefreshing() async throws {
        // The access token's clock says it is fine and the server disagrees: the `securityEpoch` case
        // (backend ADR-0005), where a password change elsewhere invalidated the token mid-life.
        // Refreshing on the server's answer rather than only on the clock is what makes that prompt.
        let rotated = TestBench.accessToken(securityEpoch: 12)
        let transport = FixtureTransport(
            sequences: [
                Self.budget: [
                    .response(status: 401, body: Self.unauthorized),
                    .response(status: 200, body: Self.payload),
                ]
            ],
            stubs: [Self.refresh: Self.rotation(access: rotated)]
        )
        let client = try await signedIn(transport, accessExpiresIn: 900, securityEpoch: 11)

        let payload = try await client.get(Self.budget, as: Payload.self)

        #expect(payload == Payload(month: "2026-08"))
        #expect(await transport.recordedRequests.map(\.path) == [Self.budget, Self.refresh, Self.budget])
        let retry = try #require(await transport.recordedRequests.last)
        #expect(retry.headers["Authorization"] == "Bearer \(rotated)")
    }

    @Test("retries once and no more, so a server that has decided is not argued with")
    @MainActor
    func retriesExactlyOnce() async throws {
        let transport = FixtureTransport(
            sequences: [
                Self.budget: [
                    .response(status: 401, body: Self.unauthorized),
                    .response(status: 401, body: Self.unauthorized),
                ]
            ],
            stubs: [Self.refresh: Self.rotation()]
        )
        let client = try await signedIn(transport)

        await #expect(throws: APIError.server(status: 401, code: ErrorCode(rawValue: "TOKEN_EXPIRED"))) {
            try await client.get(Self.budget, as: Payload.self)
        }

        // Two attempts and one refresh. A loop here would turn a server that has decided against this
        // session into a request storm.
        #expect(await transport.requestCount(for: Self.budget) == 2)
        #expect(await transport.requestCount(for: Self.refresh) == 1)
    }

    // MARK: - Single flight

    @Test("several concurrent 401s produce exactly one refresh, and every caller succeeds")
    @MainActor
    func concurrent401sRefreshOnce() async throws {
        // The bug this whole file exists for. Three screens in flight across one token expiry: without a
        // shared refresh, two of them present the token the third just spent, the backend revokes the
        // family, and the user is signed out with no explanation.
        //
        // The transport **holds all three requests until all three have arrived**, which is the only way
        // to put them genuinely in flight together. Without it the three may serialise, the second then
        // presents the token the first already refreshed into, and there is a second legitimate refresh —
        // so the test would pass or fail on the scheduler rather than on behaviour.
        let paths = ["/v1/screens/home", "/v1/screens/expenses", "/v1/screens/reports"]
        let transport = FixtureTransport(
            sequences: Dictionary(
                uniqueKeysWithValues: paths.map {
                    ($0, [
                        FixtureTransport.Outcome.response(status: 401, body: Self.unauthorized),
                        .response(status: 200, body: Self.payload),
                    ])
                }
            ),
            stubs: [Self.refresh: Self.rotation()],
            holdingFirst: paths.count
        )
        let client = try await signedIn(transport)

        let payloads = await withTaskGroup(of: Payload?.self) { group in
            for path in paths {
                group.addTask { try? await client.get(path, as: Payload.self) }
            }
            var results: [Payload?] = []
            for await result in group { results.append(result) }
            return results
        }

        #expect(payloads.compactMap { $0 }.count == 3, "every original request should be retried and succeed")
        #expect(
            await transport.requestCount(for: Self.refresh) == 1,
            "one refresh at the transport, however many callers saw a 401"
        )
        for path in paths {
            #expect(await transport.requestCount(for: path) == 2, "\(path) should be sent once and retried once")
        }

        // All three presented the *same* expired token, so **one refresh whichever way they then
        // interleave**: a caller whose `401` comes back while the refresh is still in flight joins that
        // task, and one whose `401` comes back after it landed finds its token already replaced and retries
        // with the new one. Which of the two branches each caller takes is the scheduler's business; that
        // exactly one refresh reaches the transport is not.
    }

    // MARK: - When the session ends

    @Test("a definitive 401 on refresh clears the store and signals a hard logout")
    @MainActor
    func aRefusedRefreshEndsTheSession() async throws {
        // The family was revoked — by a password change, a `logout-all`, or a reuse the backend caught.
        // There is no recovery that does not involve the user's password.
        let store = InMemoryTokenStore()
        let transport = FixtureTransport(
            stubs: [
                Self.budget: .response(status: 401, body: Self.unauthorized),
                Self.refresh: .response(status: 401, body: Self.unauthorized),
            ]
        )
        let client = try await signedIn(transport, store: store)

        await #expect(throws: APIError.unauthenticated) {
            try await client.get(Self.budget, as: Payload.self)
        }

        #expect(try await store.refreshToken() == nil, "the revoked token must not survive in the Keychain")
        #expect(await client.hasSession == false)
        // The stream buffers, so a signal sent before the throw is waiting here and arrives at once.
        #expect(await Self.wasSignalled(client))
    }

    @Test("a 401 with nothing left to refresh with ends the session without asking the server")
    @MainActor
    func a401WithNoRefreshTokenEndsTheSession() async throws {
        let transport = FixtureTransport(stubs: [Self.budget: .response(status: 401, body: Self.unauthorized)])
        let client = TestBench.client(transport)

        await #expect(throws: APIError.unauthenticated) {
            try await client.get(Self.budget, as: Payload.self)
        }

        #expect(await transport.requestCount(for: Self.refresh) == 0)
    }

    @Test("a transport failure during refresh yields offline and keeps the session")
    @MainActor
    func aTransportFailureDuringRefreshKeepsTheSession() async throws {
        // ADR-0007's other branch, and the one that matters most on a slow network: going through a tunnel
        // must never cost the user their session. Never `failed`, never a logout.
        let store = InMemoryTokenStore()
        let transport = FixtureTransport(
            stubs: [
                Self.budget: .response(status: 401, body: Self.unauthorized),
                Self.refresh: .notConnected,
            ]
        )
        let client = try await signedIn(transport, store: store)

        await #expect(throws: APIError.offline) {
            try await client.get(Self.budget, as: Payload.self)
        }

        #expect(try await store.refreshToken() == "refresh-1")
        #expect(await client.hasSession)
    }

    @Test("a 5xx on refresh keeps the session too — the server is having a bad minute")
    @MainActor
    func aServerErrorDuringRefreshKeepsTheSession() async throws {
        let store = InMemoryTokenStore()
        let transport = FixtureTransport(
            stubs: [
                Self.budget: .response(status: 401, body: Self.unauthorized),
                Self.refresh: .response(status: 503, body: Data(#"{"error":{"code":"UNAVAILABLE"}}"#.utf8)),
            ]
        )
        let client = try await signedIn(transport, store: store)

        await #expect(throws: APIError.server(status: 503, code: ErrorCode(rawValue: "UNAVAILABLE"))) {
            try await client.get(Self.budget, as: Payload.self)
        }

        #expect(try await store.refreshToken() == "refresh-1")
    }

    @Test("a store that cannot be read is offline, not a logout")
    @MainActor
    func anUnreadableStoreIsOffline() async throws {
        // A Keychain protected by `AfterFirstUnlock` cannot be read before the first unlock after a
        // reboot. Reading that as "no session" would sign the user out for having restarted their phone —
        // which is precisely why `TokenStore.refreshToken()` is allowed to throw at all.
        let transport = FixtureTransport(stubs: [Self.budget: .response(status: 200, body: Self.payload)])
        let client = TestBench.client(transport, refreshTokens: UnreadableTokenStore())

        await #expect(throws: APIError.offline) {
            try await client.get(Self.budget, as: Payload.self)
        }

        #expect(await transport.recordedRequests.isEmpty)
    }

    // MARK: - Beginning and ending a session

    @Test("beginSession stores the refresh token in the store it was handed")
    @MainActor
    func beginSessionStoresWhereItIsTold() async throws {
        let store = InMemoryTokenStore()
        let client = TestBench.client(FixtureTransport())

        await client.beginSession(
            SessionTokens(accessToken: try AccessToken(raw: TestBench.accessToken()), refreshToken: "refresh-9"),
            storingRefreshTokenIn: store
        )

        #expect(try await store.refreshToken() == "refresh-9")
    }

    @Test("beginSession clears the store it is leaving behind")
    @MainActor
    func beginSessionClearsThePreviousStore() async throws {
        // Signing in with the box unchecked, having previously signed in with it checked, must not leave
        // the old refresh token in the Keychain — that is a live 60-day credential for a session the user
        // asked not to keep.
        let kept = InMemoryTokenStore(refreshToken: "refresh-old")
        let transient = InMemoryTokenStore()
        let client = TestBench.client(FixtureTransport(), refreshTokens: kept)

        await client.beginSession(
            SessionTokens(accessToken: try AccessToken(raw: TestBench.accessToken()), refreshToken: "refresh-new"),
            storingRefreshTokenIn: transient
        )

        #expect(try await kept.refreshToken() == nil)
        #expect(try await transient.refreshToken() == "refresh-new")
    }

    @Test("endSession revokes the family server-side and clears the store")
    @MainActor
    func endSessionRevokesAndClears() async throws {
        let store = InMemoryTokenStore()
        let transport = FixtureTransport(stubs: [Self.logout: .response(status: 200, body: Data("{}".utf8))])
        let client = try await signedIn(transport, refreshToken: "refresh-1", store: store)

        await client.endSession()

        let request = try #require(await transport.recordedRequests.first { $0.path == Self.logout })
        let body = try JSONDecoder().decode([String: String].self, from: try #require(request.body))
        #expect(body["refreshToken"] == "refresh-1")
        #expect(try await store.refreshToken() == nil)
        #expect(await client.hasSession == false)
    }

    @Test("endSession clears the session even when the revoke could not be sent")
    @MainActor
    func endSessionClearsWhenOffline() async throws {
        // A user who taps "log out" on a dead network has still logged out. Leaving them signed in until
        // the network returns would be the app arguing with them.
        let store = InMemoryTokenStore()
        let transport = FixtureTransport(stubs: [Self.logout: .notConnected])
        let client = try await signedIn(transport, store: store)

        await client.endSession()

        #expect(try await store.refreshToken() == nil)
        #expect(await client.hasSession == false)
    }

    @Test("endSession refreshes first, so the token it revokes is the one the store then holds")
    @MainActor
    func endSessionRevokesTheCurrentToken() async throws {
        // Reading the stored token *before* authorising would hand the revoke a token the refresh
        // underneath it had just rotated away: the server refuses it, the new refresh token stays valid
        // for 60 days, and the logout reports success having revoked nothing.
        let store = InMemoryTokenStore()
        let transport = FixtureTransport(
            stubs: [
                Self.refresh: Self.rotation(refresh: "refresh-2"),
                Self.logout: .response(status: 200, body: Data("{}".utf8)),
            ]
        )
        let client = try await signedIn(transport, accessExpiresIn: 30, refreshToken: "refresh-1", store: store)

        await client.endSession()

        let request = try #require(await transport.recordedRequests.first { $0.path == Self.logout })
        let body = try JSONDecoder().decode([String: String].self, from: try #require(request.body))
        #expect(body["refreshToken"] == "refresh-2")
    }

    @Test("endSession does not signal a hard logout, because the caller already knows")
    @MainActor
    func endSessionDoesNotSignal() async throws {
        let transport = FixtureTransport(stubs: [Self.logout: .response(status: 200, body: Data("{}".utf8))])
        let client = try await signedIn(transport)

        await client.endSession()

        // Nothing buffered on the stream. A signal here would make the shell handle its own logout twice.
        #expect(await Self.wasSignalled(client) == false)
    }

    @Test("a 401 on the revoke does not refresh, and does not signal a hard logout either")
    @MainActor
    func endSessionDoesNotRefreshOrSignalOnA401() async throws {
        // A `401` here means the server had already ended the session — which is what the caller wants.
        // Routing the revoke through the retry path would refresh, discover the family revoked, and signal
        // a hard logout **for a logout the user asked for**; the signal exists to tell the app about a
        // session it did not end itself.
        let transport = FixtureTransport(
            stubs: [
                Self.logout: .response(status: 401, body: Self.unauthorized),
                Self.refresh: Self.rotation(),
            ]
        )
        let client = try await signedIn(transport)

        await client.endSession()

        #expect(await transport.requestCount(for: Self.refresh) == 0)
        #expect(await Self.wasSignalled(client) == false)
        #expect(await client.hasSession == false)
    }

    @Test("the revoke presents the session, so the server knows whose family to end")
    @MainActor
    func endSessionPresentsTheSession() async throws {
        let transport = FixtureTransport(stubs: [Self.logout: .response(status: 200, body: Data("{}".utf8))])
        let client = try await signedIn(transport)

        await client.endSession()

        let request = try #require(await transport.recordedRequests.first { $0.path == Self.logout })
        #expect(request.headers["Authorization"]?.hasPrefix("Bearer ") == true)
    }

    /// Whether ``APIClient/sessionEnded`` has anything waiting on it.
    ///
    /// A signal that was sent is buffered and arrives immediately, so the race below resolves at once in
    /// the interesting direction. The sleeper is what makes the *absence* of a signal an answer rather
    /// than a test that never finishes.
    private static func wasSignalled(_ client: APIClient) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                for await _ in client.sessionEnded { return true }
                return false
            }
            group.addTask {
                try? await Task.sleep(for: .milliseconds(100))
                return false
            }
            let answer = await group.next() ?? false
            group.cancelAll()
            return answer
        }
    }

    // MARK: - refreshIfNearExpiry

    @Test("refreshIfNearExpiry refreshes when the token is nearly dead")
    @MainActor
    func refreshIfNearExpiryRefreshes() async throws {
        let transport = FixtureTransport(stubs: [Self.refresh: Self.rotation()])
        let client = try await signedIn(transport, accessExpiresIn: 30)

        await client.refreshIfNearExpiry()

        #expect(await transport.requestCount(for: Self.refresh) == 1)
    }

    @Test("refreshIfNearExpiry does nothing when the token is fresh")
    @MainActor
    func refreshIfNearExpiryIsANoOpWhenFresh() async throws {
        let transport = FixtureTransport(stubs: [Self.refresh: Self.rotation()])
        let client = try await signedIn(transport, accessExpiresIn: 900)

        await client.refreshIfNearExpiry()

        #expect(await transport.recordedRequests.isEmpty)
    }

    @Test("refreshIfNearExpiry does nothing when nobody is signed in")
    @MainActor
    func refreshIfNearExpiryIsANoOpWithoutASession() async throws {
        // Otherwise every launch of a signed-out app would open with a refresh request that cannot succeed,
        // and would end a session that was never there.
        let transport = FixtureTransport(stubs: [Self.refresh: Self.rotation()])
        let client = TestBench.client(transport)

        await client.refreshIfNearExpiry()

        #expect(await transport.recordedRequests.isEmpty)
    }
}

/// A ``TokenStore`` whose read fails — the Keychain before the first unlock after a reboot.
///
/// A third conformance rather than a mock of the client's collaborators: there is no other way to reach
/// the branch that distinguishes "cannot be read" from "empty", and that distinction is the difference
/// between an offline state and an unexplained logout.
private struct UnreadableTokenStore: TokenStore {
    func refreshToken() throws -> String? { throw KeychainError.status(errSecInteractionNotAllowed) }
    func save(refreshToken: String) {}
    func clear() {}
}
