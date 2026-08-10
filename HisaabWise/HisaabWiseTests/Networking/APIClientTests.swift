import Foundation
@testable import HisaabWise
import Testing

@Suite("APIClient")
struct APIClientTests {
    private let baseURL = URL(string: "https://fixtures.invalid")!

    @MainActor
    private func makeClient(
        _ transport: FixtureTransport,
        in language: AppLanguage = .english
    ) -> APIClient {
        // No session: this suite is about what every request carries, and a client with a refresh token
        // would answer a `401` with a refresh rather than reporting it. The session's own behaviour is
        // `SessionTests`.
        APIClient(
            baseURL: baseURL,
            transport: transport,
            language: LanguageManager(selected: language),
            refreshTokens: InMemoryTokenStore()
        )
    }

    private struct Payload: Decodable, Sendable, Equatable {
        let month: String
    }

    @Test("decodes a 200 body")
    func decodesASuccessfulResponse() async throws {
        let transport = FixtureTransport(
            stubs: ["/v1/budget": .response(status: 200, body: Data(#"{"month":"2026-08"}"#.utf8))]
        )

        let payload = try await makeClient(transport).get("/v1/budget", as: Payload.self)

        #expect(payload == Payload(month: "2026-08"))
    }

    @Test("resolves the path against the injected base URL")
    func resolvesAgainstTheInjectedBaseURL() async throws {
        // ADR-0010 — the client has no default base URL and no notion of an environment. A test
        // injects one without a build configuration existing.
        let transport = FixtureTransport(
            stubs: ["/v1/budget": .response(status: 200, body: Data(#"{"month":"2026-08"}"#.utf8))]
        )

        _ = try await makeClient(transport).get("/v1/budget", as: Payload.self)

        let requests = await transport.recordedRequests
        #expect(requests.count == 1)
        #expect(requests.first?.path == "/v1/budget")
    }

    @Test("maps a transport failure to offline, preserving the session")
    func transportFailureIsOffline() async {
        // ADR-0007 — going through a tunnel must not cost the user their session, so a transport
        // failure is a separate outcome from anything the server said.
        let transport = FixtureTransport(stubs: ["/v1/budget": .notConnected])

        await #expect(throws: APIError.offline) {
            try await makeClient(transport).get("/v1/budget", as: Payload.self)
        }
    }

    @Test("lets a cancellation through rather than calling it offline")
    func cancellationIsNotOffline() async {
        // A user who navigated away has not lost their network. Rewriting a `CancellationError` as
        // `.offline` would show them an offline state and break structured concurrency besides.
        let transport = FixtureTransport(stubs: ["/v1/budget": .failure(CancellationError())])

        await #expect(throws: CancellationError.self) {
            try await makeClient(transport).get("/v1/budget", as: Payload.self)
        }
    }

    @Test("bypasses the URL cache, because every route it serves is per-user")
    func bypassesTheCache() async throws {
        // Invariant 8 — a cache HIT on per-user data is a data breach, not a performance win.
        let transport = FixtureTransport(
            stubs: ["/v1/budget": .response(status: 200, body: Data(#"{"month":"2026-08"}"#.utf8))]
        )

        _ = try await makeClient(transport).get("/v1/budget", as: Payload.self)

        let recorded = try #require(await transport.recordedRequests.first)
        #expect(recorded.cachePolicy == .reloadIgnoringLocalCacheData)
    }

    @Test("maps a non-2xx status to a server error carrying the code")
    func nonSuccessStatusCarriesTheCode() async {
        let body = Data(#"{"error":{"code":"ACCOUNT_LOCKED","message":"Try again in 15 minutes."}}"#.utf8)
        let transport = FixtureTransport(stubs: ["/v1/budget": .response(status: 423, body: body)])

        await #expect(
            throws: APIError.server(status: 423, code: ErrorCode(rawValue: "ACCOUNT_LOCKED"))
        ) {
            try await makeClient(transport).get("/v1/budget", as: Payload.self)
        }
    }

    @Test("never carries the server's message off the error path")
    func serverMessageIsDropped() async throws {
        // ADR-0016 — the `message` field is never decoded, so no screen can display English prose to
        // an Arabic-reading user.
        let prose = "Try again in 15 minutes."
        let body = Data(#"{"error":{"code":"ACCOUNT_LOCKED","message":"\#(prose)"}}"#.utf8)
        let transport = FixtureTransport(stubs: ["/v1/budget": .response(status: 423, body: body)])

        do {
            _ = try await makeClient(transport).get("/v1/budget", as: Payload.self)
            Issue.record("expected the request to fail")
        } catch let error as APIError {
            #expect(!String(describing: error).contains(prose))
            #expect(error.errorCode == ErrorCode(rawValue: "ACCOUNT_LOCKED"))
        }
    }

    @Test("falls back to an unknown code when the envelope is absent")
    func missingEnvelopeYieldsUnknownCode() async {
        let transport = FixtureTransport(
            stubs: ["/v1/budget": .response(status: 500, body: Data("upstream exploded".utf8))]
        )

        await #expect(throws: APIError.server(status: 500, code: .unknown)) {
            try await makeClient(transport).get("/v1/budget", as: Payload.self)
        }
    }

    @Test("reports a body it cannot decode as malformed, distinct from a server error")
    func undecodableBodyIsMalformed() async {
        let transport = FixtureTransport(
            stubs: ["/v1/budget": .response(status: 200, body: Data(#"{"unexpected":true}"#.utf8))]
        )

        await #expect(throws: APIError.malformedResponse) {
            try await makeClient(transport).get("/v1/budget", as: Payload.self)
        }
    }

    @Test("decodes the shared budget fixture through the same path the app uses")
    func decodesTheSharedFixture() async throws {
        let transport = FixtureTransport(stubs: ["/v1/budget": try .ok(.budgetINR)])

        let budget = try await makeClient(transport).get("/v1/budget", as: BudgetSummary.self)

        #expect(budget.income.display == "₹65,000")
    }

    // MARK: - Every request, whatever the verb

    /// The verbs are the client's own `APIClient.Method`, not a copy of the list. A rule that has to
    /// hold for all of them is written once here and checked once per verb, and a fifth verb added to
    /// the client fails to compile the `switch` below rather than arriving uncovered.
    private typealias Verb = APIClient.Method

    /// A write body. Deliberately trivial: what is asserted is that the client encodes and sends it,
    /// not what an expense looks like — that shape belongs to #18.
    private struct Draft: Encodable, Sendable {
        let note: String
    }

    /// Its own literal, like every other path in this suite, so a path change fails a test rather than
    /// being silently agreed to.
    private static let expensesPath = "/v1/expenses"

    /// Issues one request of `verb` through the real client and hands back what reached the transport.
    @MainActor
    private func recorded(
        _ verb: Verb,
        path: String = APIClientTests.expensesPath,
        in language: AppLanguage = .english,
        idempotencyKey: String? = nil
    ) async throws -> FixtureTransport.RecordedRequest {
        let transport = FixtureTransport(
            stubs: [path: .response(status: 200, body: Data(#"{"month":"2026-08"}"#.utf8))]
        )
        let client = makeClient(transport, in: language)
        let draft = Draft(note: "coffee")

        switch verb {
        case .get:
            _ = try await client.get(path, as: Payload.self)
        case .post:
            if let idempotencyKey {
                _ = try await client.post(
                    path,
                    body: draft,
                    idempotencyKey: idempotencyKey,
                    as: Payload.self
                )
            } else {
                _ = try await client.post(path, body: draft, as: Payload.self)
            }
        case .put:
            _ = try await client.put(path, body: draft, as: Payload.self)
        case .delete:
            _ = try await client.delete(path, as: Payload.self)
        }

        return try #require(await transport.recordedRequests.first)
    }

    @Test("sends the verb it was asked for", arguments: APIClient.Method.allCases)
    func sendsTheVerbItWasAskedFor(_ verb: APIClient.Method) async throws {
        let request = try await recorded(verb)

        #expect(request.method == verb.rawValue)
    }

    @Test("sets Accept-Language on every verb, not only on reads", arguments: APIClient.Method.allCases)
    func acceptLanguageIsSetOnEveryVerb(_ verb: APIClient.Method) async throws {
        // ADR-0003 — the server formats money honouring this header, and a write returns the updated
        // screen payload (ADR-0020). A write without it would answer in the wrong language, and the
        // client has no formatter to correct the figures with.
        let request = try await recorded(verb, in: .arabic)

        #expect(request.headers["Accept-Language"] == "ar")
    }

    @Test("takes Accept-Language from the app's language", arguments: AppLanguage.allCases)
    func acceptLanguageFollowsTheAppsLanguage(_ language: AppLanguage) async throws {
        // From the `LanguageManager` the graph composed — not from `Locale.preferredLanguages`, which
        // would make the header a property of the device rather than of the choice the user made in the
        // app (ADR-0011, issue #7).
        let request = try await recorded(.get, in: language)

        #expect(request.headers["Accept-Language"] == language.rawValue)
    }

    @Test("bypasses the URL cache on every verb", arguments: APIClient.Method.allCases)
    func cacheIsBypassedOnEveryVerb(_ verb: APIClient.Method) async throws {
        // Invariant 8, extended to the write verbs this ticket added.
        let request = try await recorded(verb)

        #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
    }

    @Test("asks for JSON on every verb", arguments: APIClient.Method.allCases)
    func acceptsJSONOnEveryVerb(_ verb: APIClient.Method) async throws {
        let request = try await recorded(verb)

        #expect(request.headers["Accept"] == "application/json")
    }

    // MARK: - Writes

    @Test("sends a POST body as JSON, with the content type to match")
    func postCarriesItsBody() async throws {
        let request = try await recorded(.post)

        #expect(request.body == Data(#"{"note":"coffee"}"#.utf8))
        #expect(request.headers["Content-Type"] == "application/json")
    }

    @Test("sends a PUT body as JSON")
    func putCarriesItsBody() async throws {
        let request = try await recorded(.put)

        #expect(request.body == Data(#"{"note":"coffee"}"#.utf8))
        #expect(request.headers["Content-Type"] == "application/json")
    }

    @Test("sends no body, and claims no content type, on a GET or a DELETE", arguments: [APIClient.Method.get, .delete])
    func readsAndDeletesCarryNoBody(_ verb: APIClient.Method) async throws {
        let request = try await recorded(verb)

        #expect(request.body == nil)
        #expect(request.headers["Content-Type"] == nil)
    }

    @Test("carries an Idempotency-Key on expense create")
    func expenseCreateCarriesAnIdempotencyKey() async throws {
        let request = try await recorded(.post, path: Self.expensesPath)

        let key = try #require(request.headers["Idempotency-Key"])
        #expect(UUID(uuidString: key) != nil, "the generated key should be a UUID, not \(key)")
    }

    @Test("uses the caller's key, so one user intent can be one key")
    func aCallerSuppliedKeyIsUsedVerbatim() async throws {
        // The form that will matter when a "try again" button sits in front of a write (#18): the retry
        // has to present the *same* key as the attempt it is retrying.
        let request = try await recorded(.post, idempotencyKey: "one-user-intent")

        #expect(request.headers["Idempotency-Key"] == "one-user-intent")
    }

    @Test("generates a fresh key per call, because one call is one intent by default")
    func generatedKeysDifferBetweenCalls() async throws {
        let first = try await recorded(.post).headers["Idempotency-Key"]
        let second = try await recorded(.post).headers["Idempotency-Key"]

        #expect(first != nil)
        #expect(first != second)
    }

    @Test("carries no Idempotency-Key on a verb that does not need one", arguments: [APIClient.Method.get, .put, .delete])
    func onlyPostIsKeyed(_ verb: APIClient.Method) async throws {
        // A `PUT` replaces a value and a `DELETE` names one, so sending either twice lands in the same
        // state. A key there would be ceremony implying otherwise.
        let request = try await recorded(verb)

        #expect(request.headers["Idempotency-Key"] == nil)
    }

    @Test("a write attempted offline fails offline, and is not queued")
    func aWriteOnADeadNetworkIsOffline() async throws {
        // ADR-0019 — no offline writes: no queue, no pending state, no drain. One attempt reaches the
        // transport, it fails, and the user retries.
        let transport = FixtureTransport(stubs: [Self.expensesPath: .notConnected])
        let client = await makeClient(transport)

        await #expect(throws: APIError.offline) {
            try await client.post(Self.expensesPath, body: Draft(note: "coffee"), as: Payload.self)
        }

        #expect(await transport.recordedRequests.count == 1)
    }

    @Test("a write the server refused keeps the server's code")
    func aRefusedWriteKeepsTheCode() async throws {
        // The write path goes through the same mapping the read path does, so `MONTH_CLOSED` reaches the
        // screen that offers re-filing (Product Spec §4.5) rather than reading as a generic failure.
        let body = Data(#"{"error":{"code":"MONTH_CLOSED","message":"That month is archived."}}"#.utf8)
        let transport = FixtureTransport(
            stubs: [Self.expensesPath: .response(status: 409, body: body)]
        )
        let client = await makeClient(transport)

        await #expect(throws: APIError.server(status: 409, code: .monthClosed)) {
            try await client.post(Self.expensesPath, body: Draft(note: "coffee"), as: Payload.self)
        }
    }
}
