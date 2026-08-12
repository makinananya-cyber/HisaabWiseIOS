import Foundation

/// One run through one lesson: where the reader is, how many hearts are left, what they have answered, and
/// **whether each answer was right**.
///
/// **This is the app's one piece of client-side calculation, and it is a deliberate exception** (invariant 10,
/// ADR-0020). Grading happens here so that a tap feels immediate rather than costing a round trip per question;
/// the answer this reaches is **never authoritative**. Every result is submitted with the lesson
/// (``LessonResults``), the server recomputes the XP from them, and every figure the completion screen shows
/// comes back from that response. So the exception is bounded by three things: it grades, it does not *score*,
/// and nothing it decides reaches the reader as a total.
///
/// **A value, not a view model.** The whole of the run is here — including the two rules the ticket says to test
/// explicitly, the strict numeric tolerance and the run ending at zero hearts — so both are assertable without a
/// screen or a transport. ``LessonPlayerViewModel`` holds one of these and does the writing.
///
/// **It owns no clock and no total.** The streak is the server's (invariant 6) and the XP is the server's
/// (invariant 10); what this counts is hearts, consecutive correct answers, and results, none of which is a
/// figure the reader reads.
struct LessonRun: Sendable, Equatable {
    /// Three, as the design draws three. A `static let` rather than a literal in two places, because the header
    /// draws the empty ones and the run decides when they are gone.
    static let heartCount = 3

    /// The combo lands on **every third** consecutive correct answer — the design's
    /// `combo >= 3 && combo % 3 === 0`.
    static let comboInterval = 3

    /// The strict tolerance, **in hundredths**: `|submitted − correct| < 0.5` is `< 50` here.
    ///
    /// Hundredths rather than a `Double`, for two reasons that point the same way. `Models` may hold no
    /// floating-point number outside the named geometry fractions (ADR-0003, `MoneyFormattingAbsenceTests`); and
    /// a tolerance compared in floating point has a boundary that moves with the magnitude of the value it is
    /// applied to, which for a rule whose whole content is "exactly 0.5 out is wrong" is the one property it
    /// cannot afford.
    static let toleranceInHundredths = 50

    /// The scale a typed answer is read at — two decimal places, which is what `< 0.5` needs to be expressible.
    private static let typedExponent = 2

    /// `10 ^ typedExponent`, written out rather than looped: the exponent is a constant here, so the loop
    /// ``TypedAmount`` needs for a currency's own exponent would be arithmetic to work out a literal.
    private static let hundredthsPerUnit = 100

    /// Which lesson this is a run of. What `POST /v1/learn/lessons/:id/complete` is addressed to.
    let lessonID: String

    /// The lesson's steps, in the curriculum's order — the server's (ADR-0020).
    let steps: [Curriculum.Step]

    /// Which step the reader is on. `steps.count` once the last one is behind them.
    private(set) var index = 0

    /// How many hearts are left. The run is over at zero.
    private(set) var heartsRemaining = Self.heartCount

    /// How many questions have been answered correctly **in a row**, which is what the combo counts.
    private(set) var consecutiveCorrect = 0

    /// One result per question answered, in step order. **What gets submitted** (``LessonResults``).
    private(set) var results: [QuestionResult] = []

    /// What the reader has picked or typed for the current step, and nothing else — it is reset on every
    /// ``advance()``.
    private(set) var answer = Answer.none

    /// How the current question was graded, or `nil` while it is still open.
    ///
    /// Its presence *is* the design's `run.checked`: the footer shows feedback, the options stop responding, and
    /// the primary button becomes **Continue**.
    private(set) var verdict: Verdict?

    init(lessonID: String, steps: [Curriculum.Step]) {
        self.lessonID = lessonID
        self.steps = steps
    }

    // MARK: - Where the run is

    /// The step being drawn, or `nil` when the run is finished.
    var step: Curriculum.Step? {
        steps.indices.contains(index) ? steps[index] : nil
    }

    var stepCount: Int { steps.count }

    /// Whether every step is behind the reader — **the state that submits the lesson**.
    ///
    /// A run that ended on an empty heart is deliberately *not* finished: it has no completion to submit, and
    /// conflating the two would file a lesson the reader did not get through.
    var isFinished: Bool { index >= steps.count && !isOutOfHearts }

    /// Whether the run ended because the hearts did. The design's "Out of hearts" dialog.
    var isOutOfHearts: Bool { heartsRemaining <= 0 }

    /// Whether the primary button does anything — the design's `check.disabled`.
    ///
    /// A teaching page is always ready (there is nothing to answer), a graded question is ready (the button is
    /// **Continue** now), and an open question is ready once there is an answer in it.
    var isReadyToCheck: Bool {
        guard let step else { return false }
        // A graded question's button is **Continue**, which is always live.
        guard verdict == nil else { return true }
        switch step {
        case .teach: return true
        case .singleChoice: if case .one = answer { return true } else { return false }
        case .multiSelect: if case .several(let chosen) = answer { return !chosen.isEmpty } else { return false }
        // A digit rather than a non-empty string: the design filters everything but digits and separators out of
        // the box as it is typed, so a field holding only a stray separator is a field holding nothing.
        case .numeric: if case .typed(let text) = answer { return text.contains(where: \.isNumber) } else { return false }
        }
    }

    /// How many questions have been answered correctly. **Not a score** — it is what the ring's filled arcs are
    /// reported from (``LessonProgressReport``) and what the server recomputes XP from.
    var correctCount: Int { results.count { $0.isCorrect } }

    // MARK: - The counts, spelled where they are computed

    /// The step the reader is on as the accessibility sentence draws it — **1-based**, because "step 0 of 8" is not
    /// what anybody counts.
    ///
    /// Spelled here rather than at the call site, which is the convention every interpolated catalogue key in this
    /// app depends on (see ``Curriculum/Unit/numberText``): a number is converted where it is *computed*, because
    /// the localisation scan derives `key %@` from the source and cannot know that `\(anInt)` resolves to `%lld`.
    ///
    /// None of these three is formatted, and the difference from ``LearnScreen/Stat/display`` is real rather than an
    /// inconsistency: a step out of eight and a heart out of three have no thousands separator, so `String(_:)` is
    /// the whole of their formatting, and Latin digits are pinned in both languages (ADR-0011).
    var stepNumberText: String { String(min(index + 1, stepCount)) }

    var stepCountText: String { String(stepCount) }

    var heartsRemainingText: String { String(max(heartsRemaining, 0)) }

    static var heartCountText: String { String(heartCount) }

    // MARK: - Answering

    /// Picks an option: on a single-choice question it **replaces**, on a multi-select it **toggles**.
    ///
    /// One method rather than two, because the step already says which it is — and two methods would let a screen
    /// call the wrong one. Ignored once the question has been graded, which is the design disabling every `.opt`
    /// after `Check`.
    mutating func choose(_ option: Int) {
        guard verdict == nil, let step else { return }
        switch step {
        case .singleChoice(let question):
            guard question.options.indices.contains(option) else { return }
            answer = .one(option)
        case .multiSelect(let question):
            guard question.options.indices.contains(option) else { return }
            var chosen = if case .several(let existing) = answer { existing } else { Set<Int>() }
            if chosen.contains(option) { chosen.remove(option) } else { chosen.insert(option) }
            answer = .several(chosen)
        case .teach, .numeric:
            return
        }
    }

    /// What the reader has typed into a numeric question's box, exactly as typed.
    ///
    /// Parsed at grading time rather than here, so the field shows what the reader put in it: a box that
    /// re-spelled a half-typed figure is a box that fights whoever is typing.
    mutating func type(_ text: String) {
        guard verdict == nil, case .numeric = step else { return }
        answer = .typed(text)
    }

    /// Grades the current question — **the exception, in one place**.
    ///
    /// A teaching page grades to nothing. A question already graded stays graded, so a second press of the
    /// primary button is a `Continue` rather than a re-mark. A wrong answer spends a heart and clears the combo;
    /// a right one extends it and lands a celebration on every third.
    mutating func check() {
        guard verdict == nil, let step else { return }

        let isCorrect: Bool
        let answers: [Int]
        let explanation: String

        switch step {
        case .teach:
            return
        case .singleChoice(let question):
            guard case .one(let chosen) = answer else { return }
            isCorrect = Set(question.answers) == [chosen]
            answers = question.answers
            explanation = question.explanation
        case .multiSelect(let question):
            guard case .several(let chosen) = answer, !chosen.isEmpty else { return }
            isCorrect = Set(question.answers) == chosen
            answers = question.answers
            explanation = question.explanation
        case .numeric(let question):
            guard case .typed(let text) = answer, text.contains(where: \.isNumber) else { return }
            isCorrect = Self.isWithinTolerance(typed: text, of: question.answer)
            // A numeric question has no options, so there is no index to name — the answer is the figure, and
            // the screen draws it from the step.
            answers = []
            explanation = question.explanation
        }

        results.append(QuestionResult(stepIndex: index, isCorrect: isCorrect))

        if isCorrect {
            consecutiveCorrect += 1
        } else {
            consecutiveCorrect = 0
            heartsRemaining -= 1
        }

        verdict = Verdict(
            isCorrect: isCorrect,
            answers: answers,
            explanation: explanation,
            comboMilestone: Self.comboMilestone(at: consecutiveCorrect)
        )
    }

    /// Moves to the next step, clearing the answer and the feedback with it.
    ///
    /// **A run with no hearts left does not advance**, which is what "the run ends at 0" means as a property
    /// rather than as a screen: there is no next step to draw, and ``isFinished`` never becomes true, so nothing
    /// is submitted for a lesson the reader did not get through.
    mutating func advance() {
        guard !isOutOfHearts, index < steps.count else { return }
        index += 1
        answer = .none
        verdict = nil
    }

    // MARK: - Grading a typed figure

    /// Whether a typed figure is within *less than* half a unit of `answer`.
    ///
    /// The parse is ``TypedAmount``'s, which is the app's one owner of "what did the user type" — a decimal comma
    /// is a decimal point, and any digit script reads (ADR-0011). Anything it cannot read unambiguously is
    /// **wrong** rather than unanswered: the reader has pressed Check and has to be told something.
    static func isWithinTolerance(typed: String, of answer: Int) -> Bool {
        guard let hundredths = TypedAmount.scaled(from: typed, exponent: typedExponent) else { return false }
        let (correct, overflowed) = answer.multipliedReportingOverflow(by: hundredthsPerUnit)
        guard !overflowed else { return false }
        return abs(hundredths - correct) < toleranceInHundredths
    }

    /// The combo just reached, when a celebration is due, or `nil`.
    static func comboMilestone(at consecutive: Int) -> Int? {
        guard consecutive >= comboInterval, consecutive % comboInterval == 0 else { return nil }
        return consecutive
    }
}

// MARK: - The values it holds

extension LessonRun {
    /// What the reader has put into the current step.
    ///
    /// One enum with a case per question kind rather than three optional properties, so "a typed figure on a
    /// multi-select question" is not a state anything can be in — the same reason ``Curriculum/Step`` has one
    /// discriminator instead of two.
    enum Answer: Sendable, Equatable {
        /// Nothing yet, which is every step's opening state.
        case none
        /// One option, on a single-choice question.
        case one(Int)
        /// A set of options, on a multi-select. A `Set`, because the order they were tapped in is not part of the
        /// answer and grading compares sets.
        case several(Set<Int>)
        /// A figure, exactly as it was typed.
        case typed(String)
    }

    /// How one question was graded, and everything the feedback footer draws.
    struct Verdict: Sendable, Equatable {
        let isCorrect: Bool

        /// Which options were right, as indices — so the footer can name the right answer after a wrong one, as
        /// the design's `.fb-ans` does. Empty on a numeric question, where the answer is the figure itself.
        let answers: [Int]

        /// The step's own `explanation` — the *teaching* half of a question, shown right or wrong.
        let explanation: String

        /// The combo this answer landed, or `nil`. A value rather than a `Bool`, because the badge says
        /// "COMBO ×3" and the number is the whole of what it has to say.
        let comboMilestone: Int?
    }

    /// One question's outcome, as it is submitted.
    ///
    /// **The step's index travels with it**, which is what lets the server refuse an impossible submission
    /// (invariant 10): it can check that every result names a question step of that lesson and that each appears
    /// exactly once. A bare list of booleans would be a list the server has to trust.
    struct QuestionResult: Sendable, Hashable, Encodable {
        let stepIndex: Int
        let isCorrect: Bool
    }
}
