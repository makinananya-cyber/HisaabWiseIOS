import SwiftUI

/// The lesson player, converted from the design's `.player` section — **124 steps, three hearts, and the one place
/// this app calculates anything** (#20).
///
/// **Not a `BaseView`, because it makes no request.** The steps came down with the curriculum and the reader's state
/// came down with the Learn screen; the player is handed both, so there is no `LoadState` for it to draw — the same
/// reason `LandingView` is not a conformance. The screen that *does* draw one is the celebration, whose data is the
/// response to submitting the lesson (``LessonCompletionView``).
///
/// **Grading is client-side, and this is the whole of the exception** (invariant 10, ADR-0020). It happens in
/// ``LessonRun`` so that a tap is answered without a round trip; the client's answer is never authoritative, every
/// question's result is submitted, and not one figure the reader reads is worked out here — the XP, the accuracy, and
/// the streak all arrive in the completion's response.
///
/// **The player covers the screen rather than being pushed onto it.** The design slides a full-height section up
/// over the map and the tab bar, which is a `fullScreenCover`: a lesson is a focused mode, and the way out is the
/// close affordance in its own header (or the out-of-hearts dialog's second button).
struct LessonPlayerView: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Held rather than read from the environment, so a test or a preview can construct the screen over a fixture
    /// transport (ADR-0013).
    let viewModel: LessonPlayerViewModel

    /// What leaving the lesson does. The caller's, because the player does not own the screen it came from — Learn
    /// closes it and reports where the reader got to (`LearnViewModel.closePlayer()`).
    let onClose: () -> Void

    /// Whether the out-of-hearts dialog is up.
    ///
    /// **It trails the run rather than mirroring it**, which is the design's own sequence and a bug review found:
    /// the third heart goes *inside* `check()`, so a dialog bound straight to `run.isOutOfHearts` covers the footer
    /// explaining the answer that ended the run before anybody can read it. The design waits 700ms
    /// (`setTimeout(outOfHearts, reduced ? 0 : 700)`), and under Reduce Motion it does not wait at all.
    @State private var isShowingOutOfHearts = false

    var body: some View {
        // The celebration covers the player, as the design's `#done` covers `#player`. It is a screen of its own
        // with its own four states, so it is presented rather than inlined.
        if let completion = viewModel.completion {
            LessonCompletionView(viewModel: completion, onContinue: onClose)
        } else {
            player
        }
    }

    // MARK: - The player

    private var player: some View {
        VStack(spacing: 0) {
            header

            steps

            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.palette.surface.background.ignoresSafeArea())
        // The one dialog: three wrong answers and the run is over. A system `alert` rather than the design's own
        // modal, for `LogoutControl`'s reason — it is announced, it cannot be dismissed by accident, and the two
        // choices read as choices.
        // Non-dismissible on purpose, which is the design's own behaviour: its scrim carries a handler that
        // deliberately does nothing, because the run is over and both ways on are choices worth making.
        .alert(
            Text("learn.player.outOfHearts.title"),
            isPresented: $isShowingOutOfHearts
        ) {
            Button("learn.player.outOfHearts.retry") { viewModel.restart() }
            Button("learn.player.outOfHearts.leave", role: .cancel, action: onClose)
        } message: {
            Text("learn.player.outOfHearts.message")
        }
        // The design's own delay, so the feedback under the third wrong answer is readable before the dialog covers
        // it — and none under Reduce Motion, where a panel sliding in over a sentence is the movement being avoided.
        .task(id: viewModel.run.isOutOfHearts) {
            guard viewModel.run.isOutOfHearts else {
                isShowingOutOfHearts = false
                return
            }
            if !reduceMotion { try? await Task.sleep(for: .seconds(0.7)) }
            isShowingOutOfHearts = viewModel.run.isOutOfHearts
        }
        // `.success` on a right answer, `.error` on a wrong one (ADR-0012). The ADR also names `.impact` for a lost
        // heart, which is the *same moment* as a wrong answer — two feedbacks for one event would be a stutter, so
        // the error carries both.
        .sensoryFeedback(trigger: viewModel.run.verdict) { _, verdict in
            guard let verdict else { return nil }
            return verdict.isCorrect ? .success : .error
        }
        // One container per screen, as `ScreenChrome` does for the five tab roots — the player is not a `BaseView`,
        // so it says so itself (ADR-0012).
        .accessibilityElement(children: .contain)
    }

    /// The step's arrival, and — under Reduce Motion — its replacement. One value, decided once (ADR-0012).
    private var entrance: HWEntrance {
        HWEntrance.rise.resolved(reduceMotion: reduceMotion)
    }

    /// `.p-top` — the way out, the progress, and the hearts.
    private var header: some View {
        HWRunHeader(
            stepsDone: viewModel.run.index,
            stepCount: viewModel.run.stepCount,
            heartsRemaining: viewModel.run.heartsRemaining,
            heartCount: LessonRun.heartCount,
            tint: tint,
            // The two counts said in words, because a track and three glyphs are drawings (ADR-0012). Numbered
            // arguments, so a translation can order them (ADR-0011).
            progressLabel: Text(
                "learn.player.progress.accessibilityLabel \(viewModel.run.stepNumberText) \(viewModel.run.stepCountText)"
            ),
            heartsLabel: Text(
                "learn.player.hearts.accessibilityLabel \(viewModel.run.heartsRemainingText) \(LessonRun.heartCountText)"
            ),
            onClose: onClose
        )
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 12)
    }

    /// `.p-body` — the step itself, scrolling, with the combo badge over it.
    ///
    /// **The step is a page and this is the chrome**, which is the split ADR-0033 found by looking: `ImageRenderer`
    /// does not lay out the content of a `ScrollView`, so a render of the whole screen comes back as an empty ground
    /// and a test asserting that it rendered passes on it. Everything the reader reads is in ``LessonStepPage``.
    private var steps: some View {
        ScrollView {
            if let step = viewModel.run.step {
                LessonStepPage(
                    step: step,
                    run: viewModel.run,
                    kicker: Text(
                        "learn.player.kicker \(viewModel.material.unit.content.numberText) \(viewModel.material.lesson.content.title)"
                    ),
                    tint: tint,
                    currencyToken: viewModel.material.currencyToken,
                    // **Closures rather than method references** — `set: viewModel.type` and
                    // `onChoose: viewModel.choose` crashed the compiler in IRGen (`report_at_maximum_capacity`
                    // inside `SyncCallEmission::setArgs`), which is a partially-applied `@MainActor` method being
                    // passed where a plain closure is expected. Recorded because the two forms read as equivalent
                    // and only one of them builds.
                    typed: Binding(get: { viewModel.typedAnswer }, set: { viewModel.type($0) }),
                    onChoose: { viewModel.choose($0) }
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 18)
                // A fresh identity per step, so the arrival is an arrival rather than one page's text turning
                // into another's (`.p-step{animation:stepIn}`).
                .id(viewModel.run.index)
                .transition(entrance.transition)
            }
        }
        .animation(entrance.animation, value: viewModel.run.index)
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: .infinity)
        .overlay(alignment: .top) {
            HWComboBadge(
                text: Text("learn.player.combo \(viewModel.comboMilestoneText)"),
                isPresented: viewModel.comboMilestone != nil
            )
        }
        // **The combo's announcement** — neither the badge nor its reduced form reaches VoiceOver on its own, which
        // is one of the two cases `HWAnnouncement` exists for (ADR-0012). `.immediate`, because it is feedback about
        // the answer the reader has just given: one that arrived after they had moved on would be worse than
        // silence.
        .task(id: viewModel.comboMilestone) {
            guard let milestone = viewModel.comboMilestone else { return }
            HWAnnouncement.post(
                "learn.player.combo.announcement \(viewModel.comboMilestoneText)",
                in: locale,
                priority: .immediate
            )
            // The badge's own animation runs 1.5s in the design; it goes when it has been seen.
            try? await Task.sleep(for: .seconds(1.6))
            viewModel.dismissCombo()
        }
    }

    /// `.p-foot` — the feedback, then the one button.
    private var footer: some View {
        VStack(spacing: 13) {
            if let verdict = viewModel.run.verdict {
                HWFeedbackNote(
                    isCorrect: verdict.isCorrect,
                    headline: Text(Self.headline(for: verdict, answered: viewModel.run.results.count)),
                    answerCaption: verdict.isCorrect ? nil : "learn.player.rightAnswer",
                    answers: verdict.isCorrect ? [] : answerText(verdict),
                    explanation: viewModel.resolved(verdict.explanation)
                )
                .transition(entrance.transition)
            }

            HWRunButton(
                Self.primaryTitle(for: viewModel.run),
                tone: buttonTone,
                isEnabled: viewModel.run.isReadyToCheck,
                action: { viewModel.primaryAction() }
            )
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
        // `.p-foot.right`/`.wrong` — the whole footer takes the verdict's wash, which is the design's loudest
        // signal that something has been graded.
        .background(footerGround)
        .animation(reduceMotion ? nil : HWMotion.easeInOut.animation(.emphasised), value: viewModel.run.verdict)
    }

    private var footerGround: some View {
        Rectangle()
            .fill(footerFill)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(theme.palette.surface.separator)
                    .frame(height: 1)
            }
            .ignoresSafeArea(edges: .bottom)
            .accessibilityHidden(true)
    }

    private var footerFill: Color {
        guard let isCorrect = viewModel.run.verdict?.isCorrect else { return theme.palette.surface.background }
        return theme.palette.units.verdict(isCorrect: isCorrect).soft
    }

    // MARK: - Mapping

    /// The unit's accent, from the payload's name to the palette's slot — through `LearnView`'s own table, so the
    /// player and the map cannot come to disagree about what colour a unit is.
    private var tint: HWUnitTint { LearnView.tint(viewModel.material.unit.content.accent) }

    /// Which tone the primary button takes: the unit's accent while a question is open, and the verdict's colour
    /// once it has been graded.
    private var buttonTone: HWRunButton.Tone {
        switch viewModel.run.verdict?.isCorrect {
        case true: .right
        case false: .wrong
        case nil: .lesson(tint)
        }
    }

    /// How one option is drawn: what the reader has chosen while the question is open, and what the answer key says
    /// once it has been graded.
    ///
    /// `static` and total, so the whole translation from the run to the component is one function a test can hand
    /// every state to — and so a `body` does no mapping while it draws.
    nonisolated static func state(of option: Int, in run: LessonRun) -> HWAnswerState {
        guard let verdict = run.verdict else {
            return isChosen(option, in: run) ? .chosen : .offered
        }
        // Graded: every right answer is marked right, and the reader's wrong ones are marked wrong. An option that
        // is neither goes back to plain, which is the design clearing `.sel` off everything.
        if verdict.answers.contains(option) { return .right }
        return isChosen(option, in: run) ? .wrong : .offered
    }

    /// Whether the reader has picked this option — one on a single-choice question, any number on a multi-select.
    nonisolated static func isChosen(_ option: Int, in run: LessonRun) -> Bool {
        switch run.answer {
        case .one(let chosen): chosen == option
        case .several(let chosen): chosen.contains(option)
        case .none, .typed: false
        }
    }

    /// What VoiceOver reads as an option's state. `nil` before anything has happened, where the button's own trait
    /// is the whole story — an unconditional value would be read on every option of every question.
    nonisolated static func stateLabel(_ state: HWAnswerState) -> Text? {
        switch state {
        case .offered: nil
        case .chosen: Text("learn.player.option.chosen")
        case .right: Text("learn.player.option.right")
        case .wrong: Text("learn.player.option.wrong")
        }
    }

    /// The typed box's state: open, or graded right or wrong.
    nonisolated static func numericState(_ run: LessonRun) -> HWAnswerState {
        guard let verdict = run.verdict else { return .offered }
        return verdict.isCorrect ? .right : .wrong
    }

    /// What the one button says: `Continue` past a teaching page, `Check` an open question, and `Continue` or
    /// `Got it` once one has been graded — which is the design's own three titles.
    nonisolated static func primaryTitle(for run: LessonRun) -> LocalizedStringResource {
        guard let verdict = run.verdict else {
            return run.step?.isQuestion == true ? "learn.player.check" : "learn.player.continue"
        }
        return verdict.isCorrect ? "learn.player.continue" : "learn.player.gotIt"
    }

    /// The headline over the feedback — the design's `PRAISE` and `ENCOURAGE` lists, rotated.
    ///
    /// **App copy, and all eleven of them**, because the variety is the design's own retention behaviour rather than
    /// decoration: a lesson that says "Nice!" eight times reads as a machine. The index is derived from the run so
    /// that the same answer always produces the same words — a random one would be a screen no test could state
    /// anything about.
    /// A resource rather than a `Text`, so that a test can say *which* line was chosen: two `Text`s built from one
    /// localised key are not `==` (`LocalizedTextStorage` compares by identity), which ADR-0034 records finding the
    /// hard way about a unit caption.
    nonisolated static func headline(for verdict: LessonRun.Verdict, answered: Int) -> LocalizedStringResource {
        let lines = verdict.isCorrect ? praise : encouragement
        return lines[abs(answered) % lines.count]
    }

    /// `PRAISE` — the design's seven.
    nonisolated static let praise: [LocalizedStringResource] = [
        "learn.player.praise.1", "learn.player.praise.2", "learn.player.praise.3", "learn.player.praise.4",
        "learn.player.praise.5", "learn.player.praise.6", "learn.player.praise.7",
    ]

    /// `ENCOURAGE` — the design's four. **Not "Wrong"**: the design never says it, and a learner who is told they
    /// are wrong four times stops.
    nonisolated static let encouragement: [LocalizedStringResource] = [
        "learn.player.encourage.1", "learn.player.encourage.2",
        "learn.player.encourage.3", "learn.player.encourage.4",
    ]

    /// The right answer, as the reader should have given it: the correct options for a choice question, and the
    /// figure itself for a typed one.
    ///
    /// **A list rather than a joined string** — a separator between content items is a sentence the client assembled
    /// (ADR-0011), and a multi-select question has up to four right answers.
    private func answerText(_ verdict: LessonRun.Verdict) -> [String] {
        switch viewModel.run.step {
        case .singleChoice(let question), .multiSelect(let question):
            verdict.answers.compactMap { index in
                question.options.indices.contains(index) ? viewModel.resolved(question.options[index]) : nil
            }
        case .numeric(let question):
            // The figure, spelled where it is computed (``Curriculum/Step/Numeric/answerText``) and with no symbol
            // pushed onto it: the client owns no formatter, and a symbol inside the string lands on the wrong side
            // of an Arabic figure.
            [question.answerText]
        case .teach, nil:
            []
        }
    }
}

#if DEBUG
#Preview("The player — a teaching page") {
    LessonPlayerView(viewModel: .previewTeaching, onClose: {}).hwTheme()
}

#Preview("The player — a question, answered right") {
    LessonPlayerView(viewModel: .previewAnsweredRight, onClose: {}).hwTheme()
}

#Preview("The player — a question, answered wrong") {
    LessonPlayerView(viewModel: .previewAnsweredWrong, onClose: {}).hwTheme()
}

#Preview("The player — a typed answer") {
    LessonPlayerView(viewModel: .previewNumeric, onClose: {}).hwTheme()
}

#Preview("The player — out of hearts") {
    LessonPlayerView(viewModel: .previewOutOfHearts, onClose: {}).hwTheme()
}

#Preview("The player — Arabic, right to left") {
    LessonPlayerView(viewModel: .previewTeaching, onClose: {})
        .hwTheme()
        .hwLanguage(LanguageManager(selected: .arabic))
}

#Preview("The player — AX5, where the reading matters most") {
    LessonPlayerView(viewModel: .previewTeaching, onClose: {})
        .hwTheme()
        .dynamicTypeSize(.accessibility5)
}
#endif
