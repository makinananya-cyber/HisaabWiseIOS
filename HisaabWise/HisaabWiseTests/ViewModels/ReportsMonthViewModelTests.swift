import Foundation
@testable import HisaabWise
import Testing

/// One closed month: **one read at the month's own address, and nothing derived from it** (ADR-0020, ADR-0037).
///
/// The claim this suite exists for is **invariant 7**: an archived month is immutable and carries the FX rate set
/// pinned at close, so re-reading it in another display currency converts every figure and changes no verdict. It
/// is asserted against the corpus's two reads of one month rather than described — see
/// ``aCurrencyChangeRepaintsTheFiguresAndNotTheStory()``.
///
/// **The `LoadState` mapping itself is not asserted here.** It lives in ``BaseViewModel/load()`` and is asserted in
/// `BaseViewModelTests` — one owner, one suite. What is asserted here is what this object adds.
@Suite("ReportsMonthViewModel")
@MainActor
struct ReportsMonthViewModelTests {
    private static let february = "2026-02"
    private static var path: String { Endpoint.screenReportsMonth(monthKey: february) }

    private static func makeViewModel(
        _ transport: FixtureTransport,
        monthKey: String = february
    ) -> ReportsMonthViewModel {
        ReportsMonthViewModel(monthKey: monthKey, client: TestBench.client(transport))
    }

    private static func loaded(
        _ fixture: Fixture = .reportsMonthINR,
        monthKey: String = february
    ) async throws -> ReportsMonthScreen {
        let viewModel = makeViewModel(
            FixtureTransport(stubs: [Endpoint.screenReportsMonth(monthKey: monthKey): try .ok(fixture)]),
            monthKey: monthKey
        )
        try await viewModel.load()
        return try #require(viewModel.state.value)
    }

    @Test("starts loading, before anything has been asked for")
    func startsLoading() {
        #expect(Self.makeViewModel(FixtureTransport()).state == .loading)
    }

    // MARK: - One read, at the month's own address

    /// **The single request, and the address is the month key's.** A detail assembled from the archive plus a
    /// second call would be the client joining two responses, which is one step from calculating (ADR-0020).
    @Test("asks for the month once, at its own path, and asks for nothing else")
    func asksForTheMonthOnce() async throws {
        let transport = FixtureTransport(stubs: [Self.path: try .ok(.reportsMonthINR)])
        let viewModel = Self.makeViewModel(transport)

        try await viewModel.load()

        #expect(await transport.requestCount(for: Self.path) == 1)
        #expect(await transport.recordedRequests.count == 1)
        #expect(await transport.recordedRequests.first?.path == "/v1/screens/reports/2026-02")
    }

    /// Per-user data, so it bypasses every cache — invariant 8 as a property of the request. A closed month is
    /// somebody's financial history; a cache HIT on it is a breach.
    @Test("a month is a per-user read and is never left to a URL cache")
    func theMonthBypassesEveryCache() async throws {
        let transport = FixtureTransport(stubs: [Self.path: try .ok(.reportsMonthINR)])
        _ = try await Self.makeViewModel(transport).load()

        let request = try #require(await transport.recordedRequests.first)
        #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
    }

    @Test("no connection is offline, not a failure")
    func offlineIsNotAFailure() async throws {
        let viewModel = Self.makeViewModel(FixtureTransport(stubs: [Self.path: .notConnected]))

        try await viewModel.load()

        #expect(viewModel.state == .offline)
    }

    /// A `501` — what a screen endpoint answers with until the backend has written it — is a **failure** rather
    /// than an absence, which is the state this screen was built against.
    @Test("a 501 from the month endpoint is a failed state")
    func aNotImplementedMonthIsFailed() async throws {
        let viewModel = Self.makeViewModel(
            FixtureTransport(stubs: [Self.path: .response(status: 501, body: Data())])
        )

        try await viewModel.load()

        #expect(viewModel.state.isFailed)
    }

    // MARK: - Invariant 7

    /// **The regression test this screen exists for: a currency change repaints the figures and never the story.**
    ///
    /// The two payloads are the *same* closed month — February 2026 — read in rupees and then in dirhams through
    /// the rates pinned when it closed. What must change is every monetary display string. What must not change is
    /// anything that carries the story: the verdict, the percentage, the meter's position, and every geometry
    /// fraction. A met goal stays met, and a near miss stays a near miss.
    ///
    /// Driven as a **sequence on one path**, because that is what a currency change is: the same address, read
    /// again. There is no client-side conversion to test — the absence of one is the point.
    @Test("a currency change repaints the month through the pinned rates and leaves the verdict alone")
    func aCurrencyChangeRepaintsTheFiguresAndNotTheStory() async throws {
        let viewModel = Self.makeViewModel(
            FixtureTransport(
                sequences: [Self.path: [try .ok(.reportsMonthINR), try .ok(.reportsMonthAED)]]
            )
        )

        try await viewModel.load()
        let rupees = try #require(viewModel.state.value)
        try await viewModel.load()
        let dirhams = try #require(viewModel.state.value)

        // The story, unchanged.
        #expect(dirhams.verdict == rupees.verdict)
        #expect(dirhams.verdict == .near)
        #expect(dirhams.percentageLabel == rupees.percentageLabel)
        #expect(dirhams.savings.position == rupees.savings.position)
        #expect(dirhams.wants.fill == rupees.wants.fill)
        #expect(dirhams.wants.isOver == rupees.wants.isOver)
        #expect(dirhams.totals.isAdapted == rupees.totals.isAdapted)
        #expect(dirhams.split.segments.map(\.portion) == rupees.split.segments.map(\.portion))
        #expect(dirhams.split.segments.map(\.share) == rupees.split.segments.map(\.share))
        #expect(dirhams.spending.categories.map(\.share) == rupees.spending.categories.map(\.share))
        #expect(dirhams.spending.categories.map(\.shareLabel) == rupees.spending.categories.map(\.shareLabel))
        #expect(dirhams.facts.map(\.kind) == rupees.facts.map(\.kind))
        // Every date label too: a month's entries did not move because the reader changed currency.
        #expect(
            dirhams.groups.flatMap { $0.entries.map(\.dateLabel) }
                == rupees.groups.flatMap { $0.entries.map(\.dateLabel) }
        )

        // And the figures, all of them, repainted.
        #expect(dirhams.totals.spent.display != rupees.totals.spent.display)
        #expect(dirhams.savings.saved.display != rupees.savings.saved.display)
        #expect(dirhams.savings.goal.display != rupees.savings.goal.display)
        #expect(dirhams.savings.zeroLabel != rupees.savings.zeroLabel)
        #expect(dirhams.split.income.display != rupees.split.income.display)
        #expect(dirhams.savings.saved.currency.rawValue == "AED")
        #expect(rupees.savings.saved.currency.rawValue == "INR")
    }

    /// The same claim said the other way round, and the one a reader would notice: **the figures on screen are the
    /// snapshot's own display strings**, so nothing about them was re-converted here. Asserted as an absence — the
    /// client holds no rate, no multiplication, and no formatter (ADR-0003).
    @Test("every figure on the month is a string the server formatted")
    func everyFigureIsTheServersOwnString() async throws {
        let dirhams = try await Self.loaded(.reportsMonthAED)

        var figures = [
            dirhams.totals.spent, dirhams.totals.fixed, dirhams.totals.variable,
            dirhams.totals.additionalIncome, dirhams.savings.saved, dirhams.savings.goal,
            dirhams.wants.used, dirhams.wants.allowance, dirhams.split.income,
        ]
        figures += dirhams.split.segments.map(\.amount)
        figures += dirhams.spending.categories.map(\.amount)
        figures += dirhams.groups.map(\.total)
        figures += dirhams.groups.flatMap { $0.entries.map(\.amount) }

        for figure in figures {
            #expect(figure.currency.rawValue == "AED", "a figure came back in \(figure.currency.rawValue)")
            #expect(figure.display.contains("AED"), "\(figure.display) is not the pinned snapshot's own string")
        }
        #expect(dirhams.savings.zeroLabel.contains("AED"))
    }

    // MARK: - A month with nothing in it

    /// **A closed month with nothing logged is `.loaded`, not `.empty`.**
    ///
    /// It still has a salary, a goal, a verdict, and a meter reading 500% — the reader saved everything they earned
    /// by logging nothing. The archive's own empty state, where no month has closed at all, is the one place in
    /// this tab that genuinely is `LoadState.empty` (`ReportsViewModelTests`).
    @Test("a month with nothing logged is a report rather than an empty state")
    func aQuietMonthIsLoaded() async throws {
        let viewModel = Self.makeViewModel(
            FixtureTransport(
                stubs: [Endpoint.screenReportsMonth(monthKey: "2025-11"): try .ok(.reportsMonthQuiet)]
            ),
            monthKey: "2025-11"
        )

        try await viewModel.load()

        let screen = try #require(viewModel.state.value)
        #expect(viewModel.state != .empty)
        #expect(!viewModel.isEmpty(screen))
        // The two things that make it the empty *treatment* rather than the empty state: no slices to draw a ring
        // from, and every panel with nothing in it.
        #expect(screen.spending.categories.isEmpty)
        #expect(screen.groups.count == 7)
        #expect(screen.groups.allSatisfy { $0.entries.isEmpty })
        // And it is still a report: a verdict, a goal, and a surplus.
        #expect(screen.verdict == .hit)
        #expect(screen.savings.surplus != nil)
        #expect(screen.savings.remaining == nil)
    }

    // MARK: - Presentation state

    /// Tapping a slice isolates it; tapping it again returns to the whole ring — the design's own
    /// `picked === i ? null : i`.
    @Test("isolating a slice toggles, and a second slice replaces the first")
    func isolatingASliceToggles() {
        let viewModel = Self.makeViewModel(FixtureTransport())

        #expect(viewModel.isolated == nil)
        viewModel.isolate("rent")
        #expect(viewModel.isolated == "rent")
        viewModel.isolate("groceries")
        #expect(viewModel.isolated == "groceries")
        viewModel.isolate("groceries")
        #expect(viewModel.isolated == nil, "tapping the isolated slice again did not clear it")
    }

    /// **One panel open at a time**, which is the design's own rule about the card rather than about a row.
    @Test("opening a panel closes whichever was open, and a second tap collapses it")
    func onePanelOpensAtATime() {
        let viewModel = Self.makeViewModel(FixtureTransport())

        #expect(viewModel.expanded == nil)
        viewModel.toggle("groceries")
        #expect(viewModel.isExpanded("groceries"))
        viewModel.toggle("transport")
        #expect(viewModel.isExpanded("transport"))
        #expect(!viewModel.isExpanded("groceries"), "two panels are open at once")
        viewModel.toggle("transport")
        #expect(viewModel.expanded == nil)
    }

    /// The category a re-read no longer carries stops being isolated, and the panel it no longer carries closes.
    ///
    /// Without it an `isolated` matching nothing dims every *other* slice, so the ring comes back uniformly faded
    /// with nothing isolated — the failure `HomeViewModel` records the same guard for.
    @Test("an isolation the new payload does not contain is dropped on the next read")
    func aStaleIsolationIsDropped() async throws {
        let viewModel = Self.makeViewModel(
            FixtureTransport(
                sequences: [Self.path: [try .ok(.reportsMonthINR), try .ok(.reportsMonthQuiet)]]
            )
        )

        try await viewModel.load()
        viewModel.isolate("rent")
        viewModel.toggle("rent")
        #expect(viewModel.isolated == "rent")

        // The quiet month has no categories at all, so the isolation cannot survive it. Its seven groups do
        // survive, which is what keeps the panel open — the groups are structural.
        try await viewModel.load()

        #expect(viewModel.isolated == nil)
        #expect(viewModel.isExpanded("rent"), "the panel closed although the group is still there")
    }

    /// And the isolated category is re-read out of the *current* payload rather than held, so it describes a slice
    /// that is on screen.
    @Test("the isolated category is looked up in the payload that is loaded")
    func theIsolatedCategoryComesFromThePayload() async throws {
        let transport = FixtureTransport(stubs: [Self.path: try .ok(.reportsMonthINR)])
        let viewModel = Self.makeViewModel(transport)
        try await viewModel.load()
        let screen = try #require(viewModel.state.value)

        #expect(viewModel.isolatedCategory(in: screen) == nil)
        viewModel.isolate("rent")
        #expect(viewModel.isolatedCategory(in: screen)?.name == "Rent")
        viewModel.isolate("nothing-like-it")
        #expect(viewModel.isolatedCategory(in: screen) == nil)
    }

    // MARK: - What the client refuses

    /// **A fifth split portion fails the screen rather than being drawn as something else.**
    ///
    /// The four are §4.2's, and they add up to the income printed beside them. A fifth rendered as one the client
    /// happened to recognise would be a bar whose parts no longer sum to that figure, about a month that cannot be
    /// corrected (invariant 7) — so it is a coordinated release, exactly as an unknown ``ReportsScreen/Verdict`` is.
    @Test("a split portion the client does not recognise fails the screen")
    func anUnknownPortionFailsTheScreen() async throws {
        var payload = try Self.mutablePayload()
        var split = try #require(payload["split"] as? [String: Any])
        var segments = try #require(split["segments"] as? [[String: Any]])
        segments[3]["portion"] = "leftUnspent"
        split["segments"] = segments
        payload["split"] = split

        let viewModel = Self.makeViewModel(FixtureTransport(stubs: [Self.path: try .json(payload)]))

        try await viewModel.load()

        #expect(viewModel.state.value == nil)
        #expect(viewModel.state.isFailed)
    }

    /// **And a split with a part *missing* fails too**, which is the half `Portion` cannot see: three segments
    /// decode perfectly well and draw a bar that does not add up to the income printed beside it.
    @Test("a split that is not the four portions fails the screen", arguments: [
        // One part dropped, and the four shuffled — the order is the rule's, not a preference.
        [0, 1, 2], [3, 2, 1, 0], [0, 1, 2, 3, 3],
    ])
    func anIncompleteSplitFailsTheScreen(_ order: [Int]) async throws {
        var payload = try Self.mutablePayload()
        var split = try #require(payload["split"] as? [String: Any])
        let segments = try #require(split["segments"] as? [[String: Any]])
        split["segments"] = order.map { segments[$0] }
        payload["split"] = split

        let viewModel = Self.makeViewModel(FixtureTransport(stubs: [Self.path: try .json(payload)]))

        try await viewModel.load()

        #expect(viewModel.state.value == nil, "\(order) was drawn as a split bar")
        #expect(viewModel.state.isFailed)
    }

    /// And the four in their own order decode, or the assertion above would pass on anything.
    @Test("the four portions in the rule's order decode")
    func theFourPortionsDecode() async throws {
        let screen = try await Self.loaded()

        #expect(screen.split.segments.map(\.portion) == ReportsMonthScreen.Portion.allCases)
    }

    /// **A fact whose kind the client does not know is dropped, and only that fact.**
    ///
    /// The grid is a set of tiles and the label is the app's, so a seventh kind has no words to draw itself with.
    /// Losing one tile is additive; failing the month over an extra figure nobody asked for would take a whole
    /// immutable record away.
    @Test("a fact the client does not recognise is dropped and the rest of the month is drawn")
    func anUnknownFactIsDropped() async throws {
        var payload = try Self.mutablePayload()
        var facts = try #require(payload["facts"] as? [[String: Any]])
        let known = facts.count
        facts.append(["kind": "carbonFootprint", "value": "12 kg"])
        payload["facts"] = facts

        let viewModel = Self.makeViewModel(FixtureTransport(stubs: [Self.path: try .json(payload)]))

        try await viewModel.load()

        let screen = try #require(viewModel.state.value)
        #expect(screen.facts.count == known, "the unknown fact reached the grid")
        #expect(screen.facts.map(\.kind).contains(.salary))
    }

    /// And drift in a monetary figure reaches this screen as a failure rather than as a blank total — the same
    /// `Money` guard three levels down (ADR-0003).
    @Test("a blank display string on a segment's amount fails the screen")
    func driftFailsTheScreen() async throws {
        var payload = try Self.mutablePayload()
        var split = try #require(payload["split"] as? [String: Any])
        var segments = try #require(split["segments"] as? [[String: Any]])
        var amount = try #require(segments[0]["amount"] as? [String: Any])
        amount["display"] = ""
        segments[0]["amount"] = amount
        split["segments"] = segments
        payload["split"] = split

        let viewModel = Self.makeViewModel(FixtureTransport(stubs: [Self.path: try .json(payload)]))

        try await viewModel.load()

        #expect(viewModel.state.isFailed)
    }

    /// February's payload as a dictionary a test can change one field of.
    private static func mutablePayload() throws -> [String: Any] {
        try #require(
            try JSONSerialization.jsonObject(with: TestBench.payload(.reportsMonthINR)) as? [String: Any]
        )
    }
}

extension FixtureTransport.Outcome {
    /// A `200` carrying a payload a test assembled, for the cases that change one field of a fixture.
    static func json(_ payload: [String: Any]) throws -> FixtureTransport.Outcome {
        .response(status: 200, body: try JSONSerialization.data(withJSONObject: payload))
    }
}
