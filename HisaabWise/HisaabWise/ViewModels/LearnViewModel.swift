import Foundation
import Observation

/// Learn's unit map: **two reads, one state, and nothing derived from either** (ADR-0020, ADR-0034).
///
/// It is the first `BaseViewModel` whose one `fetch()` makes two requests, and that is invariant 8 deciding where
/// the seam goes rather than an exception to ADR-0020. The curriculum is the same 100 KB for every reader and is
/// stored on disk with an ETag (``ContentResource/curriculum``); the progress through it is per-user and bypasses
/// every cache. Neither can be folded into the other without breaking one of those rules, so `fetch()` asks for
/// both — **concurrently**, because they are independent — and hands back the join as one ``LearnMap``.
///
/// **It maps no `APIError`.** There is no write on this screen yet, so the whole taxonomy is
/// `BaseViewModel.load()`'s, and `StateTaxonomyTests` does not name this file. Completing a lesson is #20's write
/// and is where that changes.
///
/// **It owns no clock.** The streak, the XP, and every unlock arrive as values from a payload that carries no date
/// at all (invariant 6, ``LearnScreen``) — so there is nothing here for a device-clock change to move, and
/// `LearnViewModelTests` asserts the absence rather than describing it.
@MainActor
@Observable
final class LearnViewModel: BaseViewModel {
    /// Not `private(set)`: ``BaseViewModel`` requires a settable `state`, and the trade-off is recorded there.
    /// Mutation stays inside `load()` by convention.
    var state: LoadState<LearnMap> = .loading

    // MARK: - What the screen is showing

    /// Which unit's guide sheet is open, as an **id** rather than the unit itself.
    ///
    /// The same rule `ExpenseCategoryView` follows: a sheet holding the value it was opened with keeps showing
    /// that value after a reload underneath it, so it holds the id and re-reads the unit from whatever payload is
    /// current (ADR-0020).
    private(set) var openGuideUnitID: String?

    /// What just happened, for the toast. `nil` once it has been shown.
    ///
    /// A **value**, not a sentence: the choice is this object's and the words are the catalogue's, which is the
    /// split `ExpensesViewModel.Notice` draws for the same reason.
    private(set) var notice: Notice?

    private let client: APIClient

    /// Where the curriculum comes from — the store, the ETag, and the offline fallback all in one place
    /// (``ContentLoader``, ADR-0009).
    private let content: ContentLoader

    init(client: APIClient, content: ContentLoader) {
        self.client = client
        self.content = content
    }

    /// **The two reads, run at once.**
    ///
    /// Concurrently rather than in sequence because neither answer feeds the other's request: the curriculum is
    /// asked for by name and the screen by session, so serialising them would cost a round trip for nothing.
    ///
    /// **Either failing fails the screen**, and that is the honest outcome rather than a partial map. A curriculum
    /// with no progress cannot say which lessons are open — it would have to guess, and the guess is what
    /// invariant 10 gives the server. Progress with no curriculum is fifteen ids and no titles. The one asymmetry
    /// is already inside `ContentLoader`: a stored curriculum is served offline, so a reader who has opened Learn
    /// before fails on the *screen* half only, which is the half that is genuinely per-user (ADR-0019).
    func fetch() async throws -> LearnMap {
        async let curriculum = content.load(.curriculum, as: Curriculum.self)
        async let progress = client.get(Endpoint.screenLearn, as: LearnScreen.self)

        return LearnMap(curriculum: try await curriculum, progress: try await progress)
    }

    /// Whether a *loaded* Learn has nothing to show.
    ///
    /// A curriculum with no units is `.empty` rather than `.loaded`, for `ArticleViewModel`'s reason: a stats bar
    /// over white space looks broken in a way the empty state does not. It is not reachable from the corpus —
    /// there are always five units — which is exactly why it is worth saying: the alternative is a screen that
    /// draws the failure of a content deployment as a working screen.
    func isEmpty(_ map: LearnMap) -> Bool { map.units.isEmpty }

    // MARK: - What the screen reads back

    /// Whether the guide sheet is up.
    ///
    /// **The id, not the resolved unit**, and the distinction is a bug review found: a sheet presented off
    /// ``openGuideUnit`` flips to hidden when a reload drops that unit, without any dismissal writing through — so
    /// the id stays set and the sheet re-presents itself when the unit comes back. Presentation follows the thing
    /// a dismissal clears.
    var isShowingGuide: Bool { openGuideUnitID != nil }

    /// The unit whose guide sheet is open, read out of the **current** payload. `nil` when no sheet is open, and
    /// also when a reload has dropped the unit under an open one — which the screen answers by closing it.
    var openGuideUnit: LearnMap.Unit? {
        openGuideUnitID.flatMap { state.value?.unit(id: $0) }
    }

    // MARK: - What the reader does

    /// Opens a unit's guide sheet — the design's `.unit-guide` button.
    func openGuide(unitID: String) {
        // The design's `hushToast()`: the sheet covers the toast, so leaving one behind would have it reappear
        // from under a panel the reader has just dismissed.
        notice = nil
        openGuideUnitID = unitID
    }

    func closeGuide() {
        openGuideUnitID = nil
    }

    /// What pressing a **locked** node does: says why, and nothing else.
    ///
    /// The design's own behaviour — `say('Finish the lesson before it to unlock this one.')`. It is the client
    /// *rendering* the lock; the server is what enforces it, so this refusal costs nothing if the two ever
    /// disagree, and a reader who has earned the lesson gets it from the next reload rather than from the client
    /// changing its mind.
    func refuseLockedLesson() {
        notice = .lessonLocked
    }

    func dismissNotice() { notice = nil }
}

// MARK: - The values it owns

extension LearnViewModel {
    /// What just happened, for the toast. The words are the screen's; the choice is this object's.
    ///
    /// One case today. It is an enum rather than a `Bool` because #20 brings the rest of the design's toasts —
    /// a lesson completed, a streak extended — and a `Bool` would have to become one anyway.
    enum Notice: Sendable, Equatable, CaseIterable {
        /// A locked node was pressed.
        case lessonLocked
    }
}
