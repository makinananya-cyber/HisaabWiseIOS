import Foundation
@testable import HisaabWise
import Testing

/// The one mapping in the app, tested as the one mapping in the app.
///
/// Before issue #11 this logic was inlined in `HomeViewModel`, which meant twelve screens were each
/// one `catch` away from telling a user in a tunnel that something had broken. These assertions are
/// what make ``BaseViewModel/load()`` the only place `APIError` becomes a ``LoadState``.
@Suite("BaseViewModel.load")
@MainActor
struct BaseViewModelTests {
    // MARK: Conforming probes

    /// A conformance over the real client and the real transport seam, so what is asserted is the
    /// mapping the app performs rather than a re-statement of it (ADR-0013).
    @Observable
    @MainActor
    final class BudgetProbe: BaseViewModel {
        var state: LoadState<BudgetSummary> = .loading

        private let client: APIClient

        init(_ transport: FixtureTransport) {
            client = TestBench.client(transport)
        }

        func fetch() async throws -> BudgetSummary {
            try await client.get(Endpoint.budget, as: BudgetSummary.self)
        }
    }

    /// A list-shaped screen, so that `isEmpty` has something to be empty about. Home's payload never
    /// is — a salary is always a figure — and every screen with a list on it will be.
    @Observable
    @MainActor
    final class ListProbe: BaseViewModel {
        var state: LoadState<[String]> = .loading

        private let items: [String]

        init(items: [String]) {
            self.items = items
        }

        func fetch() async throws -> [String] { items }

        func isEmpty(_ value: [String]) -> Bool { value.isEmpty }
    }

    /// Throws something that is not an `APIError` at all — a programmer error, a decoding helper, a
    /// future layer. It must still land somewhere renderable.
    @Observable
    @MainActor
    final class ThrowingProbe: BaseViewModel {
        struct Unexpected: Error {}

        var state: LoadState<Int> = .loading

        private let error: any Error

        init(throwing error: any Error) {
            self.error = error
        }

        func fetch() async throws -> Int { throw error }
    }

    // MARK: Success

    @Test("maps a decoded response to loaded")
    func successIsLoaded() async throws {
        let viewModel = BudgetProbe(FixtureTransport(stubs: [Endpoint.budget: try .ok(.budgetINR)]))

        try await viewModel.load()

        #expect(viewModel.state.value?.income.display == "₹65,000")
    }

    @Test("treats a response as loaded unless the screen says it is empty")
    func isEmptyDefaultsToFalse() async throws {
        let viewModel = BudgetProbe(FixtureTransport(stubs: [Endpoint.budget: try .ok(.budgetINR)]))

        try await viewModel.load()

        // `BudgetProbe` supplies no `isEmpty`, so the default one answers — and it answers `false`.
        #expect(viewModel.state.value != nil)
    }

    // MARK: Empty

    @Test("maps a successful response the screen calls empty to empty, not to loaded")
    func emptyCollectionIsEmpty() async throws {
        let viewModel = ListProbe(items: [])

        try await viewModel.load()

        #expect(viewModel.state == .empty)
        // Not `.loaded([])`: a screen drawing an empty list is the defect the case exists to prevent.
        #expect(viewModel.state.value == nil)
    }

    @Test("maps a non-empty collection to loaded")
    func nonEmptyCollectionIsLoaded() async throws {
        let viewModel = ListProbe(items: ["one"])

        try await viewModel.load()

        #expect(viewModel.state == .loaded(["one"]))
    }

    // MARK: Failure

    // ADR-0016 — offline is a supported mode, not a fault, and ADR-0007 says it never costs a
    // session either.
    @Test("maps a transport failure to offline, never to failed")
    func transportFailureIsOffline() async throws {
        let viewModel = BudgetProbe(FixtureTransport(stubs: [Endpoint.budget: .notConnected]))

        try await viewModel.load()

        #expect(viewModel.state == .offline)
        #expect(!viewModel.state.isFailed)
    }

    @Test("maps a definitive server error to failed, carrying the code")
    func serverErrorIsFailed() async throws {
        let body = Data(#"{"error":{"code":"RATE_LIMITED","message":"Slow down, friend."}}"#.utf8)
        let viewModel = BudgetProbe(
            FixtureTransport(stubs: [Endpoint.budget: .response(status: 429, body: body)])
        )

        try await viewModel.load()

        #expect(viewModel.state == .failed(ErrorCode(rawValue: "RATE_LIMITED")))
        #expect(!viewModel.state.isOffline)
    }

    @Test("maps a body it cannot decode to failed, not to empty")
    func malformedBodyIsFailed() async throws {
        let viewModel = BudgetProbe(
            FixtureTransport(
                stubs: [Endpoint.budget: .response(status: 200, body: Data(#"{"month":"2026-08"}"#.utf8))]
            )
        )

        try await viewModel.load()

        #expect(viewModel.state == .failed(.malformedResponse))
    }

    @Test("maps an error that is not an APIError to failed, without inventing a code")
    func unrecognisedErrorIsFailedUnknown() async throws {
        let viewModel = ThrowingProbe(throwing: ThrowingProbe.Unexpected())

        try await viewModel.load()

        #expect(viewModel.state == .failed(.unknown))
    }

    @Test("never carries the server's message anywhere a screen could read it")
    func serverMessageNeverReachesTheState() async throws {
        let prose = "Slow down, friend."
        let body = Data(#"{"error":{"code":"RATE_LIMITED","message":"\#(prose)"}}"#.utf8)
        let viewModel = BudgetProbe(
            FixtureTransport(stubs: [Endpoint.budget: .response(status: 429, body: body)])
        )

        try await viewModel.load()

        // The whole state, stringified, is the widest net a screen has to draw from.
        #expect(!String(describing: viewModel.state).contains(prose))
    }

    // MARK: Cancellation

    @Test("propagates CancellationError — a user who navigated away is not offline")
    func cancellationPropagates() async throws {
        let viewModel = BudgetProbe(
            FixtureTransport(stubs: [Endpoint.budget: .failure(CancellationError())])
        )

        await #expect(throws: CancellationError.self) {
            try await viewModel.load()
        }

        // Swallowing it would have parked the screen on `.offline` for a request nobody is waiting
        // for. The state is left where the abandoned load found it.
        #expect(viewModel.state == .loading)
        #expect(!viewModel.state.isOffline)
        #expect(!viewModel.state.isFailed)
    }

    @Test("propagates cancellation even when the transport reports it as a plain failure")
    func cancellationOfAnAlreadyCancelledTaskPropagates() async throws {
        // `URLSession` reports cancellation as `URLError.cancelled`, which the client cannot tell
        // from any other transport failure and so maps to `offline`. On a task that is *itself*
        // cancelled, that answer is wrong, and this is the check that keeps it from being given.
        let viewModel = BudgetProbe(FixtureTransport(stubs: [Endpoint.budget: .notConnected]))

        let task = Task { try await viewModel.load() }
        task.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(!viewModel.state.isOffline)
    }

    // MARK: Reload

    @Test("returns to loading on reload, so a retry is visible")
    func reloadReturnsToLoading() async throws {
        let viewModel = BudgetProbe(
            FixtureTransport(queue: [.notConnected, try .ok(.budgetINR)])
        )

        try await viewModel.load()
        #expect(viewModel.state == .offline)

        try await viewModel.load()
        #expect(viewModel.state.value?.income.display == "₹65,000")
    }
}
