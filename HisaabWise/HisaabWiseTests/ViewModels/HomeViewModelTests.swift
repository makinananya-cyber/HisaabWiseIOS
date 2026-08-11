import Foundation
@testable import HisaabWise
import Testing

/// Home reads **one endpoint** and derives nothing from it (ADR-0020).
///
/// The suite this replaces asserted the walking skeleton: one canned budget payload through the real seam, out as
/// a display string. The claims are the same in kind and larger in scope — the request Home makes, the payload it
/// decodes, and the three things it is allowed to *own*: which slice is isolated, which tip is showing, and
/// nothing else.
///
/// **The state mapping is not asserted here.** It lives in ``BaseViewModel/load()`` and is asserted in
/// `BaseViewModelTests` — one owner, one suite.
@Suite("HomeViewModel")
@MainActor
struct HomeViewModelTests {
    private static func makeViewModel(
        _ transport: FixtureTransport,
        store: any ContentStore = InMemoryContentStore()
    ) -> HomeViewModel {
        let client = TestBench.client(transport)
        return HomeViewModel(client: client, content: ContentLoader(client: client, store: store))
    }

    /// The screen, plus the tip pool for the tests that cycle.
    private static func stubs(_ home: Fixture = .homeINR) throws -> [String: FixtureTransport.Outcome] {
        [
            Endpoint.screenHome: try .ok(home),
            Endpoint.contentTips: try .ok(.tips),
        ]
    }

    @Test("starts loading, before anything has been asked for")
    func startsLoading() {
        #expect(Self.makeViewModel(FixtureTransport()).state == .loading)
    }

    // MARK: - One request

    /// **The single request, asserted as a request count.** Home used to read `/v1/budget`; a screen that needed
    /// the budget, the tips, the streak, and the article list would fetch four and derive the join, which is how
    /// D1, D10, D11, and D16 all happened.
    @Test("asks for the screen once, and asks for nothing else")
    func asksForTheScreenOnce() async throws {
        let transport = FixtureTransport(stubs: try Self.stubs())
        let viewModel = Self.makeViewModel(transport)

        try await viewModel.load()

        let requests = await transport.recordedRequests
        #expect(requests.map(\.path) == [Endpoint.screenHome])
        #expect(requests.map(\.method) == ["GET"])
        // And specifically not the engine's own endpoint, which no screen reads any more.
        #expect(await transport.requestCount(for: Endpoint.budget) == 0)
    }

    @Test("decodes every part of the screen the design draws")
    func decodesTheScreen() async throws {
        let viewModel = Self.makeViewModel(FixtureTransport(stubs: try Self.stubs()))

        try await viewModel.load()
        let screen = try #require(viewModel.state.value)

        // The greeting and the date are the **server's**, not the device clock's (invariant 6).
        #expect(screen.greeting == "Good morning")
        #expect(screen.dateLabel == "Tuesday, 11 August")
        #expect(screen.monthLabel == "August")

        // Six categories, each with its share as a fraction *and* its percentage as a string — the first is
        // geometry, the second is what the user reads, and neither is computed here.
        #expect(screen.spending.categories.count == 6)
        #expect(screen.spending.total.display == "₹5,539")
        #expect(screen.spending.shareOfPayLabel == "9% of pay")
        #expect(!screen.spending.isFirstRun)

        // The meter arrives as a position, a percentage string, and a verdict.
        #expect(screen.savings.saved.display == "₹23,000")
        #expect(screen.savings.percentageLabel == "177% of goal")
        #expect(screen.savings.verdict == .met)
        #expect(screen.savings.remaining == nil)

        #expect(screen.learning.streak == 4)
        #expect(screen.articles.count == 3)
        #expect(screen.articles.first?.icon == .shield)
    }

    /// **Defect D1's regression test, at the level it can be tested here.** The figure that was hardcoded is not
    /// on this screen at all: "% of pay" arrives as a sentence, so there is no salary for the client to hold and
    /// nothing to hardcode it *against*. `HomeViewTests` asserts the cards agree.
    @Test("no figure on the screen is a number this client could have computed")
    func nothingIsDerived() async throws {
        let viewModel = Self.makeViewModel(FixtureTransport(stubs: try Self.stubs()))

        try await viewModel.load()
        let screen = try #require(viewModel.state.value)

        // Every displayed figure is a string the server formatted, and the two `Double`s are geometry.
        #expect(screen.spending.shareOfPayLabel.contains("%"))
        #expect(screen.savings.percentageLabel.contains("%"))
        #expect(screen.spending.categories.allSatisfy { $0.shareLabel.contains("%") })
        // And Home holds no salary to divide by. The scan names the *shapes* defect D1 took — a literal, and a
        // ratio taken against one — rather than the word, which registration's own salary field uses honestly.
        let home = try SourceTree.codeLines(of: SourceTree.appSources.appending(path: "Views/HomeView.swift"))
        for shape in ["salary", "8000", "8_000", "/ 100", "* 100"] {
            #expect(
                home.first { $0.contains(shape) } == nil,
                "HomeView references \(shape) — the salary has one owner and this screen is not it (defect D1)"
            )
        }
    }

    @Test("a money payload with an unknown currency fails rather than converting at rate 1.0")
    func unknownCurrencyFailsTheLoad() async throws {
        // Defect D15, through the whole stack: the client refuses the response instead of reporting a foreign
        // amount as though it were USD. The screen payload is nested, so this also proves the refusal survives
        // being three levels down.
        var payload = try #require(
            try JSONSerialization.jsonObject(with: TestBench.payload(.homeINR)) as? [String: Any]
        )
        var spending = try #require(payload["spending"] as? [String: Any])
        spending["total"] = ["minor": 650_000, "currency": "ZZZ", "exponent": 2, "display": "ZZZ 6,500"]
        payload["spending"] = spending
        let body = try JSONSerialization.data(withJSONObject: payload)

        let viewModel = Self.makeViewModel(
            FixtureTransport(stubs: [Endpoint.screenHome: .response(status: 200, body: body)])
        )

        try await viewModel.load()

        #expect(viewModel.state == .failed(.malformedResponse))
    }

    /// A `501` is what every unwritten screen endpoint answers with, and it is a **failure** rather than an
    /// absence: the screen has nothing to draw and the server has said why.
    @Test("an unwritten endpoint is a failed state, not an empty one")
    func notImplementedIsAFailure() async throws {
        let viewModel = Self.makeViewModel(
            FixtureTransport(stubs: [Endpoint.screenHome: .response(status: 501, body: Data())])
        )

        try await viewModel.load()

        #expect(viewModel.state.isFailed)
    }

    /// A first-run month is **not** `LoadState.empty`. The screen still has a goal, a tip, a streak, and three
    /// articles; only the donut has nothing in it, and the payload says so.
    @Test("a first-run month loads as a screen, with the spending card marked")
    func firstRunIsALoadedScreen() async throws {
        let viewModel = Self.makeViewModel(FixtureTransport(stubs: try Self.stubs(.homeFirstRun)))

        try await viewModel.load()
        let screen = try #require(viewModel.state.value)

        #expect(viewModel.state.isFailed == false)
        #expect(screen.spending.isFirstRun)
        #expect(screen.spending.categories.isEmpty)
        // And the rest of the screen is there.
        #expect(screen.savings.goal.display == "₹13,000")
        #expect(!screen.articles.isEmpty)
    }

    // MARK: - Isolating a slice

    @Test("tapping a slice isolates it, and tapping it again returns to the whole ring")
    func isolatingASlice() async throws {
        let viewModel = Self.makeViewModel(FixtureTransport(stubs: try Self.stubs()))
        try await viewModel.load()
        let screen = try #require(viewModel.state.value)

        #expect(viewModel.isolated == nil)
        #expect(viewModel.isolatedCategory(in: screen) == nil)

        viewModel.isolate("groceries")
        #expect(viewModel.isolatedCategory(in: screen)?.name == "Groceries")
        #expect(viewModel.isolatedCategory(in: screen)?.shareLabel == "16%")

        viewModel.isolate("groceries")
        #expect(viewModel.isolated == nil, "tapping the isolated slice again did not return to the whole ring")

        // A different slice replaces the isolation rather than adding to it.
        viewModel.isolate("rent")
        viewModel.isolate("transport")
        #expect(viewModel.isolated == "transport")
    }

    /// **An id, not an index.** A reload that returns the categories in a different order would move an
    /// index-based isolation to a different category without the user touching anything — and a reload that drops
    /// the isolated category leaves the ring whole rather than showing a slice that is not there.
    @Test("an isolation that is no longer in the payload reads as no isolation")
    func aVanishedIsolationIsNoIsolation() async throws {
        let viewModel = Self.makeViewModel(FixtureTransport(stubs: try Self.stubs()))
        try await viewModel.load()

        viewModel.isolate("groceries")
        let firstRun = try Fixture.homeFirstRun.decode(HomeScreen.self)

        #expect(viewModel.isolated == "groceries")
        #expect(viewModel.isolatedCategory(in: firstRun) == nil)
    }

    // MARK: - The tip

    /// **The server chose it, and the `dayKey` is how that is checkable.** The client owns no date arithmetic for
    /// tips and never calls `Date()`: two payloads with different days produce different tips, and the device
    /// clock produces none.
    @Test("the tip comes from the payload, chosen by dayKey rather than by the device clock")
    func theTipIsTheServersChoice() async throws {
        let viewModel = Self.makeViewModel(FixtureTransport(stubs: try Self.stubs()))
        try await viewModel.load()
        let screen = try #require(viewModel.state.value)

        #expect(screen.tip.dayKey == "2026-08-11")
        #expect(viewModel.tip(in: screen).id == screen.tip.id)

        // A payload for a different day carries a different tip, and the client renders whichever it was given.
        var payload = try #require(
            try JSONSerialization.jsonObject(with: TestBench.payload(.homeINR)) as? [String: Any]
        )
        payload["tip"] = [
            "id": "tip-22", "dayKey": "2026-08-12",
            "text": "Pay yourself first.", "currencyToken": "₹",
        ]
        let other = try JSONDecoder().decode(
            HomeScreen.self,
            from: try JSONSerialization.data(withJSONObject: payload)
        )

        #expect(other.tip.id == "tip-22")
        #expect(viewModel.tip(in: other).id == "tip-22")
    }

    /// And nothing in the app reaches for the clock to pick one.
    @Test("no view model or view calls Date() to choose a tip")
    func nothingPicksATipByDate() throws {
        try SourceTree.expectAbsent(
            ["dayOfYear", "Date().timeIntervalSince", "component(.day"],
            from: ["ViewModels", "Views"],
            because: "the tip is chosen server-side by dayKey; the client never picks by date (ADR-0016)"
        )
    }

    /// `{c}` is substituted from the **server-supplied** token, so ADR-0003's spacing rule keeps one owner. The
    /// amounts inside a tip are illustrative and are never converted (ADR-0016).
    @Test("the currency token is substituted and the amounts are left alone")
    func theCurrencyTokenIsSubstituted() async throws {
        let viewModel = Self.makeViewModel(FixtureTransport(stubs: try Self.stubs()))
        try await viewModel.load()
        let tip = viewModel.tip(in: try #require(viewModel.state.value))

        #expect(tip.text.contains("{c}"), "the payload no longer carries the token verbatim")
        #expect(!tip.resolvedText.contains("{c}"))
        #expect(tip.resolvedText.contains("₹6,400"))
        // Illustrative: the figure in the text is the content's, not a converted one.
        #expect(tip.resolvedText.contains("₹640"))
    }

    /// **Show me another cycles in memory** over the cached pool (ADR-0016) — the day's tip first, then each
    /// substitute, wrapping at the end.
    @Test("show me another cycles through the pool without asking the screen again")
    func showAnotherTipCycles() async throws {
        let transport = FixtureTransport(stubs: try Self.stubs())
        let viewModel = Self.makeViewModel(transport)
        try await viewModel.load()
        let screen = try #require(viewModel.state.value)
        let day = viewModel.tip(in: screen)

        await viewModel.showAnotherTip(after: day)
        let second = viewModel.tip(in: screen)
        await viewModel.showAnotherTip(after: second)
        let third = viewModel.tip(in: screen)

        #expect(second.id != day.id)
        #expect(third.id != second.id)
        // The day's tip is `tip-07`, so the pool advances to `tip-08` and `tip-09`.
        #expect(second.id == "tip-08")
        #expect(third.id == "tip-09")

        // **The screen was not re-read**, and the pool was fetched once however many times the control was
        // pressed — which is what "in memory" means.
        #expect(await transport.requestCount(for: Endpoint.screenHome) == 1)
        #expect(await transport.requestCount(for: Endpoint.contentTips) == 1)

        // And the substitute keeps *this* payload's currency token: the pool is cacheable and therefore cannot
        // carry one user's currency.
        #expect(viewModel.tip(in: screen).currencyToken == screen.tip.currencyToken)
    }

    /// A pool that will not load leaves the day's tip on screen. A failed *nicety* must not replace a screen that
    /// is fine, which is why this does not go through `load()`.
    @Test("a tip pool that will not load leaves the screen alone")
    func aFailedPoolLeavesTheScreen() async throws {
        let transport = FixtureTransport(stubs: [
            Endpoint.screenHome: try .ok(.homeINR),
            Endpoint.contentTips: .notConnected,
        ])
        let viewModel = Self.makeViewModel(transport)
        try await viewModel.load()
        let screen = try #require(viewModel.state.value)

        await viewModel.showAnotherTip(after: viewModel.tip(in: screen))

        #expect(viewModel.tip(in: screen).id == screen.tip.id)
        #expect(viewModel.state.value != nil, "a failed tip pool replaced a screen that had loaded")
    }
}
