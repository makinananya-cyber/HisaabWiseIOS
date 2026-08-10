import Foundation
import SwiftUI
@testable import HisaabWise
import Testing

/// ADR-0016's two rules about failure, as assertions.
///
/// `offline` is never *styled* as `failed` — which a snapshot could show but not state as a rule — and
/// the server's `message` never reaches a rendered string. The presentation is pulled out of `body` as
/// a value precisely so that both are facts a test can check rather than pixels a reviewer has to
/// eyeball.
@Suite("StateView")
@MainActor
struct StateViewTests {
    /// A screen's copy: the one string only the screen can write, and the shared defaults for the rest.
    private let copy = StateCopy(empty: "home.empty")

    private func presentation<Value: Sendable>(
        _ state: LoadState<Value>,
        copy: StateCopy? = nil
    ) throws -> StatePresentation {
        try #require(StatePresentation(state: state, copy: copy ?? self.copy, palette: .standard))
    }

    // MARK: The taxonomy

    @Test("has no placeholder for loaded — data draws itself")
    func loadedHasNoPresentation() {
        #expect(StatePresentation(state: LoadState.loaded(1), copy: copy, palette: .standard) == nil)
    }

    /// The criterion the whole taxonomy exists for. Offline is a supported mode; a fault is a fault.
    @Test("offline is visually distinct from failed, not merely differently worded")
    func offlineIsNotStyledAsFailed() throws {
        let offline = try presentation(LoadState<Int>.offline)
        let failed = try presentation(LoadState<Int>.failed(.unknown))

        #expect(offline != failed)
        #expect(offline.symbol != failed.symbol)
        // The tint is the load-bearing half: the same symbol in danger red would still read as a fault.
        #expect(offline.tint != failed.tint)
        #expect(offline.message != failed.message)
    }

    @Test("loading shows progress rather than a symbol")
    func loadingShowsProgress() throws {
        let loading = try presentation(LoadState<Int>.loading)

        #expect(loading.showsProgress)
        #expect(loading.symbol == nil)
        #expect(loading.retry == nil)
    }

    @Test("empty is not a fault and not a progress state")
    func emptyIsItsOwnThing() throws {
        let empty = try presentation(LoadState<Int>.empty)
        let failed = try presentation(LoadState<Int>.failed(.unknown))

        #expect(!empty.showsProgress)
        #expect(empty.tint != failed.tint)
        #expect(empty.message == copy.empty)
    }

    // MARK: The CTA

    @Test("offline and failed offer the retry the screen titled")
    func retryIsOfferedWhereRetryingHelps() throws {
        #expect(try presentation(LoadState<Int>.offline).retry == copy.retry)
        #expect(try presentation(LoadState<Int>.failed(.unknown)).retry == copy.retry)
    }

    @Test("empty never offers a retry, however much the screen supplied")
    func emptyOffersNoRetry() throws {
        // Re-asking a question the server has already answered is not a remedy. The CTA that belongs on
        // an empty screen is the screen's own, and arrives with the first screen that has one (#18).
        #expect(copy.retry != nil)
        #expect(try presentation(LoadState<Int>.empty).retry == nil)
    }

    @Test("a screen that offers no retry gets no CTA in any state")
    func retryIsOptional() throws {
        let silent = StateCopy(empty: "home.empty", retry: nil)

        for state in [LoadState<Int>.loading, .empty, .offline, .failed(.unknown)] {
            #expect(try presentation(state, copy: silent).retry == nil)
        }
    }

    // MARK: The error-code mapping

    @Test("an unmapped code yields generic copy rather than nothing")
    func unmappedCodeIsGeneric() {
        #expect(ErrorCopy.message(for: ErrorCode(rawValue: "SOMETHING_NEW")) == ErrorCopy.generic)
        #expect(ErrorCopy.message(for: .unknown) == ErrorCopy.generic)
    }

    @Test("a recognised code gets copy of its own")
    func recognisedCodeIsSpecific() {
        for code in ErrorCopy.recognisedCodes {
            #expect(ErrorCopy.message(for: code) != ErrorCopy.generic, "\(code) maps to generic copy")
        }
        #expect(!ErrorCopy.recognisedCodes.isEmpty)
    }

    @Test("the code reaches the copy, so two failures do not read alike")
    func failedCopyFollowsTheCode() throws {
        let rateLimited = try presentation(LoadState<Int>.failed(.rateLimited))
        let unknown = try presentation(LoadState<Int>.failed(.unknown))

        #expect(rateLimited.message != unknown.message)
        #expect(rateLimited.message == ErrorCopy.message(for: .rateLimited))
    }

    /// The end of the pipeline the client is built to make impossible: prose from the wire on screen.
    @Test("the server's message never reaches a rendered string")
    func serverMessageNeverReachesTheScreen() async throws {
        let prose = "Slow down, friend."
        let body = Data(#"{"error":{"code":"RATE_LIMITED","message":"\#(prose)"}}"#.utf8)
        let viewModel = HomeViewModel(
            client: TestBench.client(
                FixtureTransport(stubs: [Endpoint.budget: .response(status: 429, body: body)])
            )
        )

        try await viewModel.load()

        // Straight through: wire → client → state → presentation → the string a `Text` would draw.
        let presentation = try presentation(viewModel.state)
        #expect(!String(localized: presentation.message).contains(prose))
        #expect(!String(describing: presentation).contains(prose))
    }

    // MARK: Copy exists

    /// A key with no copy behind it shows the user the key. These are the shared ones, which no
    /// screen's own test would cover.
    @Test("every shared state key has English copy")
    func sharedCopyExists() throws {
        var keys = [copy.loading.key, copy.empty.key, copy.offline.key, ErrorCopy.generic.key]
        keys += copy.retry.map { [$0.key] } ?? []
        keys += ErrorCopy.recognisedCodes.map { ErrorCopy.message(for: $0).key }

        try CatalogueCopy.expectEnglishCopy(forKeys: keys)
    }

    // MARK: It renders

    @Test("renders in every state, through the real environment")
    func rendersInEveryState() throws {
        for state in [LoadState<Int>.loading, .empty, .offline, .failed(.rateLimited), .loaded(1)] {
            let view = StateView(state: state, copy: copy, reload: {}) { value in
                Text(verbatim: "\(value)")
            }
            #expect(TestBench.render(view) != nil, "\(state) did not render")
        }
    }
}
