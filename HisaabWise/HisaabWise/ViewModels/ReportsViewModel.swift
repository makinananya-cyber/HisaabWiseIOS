import Observation

/// Reports: **one request, and nothing derived from it** (ADR-0020).
///
/// `GET /v1/screens/reports` carries the archive already grouped by year with each year's savings total, and the
/// trend chart's bars with their heights, their percentages, and their verdicts. The prototype derived every one
/// of those at render time from a single `ARCHIVE` array — six category sums per month, a mean across the six
/// months, a reduction per year group, and a division followed by a threshold for the verdict.
///
/// **The threshold is the one that matters.** Defect D11 is two tables for one pill: Reports thresholded at
/// 100/70 and Home at 80/45, over the same number. §4.2 settles it server-side, and the client's half of that
/// settlement is arithmetic it does not have — there is no `saved`, no `goal`, and no percentage as a number in
/// the payload to threshold.
///
/// **So this object owns no presentation state at all**, which is why it is the shortest view model in the app.
/// Home holds an isolated slice and a substituted tip; Expenses holds a draft; Learn holds a run. An archive is
/// a record: there is nothing to choose about it and nothing to type into it. The month a reader opens is #22's,
/// and it is a *pushed screen* rather than a selection this object would have to remember.
@MainActor
@Observable
final class ReportsViewModel: BaseViewModel {
    /// Not `private(set)`: ``BaseViewModel`` requires a settable `state`, and the trade-off is recorded there.
    /// Mutation stays inside `load()` by convention.
    var state: LoadState<ReportsScreen> = .loading

    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    /// **The single request.** No second call, no join, and no `Date()` — the client owns no calendar with which
    /// to name a month or decide which ones have closed.
    func fetch() async throws -> ReportsScreen {
        try await client.get(Endpoint.screenReports, as: ReportsScreen.self)
    }

    /// Whether a *loaded* archive has nothing in it.
    ///
    /// **`true` when no month has closed, and this is the screen where that is right** — the one place in the
    /// app where an empty payload really is `LoadState.empty`. Home's first run is not: it keeps a savings meter,
    /// a tip, a streak, and three articles, so the empty treatment lives inside one card there. An archive with
    /// no months has no hero worth drawing — no average of nothing, no trend through no points, and a goal line
    /// across an empty plot — so the whole screen is one sentence.
    ///
    /// Reading `years.isEmpty` is not the client inferring a state the server should have sent: unlike Home's
    /// `isFirstRun`, "no months have closed" has one meaning however the reader got there, and `isEmpty(_:)` is
    /// the base contract's own hook for exactly this question.
    /// **`false`, always** — see ``ReportsView/stateCopy``.
    ///
    /// "No month has closed yet" is a true thing about the archive, not a reason to replace the screen: the tab
    /// keeps its heading and the page draws the sentence where the months would be. The emptiness is still read,
    /// one layer up, from the same `screen.years` this used to test.
    func isEmpty(_ screen: ReportsScreen) -> Bool { false }

    /// A view model for one closed month, made from the row that was tapped (#22).
    ///
    /// Made **here** rather than at the composition root, for the reason `HomeViewModel.articleViewModel(for:)`
    /// is: it is per-tap and holds nothing worth keeping between taps. This object has the client, and
    /// `LayeringTests` keeps the client out of `Views/` — so a method on the view model is the only place a
    /// screen can get one from.
    ///
    /// It takes the **month key** rather than the row, because the key is the detail's address and the row
    /// carries nothing the detail's own payload does not (ADR-0037).
    func monthViewModel(monthKey: String) -> ReportsMonthViewModel {
        ReportsMonthViewModel(monthKey: monthKey, client: client)
    }
}
