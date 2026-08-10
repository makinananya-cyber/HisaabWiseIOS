import Foundation
@testable import HisaabWise
import Testing

@Suite("APIClient")
struct APIClientTests {
    private let baseURL = URL(string: "https://fixtures.invalid")!

    private func makeClient(_ transport: FixtureTransport) -> APIClient {
        APIClient(baseURL: baseURL, transport: transport)
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
}
