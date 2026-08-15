import Foundation
@testable import HisaabWise
import Testing

/// Reports reads **one endpoint and derives nothing from it** (ADR-0020, ADR-0036).
///
/// The two claims worth asserting here are the ones this screen exists to keep. **The verdict is the server's**
/// — defect D11 is two threshold tables over one number, so the test is not "the client thresholds correctly"
/// but that it *cannot*: the payload carries no `saved`, no `goal`, and no percentage as a number. And **the
/// empty archive is `LoadState.empty`**, which makes this the first screen in the app whose `isEmpty(_:)` says
/// yes.
///
/// **The `LoadState` mapping itself is not asserted here.** It lives in ``BaseViewModel/load()`` and is asserted
/// in `BaseViewModelTests` — one owner, one suite. What is asserted here is what this object adds.
@Suite("ReportsViewModel")
@MainActor
struct ReportsViewModelTests {
    private static func makeViewModel(_ transport: FixtureTransport) -> ReportsViewModel {
        ReportsViewModel(client: TestBench.client(transport))
    }

    private static func loaded(_ fixture: Fixture = .reportsINR) async throws -> ReportsScreen {
        let viewModel = makeViewModel(FixtureTransport(stubs: [Endpoint.screenReports: try .ok(fixture)]))
        try await viewModel.load()
        return try #require(viewModel.state.value)
    }

    @Test("starts loading, before anything has been asked for")
    func startsLoading() {
        #expect(Self.makeViewModel(FixtureTransport()).state == .loading)
    }

    // MARK: - One read, and only one

    /// **The single request, asserted as a count.** An archive assembled from a month at a time would be one
    /// round trip per closed month, and the client would then be joining them.
    @Test("asks for the screen once, and asks for nothing else")
    func asksForTheScreenOnce() async throws {
        let transport = FixtureTransport(stubs: [Endpoint.screenReports: try .ok(.reportsINR)])
        let viewModel = Self.makeViewModel(transport)

        try await viewModel.load()

        #expect(await transport.requestCount(for: Endpoint.screenReports) == 1)
        #expect(await transport.recordedRequests.count == 1)
    }

    /// Per-user data, so it bypasses every cache — invariant 8 as a property of the request rather than as a
    /// sentence in a document. An archive is somebody's financial history; a cache HIT on it is a breach.
    @Test("the archive is a per-user read and is never left to a URL cache")
    func theArchiveBypassesEveryCache() async throws {
        let transport = FixtureTransport(stubs: [Endpoint.screenReports: try .ok(.reportsINR)])
        _ = try await Self.makeViewModel(transport).load()

        let request = try #require(await transport.recordedRequests.first)
        #expect(request.path == Endpoint.screenReports)
        #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
    }

    /// Offline is offline rather than a fault — the taxonomy's rule, at this screen's one request.
    @Test("no connection is offline, not a failure")
    func offlineIsNotAFailure() async throws {
        let viewModel = Self.makeViewModel(FixtureTransport(stubs: [Endpoint.screenReports: .notConnected]))

        try await viewModel.load()

        #expect(viewModel.state == .offline)
        #expect(viewModel.state.value == nil)
    }

    /// A `501` — what every screen endpoint answers with until the backend has written it — is a **failure** and
    /// not an absence, which is the state this screen was built against.
    @Test("a 501 from the screen endpoint is a failed state")
    func aNotImplementedScreenIsFailed() async throws {
        let viewModel = Self.makeViewModel(
            FixtureTransport(stubs: [Endpoint.screenReports: .response(status: 501, body: Data())])
        )

        try await viewModel.load()

        #expect(viewModel.state.isFailed)
    }

    // MARK: - The empty archive

    /// **The first `LoadState.empty` the app can actually reach.**
    ///
    /// An archive with no closed months has no hero worth drawing — no mean of nothing, no trend through no
    /// points — so the whole screen is one sentence. Unlike Home's first run, which keeps four of its five cards
    /// and puts the empty treatment inside the fifth.
    @Test("an archive with no closed months stays loaded, and the page says it is empty")
    func anArchiveWithNoClosedMonthsStaysLoaded() async throws {
        // **Not `LoadState.empty`.** `StateView` replaces the whole screen, which took the eyebrow and the title
        // with it — the tab a reader had just chosen came back with no name on it. `ReportsArchivePage` keeps the
        // chrome and draws the sentence where the months would be, so the emptiness is read one layer up from
        // the same `years` this used to test (``ReportsView/stateCopy``).
        let transport = FixtureTransport(stubs: [Endpoint.screenReports: try .ok(.reportsEmpty)])
        let viewModel = ReportsViewModel(client: TestBench.client(transport))

        try await viewModel.load()

        #expect(viewModel.state.value?.years.isEmpty == true)
        #expect(viewModel.isEmpty(try #require(viewModel.state.value)) == false)
    }

    /// And a populated one is not, which is the half that would go silently wrong if `isEmpty` were inverted or
    /// keyed on the wrong field.
    @Test("an archive with months in it is loaded", arguments: [Fixture.reportsINR, .reportsTwoYears])
    func aPopulatedArchiveIsLoaded(_ fixture: Fixture) async throws {
        let viewModel = Self.makeViewModel(FixtureTransport(stubs: [Endpoint.screenReports: try .ok(fixture)]))

        try await viewModel.load()

        #expect(viewModel.state.value != nil)
        #expect(viewModel.state != .empty)
    }

    // MARK: - Defect D11 — the client cannot threshold

    /// **The verdict is rendered verbatim, hit / near / miss, in the order the payload sends them.**
    ///
    /// Stated as the whole sequence rather than as three lookups: a client that had gone back to thresholding
    /// would agree with the server about most months and disagree about the ones near a boundary, which is
    /// exactly what a spot check of one month would miss.
    @Test("the screen renders the payload's verdicts, in order and unchanged")
    func theVerdictsAreThePayloads() async throws {
        let screen = try await Self.loaded()

        #expect(screen.allMonths.map(\.verdict) == [.miss, .hit, .near, .hit, .miss, .near])
        #expect(screen.trend.bars.map(\.verdict) == [.near, .miss, .hit, .near, .hit, .miss])
    }

    /// **And there is nothing in the payload to threshold with**, which is the stronger claim: no `saved`, no
    /// `goal`, and no percentage as a number reaches the client, in any month or any bar.
    ///
    /// Asserted against the **wire** rather than against the decoded type, because that is where it could come
    /// back: a `Decodable` ignores keys it does not name, so a server that started sending `saved` per month
    /// would be invisible to a test that only read `ReportsScreen`. This is the D11 regression test, and it is
    /// the same shape as `MoneyFormattingAbsenceTests` — a rule enforced by absence.
    @Test("no month and no bar carries a figure the client could threshold", arguments: [
        Fixture.reportsINR, .reportsTwoYears,
    ])
    func thePayloadCarriesNothingToThreshold(_ fixture: Fixture) throws {
        let payload = try #require(
            try JSONSerialization.jsonObject(with: TestBench.payload(fixture)) as? [String: Any]
        )
        let years = try #require(payload["years"] as? [[String: Any]])
        let bars = try #require((payload["trend"] as? [String: Any])?["bars"] as? [[String: Any]])
        let summary = try #require(payload["summary"] as? [String: Any])

        // The hero too, which the first version of this test left out and review caught. Exact keys rather than
        // substrings, so `totalSaved` and `goalsMetLabel` — a figure and a sentence, both legitimate — are not
        // mistaken for the `saved` and `goal` a client could divide.
        for banned in ["saved", "goal", "percent", "percentage", "salary", "income"] {
            #expect(summary[banned] == nil, "the hero carries \(banned) — the client could threshold it (D11)")
        }

        // A percentage as a *sentence* is what a screen draws; a percentage as a number is what a screen would
        // threshold. Only the first is on the wire.
        for month in years.flatMap({ ($0["months"] as? [[String: Any]]) ?? [] }) {
            for banned in ["saved", "goal", "percent", "percentage", "salary", "income"] {
                #expect(month[banned] == nil, "a month carries \(banned) — the client could threshold it (D11)")
            }
            #expect(month["percentageLabel"] is String)
        }
        for bar in bars {
            for banned in ["saved", "goal", "percent", "percentage"] {
                #expect(bar[banned] == nil, "a bar carries \(banned) — the client could threshold it (D11)")
            }
        }
    }

    /// The grouping and both orderings arrive from the server, and this object does not touch them.
    ///
    /// `allMonths` is the only thing on the payload that walks the nesting, and what it is asserted to be is a
    /// **flattening** — the months in exactly the order the groups hold them, with nothing sorted, merged, or
    /// re-totalled on the way through.
    @Test("the grouping and the ordering are the payload's, and flattening changes neither")
    func theGroupingIsThePayloads() async throws {
        let screen = try await Self.loaded(.reportsTwoYears)

        #expect(screen.years.map(\.label) == ["2026", "2025"])
        #expect(screen.allMonths.map(\.monthKey) == ["2026-02", "2026-01", "2025-12"])
        #expect(screen.years.flatMap { $0.months.map(\.monthKey) } == screen.allMonths.map(\.monthKey))
    }

    // MARK: - A verdict the client has not agreed to

    /// **An unrecognised verdict fails the screen rather than degrading**, which is the one decision
    /// ``ReportsScreen/Verdict`` makes and the opposite of Home's.
    ///
    /// Home's pill describes a month still running, so an unknown verdict reading as "on track" is a hedge about
    /// something that has not happened. This describes a month that has closed and is immutable (invariant 7): a
    /// fourth verdict drawn as `near` would tell a reader that a month they smashed or missed outright nearly
    /// hit its goal, and it would keep saying so for ever.
    @Test("a verdict the client does not recognise fails the screen")
    func anUnknownVerdictFailsTheScreen() async throws {
        var payload = try #require(
            try JSONSerialization.jsonObject(with: TestBench.payload(.reportsINR)) as? [String: Any]
        )
        var years = try #require(payload["years"] as? [[String: Any]])
        var months = try #require(years[0]["months"] as? [[String: Any]])
        months[0]["verdict"] = "exceeded"
        years[0]["months"] = months
        payload["years"] = years

        let viewModel = Self.makeViewModel(
            FixtureTransport(stubs: [
                Endpoint.screenReports: .response(
                    status: 200,
                    body: try JSONSerialization.data(withJSONObject: payload)
                ),
            ])
        )

        try await viewModel.load()

        #expect(viewModel.state.value == nil)
        #expect(viewModel.state.isFailed)
    }

    /// And drift in a monetary figure reaches this screen as a failure rather than as a blank total — the same
    /// `Money` guard three levels down (ADR-0003).
    @Test("a blank display string on a year's total fails the screen")
    func driftFailsTheScreen() async throws {
        var payload = try #require(
            try JSONSerialization.jsonObject(with: TestBench.payload(.reportsINR)) as? [String: Any]
        )
        var years = try #require(payload["years"] as? [[String: Any]])
        var total = try #require(years[0]["totalSaved"] as? [String: Any])
        total["display"] = ""
        years[0]["totalSaved"] = total
        payload["years"] = years

        let viewModel = Self.makeViewModel(
            FixtureTransport(stubs: [
                Endpoint.screenReports: .response(
                    status: 200,
                    body: try JSONSerialization.data(withJSONObject: payload)
                ),
            ])
        )

        try await viewModel.load()

        #expect(viewModel.state.isFailed)
    }
}
