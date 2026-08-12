import Foundation

/// What `POST /v1/learn/lessons/{id}/complete` answers with: the celebration screen, **fully computed**, with the
/// updated Learn screen inside it (ADR-0020).
///
/// **Every figure on the completion screen is in here and none of it is worked out on the device**, which is the
/// boundary around the app's one client-side calculation (invariant 10). The client graded the questions so that
/// each tap felt immediate; the *totals* — what the run earned, how accurate it was, what the streak now is — are
/// the server's, recomputed from the submitted results and sent back. A client that added up its own XP would be
/// the two-owners shape defect D1 was, on the one screen whose whole job is to tell the reader what they earned.
///
/// **A write returning the screen payload, one layer out.** The other writes in the app answer with exactly the
/// screen they changed; this one answers with the screen it *produced* — the celebration — and carries the screen
/// it changed as a field. Both re-render from server truth: the completion draws these figures, and ``screen``
/// replaces the map behind it, so the ring that has just filled and the streak pill that has just moved are the
/// server's and not a patch.
///
/// **It carries no date, no timestamp, and no day key**, exactly as ``LearnScreen`` carries none (invariant 6).
/// The week strip is the interesting case: seven days with a label and a state each, *decided* server-side against
/// the reader's stored timezone, because a client that knew which day was today could move the streak by moving
/// the clock — which is precisely what the design does.
struct LessonCompletion: Sendable, Hashable, Decodable {
    /// Whether this is the **first** time the lesson has been finished — which is what decides whether anything
    /// was earned (defect D13).
    ///
    /// The design's `already` flag, and it changes the headline: "Lesson complete!" or "Lesson revisited!". The
    /// design then awards the XP either way, which is the defect: a replay may update the accuracy and earns
    /// nothing. So this is not decoration — it is the reader's explanation for a `0` beside "XP earned", and the
    /// server is the only thing that knows it.
    let isFirstCompletion: Bool

    /// What the run earned, ready to draw: `+30`, or `0` on a replay.
    ///
    /// **Signed by the server**, for the reason an incoming expense's display string is (ADR-0033): a `+` pushed
    /// onto the front of a string by the client lands on the wrong side of an Arabic figure. ``LearnScreen/Stat``'s
    /// three fields for the reason they exist there — the client owns no thousands separator, "30 experience
    /// points" is a count with a plural in it, and ``LearnScreen/Stat/value`` is drawn by nothing so that a test
    /// can assert a replay earned **zero** rather than compare two strings.
    let xpEarned: LearnScreen.Stat

    /// How much of the run was right — the design's `Math.round((correct / asked) * 100)`.
    ///
    /// A **percentage the server computes**, which is what ADR-0020 says about every percentage on every screen:
    /// the client holds the results it submitted and could divide them, and that is exactly the second owner the
    /// rule exists to prevent. `display` carries the `%`, whose position is a language's decision.
    let accuracy: LearnScreen.Stat

    /// The sentence under the headline — "Your streak just grew to 5 days…", or "You have already learned
    /// something today…".
    ///
    /// **Server-composed, and that is ``LearnScreen/Stat/accessibilityLabel``'s reason rather than a new one**: it
    /// is a count *and* a plural, and Arabic has six plural forms (ADR-0011). The alternative was two catalogue
    /// sentences chosen by a `Bool` with the streak interpolated, which is the same sentence assembled from a
    /// figure and a translation that cannot agree about the number.
    let streakLine: String

    /// The design's `.week` — seven days, each either lit or not, and one of them today.
    let week: [Day]

    /// The Learn screen as it now stands: the new XP total, the new streak, the filled ring, and the next lesson
    /// unlocked.
    ///
    /// **The write's own screen payload** (ADR-0020). The map behind the player re-renders from this rather than
    /// reloading, which is one request fewer and — more to the point — makes it impossible for the completion
    /// screen and the map to disagree about what just happened.
    let screen: LearnScreen

    /// One day in the week strip.
    ///
    /// **Its label is the server's and so is its state.** The design builds the strip from `new Date().getDay()`
    /// and a subtraction over the streak, which puts the day boundary on the device (invariant 6) and the day
    /// names in the client's own array. Both are here: `Su` in the reader's language, and lit or not by the
    /// server's own reckoning of their week.
    struct Day: Sendable, Hashable, Decodable {
        /// "Su" — two letters in the design, and whatever a language's short form is.
        let label: String

        /// Whether something was finished that day. The design's `.wd.on`.
        let isComplete: Bool

        /// Whether this is the reader's today, in *their* timezone. The design's `.wd.today`, which it draws with
        /// a bump.
        let isToday: Bool

        /// What VoiceOver reads for the day — "Sunday, complete" · "Today, nothing yet".
        ///
        /// Server-composed, because a day name plus a state is a sentence and the strip is otherwise seven
        /// two-letter labels a screen reader would spell out. The design has no accessibility text here at all.
        let accessibilityLabel: String
    }
}
