import Foundation
@testable import HisaabWise
import Testing

/// One run through a lesson: the hearts, the combo, the per-question results, and **the app's one piece of
/// client-side grading** (invariant 10, ADR-0020's single exception).
///
/// It is a value with no transport in it, so every rule the ticket names is asserted directly rather than
/// through a screen. Two of them are the ones that would be wrong in a way nobody notices: the numeric
/// tolerance is **strict**, so an answer exactly half a unit out is wrong, and the run **ends** at zero hearts
/// rather than continuing with a negative count.
///
/// **The steps come from the corpus**, not from values assembled here (ADR-0013): the boundary test is run
/// against `u1l1`'s own numeric question — answer `3600` — so a curriculum whose content changed under it fails
/// here rather than passing against a step this file invented.
@Suite("LessonRun")
struct LessonRunTests {
    private static func curriculum() throws -> Curriculum {
        try Fixture.curriculum.decode(Curriculum.self)
    }

    private static func run(_ lessonID: String) throws -> LessonRun {
        let lesson = try #require(try curriculum().lesson(id: lessonID))
        return LessonRun(lessonID: lesson.id, steps: lesson.steps)
    }

    /// Walks to the first step of `kind`, answering nothing on the way — the teaching pages ahead of a question
    /// are all `Continue`.
    private static func run(_ lessonID: String, upToStep index: Int) throws -> LessonRun {
        var run = try run(lessonID)
        while run.index < index {
            run.advance()
        }
        return run
    }

    // MARK: - Where a run starts

    @Test("a run starts on the first step with every heart")
    func aRunStarts() throws {
        let run = try Self.run("u1l1")

        #expect(run.index == 0)
        #expect(run.stepCount == 8)
        #expect(run.heartsRemaining == 3)
        #expect(LessonRun.heartCount == 3)
        #expect(run.results.isEmpty)
        #expect(run.verdict == nil)
        #expect(!run.isFinished)
        #expect(!run.isOutOfHearts)
        // A teaching page has nothing to answer, so its `Continue` is live from the moment it is drawn.
        #expect(run.isReadyToCheck)
    }

    /// A teaching step is **advanced past, not graded**: it produces no result, spends no heart, and leaves the
    /// combo where it was.
    @Test("a teaching step is advanced past and produces no result")
    func aTeachingStepIsNotGraded() throws {
        var run = try Self.run("u1l1")

        run.check()
        #expect(run.verdict == nil, "a teaching page was graded")

        run.advance()
        #expect(run.index == 1)
        #expect(run.results.isEmpty)
        #expect(run.heartsRemaining == 3)
    }

    // MARK: - Single choice

    /// `u1l1`'s fifth step is the first question: one right answer out of four, and `Check` stays inert until
    /// something is picked — the design's `check.disabled = true` until an option is chosen.
    @Test("a single-choice question grades the one option that was picked")
    func singleChoiceGrading() throws {
        var run = try Self.run("u1l1", upToStep: 4)
        let question = try #require(Self.question(in: run))

        #expect(!run.isReadyToCheck)

        let right = try #require(question.answers.first)
        run.choose(right)
        #expect(run.isReadyToCheck)

        run.check()
        let verdict = try #require(run.verdict)
        #expect(verdict.isCorrect)
        #expect(verdict.answers == question.answers)
        #expect(verdict.explanation == question.explanation)
        #expect(run.results == [LessonRun.QuestionResult(stepIndex: 4, isCorrect: true)])
        #expect(run.heartsRemaining == 3)
    }

    /// **Choosing replaces rather than accumulates**, which is what makes single choice single: the design clears
    /// every other `.sel` before marking the one that was tapped.
    @Test("choosing again on a single-choice question replaces the choice")
    func singleChoiceReplaces() throws {
        var run = try Self.run("u1l1", upToStep: 4)
        let question = try #require(Self.question(in: run))
        let right = try #require(question.answers.first)
        let wrong = try #require(question.options.indices.first { !question.answers.contains($0) })

        run.choose(right)
        run.choose(wrong)
        run.check()

        #expect(run.verdict?.isCorrect == false)
        // And the *right* answer is still what the feedback names, which is what the reader is shown.
        #expect(run.verdict?.answers == question.answers)
    }

    /// A graded question does not re-grade: the design disables every option once `Check` has been pressed, and a
    /// second press is `Continue`.
    @Test("a graded question ignores a further choice and a second check")
    func aGradedQuestionIsSettled() throws {
        var run = try Self.run("u1l1", upToStep: 4)
        let question = try #require(Self.question(in: run))
        let wrong = try #require(question.options.indices.first { !question.answers.contains($0) })

        run.choose(wrong)
        run.check()
        let settled = run

        run.choose(try #require(question.answers.first))
        run.check()

        #expect(run == settled, "a settled question was answered twice")
        #expect(run.results.count == 1)
        #expect(run.heartsRemaining == 2)
    }

    // MARK: - Multi-select

    /// `u1l3`'s "Which of these are NEEDS?" — every right option and no wrong one, which is the whole of the rule
    /// the design writes as a sorted join.
    @Test("a multi-select question is right only when the whole set matches")
    func multiSelectGrading() throws {
        var run = try Self.run("u1l3", upToStep: 4)
        let question = try #require(Self.question(in: run))
        #expect(question.answers.count > 1, "u1l3's step 4 is no longer the multi-select one")

        #expect(!run.isReadyToCheck)
        for option in question.answers { run.choose(option) }
        #expect(run.isReadyToCheck)

        run.check()
        #expect(run.verdict?.isCorrect == true)
    }

    @Test("choosing twice on a multi-select question deselects")
    func multiSelectToggles() throws {
        var run = try Self.run("u1l3", upToStep: 4)
        let question = try #require(Self.question(in: run))
        let first = try #require(question.answers.first)

        run.choose(first)
        run.choose(first)
        #expect(!run.isReadyToCheck, "an empty set left Check live")

        for option in question.answers { run.choose(option) }
        // One right answer short is wrong, and so is one wrong answer too many.
        run.choose(first)
        run.check()
        #expect(run.verdict?.isCorrect == false)
    }

    @Test("a multi-select answer with a wrong option in it is wrong")
    func multiSelectRefusesAnExtra() throws {
        var run = try Self.run("u1l3", upToStep: 4)
        let question = try #require(Self.question(in: run))
        let extra = try #require(question.options.indices.first { !question.answers.contains($0) })

        for option in question.answers { run.choose(option) }
        run.choose(extra)
        run.check()

        #expect(run.verdict?.isCorrect == false)
        #expect(run.heartsRemaining == 2)
    }

    // MARK: - The numeric tolerance

    /// **The boundary, asserted from both sides.** `u1l1`'s numeric answer is `3600`, and the design grades with
    /// `Math.abs(v - correct) < 0.5` — so `3600.49` is right, `3600.5` is **wrong**, and an implementation using
    /// `<=` passes every other test in this file.
    ///
    /// The comparison is integer arithmetic in hundredths, because `Models` may hold no `Double` (ADR-0003,
    /// `MoneyFormattingAbsenceTests`) — and a tolerance compared in floating point is a tolerance whose boundary
    /// depends on the value it is applied to.
    @Test("the numeric tolerance is strict: exactly half a unit out is wrong", arguments: [
        (typed: "3600", isCorrect: true),
        (typed: "3600.0", isCorrect: true),
        (typed: "3600.49", isCorrect: true),
        (typed: "3599.51", isCorrect: true),
        // The boundary itself, from both sides. Neither is within *less than* half a unit.
        (typed: "3600.5", isCorrect: false),
        (typed: "3599.5", isCorrect: false),
        (typed: "3601", isCorrect: false),
        (typed: "0", isCorrect: false),
    ])
    func theNumericToleranceIsStrict(_ testCase: (typed: String, isCorrect: Bool)) throws {
        var run = try Self.run("u1l1", upToStep: 6)
        guard case .numeric(let question) = try #require(run.step) else {
            Issue.record("u1l1's step 6 is no longer the numeric one")
            return
        }
        #expect(question.answer == 3600)

        run.type(testCase.typed)
        run.check()

        #expect(run.verdict?.isCorrect == testCase.isCorrect, "\(testCase.typed)")
    }

    /// **A decimal comma is a decimal point**, which is `TypedAmount`'s rule rather than a second one: a
    /// `.decimalPad` offers the *device region's* separator, and under `ar` the digits stay Latin (ADR-0011).
    @Test("a typed answer is read by TypedAmount's rules, comma separator included", arguments: [
        (typed: "3600,49", isCorrect: true),
        (typed: "3600,5", isCorrect: false),
        (typed: "3,600", isCorrect: true),
        (typed: "٣٦٠٠", isCorrect: true),
    ])
    func theSeparatorAndTheDigitScript(_ testCase: (typed: String, isCorrect: Bool)) throws {
        var run = try Self.run("u1l1", upToStep: 6)

        run.type(testCase.typed)
        run.check()

        #expect(run.verdict?.isCorrect == testCase.isCorrect, "\(testCase.typed)")
    }

    /// Nothing typed leaves `Check` inert, and something that is not a figure at all grades as **wrong** rather
    /// than as nothing happening — a reader who has pressed Check has to be told something.
    @Test("an empty numeric answer cannot be checked and an unreadable one is wrong")
    func anUnreadableNumericAnswer() throws {
        var run = try Self.run("u1l1", upToStep: 6)
        #expect(!run.isReadyToCheck)

        run.type("  ")
        #expect(!run.isReadyToCheck)

        run.type("3600.505")
        #expect(run.isReadyToCheck)
        run.check()
        #expect(run.verdict?.isCorrect == false)
    }

    // MARK: - Hearts

    /// **Three hearts, and the run ends at zero.** A fourth wrong answer is not reachable: the run is over, and
    /// nothing advances past the step that ended it.
    @Test("three wrong answers end the run")
    func heartsExhaustionEndsTheRun() throws {
        var run = try Self.run("u3l3")
        var spent = 0

        while spent < 3 {
            if let question = Self.question(in: run) {
                let wrong = try #require(question.options.indices.first { !question.answers.contains($0) })
                run.choose(wrong)
                run.check()
                spent += 1
                #expect(run.heartsRemaining == 3 - spent)
            }
            guard spent < 3 else { break }
            run.advance()
        }

        #expect(run.heartsRemaining == 0)
        #expect(run.isOutOfHearts)

        // The run is over: advancing does nothing, so no step after it is ever drawn and nothing is submitted.
        let ended = run
        run.advance()
        #expect(run == ended, "the run advanced past the step that ended it")
        #expect(!run.isFinished, "an exhausted run reads as finished, which is what submits it")
    }

    // MARK: - Combos

    /// **Every third consecutive correct answer**, and the count resets on a wrong one — the design's
    /// `combo >= 3 && combo % 3 === 0`.
    ///
    /// `u3l3` is the lesson with five questions in a row, which is what makes three-then-six assertable in one
    /// run.
    @Test("a combo lands on every third consecutive correct answer")
    func combosLandOnEveryThird() throws {
        var run = try Self.run("u3l3")
        var milestones: [Int] = []
        var correct = 0

        while !run.isFinished {
            if let question = Self.question(in: run) {
                run.choose(try #require(question.answers.first))
                run.check()
                correct += 1
                if let milestone = run.verdict?.comboMilestone { milestones.append(milestone) }
                #expect(run.consecutiveCorrect == correct)
            }
            run.advance()
        }

        #expect(correct == 5, "u3l3 no longer has five questions in it")
        #expect(milestones == [3], "a combo landed on something other than the third answer")
        #expect(LessonRun.comboInterval == 3)
    }

    /// **Every third, not just the third.** The corpus's longest lesson has five questions in it, so a run cannot
    /// reach six in a row — which left "every third" resting on one data point. The rule itself is a pure function and
    /// can be asked directly.
    @Test("the combo milestone is every third and nothing else", arguments: [
        (consecutive: 0, milestone: nil), (consecutive: 1, milestone: nil), (consecutive: 2, milestone: nil),
        (consecutive: 3, milestone: 3), (consecutive: 4, milestone: nil), (consecutive: 5, milestone: nil),
        (consecutive: 6, milestone: 6), (consecutive: 7, milestone: nil), (consecutive: 8, milestone: nil),
        (consecutive: 9, milestone: 9), (consecutive: 12, milestone: 12),
    ])
    func theComboIntervalHolds(_ testCase: (consecutive: Int, milestone: Int?)) {
        #expect(LessonRun.comboMilestone(at: testCase.consecutive) == testCase.milestone, "\(testCase.consecutive)")
    }

    @Test("a wrong answer resets the combo")
    func aWrongAnswerResetsTheCombo() throws {
        var run = try Self.run("u3l3", upToStep: 4)
        let first = try #require(Self.question(in: run))

        run.choose(try #require(first.answers.first))
        run.check()
        #expect(run.consecutiveCorrect == 1)
        run.advance()

        let second = try #require(Self.question(in: run))
        run.choose(try #require(second.options.indices.first { !second.answers.contains($0) }))
        run.check()

        #expect(run.consecutiveCorrect == 0)
        #expect(run.verdict?.comboMilestone == nil)
    }

    // MARK: - What gets submitted

    /// **One result per question, in step order, and the run is finished when the last step is behind it.** That
    /// list is the whole of what the server recomputes XP from (invariant 10), so a question that produced no
    /// result would be a lesson the server refuses.
    @Test("a finished run carries one result per question, naming its step")
    func aFinishedRunCarriesEveryResult() throws {
        var run = try Self.run("u1l1")
        let questionSteps = run.steps.enumerated().filter { $0.element.isQuestion }.map(\.offset)

        while !run.isFinished {
            if let question = Self.question(in: run) {
                run.choose(try #require(question.answers.first))
                run.check()
            } else if case .numeric(let numeric) = run.step {
                run.type(numeric.answerText)
                run.check()
            }
            run.advance()
        }

        #expect(run.isFinished)
        #expect(run.step == nil)
        #expect(run.results.map(\.stepIndex) == questionSteps)
        #expect(run.results.allSatisfy { $0.isCorrect })
        #expect(run.correctCount == questionSteps.count)
        #expect(run.heartsRemaining == 3)
    }

    /// **The grading takes no locale, which is what "under `ar` with Latin digits" means here** (ADR-0011).
    ///
    /// Asserted as an **absence**, for the reason the streak's clock test is: there is no locale in the path at all,
    /// so an Arabic reader's keystrokes and an English reader's produce the same number by construction rather than by
    /// two code paths agreeing. A test that switched the app's language and re-graded would be asserting that a
    /// function with no locale argument ignores the locale.
    @Test("nothing in the grading path reads a locale or a formatter")
    func gradingIsLocaleIndependent() throws {
        for path in ["Models/LessonRun.swift", "Models/TypedAmount.swift"] {
            let code = try SourceTree.codeLines(of: SourceTree.appSources.appending(path: path))
            for symbol in ["Locale", "NumberFormatter", "FormatStyle", "formatted("] {
                #expect(
                    code.first { $0.contains(symbol) } == nil,
                    "\(path) references \(symbol) — client and server must parse byte-identical input (ADR-0011)"
                )
            }
        }

        // And the property that absence buys: the same figure, typed in either script, grades the same.
        var latin = try Self.run("u1l1", upToStep: 6)
        var arabic = latin
        latin.type("3600")
        arabic.type("٣٦٠٠")
        latin.check()
        arabic.check()
        #expect(latin.verdict?.isCorrect == true)
        #expect(arabic.verdict?.isCorrect == latin.verdict?.isCorrect)
    }

    /// The current step's options and answer key, for the choice kinds. `nil` on a teaching or numeric step.
    private static func question(in run: LessonRun) -> Curriculum.Step.Question? {
        switch run.step {
        case .singleChoice(let question), .multiSelect(let question): question
        default: nil
        }
    }
}
