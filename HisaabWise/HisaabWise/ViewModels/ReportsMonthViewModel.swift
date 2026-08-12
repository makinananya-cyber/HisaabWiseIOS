import Observation

/// One closed month: **one request, and nothing derived from it** (ADR-0020).
///
/// `GET /v1/screens/reports/:monthKey` carries the whole page — the totals, the donut's shares, the meter's
/// position, the wants allowance, the four split-bar segments, every logged entry with its date label, and the
/// facts grid. The prototype worked all of it out in the browser from one `ARCHIVE` literal: `budget(m)`
/// re-implemented the 50/30/20 engine, `goalPct(m)` divided saved by goal so `verdict(m)` could threshold the
/// quotient, `drawSplit()` reduced four amounts to widths, and `dayLabel(m, day)` built a date out of
/// `new Date(...)`.
///
/// **A pushed screen with its own `fetch()`**, which is `ArticleViewModel`'s shape rather than
/// `ExpenseCategoryView`'s: a month detail is not a projection of the archive payload — it is a read of its own
/// address, and the archive carries nothing about a month beyond what its row draws. So it has its own four
/// states, and a month that will not load says so on the month's own page.
///
/// **What this object owns is presentation state, and there is exactly this much of it:** which slice is
/// isolated, and which accordion panel is open. Neither is a figure. The archive's own view model owns none at
/// all, and that difference is the difference between a list and a page.
@MainActor
@Observable
final class ReportsMonthViewModel: BaseViewModel {
    /// Not `private(set)`: ``BaseViewModel`` requires a settable `state`, and the trade-off is recorded there.
    /// Mutation stays inside `load()` by convention.
    var state: LoadState<ReportsMonthScreen> = .loading

    /// Which month. **The screen's address**, taken from the archive row that was tapped — so a detail can only
    /// be opened for a month the archive listed.
    let monthKey: String

    /// The isolated slice's id, or `nil` for the whole ring.
    ///
    /// An **id** rather than an index, for `HomeViewModel.isolated`'s reason: an index would move the isolation
    /// to a different category if a re-read returned them in another order.
    private(set) var isolated: String?

    /// Which accordion panel is open, or `nil` for none.
    ///
    /// **One at a time**, which is the design's own `$$('#acc .arow.open').forEach(close)` — it keeps the card
    /// short and the choice obvious. A `String?` rather than a `Set`, so "two panels open" is not representable.
    private(set) var expanded: String?

    private let client: APIClient

    init(monthKey: String, client: APIClient) {
        self.monthKey = monthKey
        self.client = client
    }

    /// **The single request**, at this month's own address.
    ///
    /// It is also the **repaint** a currency change asks for: an archived month is immutable and carries the FX
    /// rate set pinned at close (invariant 7), so re-reading it is how the figures come back in another currency —
    /// converted through those rates, with the verdict untouched. There is no client-side conversion to do and
    /// none available to do it with.
    func fetch() async throws -> ReportsMonthScreen {
        let screen = try await client.get(
            Endpoint.screenReportsMonth(monthKey: monthKey),
            as: ReportsMonthScreen.self
        )
        // **An isolation the new payload does not contain is dropped**, as `HomeViewModel` drops one: an
        // `isolated` matching no slice dims every *other* slice, so the ring comes back uniformly faded with
        // nothing isolated.
        if let isolated, !screen.spending.categories.contains(where: { $0.id == isolated }) {
            self.isolated = nil
        }
        // The same for an open panel, which is cheaper to reason about than to leave: the seven groups are
        // structural, so this only bites if a re-read stopped carrying one.
        if let expanded, !screen.groups.contains(where: { $0.id == expanded }) {
            self.expanded = nil
        }
        return screen
    }

    /// Whether a *loaded* month has nothing to show.
    ///
    /// **`false`, and a month with nothing logged is the case that makes it worth saying.** That month still has a
    /// salary, a goal, a verdict, and a savings meter that reads 500% — the reader saved everything they earned by
    /// logging nothing, which is a report rather than an absence. Routing it through `.empty` would replace all of
    /// it with one sentence, where the archive's own empty state — no closed months at all — genuinely is one
    /// (``ReportsViewModel/isEmpty(_:)``).
    ///
    /// What the empty *treatment* covers here is narrower and lives inside the cards: the empty ring where there
    /// are no slices, and a note inside each accordion panel with nothing in it — the same narrowing `HomeView`
    /// records for its first-run donut.
    func isEmpty(_ screen: ReportsMonthScreen) -> Bool { false }

    // MARK: - Isolating a slice

    /// Taps a slice or a key row. Tapping the isolated one again returns to the whole ring, which is the design's
    /// own `picked === i ? null : i`.
    func isolate(_ id: String?) {
        isolated = (isolated == id) ? nil : id
    }

    /// The category the centre readout describes, or `nil` for the total.
    ///
    /// It re-reads the id out of the *current* payload rather than holding the category, so a re-read that drops a
    /// category leaves the ring whole instead of describing a slice that is no longer there.
    func isolatedCategory(in screen: ReportsMonthScreen) -> ReportsMonthScreen.Category? {
        guard let isolated else { return nil }
        return screen.spending.categories.first { $0.id == isolated }
    }

    // MARK: - Opening a panel

    /// Opens one accordion panel and closes whichever was open — including this one, so a second tap collapses it.
    func toggle(_ groupID: String) {
        expanded = (expanded == groupID) ? nil : groupID
    }

    /// Whether `groupID`'s panel is the open one.
    func isExpanded(_ groupID: String) -> Bool { expanded == groupID }
}
