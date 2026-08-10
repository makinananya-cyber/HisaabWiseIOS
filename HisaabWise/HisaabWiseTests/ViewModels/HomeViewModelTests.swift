import Foundation
@testable import HisaabWise
import Testing

/// The walking skeleton, end to end: a canned HTTP payload goes through the real transport seam, the real
/// client, and the real decoding, and comes out as a display string a view can render.
///
/// **The state mapping is not asserted here.** It moved to ``BaseViewModel/load()`` with issue #11 and is
/// asserted in `BaseViewModelTests` — one owner, one suite. What is left is what is Home's: the request it
/// makes, and the payload it decodes.
@Suite("HomeViewModel")
@MainActor
struct HomeViewModelTests {
    private let budgetPath = "/v1/budget"

    private func makeViewModel(_ transport: FixtureTransport) -> HomeViewModel {
        HomeViewModel(client: TestBench.client(transport))
    }

    @Test("starts loading, before anything has been asked for")
    func startsLoading() {
        let viewModel = makeViewModel(FixtureTransport())

        #expect(viewModel.state == .loading)
    }

    @Test("renders the server's display string for an INR salary")
    func loadsTheDisplayString() async throws {
        let transport = FixtureTransport(stubs: [budgetPath: try .ok(.budgetINR)])
        let viewModel = makeViewModel(transport)

        try await viewModel.load()

        // Defect D1 — this figure has exactly one owner. The view model reads it and does not compute it,
        // and the string is the server's, symbol spacing included: `₹65,000`, not `INR 65,000`.
        #expect(viewModel.state.value?.income.display == "₹65,000")
        #expect(viewModel.state.value?.income.minor == 6_500_000)
        #expect(viewModel.state.value?.income.currency.rawValue == "INR")
        #expect(viewModel.state.value?.month == "2026-08")
    }

    @Test("asks for the budget once, at the documented path")
    func requestsTheBudgetEndpoint() async throws {
        let transport = FixtureTransport(stubs: [budgetPath: try .ok(.budgetINR)])
        let viewModel = makeViewModel(transport)

        try await viewModel.load()

        let requests = await transport.recordedRequests
        #expect(requests.map(\.path) == [budgetPath])
        #expect(requests.map(\.method) == ["GET"])
    }

    @Test("a money payload with an unknown currency fails rather than converting at rate 1.0")
    func unknownCurrencyFailsTheLoad() async throws {
        // Defect D15, all the way through the stack: the client refuses the response instead of
        // reporting a foreign amount as though it were USD.
        let body = Data(
            #"{"month":"2026-08","income":{"minor":650000,"currency":"ZZZ","exponent":2,"display":"ZZZ 6,500"}}"#.utf8
        )
        let transport = FixtureTransport(stubs: [budgetPath: .response(status: 200, body: body)])
        let viewModel = makeViewModel(transport)

        try await viewModel.load()

        #expect(viewModel.state == .failed(.malformedResponse))
    }
}
