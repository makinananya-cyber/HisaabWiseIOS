import Foundation

/// `POST /v1/learn/lessons/{id}/complete` — a finished lesson, as **per-question results and nothing else**.
///
/// **This is the shape that makes client-side grading safe** (invariant 10). The client grades so that a tap feels
/// immediate; what it sends is not a score but a report — which question, and whether the reader got it right —
/// and the server recomputes the XP from it: 10 a correct answer plus a 20 completion bonus, **on the first
/// completion only** (defect D13). So the two rules that decide what the reader earns live server-side, and the
/// figures come back in the response (``LessonCompletion``).
///
/// **No XP, no accuracy, and no hearts.** Each of the three is derivable from these results, and a client that
/// sent one would be a client the server had to either trust or contradict. It is also what lets the server
/// **refuse** an impossible submission — every result naming a question step of that lesson, each exactly once,
/// no more wrong answers than there are hearts — which is what a `422` says.
///
/// **The lesson id is in the path, not in the body.** One id, one owner: a body carrying a second copy is a
/// request that can disagree with its own address.
struct LessonResults: Sendable, Hashable, Encodable {
    let results: [LessonRun.QuestionResult]
}

/// `POST /v1/learn/progress` — where the reader got to, so that an interrupted run is not lost.
///
/// The design keeps this on the device (`state.progress[id] = max(existing, run.correct)`), which is a per-user
/// figure held by the client and therefore the wrong owner twice over: it does not survive a reinstall, and it is
/// the number the progress ring is drawn from (`LessonProgress.filledSegments`), which ADR-0020 gives to the
/// server.
///
/// **It reports the same facts a completion does**, plus the step reached — and deliberately not the ring's count.
/// The server decides how many arcs a part-answered lesson lights, because it decides that for a completed one
/// too, and a ring whose fill came from the client on Tuesday and the server on Wednesday is a ring with two
/// owners.
struct LessonProgressReport: Sendable, Hashable, Encodable {
    /// Which lesson. In the body here, because the route is the collection rather than one lesson — the reader
    /// may abandon any of fifteen and there is one place to say so.
    let lessonID: String

    /// How many steps are behind the reader — the design's `run.i`, which is what "resume where you left off"
    /// needs and what a ring alone cannot say.
    let stepIndex: Int

    /// One result per question answered **so far**. Empty for a reader who left during the teaching pages, which
    /// is a real and common shape: they got three steps in and put the phone down.
    let results: [LessonRun.QuestionResult]

    private enum CodingKeys: String, CodingKey {
        case lessonID = "lessonId"
        case stepIndex
        case results
    }
}
