import Foundation
import HWCore
import HWFeatures
import HWFixtures
import HWNetworking
import Testing

/// The walking skeleton, end to end: a canned HTTP payload goes through the real transport seam, the
/// real client, and the real decoding, and comes out as a display string a view can render.
@Suite("HomeStore")
@MainActor
struct HomeStoreTests {
    private let budgetPath = "/v1/budget"

    private func makeStore(_ transport: FixtureTransport) -> HomeStore {
        HomeStore(
            client: APIClient(
                baseURL: URL(string: "https://fixtures.invalid")!,
                transport: transport
            )
        )
    }

    @Test("starts loading, before anything has been asked for")
    func startsLoading() {
        let store = makeStore(FixtureTransport())

        #expect(store.state == .loading)
    }

    @Test("renders the server's display string for an INR salary")
    func loadsTheDisplayString() async throws {
        let transport = FixtureTransport(stubs: [budgetPath: try .ok(.budgetINR)])
        let store = makeStore(transport)

        await store.load()

        // Defect D1 — this figure has exactly one owner. The store reads it and does not compute it,
        // and the string is the server's, symbol spacing included: `₹65,000`, not `INR 65,000`.
        #expect(store.state.value?.income.display == "₹65,000")
        #expect(store.state.value?.income.minor == 6_500_000)
        #expect(store.state.value?.income.currency.rawValue == "INR")
        #expect(store.state.value?.month == "2026-08")
    }

    @Test("asks for the budget once, at the documented path")
    func requestsTheBudgetEndpoint() async throws {
        let transport = FixtureTransport(stubs: [budgetPath: try .ok(.budgetINR)])
        let store = makeStore(transport)

        await store.load()

        let requests = await transport.recordedRequests
        #expect(requests.map(\.path) == [budgetPath])
        #expect(requests.map(\.method) == ["GET"])
    }

    // ADR-0016 — offline is a supported mode, not a fault. A user in a tunnel must not be told
    // something failed, and ADR-0007 says they must not be signed out either.
    @Test("surfaces a transport failure as offline, never as failed")
    func transportFailureIsOffline() async {
        let transport = FixtureTransport(stubs: [budgetPath: .notConnected])
        let store = makeStore(transport)

        await store.load()

        #expect(store.state == .offline)
        #expect(!store.state.isFailed)
    }

    @Test("surfaces a definitive server error as failed, carrying the code")
    func serverErrorIsFailed() async {
        let body = Data(#"{"error":{"code":"RATE_LIMITED","message":"Slow down, friend."}}"#.utf8)
        let transport = FixtureTransport(stubs: [budgetPath: .response(status: 429, body: body)])
        let store = makeStore(transport)

        await store.load()

        #expect(store.state == .failed(ErrorCode(rawValue: "RATE_LIMITED")))
        #expect(!store.state.isOffline)
    }

    @Test("never carries the server's message anywhere a screen could read it")
    func serverMessageIsNotSurfaced() async {
        let prose = "Slow down, friend."
        let body = Data(#"{"error":{"code":"RATE_LIMITED","message":"\#(prose)"}}"#.utf8)
        let transport = FixtureTransport(stubs: [budgetPath: .response(status: 429, body: body)])
        let store = makeStore(transport)

        await store.load()

        guard case .failed(let code) = store.state else {
            Issue.record("expected a failed state, got \(store.state)")
            return
        }
        // The whole state, stringified, is the widest net a screen has to draw from.
        #expect(!String(describing: store.state).contains(prose))
        #expect(code.rawValue == "RATE_LIMITED")
    }

    @Test("surfaces an unrecognised error code without inventing one")
    func unmappedCodeSurvivesIntact() async {
        let body = Data(#"{"error":{"code":"SOMETHING_NEW"}}"#.utf8)
        let transport = FixtureTransport(stubs: [budgetPath: .response(status: 500, body: body)])
        let store = makeStore(transport)

        await store.load()

        #expect(store.state == .failed(ErrorCode(rawValue: "SOMETHING_NEW")))
    }

    @Test("surfaces a body it cannot decode as failed, not as empty")
    func malformedBodyIsFailed() async {
        let transport = FixtureTransport(
            stubs: [budgetPath: .response(status: 200, body: Data(#"{"month":"2026-08"}"#.utf8))]
        )
        let store = makeStore(transport)

        await store.load()

        #expect(store.state == .failed(.malformedResponse))
    }

    @Test("a money payload with an unknown currency fails rather than converting at rate 1.0")
    func unknownCurrencyFailsTheLoad() async {
        // Defect D15, all the way through the stack: the client refuses the response instead of
        // reporting a foreign amount as though it were USD.
        let body = Data(
            #"{"month":"2026-08","income":{"minor":650000,"currency":"ZZZ","exponent":2,"display":"ZZZ 6,500"}}"#.utf8
        )
        let transport = FixtureTransport(stubs: [budgetPath: .response(status: 200, body: body)])
        let store = makeStore(transport)

        await store.load()

        #expect(store.state == .failed(.malformedResponse))
    }

    @Test("returns to loading on reload, so a retry is visible")
    func reloadReturnsToLoading() async throws {
        let transport = FixtureTransport(
            queue: [.notConnected, try .ok(.budgetINR)],
            stubs: [:]
        )
        let store = makeStore(transport)

        await store.load()
        #expect(store.state == .offline)

        await store.load()
        #expect(store.state.value?.income.display == "₹65,000")
    }
}
