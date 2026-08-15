import Observation

/// Home: **one request, and nothing derived from it** (ADR-0020).
///
/// It used to read `GET /v1/budget` and render one figure. It now reads `GET /v1/screens/home`, which carries the
/// spending split, the savings meter, the selected tip, the streak, and the article teasers — all computed. The
/// migration is the point rather than a tidy-up: a screen that fetched the budget, the tips, the streak, and the
/// article list would compose four responses, and composing is one step from calculating. Defects D1, D10, D11,
/// and D16 all happened that way.
///
/// **What this object owns is presentation state, and there is exactly this much of it:** which slice is
/// isolated, and which tip is showing. Neither is a figure.
@MainActor
@Observable
final class HomeViewModel: BaseViewModel {
    /// Not `private(set)`: ``BaseViewModel`` requires a settable `state`, and the trade-off is recorded there.
    /// Mutation stays inside `load()` by convention.
    var state: LoadState<HomeScreen> = .loading

    /// The isolated slice's id, or `nil` for the whole ring.
    ///
    /// An **id** rather than an index, so it survives a refresh: a reload that returns the categories in a
    /// different order would otherwise move the isolation to a different category without the user touching
    /// anything.
    private(set) var isolated: String?

    /// The tip currently on screen, or `nil` while it is the day's own.
    ///
    /// **The day's tip is the server's and the cycling is the client's**, and this property is the seam between
    /// them. `nil` means "show what the payload selected"; anything else is a tip the user asked for by pressing
    /// **Show me another**.
    ///
    /// **In memory, and it resets next launch** (ADR-0016). Persisting it would make "show me another" a
    /// preference, and tomorrow's tip is the server's to choose.
    private(set) var substitutedTip: TipList.Tip?

    /// The pool, once it has been fetched. Cacheable content, so a second launch reads it from the store with an
    /// ETag rather than downloading 49 tips again (ADR-0009).
    private var pool: [TipList.Tip] = []

    private let client: APIClient

    /// Where the tip pool comes from. The **only** other thing Home reads, and it is not part of the screen: ADR-
    /// 0020 keeps cacheable content out of per-user payloads, so "one request per screen" and "the pool is a
    /// separate ETag'd resource" are the same decision rather than an exception to it.
    private let content: ContentLoader

    /// Whether the reader has waved away the savings-goal suggestion.
    ///
    /// **In memory, and it resets next launch**, for the same reason the substituted tip is: this is "not right
    /// now", not a stored preference. The server will offer the suggestion again while the drift is still there,
    /// which is the honest behaviour — the goal really is behind their pay until one of the two moves.
    private(set) var hasDismissedGoalNudge = false

    /// True while `PUT /v1/me/goal` is in flight.
    private(set) var isRaisingGoal = false

    init(client: APIClient, content: ContentLoader) {
        self.client = client
        self.content = content
    }

    /// Takes the suggested savings goal — `PUT /v1/me/goal`.
    ///
    /// **The figure comes from the payload, not from arithmetic here.** The client is handed the amount the server
    /// would pick and sends that same amount back; computing a fifth of the salary locally would make the client a
    /// second owner of a rule the budget engine owns (invariant 3).
    ///
    /// A failure is silent and leaves the card up: nothing has changed, the suggestion is still true, and the reader
    /// can press it again. There is no queue (ADR-0019) and nothing here worth replacing the screen over.
    func raiseGoal(to suggested: Money) async {
        guard !isRaisingGoal else { return }
        isRaisingGoal = true
        defer { isRaisingGoal = false }

        let body = SavingsGoalUpdate(
            savingsGoal: MoneyAmount(minor: suggested.minor, currency: suggested.currency.rawValue)
        )
        guard (try? await client.put(Endpoint.goal, body: body, as: AccountScreen.self)) != nil else { return }

        // The goal is on every card that mentions it, so the screen is re-read rather than patched (ADR-0020).
        try? await load()
    }

    func dismissGoalNudge() {
        hasDismissedGoalNudge = true
    }

    /// **The single request.** No second call, no join, no `Date()`.
    func fetch() async throws -> HomeScreen {
        let screen = try await client.get(Endpoint.screenHome, as: HomeScreen.self)
        // **An isolation the new payload does not contain is dropped**, as the design's `render()` resets
        // `picked`. Keeping it dimmed every *other* slice — `isolated == slice.id` matching nothing — so the ring
        // came back uniformly faded with nothing isolated and no way out but tapping a slice.
        if let isolated, !screen.spending.categories.contains(where: { $0.id == isolated }) {
            self.isolated = nil
        }
        return screen
    }

    /// Whether a *loaded* Home has nothing to show.
    ///
    /// `false`, deliberately, and this is the one screen where that needs saying. A first-run month is **not**
    /// `LoadState.empty`: the screen has a savings meter, a tip, a streak, and three articles to draw, and only
    /// the donut has nothing in it. Routing it through `.empty` would replace the whole screen with one sentence
    /// — the design puts the grey ring and the CTA *inside* the spending card and keeps the rest.
    ///
    /// `spending.isFirstRun` is what the card reads.
    func isEmpty(_ screen: HomeScreen) -> Bool { false }

    // MARK: - Isolating a slice

    /// Taps a slice or a key row. Tapping the isolated one again returns to the whole ring, which is the
    /// design's own `picked === i ? null : i`.
    func isolate(_ id: String?) {
        isolated = (isolated == id) ? nil : id
    }

    /// The category the centre readout describes, or `nil` for the total.
    ///
    /// It re-reads the id out of the *current* payload rather than holding the category, so a refresh that drops
    /// a category leaves the ring whole instead of showing a slice that is no longer there.
    func isolatedCategory(in screen: HomeScreen) -> HomeScreen.Category? {
        guard let isolated else { return nil }
        return screen.spending.categories.first { $0.id == isolated }
    }

    // MARK: - Another tip

    /// **Show me another** — the next tip in the pool, in memory.
    ///
    /// The pool is fetched on the **first** press rather than with the screen: Home paints from one request, and
    /// 49 tips nobody may ask for is not worth a second one at load time. Afterwards every press is local, which
    /// is what ADR-0016 means by cycling in memory.
    ///
    /// It advances from whatever is showing — the day's tip first, then each substitute — and wraps, so the
    /// control keeps working past the end of the list. A pool that will not load leaves the day's tip on screen
    /// and reports nothing: the tip is a nicety, and a failed *nicety* must not replace a screen that is fine
    /// (which is why this does not go through `load()`).
    func showAnotherTip(after current: HomeScreen.Tip) async {
        if pool.isEmpty {
            pool = (try? await content.load(.tips, as: TipList.self))?.tips ?? []
        }
        guard !pool.isEmpty else { return }

        let showing = substitutedTip?.id ?? current.id
        let next = pool.firstIndex { $0.id == showing }.map { ($0 + 1) % pool.count } ?? 0
        substitutedTip = pool[next]
    }

    /// A view model for one article, made from its teaser.
    ///
    /// Made **here** rather than at the composition root, for the reason a registration form is made there and
    /// not here: this one is per-*tap*, and it holds nothing worth keeping between taps. Home has the teaser and
    /// the content loader, so Home is the only thing that can build it — and `LayeringTests` keeps the loader out
    /// of `Views/`, which is why this is a method on the view model rather than a closure the screen holds.
    func articleViewModel(for teaser: HomeScreen.ArticleTeaser) -> ArticleViewModel {
        ArticleViewModel(id: teaser.id, content: content)
    }

    /// What the tip card draws: the substitute if the user asked for one, otherwise the day's.
    ///
    /// The **currency token travels with the day's tip**, not with the pool entry — the pool is cacheable and
    /// therefore identical for everybody, so it cannot carry one user's currency. Substituting a pool tip means
    /// keeping the payload's token and swapping the text, which is exactly what this returns.
    func tip(in screen: HomeScreen) -> HomeScreen.Tip {
        guard let substitutedTip else { return screen.tip }
        return HomeScreen.Tip(
            id: substitutedTip.id,
            dayKey: screen.tip.dayKey,
            text: substitutedTip.text,
            currencyToken: screen.tip.currencyToken
        )
    }
}
