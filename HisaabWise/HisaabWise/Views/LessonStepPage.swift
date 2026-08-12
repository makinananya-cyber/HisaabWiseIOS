import SwiftUI

/// One step, drawn: a page of teaching, a question with options, or a box to type a figure into.
///
/// **Separate from ``LessonPlayerView`` for the reason `LearnMapPage` is separate from `LearnView`** — `ImageRenderer`
/// does not lay out the content of a `ScrollView`, so a render of the whole player comes back as an empty ground and
/// a test asserting that it rendered passes on it (ADR-0033). Everything the reader reads is here.
///
/// It holds no view model, deliberately: it takes the step it draws, the run's own state, and two closures. So a test
/// can render every one of the four step kinds without a transport, and nothing in it can fetch or grade.
struct LessonStepPage: View {
    @Environment(ThemeManager.self) private var theme

    let step: Curriculum.Step

    /// The run, for what has been chosen and what the verdict is. **Read, never changed** — the two ways to change it
    /// are the closures below.
    let run: LessonRun

    /// "UNIT 1 · GROSS VS. NET INCOME" — composed by the screen, because it joins a number and a server string.
    let kicker: Text

    let tint: HWUnitTint

    /// What `{c}` becomes in this lesson's text (ADR-0016).
    let currencyToken: CurrencyToken

    /// The numeric box's text, bound through the view model so that the run owns the answer and the field owns
    /// nothing.
    let typed: Binding<String>

    let onChoose: (Int) -> Void

    var body: some View {
        switch step {
        case .teach(let teaching): self.teaching(teaching)
        case .singleChoice(let question): self.question(question, allowsMany: false)
        case .multiSelect(let question): self.question(question, allowsMany: true)
        case .numeric(let question): numeric(question)
        }
    }

    private func resolved(_ text: String) -> String { currencyToken.resolve(text) }

    /// A teaching page: the kicker, the heading, the prose, whichever blocks this step carries, and the tip.
    ///
    /// **Every string is server content with `{c}` resolved** (ADR-0016) and its emphasis in markdown (``HWMarkdown``)
    /// — the design writes `<b>` inline, which cannot reach a `Text`. The figures inside an example are
    /// *illustrative*: only the symbol follows the reader's account, and the amounts keep the numbers they were
    /// written around.
    private func teaching(_ teaching: Curriculum.Step.Teach) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HWKicker(text: kicker, systemImage: "lightbulb", tint: tint)

            Text(HWMarkdown.attributed(resolved(teaching.heading)))
                .font(.hw(.heading))
                .foregroundStyle(theme.palette.surface.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            paragraphs(teaching.paragraphs)

            ForEach(teaching.list) { entry in
                HWTeachingEntry(term: resolved(entry.term), detail: resolved(entry.detail), tint: tint)
            }

            // **After the list, because the position is load-bearing**: the sentence refers back to the items above
            // it (``Curriculum/Step/Teach/afterList``).
            paragraphs(teaching.afterList)

            if let example = teaching.example {
                HWWorkedExample(heading: resolved(example.heading), text: resolved(example.body), tint: tint)
            }

            if let tip = teaching.tip {
                HWTeachingTip(caption: "learn.player.tip", text: resolved(tip))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func paragraphs(_ paragraphs: [String]) -> some View {
        // Keyed by position: two paragraphs of a lesson can read alike, and a duplicate identity draws one of them.
        ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
            Text(HWMarkdown.attributed(resolved(paragraph)))
                .font(.hw(.bodyLarge))
                .foregroundStyle(theme.palette.surface.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// A question with options — one right answer or several.
    private func question(_ question: Curriculum.Step.Question, allowsMany: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HWKicker(
                text: Text(allowsMany ? "learn.player.kind.multi" : "learn.player.kind.single"),
                systemImage: "star",
                tint: tint
            )

            prompt(question.prompt)

            ForEach(Array(question.options.enumerated()), id: \.offset) { index, text in
                option(index, text: text, allowsMany: allowsMany)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func option(_ index: Int, text: String, allowsMany: Bool) -> some View {
        let state = LessonPlayerView.state(of: index, in: run)
        return HWAnswerOption(
            text: resolved(text),
            state: state,
            allowsMany: allowsMany,
            stateLabel: LessonPlayerView.stateLabel(state),
            action: { onChoose(index) }
        )
    }

    /// A question the reader types a figure into.
    ///
    /// **The symbol is drawn beside the box rather than pushed onto the string**, so it mirrors under Arabic — and the
    /// box takes it only when the question is about money, which eleven of the fourteen numeric steps are
    /// (``Curriculum/Step/Numeric/showsCurrencySymbol``).
    private func numeric(_ question: Curriculum.Step.Numeric) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HWKicker(text: Text("learn.player.kind.numeric"), systemImage: "number", tint: tint)

            prompt(question.prompt)

            HWAnswerField(
                "learn.player.answer.label",
                text: typed,
                symbol: question.showsCurrencySymbol ? currencyToken.token : nil,
                state: LessonPlayerView.numericState(run),
                hint: "learn.player.answer.hint",
                isEditable: run.verdict == nil
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func prompt(_ prompt: String) -> some View {
        Text(HWMarkdown.attributed(resolved(prompt)))
            .font(.hw(.subheading))
            .foregroundStyle(theme.palette.surface.ink)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

#if DEBUG
/// The corpus's own steps, so a preview draws the content the app will draw (ADR-0013).
@MainActor
private func previewPage(
    lessonID: String,
    index: Int,
    typed: Binding<String> = .constant("")
) -> some View {
    let material = LessonPlayerViewModel.previewMaterial(lessonID: lessonID)
    let steps = material.lesson.content.steps
    guard steps.indices.contains(index) else {
        preconditionFailure("\(lessonID) has no step \(index)")
    }
    return LessonStepPage(
        step: steps[index],
        run: LessonRun(lessonID: lessonID, steps: steps),
        kicker: Text(verbatim: "Unit 1 · \(material.lesson.content.title)"),
        tint: LearnView.tint(material.unit.content.accent),
        currencyToken: material.currencyToken,
        typed: typed,
        onChoose: { _ in }
    )
}

#Preview("A teaching page — prose, a list, an example, and a tip") {
    ScrollView { previewPage(lessonID: "u1l1", index: 1).padding(20) }.hwTheme()
}

#Preview("A single-choice question") {
    ScrollView { previewPage(lessonID: "u1l1", index: 4).padding(20) }.hwTheme()
}

#Preview("A multi-select question") {
    ScrollView { previewPage(lessonID: "u1l3", index: 4).padding(20) }.hwTheme()
}

#Preview("A typed answer, with the reader's own symbol beside the box") {
    @Previewable @State var typed = "3600"

    ScrollView { previewPage(lessonID: "u1l1", index: 6, typed: $typed).padding(20) }.hwTheme()
}

#Preview("RTL — the bullets and the boxes lead on the right") {
    ScrollView { previewPage(lessonID: "u1l1", index: 2).padding(20) }
        .hwTheme()
        .hwLanguage(LanguageManager(selected: .arabic))
}

#Preview("AX5 — a lesson step is reading content, so it scales unclamped") {
    ScrollView { previewPage(lessonID: "u1l1", index: 1).padding(20) }
        .hwTheme()
        .dynamicTypeSize(.accessibility5)
}
#endif
