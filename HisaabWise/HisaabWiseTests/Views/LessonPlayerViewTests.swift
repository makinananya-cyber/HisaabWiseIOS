import Foundation
import SwiftUI
@testable import HisaabWise
import Testing

/// The lesson player's screens: what they map, what they draw, and the copy behind every key they render.
///
/// The run's rules are `LessonRunTests` and the submission is `LessonPlayerViewModelTests`. What is left here is
/// what a *screen* owns — the mapping from the run onto the components, the words, and the fact that four different
/// kinds of step draw four different pictures.
@Suite("LessonPlayerView")
@MainActor
struct LessonPlayerViewTests {
    private static func material(_ lessonID: String = "u1l1") throws -> LearnMap.Material {
        let map = LearnMap(
            curriculum: try Fixture.curriculum.decode(Curriculum.self),
            progress: try Fixture.learnInProgress.decode(LearnScreen.self)
        )
        return try #require(map.material(forLessonID: lessonID))
    }

    private static func run(_ lessonID: String = "u1l1", upToStep index: Int = 0) throws -> LessonRun {
        var run = LessonRun(lessonID: lessonID, steps: try material(lessonID).lesson.content.steps)
        while run.index < index { run.advance() }
        return run
    }

    private static func page(_ run: LessonRun, lessonID: String = "u1l1") throws -> LessonStepPage {
        let material = try material(lessonID)
        return LessonStepPage(
            step: try #require(run.step),
            run: run,
            kicker: Text(verbatim: "Unit 1"),
            tint: LearnView.tint(material.unit.content.accent),
            currencyToken: material.currencyToken,
            typed: .constant(""),
            onChoose: { _ in }
        )
    }

    // MARK: - Mapping the run onto the components

    /// **An option's state is the reader's choice while the question is open, and the answer key's once it is
    /// graded.** Total over every case, so a `body` does no deciding while it draws.
    @Test("an option is offered until it is chosen, and marked right or wrong once it is graded")
    func optionStates() throws {
        var run = try Self.run(upToStep: 4)
        guard case .singleChoice(let question) = try #require(run.step) else {
            Issue.record("u1l1's step 4 is no longer a single-choice question")
            return
        }
        let right = try #require(question.answers.first)
        let wrong = try #require(question.options.indices.first { !question.answers.contains($0) })

        for option in question.options.indices {
            #expect(LessonPlayerView.state(of: option, in: run) == .offered)
        }

        run.choose(wrong)
        #expect(LessonPlayerView.state(of: wrong, in: run) == .chosen)
        #expect(LessonPlayerView.state(of: right, in: run) == .offered)

        run.check()
        // The right answer is shown as right even though nobody picked it — which is the point of showing it.
        #expect(LessonPlayerView.state(of: right, in: run) == .right)
        #expect(LessonPlayerView.state(of: wrong, in: run) == .wrong)
        // And an option that is neither goes back to plain, which is the design clearing `.sel` off everything.
        let untouched = question.options.indices.filter { $0 != right && $0 != wrong }
        for option in untouched {
            #expect(LessonPlayerView.state(of: option, in: run) == .offered)
        }
    }

    /// A multi-select's chosen set is what the reader has ticked, not one option.
    @Test("a multi-select marks every option the reader has ticked")
    func multiSelectStates() throws {
        var run = try Self.run("u1l3", upToStep: 4)
        guard case .multiSelect(let question) = try #require(run.step) else {
            Issue.record("u1l3's step 4 is no longer the multi-select one")
            return
        }

        for option in question.answers { run.choose(option) }
        for option in question.answers {
            #expect(LessonPlayerView.state(of: option, in: run) == .chosen)
        }
    }

    /// **Only a state worth saying is said.** An untouched option's value would otherwise be read on every option of
    /// every question, which is four extra words per answer for no information.
    @Test("only a chosen or graded option carries a VoiceOver value")
    func stateLabels() {
        #expect(LessonPlayerView.stateLabel(.offered) == nil)
        for state in [HWAnswerState.chosen, .right, .wrong] {
            #expect(LessonPlayerView.stateLabel(state) != nil, "\(state)")
        }
    }

    @Test("the typed box is open until it is graded, and then says which it was")
    func numericStates() throws {
        var run = try Self.run(upToStep: 6)
        #expect(LessonPlayerView.numericState(run) == .offered)

        run.type("3600")
        #expect(LessonPlayerView.numericState(run) == .offered, "typing graded the answer")

        run.check()
        #expect(LessonPlayerView.numericState(run) == .right)
    }

    /// **The one button says three different things**, and the run decides which — so the title and what the press
    /// does cannot come apart.
    @Test("the primary button reads Continue, Check, and then Continue or Got it")
    func primaryTitles() throws {
        // A teaching page: Continue, with nothing to check.
        var run = try Self.run()
        #expect(LessonPlayerView.primaryTitle(for: run).key == "learn.player.continue")

        // A question: Check.
        run = try Self.run(upToStep: 4)
        #expect(LessonPlayerView.primaryTitle(for: run).key == "learn.player.check")

        guard case .singleChoice(let question) = try #require(run.step) else { return }
        var right = run
        right.choose(try #require(question.answers.first))
        right.check()
        #expect(LessonPlayerView.primaryTitle(for: right).key == "learn.player.continue")

        var wrong = run
        wrong.choose(try #require(question.options.indices.first { !question.answers.contains($0) }))
        wrong.check()
        #expect(LessonPlayerView.primaryTitle(for: wrong).key == "learn.player.gotIt")
    }

    /// **The headline rotates, and the rotation is deterministic.** The design's own seven-and-four lists, chosen by
    /// how many questions have been answered — a random one would be a screen no test could state anything about.
    @Test("the feedback headline rotates through the design's own lines")
    func headlinesRotate() {
        let right = LessonRun.Verdict(isCorrect: true, answers: [0], explanation: "", comboMilestone: nil)
        let wrong = LessonRun.Verdict(isCorrect: false, answers: [0], explanation: "", comboMilestone: nil)

        #expect(LessonPlayerView.praise.count == 7)
        #expect(LessonPlayerView.encouragement.count == 4)
        // Same answer, same words — twice.
        #expect(
            LessonPlayerView.headline(for: right, answered: 3) == LessonPlayerView.headline(for: right, answered: 3)
        )
        // And the two lists do not overlap: praise never lands on an encouragement.
        #expect(Set(LessonPlayerView.praise.map(\.key)).isDisjoint(with: LessonPlayerView.encouragement.map(\.key)))

        // Every line in both lists is reachable, so no catalogue entry is copy nobody sees.
        var reached: Set<String> = []
        for answered in 0..<28 {
            reached.insert(LessonPlayerView.headline(for: right, answered: answered).key)
            reached.insert(LessonPlayerView.headline(for: wrong, answered: answered).key)
        }
        #expect(reached.count == 11)
    }

    /// The week strip's mapping is a copy and nothing else: seven days in, seven days out, in order.
    @Test("the week strip is the payload's own seven days")
    func theWeekIsCopiedThrough() throws {
        let completion = try Fixture.lessonCompleted.decode(LessonCompletion.self)
        let week = LessonCompletionView.week(completion.week)

        #expect(week.count == 7)
        #expect(week.map(\.label) == completion.week.map(\.label))
        #expect(week.map(\.isComplete) == completion.week.map(\.isComplete))
        #expect(week.filter(\.isToday).count == 1)
        #expect(week.map(\.accessibilityLabel) == completion.week.map(\.accessibilityLabel))
    }

    // MARK: - It draws

    /// **The four kinds of step draw four different pictures**, which is the assertion an empty ground cannot pass.
    ///
    /// `ImageRenderer` does not lay out the content of a `ScrollView` (ADR-0033), which is why ``LessonStepPage``
    /// exists apart from the player — and why "it rendered" is not enough on its own: a page drawing nothing renders
    /// perfectly well.
    @Test("a teaching page, both question kinds, and a typed answer draw four different pictures")
    func everyStepKindDraws() throws {
        var pictures: [String: Data] = [:]

        for (name, run) in [
            ("teach", try Self.run(upToStep: 0)),
            ("single", try Self.run(upToStep: 4)),
            ("numeric", try Self.run(upToStep: 6)),
        ] {
            pictures[name] = try #require(
                TestBench.render(try Self.page(run), height: nil)?.pngData(),
                "\(name) did not render"
            )
        }

        let multi = try Self.run("u1l3", upToStep: 4)
        pictures["multi"] = try #require(
            TestBench.render(try Self.page(multi, lessonID: "u1l3"), height: nil)?.pngData()
        )

        #expect(Set(pictures.values).count == 4, "two step kinds drew the same picture")
    }

    /// A graded question draws differently from an open one — the marks, the wash, and the disabled box.
    @Test("grading a question changes what is drawn")
    func gradingChangesThePicture() throws {
        var run = try Self.run(upToStep: 4)
        let open = try #require(TestBench.render(try Self.page(run), height: nil)?.pngData())

        guard case .singleChoice(let question) = try #require(run.step) else { return }
        run.choose(try #require(question.answers.first))
        run.check()
        let graded = try #require(TestBench.render(try Self.page(run), height: nil)?.pngData())

        #expect(open != graded)
    }

    /// **The week strip is replaced above the accessibility threshold, not shrunk** (ADR-0012) — asserted as two
    /// different pictures, because the swap happens inside `hwVisualisation` and a component cannot be asked which
    /// branch it took.
    @Test("the week strip draws a different picture above the accessibility threshold")
    func theWeekStripIsReplaced() throws {
        let completion = try Fixture.lessonCompleted.decode(LessonCompletion.self)
        let strip = HWWeekStrip(days: LessonCompletionView.week(completion.week))

        let drawn = try #require(TestBench.render(strip.padding(20), height: nil)?.pngData())
        let replaced = try #require(
            TestBench.render(strip.padding(20).dynamicTypeSize(.accessibility3), height: nil)?.pngData()
        )

        #expect(drawn != replaced, "the strip was shrunk rather than replaced")
    }

    /// The screens render — a smoke test, for the reason `LearnViewTests` records: what it proves is that nothing
    /// traps with the environment they were given.
    @Test("the player and the celebration render")
    func theScreensRender() throws {
        #expect(TestBench.render(LessonPlayerView(viewModel: .previewTeaching, onClose: {})) != nil)
        #expect(
            TestBench.render(
                LessonCompletionView(viewModel: .previewCompleted, onContinue: {})
            ) != nil
        )
    }

    /// **The previews land where they say they do**, which is a regression guard rather than a nicety: the helper
    /// behind them walks the run by pressing the primary button, and the first version spun for ever the moment the
    /// walk crossed a question — an unanswered one is not `isReadyToCheck`, so the press moved nothing. "The player —
    /// a typed answer" hung Xcode rather than drawing anything, and no test noticed because no test used a preview.
    ///
    /// The time limit is the belt: a future regression should fail rather than hang the suite.
    @Test("every preview of the player lands on the state it claims", .timeLimit(.minutes(1)))
    func thePreviewsLandWhereTheyClaim() throws {
        #expect(LessonPlayerViewModel.previewTeaching.run.index == 0)

        let numeric = LessonPlayerViewModel.previewNumeric
        #expect(numeric.run.index == 6)
        if case .numeric = numeric.run.step {} else { Issue.record("previewNumeric is not on a numeric step") }
        #expect(numeric.run.verdict == nil, "the typed box is open in this preview")

        let right = LessonPlayerViewModel.previewAnsweredRight
        #expect(right.run.verdict?.isCorrect == true)
        #expect(right.run.heartsRemaining == 3)

        let wrong = LessonPlayerViewModel.previewAnsweredWrong
        #expect(wrong.run.verdict?.isCorrect == false)
        #expect(wrong.run.heartsRemaining == 2)

        let exhausted = LessonPlayerViewModel.previewOutOfHearts
        #expect(exhausted.run.isOutOfHearts)
        #expect(exhausted.completion == nil, "an exhausted run built a completion")
    }

    // MARK: - The copy

    /// Every key these two screens render has English copy behind it, and the two interpolated ones **number their
    /// arguments** — a translation that wants the count first has to be able to ask (ADR-0011).
    @Test("the player's copy is in the catalogue, and its format strings are positional")
    func theCopyIsThere() throws {
        try CatalogueCopy.expectEnglishCopy(forKeys: [
            "component.lesson.close",
            "learn.player.answer.hint", "learn.player.answer.label",
            "learn.player.check", "learn.player.continue", "learn.player.gotIt",
            "learn.player.combo %@", "learn.player.combo.announcement %@",
            "learn.player.hearts.accessibilityLabel %@ %@", "learn.player.kicker %@ %@",
            "learn.player.kind.multi", "learn.player.kind.numeric", "learn.player.kind.single",
            "learn.player.option.chosen", "learn.player.option.right", "learn.player.option.wrong",
            "learn.player.outOfHearts.leave", "learn.player.outOfHearts.message",
            "learn.player.outOfHearts.retry", "learn.player.outOfHearts.title",
            "learn.player.progress.accessibilityLabel %@ %@",
            "learn.player.rightAnswer", "learn.player.tip",
            "learn.completion.accuracy", "learn.completion.announcement %@ %@",
            "learn.completion.continue", "learn.completion.empty", "learn.completion.streak",
            "learn.completion.title", "learn.completion.title.again", "learn.completion.xp",
        ] + LessonPlayerView.praise.map(\.key) + LessonPlayerView.encouragement.map(\.key))

        for key in [
            "learn.player.progress.accessibilityLabel %@ %@",
            "learn.player.hearts.accessibilityLabel %@ %@",
            "learn.player.kicker %@ %@",
            "learn.completion.announcement %@ %@",
        ] {
            let value = try #require(CatalogueCopy.english(in: try CatalogueCopy.entry(key)))
            #expect(value.contains("%1$@"), "\(key) does not number its first argument")
            #expect(value.contains("%2$@"), "\(key) does not number its second argument")
        }
    }

    /// **The counts are spelled where they are computed** — `stepNumberText` is 1-based, because "step 0 of 8" is
    /// not what anybody counts, and it stops at the last step rather than running past it.
    @Test("the step and heart counts read as a reader would count them")
    func theCountsAreOneBased() throws {
        var run = try Self.run()
        #expect(run.stepNumberText == "1")
        #expect(run.stepCountText == "8")
        #expect(run.heartsRemainingText == "3")
        #expect(LessonRun.heartCountText == "3")

        while !run.isFinished { run.advance() }
        #expect(run.stepNumberText == "8", "the last step read as a ninth")
    }
}
