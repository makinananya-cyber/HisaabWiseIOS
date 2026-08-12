import Foundation
import Observation

/// The celebration screen: **one write, and the screen it answers with is the screen** (ADR-0020, #20).
///
/// It is a `BaseViewModel` whose ``fetch()`` is a `POST`, which is the decision worth reading here. Every other
/// conformance reads a `GET`; this one submits the finished lesson and draws what comes back. That is not a
/// stretch of the contract — it is what the contract says: a write answers with the payload the screen renders, so
/// the completion screen's data genuinely *is* the response to the submission. Three things follow for free, and
/// each is one the ticket asks for:
///
/// - **No connection means `LoadState.offline`, with a retry and nothing queued** (ADR-0019). The mapping is
///   ``BaseViewModel/load()``'s, so this object adds no fifth owner of it (`StateTaxonomyTests`), and the retry is
///   the shared chrome's CTA — a button the reader presses, never a re-send behind their back.
/// - **A `422` is a definite failure.** The server refuses an impossible submission (invariant 10) — a lesson whose
///   predecessor is unfinished, a result naming a step that is not a question — and there is nothing for the client
///   to correct, so it renders as the failed state carrying the code.
/// - **The figures are read, never computed.** The XP earned, the accuracy, and the streak all arrive in
///   ``LessonCompletion``; the client held the per-question results it submitted and could have divided them, which
///   is exactly the second owner ADR-0020 exists to prevent.
///
/// **One `Idempotency-Key` per intent, reused across retries** — the caller-supplied form `APIClient.post` was
/// written for and the rule `ExpensesViewModel` follows: finishing a lesson happens once, so a submission that
/// reached the server and lost its response must be recognised rather than counted twice. Minted at `init` because
/// *this object* is the intent: a second run of the same lesson is a new player, a new completion, and a new key.
@MainActor
@Observable
final class LessonCompletionViewModel: BaseViewModel {
    /// Not `private(set)`: ``BaseViewModel`` requires a settable `state`, and the trade-off is recorded there.
    var state: LoadState<LessonCompletion> = .loading

    /// Which lesson was finished. Addressed in the path, so there is one copy of it in the request.
    let lessonID: String

    /// One result per question, as the run recorded them. **Held rather than re-read**, so a retry submits exactly
    /// what the first attempt did — a payload that could change between attempts is a payload the idempotency key
    /// is lying about.
    private let results: [LessonRun.QuestionResult]

    private let idempotencyKey = UUID().uuidString

    private let client: APIClient

    /// Where the updated Learn screen goes, so the map behind the player re-renders from server truth rather than
    /// reloading (ADR-0020). Supplied by ``LearnViewModel``, which owns the map.
    private let onScreenUpdate: (LearnScreen) -> Void

    init(
        lessonID: String,
        results: [LessonRun.QuestionResult],
        client: APIClient,
        onScreenUpdate: @escaping (LearnScreen) -> Void
    ) {
        self.lessonID = lessonID
        self.results = results
        self.client = client
        self.onScreenUpdate = onScreenUpdate
    }

    /// **The submission.** `POST /v1/learn/lessons/:id/complete`, with the per-question results and nothing else
    /// (``LessonResults``).
    func fetch() async throws -> LessonCompletion {
        let completion = try await client.post(
            Endpoint.lessonCompletion(lessonID: lessonID),
            body: LessonResults(results: results),
            idempotencyKey: idempotencyKey,
            as: LessonCompletion.self
        )
        // The map is updated from the *same* response the celebration is drawn from, which is what makes it
        // impossible for the two to disagree about what just happened.
        onScreenUpdate(completion.screen)
        return completion
    }
}
