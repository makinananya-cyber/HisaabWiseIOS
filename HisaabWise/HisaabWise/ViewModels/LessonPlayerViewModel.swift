import Foundation
import Observation

/// The lesson player: **the run, and the two things a run can become** — an exhausted set of hearts, or a
/// completion (#20).
///
/// **It is not a `BaseViewModel`, because it makes no read.** The lesson's steps arrived with the curriculum and
/// the reader's state arrived with the Learn screen; the player is handed both and needs nothing else, so there is
/// no `LoadState` for it to draw — the same reason `LandingViewModel` is not a conformance. What *does* have a
/// `LoadState` is the completion, because submitting the lesson is a request that can fail
/// (``LessonCompletionViewModel``).
///
/// **What it owns is a run and a presentation, and nothing else.** The grading is ``LessonRun``'s, which is a value
/// with no transport in it; the writing is one method here and one object beside it. Not one figure the reader reads
/// is worked out in this file.
///
/// **It keeps its own copy of the lesson, deliberately** — the opposite of the guide sheet, which holds a unit *id*
/// and re-reads it from the current payload so a reload writes through (ADR-0020). A run is not a view of server
/// state: it is what the reader is doing right now, and re-reading it from each reload would restart the lesson
/// under them. So the material is taken once, at `init`, and the map behind the player may change freely.
@MainActor
@Observable
final class LessonPlayerViewModel {
    /// The unit, the lesson, and the currency token its steps need. Taken once — see above.
    let material: LearnMap.Material

    /// Where the reader is in the lesson, and how it is going.
    private(set) var run: LessonRun

    /// The celebration, once the last step is behind them. `nil` for a run still in progress.
    ///
    /// Made here rather than by the screen, so that "finishing the lesson submits it exactly once" is a property of
    /// this object: a view that constructed one in its `body` would build a new submission on every re-render.
    private(set) var completion: LessonCompletionViewModel?

    /// The combo the reader has just landed, for the badge and the announcement. `nil` once it has been shown.
    ///
    /// A **value**, not a sentence — the split `ExpensesViewModel.Notice` draws: the number is this object's and the
    /// words are the catalogue's.
    private(set) var comboMilestone: Int?

    private let client: APIClient

    /// Where the updated Learn screen goes when the completion lands (ADR-0020). Passed straight to the completion.
    private let onScreenUpdate: (LearnScreen) -> Void

    init(
        material: LearnMap.Material,
        client: APIClient,
        onScreenUpdate: @escaping (LearnScreen) -> Void
    ) {
        self.material = material
        self.client = client
        self.onScreenUpdate = onScreenUpdate
        run = LessonRun(lessonID: material.lesson.id, steps: material.lesson.content.steps)
    }

    // MARK: - What the screen reads back

    /// **There are no pass-throughs to the run, deliberately.** The step, the hearts, the verdict, and whether the
    /// button is live are all `run`'s, and the screen reads them there — two of them were forwarded here at first,
    /// which left the view reaching past the forwarding for the other six. One owner of "what is the run doing" is
    /// worth more than the shorter call site (review found the inconsistency).
    ///
    /// `{c}` resolved against the reader's own currency (``CurrencyToken``, ADR-0016). The amounts in a lesson are
    /// illustrative and are never converted — only the symbol follows the account.
    func resolved(_ text: String) -> String { material.currencyToken.resolve(text) }

    // MARK: - What the reader does

    /// Picks an option — replacing on a single-choice question, toggling on a multi-select. The run knows which.
    func choose(_ option: Int) {
        run.choose(option)
    }

    /// What the reader has typed into a numeric question's box, or an empty string on any other step.
    var typedAnswer: String {
        if case .typed(let text) = run.answer { return text }
        return ""
    }

    /// What the reader has typed into a numeric question's box, **reduced to what a figure may contain**.
    ///
    /// The design does the same as the box is typed into (`replace(/[^0-9.]/g, '')`), and it is local input
    /// validation rather than a calculation (ADR-0020): it decides what may be in the box, not what any figure is.
    /// Both separators survive, because a `.decimalPad` offers the *device region's* and a comma may be the decimal
    /// point (``TypedAmount``) — and every digit script survives, because a reader typing Arabic-Indic digits has
    /// typed a figure.
    func type(_ text: String) {
        run.type(text.filter { $0.isNumber || $0 == "." || $0 == "," })
    }

    /// **The one button.** The design has a single primary control whose job changes with the step: `Continue` on a
    /// teaching page, `Check` on an open question, and `Continue` / `Got it` once a question has been graded.
    ///
    /// One method for all three, because the run already knows which state it is in — and two methods would let a
    /// screen call the wrong one.
    func primaryAction() {
        guard run.isReadyToCheck else { return }

        if run.step?.isQuestion == true, run.verdict == nil {
            run.check()
            comboMilestone = run.verdict?.comboMilestone
            return
        }

        run.advance()
        if run.isFinished { finish() }
    }

    /// **Try again** from the out-of-hearts dialog: the same lesson, from the top, with three hearts.
    ///
    /// A fresh ``LessonRun`` rather than a reset of the old one, so there is no partial state to forget to clear —
    /// and the results of the abandoned attempt go with it, which is right: they were never submitted, and a run
    /// that ended on an empty heart has no completion to file.
    func restart() {
        run = LessonRun(lessonID: material.lesson.id, steps: material.lesson.content.steps)
        comboMilestone = nil
    }

    func dismissCombo() { comboMilestone = nil }

    /// The combo just landed, as the badge draws it. Empty when there is none, which is a badge at zero opacity.
    ///
    /// Spelled here rather than at the call site, for ``LessonRun/stepNumberText``'s reason: a number is converted
    /// where it is computed, because the localisation scan cannot know that `\(anInt)` resolves to `%lld`.
    var comboMilestoneText: String { comboMilestone.map(String.init) ?? "" }

    // MARK: - Finishing

    /// Builds the completion, which submits itself when the screen appears.
    ///
    /// The submission is *not* started here: it is the completion screen's own load, so the four states it can
    /// land in are the shared ones and the retry is the chrome's (``LessonCompletionViewModel``). A run finished
    /// with no connection therefore shows an offline celebration screen with a **Try again** on it, and nothing is
    /// queued (ADR-0019).
    private func finish() {
        guard completion == nil else { return }
        completion = LessonCompletionViewModel(
            lessonID: run.lessonID,
            results: run.results,
            client: client,
            onScreenUpdate: onScreenUpdate
        )
    }
}
