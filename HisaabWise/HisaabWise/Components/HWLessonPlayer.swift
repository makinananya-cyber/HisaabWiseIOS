import SwiftUI

/// How an answer is drawn: untouched, chosen, or graded (#20).
///
/// A component-owned enum rather than the run's own, for ``HWLessonNodeState``'s reason: the caller says what the
/// answer *is* and the component says what that looks like. `LessonPlayerView` maps the run onto it, and a test
/// asserts the mapping is total.
enum HWAnswerState: Sendable, Equatable, CaseIterable {
    /// `.opt` — offered, and nothing has happened to it.
    case offered
    /// `.opt.sel` — the reader has picked it and has not pressed Check.
    case chosen
    /// `.opt.right` — graded, and this is an answer.
    case right
    /// `.opt.wrong` — graded, and the reader picked this one and should not have.
    case wrong
}

/// The design's `.p-top` — the way out of a lesson, how far through it the reader is, and how many hearts are left.
///
/// **Three things in one component because they are one row and one fact**: the reader glances at it to know
/// whether to keep going. Splitting it would make the progress bar a control with no context and leave the hearts
/// beside it belonging to nothing.
///
/// **The bar and the hearts are hidden from VoiceOver and said in words instead.** A 14pt track and three glyphs
/// are drawings; the caller supplies the sentences, because "Step 3 of 8" and "2 hearts left" are counts with
/// plurals in them and the words belong in the catalogue (ADR-0011, ADR-0012).
struct HWRunHeader: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How many steps are behind the reader, and how many there are. **Two counts, not a fraction** — the same
    /// shape the lesson ring is drawn from, so the bar and a "step 3 of 8" cannot round differently.
    private let stepsDone: Int
    private let stepCount: Int

    /// How many hearts are left, and how many the run started with.
    private let heartsRemaining: Int
    private let heartCount: Int

    private let tint: HWUnitTint

    /// What VoiceOver reads for the bar — "Step 3 of 8". The caller's, from the catalogue.
    private let progressLabel: Text
    /// And for the hearts — "2 of 3 hearts left".
    private let heartsLabel: Text

    /// `.p-x` — closes the lesson.
    private let onClose: () -> Void

    init(
        stepsDone: Int,
        stepCount: Int,
        heartsRemaining: Int,
        heartCount: Int,
        tint: HWUnitTint,
        progressLabel: Text,
        heartsLabel: Text,
        onClose: @escaping () -> Void
    ) {
        self.stepsDone = stepsDone
        self.stepCount = stepCount
        self.heartsRemaining = heartsRemaining
        self.heartCount = heartCount
        self.tint = tint
        self.progressLabel = progressLabel
        self.heartsLabel = heartsLabel
        self.onClose = onClose
    }

    /// `.p-bar{height:14px}`.
    private static let trackHeight: CGFloat = 14

    private var accent: HWPalette.UnitAccent { theme.palette.units.accent(tint) }

    /// How much of the track is filled. Clamped, because a payload-independent count is still a count that could
    /// be out of range while a step is being added.
    private var fill: Double {
        guard stepCount > 0 else { return 0 }
        return min(max(Double(stepsDone) / Double(stepCount), 0), 1)
    }

    var body: some View {
        HStack(spacing: 12) {
            HWIconButton(
                HWComponentCopy.closeLesson,
                systemImage: "xmark",
                action: onClose
            )

            track
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(progressLabel)

            hearts
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(heartsLabel)
        }
        .accessibilityElement(children: .contain)
    }

    /// `.p-bar` and its `.p-fill`, which grows as the reader moves through the lesson.
    private var track: some View {
        // `GeometryReader`, because the fill's width is a fraction of a width only the layout knows — the same
        // reason `HWBudgetBar` reads one.
        GeometryReader { proxy in
            Capsule()
                .fill(theme.palette.feedback.lockedSoft)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(
                            // `.leading`/`.trailing` rather than fixed points: the gradient runs the way the bar
                            // fills, which under Arabic is the other way (ADR-0011).
                            LinearGradient(
                                colors: [accent.base, accent.deep],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: fill * proxy.size.width)
                }
        }
        .frame(height: Self.trackHeight)
        // `transition:transform .45s var(--ease-out)`. Under Reduce Motion the fill is simply *there* at its new
        // width, which is the replacement rather than a slower slide (ADR-0012).
        .animation(reduceMotion ? nil : HWMotion.easeOut.animation(.emphasised), value: fill)
    }

    /// A heart's glyph: filled while it is there, an outline once it is gone.
    ///
    /// **A function rather than a ternary at the call site**, and that is a localisation-scan requirement rather than
    /// a style: `LocalisationTests` recognises keys by their shape — a dotted, lower-camel string — and cuts a
    /// symbol's *argument* out of the line before it reads them. It can only cut a literal or a simple identifier's
    /// ternary, so `systemName: index < heartsRemaining ? "heart.fill" : "heart"` left `heart.fill` reading as a
    /// catalogue key with nothing behind it.
    nonisolated static func heart(isSpent: Bool) -> String {
        isSpent ? "heart" : "heart.fill"
    }

    /// `.p-hearts` — three of them, the spent ones faded as the design fades them.
    private var hearts: some View {
        HStack(spacing: 3) {
            ForEach(0..<max(heartCount, 0), id: \.self) { index in
                Image(systemName: Self.heart(isSpent: index >= heartsRemaining))
                    // Sized through the scale rather than at the design's 19px, so a heart grows with the type
                    // beside it (ADR-0012).
                    .font(.hw(.bodyLarge))
                    .foregroundStyle(theme.palette.units.coral.base)
                    // `.p-hearts svg.gone{opacity:.22;transform:scale(.82)}` — and the outline glyph as well, so
                    // a spent heart is not only fainter but a different shape: opacity alone is a state a reader
                    // with low vision can miss.
                    .opacity(index < heartsRemaining ? 1 : 0.32)
            }
        }
        // The spend is a state change rather than a movement, so the fade is eased and the design's `heartHit`
        // pulse is not converted: an attention bounce has nothing to replace it with under Reduce Motion, and the
        // sentence beside it already says how many are left (ADR-0012).
        .animation(reduceMotion ? nil : HWMotion.easeOut.animation(.standard), value: heartsRemaining)
    }
}

/// The design's `.combo` — "COMBO ×3", the pill that lands on every third consecutive right answer.
///
/// **It is decoration with a replacement, not decoration alone.** The design's version scales in, holds, and floats
/// away; under Reduce Motion it cross-fades instead of springing (ADR-0012), and the screen posts an announcement
/// either way — because neither the animated nor the static form reaches VoiceOver on its own, which is one of the
/// two cases `HWAnnouncement` exists for.
struct HWComboBadge: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// "COMBO ×3" — the caller's, because the number is the run's and the word is the catalogue's.
    private let text: Text
    private let isPresented: Bool

    init(text: Text, isPresented: Bool) {
        self.text = text
        self.isPresented = isPresented
    }

    var body: some View {
        text
            .font(.hw(.micro).weight(.heavy))
            .tracking(0.8)
            .textCase(.uppercase)
            // `background:var(--sun);color:#5A3D00` — the sun accent's own deep ink rather than the design's
            // one-off brown, which is not a token.
            .foregroundStyle(theme.palette.units.sun.deep)
            .padding(.horizontal, 13)
            .padding(.vertical, 5)
            .hwBox(fill: theme.palette.units.sun.base, radius: .medium, elevation: .small)
            .fixedSize(horizontal: false, vertical: true)
            .opacity(isPresented ? 1 : 0)
            // The spring is the celebration; the cross-fade is what is left of it when movement is unwelcome.
            .scaleEffect(reduceMotion || isPresented ? 1 : 0.85)
            .animation(
                reduceMotion
                    ? HWMotion.easeInOut.animation(.standard)
                    : HWMotion.easeBack.animation(.emphasised),
                value: isPresented
            )
            // Said by the screen's announcement instead: a floating badge is a second element about the answer
            // beside it, and a VoiceOver user hearing both hears the combo twice.
            .accessibilityHidden(true)
    }
}

/// The design's `.btn-go` / `.btn-ok` / `.btn-no` — the lesson player's one primary control.
///
/// **Not a fifth ``HWButtonVariant``, and the reason is what it is tinted by.** `HWButtonAppearance` resolves a
/// fill from a variant, an appearance, and the palette; this control's fill is the *unit's* accent while a question
/// is open and the *verdict's* colour once it has been graded — neither of which that type can see. Folding them in
/// would also make `.primary` with a verdict representable, which is the shape one enum with one job avoids.
///
/// It is still a component rather than something the screen styles: a screen never draws a button (ADR-0018's
/// vocabulary rule), and this is the button the player draws.
struct HWRunButton: View {
    @Environment(ThemeManager.self) private var theme

    /// What the button is for at this moment, which is also what it is coloured by.
    enum Tone: Sendable, Equatable {
        /// `.btn-go` — Continue or Check, in the unit's accent.
        case lesson(HWUnitTint)
        /// `.btn-ok` — Continue, after a right answer.
        case right
        /// `.btn-no` — Got it, after a wrong one.
        case wrong
    }

    private let title: LocalizedStringResource
    private let tone: Tone
    private let isEnabled: Bool
    private let action: () -> Void

    init(_ title: LocalizedStringResource, tone: Tone, isEnabled: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.tone = tone
        self.isEnabled = isEnabled
        self.action = action
    }

    /// `.btn{height:54px}`, as a **minimum** so AX5 grows the control rather than clipping it — the same reading
    /// ``HWButton/minimumHeight`` takes of the design's height cluster.
    private static let minimumHeight: CGFloat = 54

    private var fill: AnyShapeStyle {
        guard isEnabled else { return AnyShapeStyle(theme.palette.feedback.lockedSoft) }
        switch tone {
        case .lesson(let tint):
            let accent = theme.palette.units.accent(tint)
            return AnyShapeStyle(
                LinearGradient(
                    colors: [accent.base, accent.deep],
                    // Two `UnitPoint`s rather than the design's 150°, so the fill mirrors with the layout
                    // (ADR-0011).
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case .right:
            return AnyShapeStyle(theme.palette.units.verdict(isCorrect: true).base)
        case .wrong:
            return AnyShapeStyle(theme.palette.units.verdict(isCorrect: false).base)
        }
    }

    /// `.btn[disabled]{color:#9BA5BC}` — the locked role's own ink, rather than the design's one-off grey.
    private var ink: Color {
        isEnabled ? theme.palette.brand.ink : theme.palette.surface.inkTertiary
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.hw(.bodyLarge).weight(.heavy))
                .textCase(.uppercase)
                .foregroundStyle(ink)
                .multilineTextAlignment(.center)
                // Wraps rather than shrinking, so a longer language grows the button (ADR-0011).
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: Self.minimumHeight)
                .padding(.horizontal, 16)
                .hwBox(fill: fill, radius: .large, elevation: isEnabled ? .small : nil)
                .contentShape(.rect)
        }
        .buttonStyle(HWPressStyle())
        .disabled(!isEnabled)
        .accessibilityLabel(Text(title))
    }
}

/// The design's `.kicker` — the small tinted chip above a step saying what kind of step it is.
///
/// "UNIT 1 · GROSS VS. NET INCOME" on a teaching page, "CHOOSE ONE" or "TYPE THE NUMBER" on a question. The caller
/// supplies the words because only it knows which of the two it is holding — a unit caption is server content and
/// a question's instruction is app copy (ADR-0020).
struct HWKicker: View {
    @Environment(ThemeManager.self) private var theme

    private let text: Text
    private let systemImage: String
    private let tint: HWUnitTint

    init(text: Text, systemImage: String, tint: HWUnitTint) {
        self.text = text
        self.systemImage = systemImage
        self.tint = tint
    }

    private var accent: HWPalette.UnitAccent { theme.palette.units.accent(tint) }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.hw(.micro))
                .accessibilityHidden(true)

            text
                .font(.hw(.micro).weight(.bold))
                .tracking(1.2)
                .textCase(.uppercase)
                .fixedSize(horizontal: false, vertical: true)
        }
        // `background:var(--acc-soft);color:var(--acc-deep)` — the one place in this file where the design's own
        // accent-on-wash pairing measures well enough to keep, because the wash is the pale `soft` value rather
        // than the saturated `base` (ADR-0034's finding).
        .foregroundStyle(accent.deep)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .hwBox(fill: accent.soft, radius: .small)
    }
}

/// The design's `.opt` — one answer, offered and then graded.
///
/// **It stays a button after grading rather than becoming disabled.** The design sets `el.disabled = true` on every
/// option once Check is pressed, which in SwiftUI would take the graded answers out of the accessibility tree —
/// so the reader who most needs to hear "this was the right one" would hear nothing. It is enabled and *inert*
/// instead: the caller stops accepting choices, and the state is announced as the option's value.
struct HWAnswerOption: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The option's text. **Server content**, so it arrives as a `String` and is drawn with its markdown emphasis
    /// (``HWMarkdown``).
    private let text: String
    private let state: HWAnswerState
    /// Whether several answers may be chosen — which the design says with the shape of the box: a square for
    /// multi-select, a circle for one-of.
    private let allowsMany: Bool
    /// What VoiceOver reads as the option's state: "chosen", "the right answer", "your answer, and it is wrong".
    /// `nil` before anything has happened, where the button's own trait is the whole story.
    private let stateLabel: Text?
    private let action: () -> Void

    init(
        text: String,
        state: HWAnswerState,
        allowsMany: Bool,
        stateLabel: Text? = nil,
        action: @escaping () -> Void
    ) {
        self.text = text
        self.state = state
        self.allowsMany = allowsMany
        self.stateLabel = stateLabel
        self.action = action
    }

    /// `.opt-box{width:24px}`.
    private static let boxSize: CGFloat = 24

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                mark

                Text(HWMarkdown.attributed(text))
                    .font(.hw(.bodyLarge))
                    .foregroundStyle(theme.palette.surface.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(15)
            .frame(minHeight: HWTouchTarget.minimum)
            .hwBox(fill: fill, radius: .large, border: border, borderWidth: 2)
            .contentShape(.rect)
        }
        .buttonStyle(HWPressStyle.compact)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: text))
        .accessibilityValue(stateLabel ?? Text(verbatim: ""))
        // The border and the fill move together, so one animation covers the whole state change — and under
        // Reduce Motion the new colours are simply there (ADR-0012).
        .animation(reduceMotion ? nil : HWMotion.easeOut.animation(.quick), value: state)
    }

    /// `.opt-box` — a tick when the option is chosen or right, and a cross when it is the reader's wrong one.
    ///
    /// **A cross rather than a tick in the red box**, which is the design's own correction: a tick inside a danger
    /// fill reads as a contradiction.
    private var mark: some View {
        Image(systemName: state == .wrong ? "xmark" : "checkmark")
            .font(.hw(.caption).weight(.heavy))
            .foregroundStyle(theme.palette.brand.ink)
            .opacity(state == .offered ? 0 : 1)
            .frame(width: Self.boxSize, height: Self.boxSize)
            .hwBox(
                fill: markFill,
                // **The shape is how the design says "pick more than one"**, so the two have to be
                // unmistakable — and `.small` is not. That step is 11pt, collapsed from the design's 10–12px
                // cluster around *large* controls, and on a 24pt box it draws a circle: put beside the
                // single-choice pill it made the two kinds of question look identical. Found by looking at a
                // render. `.hairline` is the step that reads as a square at this size.
                radius: allowsMany ? .hairline : .pill,
                border: state == .offered ? theme.palette.surface.separatorStrong : markFill,
                borderWidth: 2
            )
            .accessibilityHidden(true)
    }

    /// The graded pair comes from ``HWPalette/Units/verdict(isCorrect:)``, so "mint means right" is decided in one
    /// place for the whole player rather than re-derived at each of the eight sites that draws it.
    private var verdict: HWPalette.UnitAccent? {
        switch state {
        case .offered, .chosen: nil
        case .right: theme.palette.units.verdict(isCorrect: true)
        case .wrong: theme.palette.units.verdict(isCorrect: false)
        }
    }

    private var markFill: Color {
        guard let verdict else { return state == .chosen ? theme.palette.accent.base : .clear }
        return verdict.base
    }

    /// `.opt{background:var(--card)}` and the three graded washes.
    private var fill: Color {
        guard let verdict else {
            return state == .chosen ? theme.palette.accent.tint : theme.palette.surface.raised
        }
        return verdict.soft
    }

    private var border: Color {
        guard let verdict else {
            return state == .chosen ? theme.palette.accent.base : theme.palette.surface.separator
        }
        return verdict.base
    }
}

/// The design's `.numwrap` — the box a figure is typed into, with the display currency's symbol beside it when the
/// question is about money.
///
/// **It is not ``HWMoneyField``, and the difference is the point.** That field is for an amount on its way to the
/// server as `{minor, currency}` and announces itself with an ISO code; this is an *answer to a question*, which may
/// be a percentage or a number of years, and eleven of the curriculum's fourteen numeric steps happen to be money
/// while three are not. The symbol here is decoration the step asks for, and there is no currency travelling with
/// what is typed.
///
/// **The symbol is a view beside the box rather than a character in the string**, which is what makes it mirror: a
/// symbol pushed onto the front of a figure lands on the wrong side of it in Arabic (ADR-0033's finding, applied to
/// an input).
struct HWAnswerField: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isFocused: Bool

    /// What VoiceOver calls the box. The design's `aria-label="Your answer"`.
    private let label: LocalizedStringResource
    @Binding private var text: String
    /// The display currency's symbol, or `nil` on a question that is not about money.
    private let symbol: String?
    /// `.numwrap.right` / `.numwrap.wrong`, or ``HWAnswerState/offered`` while the question is open.
    private let state: HWAnswerState
    /// The design's `.num-hint` — "Whole numbers are fine — no commas needed."
    private let hint: LocalizedStringResource?
    /// Whether the box still takes typing. `false` once the answer has been graded, as the design disables it.
    private let isEditable: Bool

    init(
        _ label: LocalizedStringResource,
        text: Binding<String>,
        symbol: String? = nil,
        state: HWAnswerState = .offered,
        hint: LocalizedStringResource? = nil,
        isEditable: Bool = true
    ) {
        self.label = label
        self._text = text
        self.symbol = symbol
        self.state = state
        self.hint = hint
        self.isEditable = isEditable
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            box

            if let hint {
                Text(hint)
                    .font(.hw(.caption))
                    .foregroundStyle(theme.palette.surface.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .animation(reduceMotion ? nil : HWMotion.easeOut.animation(.quick), value: state)
    }

    private var box: some View {
        HStack(spacing: 10) {
            if let symbol {
                Text(verbatim: symbol)
                    .font(.hw(.heading))
                    .foregroundStyle(theme.palette.accent.deep)
                    // Read as part of the field's value below rather than as a loose "₹".
                    .accessibilityHidden(true)
            }

            TextField(text: $text) { Text(label) }
                .textFieldStyle(.plain)
                .font(.hw(.heading))
                // `font-variant-numeric:tabular-nums`, so a figure does not shuffle as it is typed.
                .monospacedDigit()
                .foregroundStyle(theme.palette.surface.ink)
                .tint(theme.palette.accent.base)
                // `inputmode="decimal"` — a keypad with a separator, because an answer can have a fraction and the
                // tolerance is what makes typing one work.
                .keyboardType(.decimalPad)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .disabled(!isEditable)
                .focused($isFocused)
                .accessibilityLabel(Text(label))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .frame(minHeight: HWTextField.minimumHeight)
        .hwBox(fill: fill, radius: .extraLarge, border: border, borderWidth: 2)
    }

    /// Which of the graded pair, or `nil` while the question is open.
    ///
    /// **`.chosen` reads as open here, and that is the one case of ``HWAnswerState`` this control cannot use**: a box
    /// has no "picked it" state, because typing *is* the choosing. It takes the shared enum anyway rather than a
    /// fourth vocabulary for one control — `LessonPlayerView.numericState(_:)` never produces the case, so the inert
    /// value is unreachable from the app.
    private var verdict: HWPalette.UnitAccent? {
        switch state {
        case .offered, .chosen: nil
        case .right: theme.palette.units.verdict(isCorrect: true)
        case .wrong: theme.palette.units.verdict(isCorrect: false)
        }
    }

    /// `.numwrap{background:var(--card)}` and the two graded washes.
    private var fill: Color {
        verdict?.soft ?? theme.palette.surface.raised
    }

    /// `:focus-within{border-color:var(--acc)}`, and the graded pair.
    private var border: Color {
        if let verdict { return verdict.base }
        return isFocused ? theme.palette.accent.muted : theme.palette.surface.separator
    }
}

/// The design's `.fb` — what the footer says once an answer has been graded.
///
/// A glyph, a headline, the right answer when the reader missed it, and the step's own explanation — which is the
/// *teaching* half of a question and is shown whether the answer was right or wrong.
///
/// **The right answer is a list, not a joined string.** The design writes `s.correct.map(...).join(' · ')`; a
/// separator between content items is a sentence the client assembled, and a multi-select question has up to four
/// of them (ADR-0011).
struct HWFeedbackNote: View {
    @Environment(ThemeManager.self) private var theme

    private let isCorrect: Bool
    /// "Exactly right!" / "Not quite" — app copy, rotated by the screen as the design rotates it.
    private let headline: Text
    /// "The right answer:" — drawn only when there is one to show.
    private let answerCaption: LocalizedStringResource?
    /// The answers the reader should have given, as server content. Empty when they got it right.
    private let answers: [String]
    /// The step's `explanation`. Server content, with its markdown emphasis.
    private let explanation: String

    init(
        isCorrect: Bool,
        headline: Text,
        answerCaption: LocalizedStringResource? = nil,
        answers: [String] = [],
        explanation: String
    ) {
        self.isCorrect = isCorrect
        self.headline = headline
        self.answerCaption = answerCaption
        self.answers = answers
        self.explanation = explanation
    }

    private var accent: HWPalette.UnitAccent {
        theme.palette.units.verdict(isCorrect: isCorrect)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                Image(systemName: isCorrect ? "checkmark" : "xmark")
                    .font(.hw(.caption).weight(.heavy))
                    .foregroundStyle(theme.palette.brand.ink)
                    .frame(width: 32, height: 32)
                    .hwBox(fill: accent.base, radius: .pill)
                    .accessibilityHidden(true)

                headline
                    .font(.hw(.subheading))
                    .foregroundStyle(accent.deep)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let answerCaption, !answers.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text(answerCaption)
                        .font(.hw(.caption).weight(.semibold))
                        .foregroundStyle(theme.palette.surface.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(Array(answers.enumerated()), id: \.offset) { _, answer in
                        Text(HWMarkdown.attributed(answer))
                            .font(.hw(.caption).weight(.bold))
                            .foregroundStyle(accent.deep)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .hwBox(fill: theme.palette.surface.raised, radius: .medium, border: theme.palette.surface.separator)
            }

            Text(HWMarkdown.attributed(explanation))
                .font(.hw(.body))
                .foregroundStyle(theme.palette.surface.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // One element: a glyph, a headline, a box, and a paragraph are four views saying one thing about the answer
        // the reader has just given.
        .accessibilityElement(children: .combine)
    }
}

/// The design's `.t-li` — one term-and-explanation row on a teaching page.
struct HWTeachingEntry: View {
    @Environment(ThemeManager.self) private var theme

    private let term: String
    private let detail: String
    private let tint: HWUnitTint

    init(term: String, detail: String, tint: HWUnitTint) {
        self.term = term
        self.detail = detail
        self.tint = tint
    }

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            // `.t-dot` — the accent bullet, which is decoration and says nothing.
            Circle()
                .fill(theme.palette.units.accent(tint).base)
                .frame(width: 8, height: 8)
                .padding(.top, 6)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(HWMarkdown.attributed(term))
                    .font(.hw(.bodyLarge).weight(.heavy))
                    .foregroundStyle(theme.palette.surface.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text(HWMarkdown.attributed(detail))
                    .font(.hw(.body))
                    .foregroundStyle(theme.palette.surface.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(13)
        .hwBox(
            fill: theme.palette.surface.raised,
            radius: .medium,
            border: theme.palette.surface.separator,
            elevation: .small
        )
        // The term and its explanation are one thing to read, which is what `ArticleView`'s entries do too.
        .accessibilityElement(children: .combine)
    }
}

/// The design's `.eg` — a worked example, in the unit's own wash.
///
/// Its body carries its own blank lines, because the breaks are *inside* one calculation rather than between
/// paragraphs (``Curriculum/Step/Example``).
struct HWWorkedExample: View {
    @Environment(ThemeManager.self) private var theme

    private let heading: String
    /// The worked calculation, carrying its own blank lines. Named `text` rather than `body`, which is the one name
    /// a `View` cannot have twice.
    private let text: String
    private let tint: HWUnitTint

    init(heading: String, text: String, tint: HWUnitTint) {
        self.heading = heading
        self.text = text
        self.tint = tint
    }

    private var accent: HWPalette.UnitAccent { theme.palette.units.accent(tint) }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Image(systemName: "sparkles")
                    .font(.hw(.micro))
                    .accessibilityHidden(true)

                Text(HWMarkdown.attributed(heading))
                    .font(.hw(.micro).weight(.bold))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(accent.deep)

            Text(HWMarkdown.attributed(text))
                .font(.hw(.body))
                .foregroundStyle(theme.palette.surface.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .hwBox(fill: accent.soft, radius: .large)
        .accessibilityElement(children: .combine)
    }
}

/// The design's `.tip` — the dashed "Remember it:" box at the end of a teaching page.
///
/// **The caption is app copy and the sentence is content**, which is why they arrive separately: "Remember it:" is
/// the app's word for what the box is, and the tip itself is the writer's.
struct HWTeachingTip: View {
    @Environment(ThemeManager.self) private var theme

    private let caption: LocalizedStringResource
    private let text: String

    init(caption: LocalizedStringResource, text: String) {
        self.caption = caption
        self.text = text
    }

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "lightbulb")
                .font(.hw(.bodyLarge))
                .foregroundStyle(theme.palette.units.sun.deep)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(caption)
                    .font(.hw(.caption).weight(.heavy))
                    // `.tip b{color:#553D06}` — the sun accent's deep value, which is the token for that brown.
                    .foregroundStyle(theme.palette.units.sun.deep)
                    .fixedSize(horizontal: false, vertical: true)

                Text(HWMarkdown.attributed(text))
                    .font(.hw(.body))
                    .foregroundStyle(theme.palette.surface.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        // `border:1px dashed rgba(240,180,41,.55)` — the dash is the design's, and `hwBox` carries it so that a
        // second dashed border is not drawn by hand (``HWEmptyNote`` is the other caller).
        .hwBox(
            fill: theme.palette.units.sun.soft,
            radius: .large,
            border: theme.palette.units.sun.base,
            borderDash: HWBorderDash.standard
        )
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("The player's chrome — progress, hearts, and a combo") {
    VStack(spacing: 26) {
        HWRunHeader(
            stepsDone: 3,
            stepCount: 8,
            heartsRemaining: 3,
            heartCount: 3,
            tint: .sun,
            progressLabel: Text(verbatim: "Step 4 of 8"),
            heartsLabel: Text(verbatim: "3 of 3 hearts left")
        ) {}

        HWRunHeader(
            stepsDone: 6,
            stepCount: 8,
            heartsRemaining: 1,
            heartCount: 3,
            tint: .coral,
            progressLabel: Text(verbatim: "Step 7 of 8"),
            heartsLabel: Text(verbatim: "1 of 3 hearts left")
        ) {}

        HWComboBadge(text: Text(verbatim: "Combo ×3"), isPresented: true)
    }
    .padding(22)
    .background(HWPreviewGround())
    .hwTheme()
}

#Preview("A question — offered, chosen, and both graded states") {
    VStack(spacing: 12) {
        HWKicker(text: Text(verbatim: "Choose one"), systemImage: "star", tint: .mint)

        HWAnswerOption(text: "The money that actually arrives", state: .offered, allowsMany: false) {}
        HWAnswerOption(text: "The number in your contract", state: .chosen, allowsMany: false) {}
        HWAnswerOption(
            text: "The money that **actually** arrives",
            state: .right,
            allowsMany: true,
            stateLabel: Text(verbatim: "The right answer")
        ) {}
        HWAnswerOption(
            text: "Your gross pay",
            state: .wrong,
            allowsMany: true,
            stateLabel: Text(verbatim: "Your answer, and it is wrong")
        ) {}
    }
    .padding(22)
    .background(HWPreviewGround())
    .hwTheme()
}

#Preview("A typed answer — open, right, and wrong") {
    @Previewable @State var open = ""
    @Previewable @State var right = "3600"
    @Previewable @State var wrong = "4000"

    VStack(spacing: 20) {
        HWAnswerField(
            "Your answer",
            text: $open,
            symbol: "₹",
            hint: "Whole numbers are fine — no commas needed."
        )
        HWAnswerField("Your answer", text: $right, symbol: "₹", state: .right, isEditable: false)
        HWAnswerField("Your answer", text: $wrong, state: .wrong, isEditable: false)
    }
    .padding(22)
    .background(HWPreviewGround())
    .hwTheme()
}

#Preview("The feedback footer, right and wrong") {
    VStack(spacing: 20) {
        HWFeedbackNote(
            isCorrect: true,
            headline: Text(verbatim: "Exactly right!"),
            explanation: "Net pay is what lands in the account. **Plan with the money, not the promise.**"
        )

        HWFeedbackNote(
            isCorrect: false,
            headline: Text(verbatim: "Not quite"),
            answerCaption: "The right answer:",
            answers: ["Rent", "Groceries", "Medicine"],
            explanation: "Rent, food and medicine keep you safe and healthy."
        )
    }
    .padding(22)
    .background(HWPreviewGround())
    .hwTheme()
}

#Preview("A teaching page's three blocks") {
    VStack(spacing: 14) {
        HWTeachingEntry(
            term: "Basic salary",
            detail: "The main part of your pay, and what your gratuity is worked out on.",
            tint: .sky
        )
        HWWorkedExample(
            heading: "Same total, different basic",
            text: "Two people both earn **₹8,000** a month.\n\n**Sara:** basic ₹5,000 + allowances ₹3,000",
            tint: .sky
        )
        HWTeachingTip(
            caption: "Remember it:",
            text: "Gross = the promise. Net = the money. Plan with the money."
        )
    }
    .padding(22)
    .background(HWPreviewGround())
    .hwTheme()
}

#Preview("AX3 — every block grows and the option boxes stay put") {
    @Previewable @State var typed = "3600"

    ScrollView {
        VStack(spacing: 14) {
            HWRunHeader(
                stepsDone: 3,
                stepCount: 8,
                heartsRemaining: 2,
                heartCount: 3,
                tint: .violet,
                progressLabel: Text(verbatim: "Step 4 of 8"),
                heartsLabel: Text(verbatim: "2 of 3 hearts left")
            ) {}
            HWAnswerOption(text: "The money that actually arrives in your account", state: .chosen, allowsMany: false) {}
            HWAnswerField("Your answer", text: $typed, symbol: "₹", state: .right, isEditable: false)
            HWTeachingTip(caption: "Remember it:", text: "Plan with the money that arrives.")
        }
        .padding(22)
    }
    .dynamicTypeSize(.accessibility3)
    .background(HWPreviewGround())
    .hwTheme()
}

#Preview("RTL — the bar fills from the right and the marks lead") {
    // Latin digits under Arabic, which is ADR-0011's decision rather than an oversight in the preview: UAE
    // financial figures are conventionally written in Western digits and the server sends none other.
    @Previewable @State var typed = "3600"

    VStack(spacing: 14) {
        HWRunHeader(
            stepsDone: 3,
            stepCount: 8,
            heartsRemaining: 2,
            heartCount: 3,
            tint: .sun,
            progressLabel: Text(verbatim: "الخطوة 4 من 8"),
            heartsLabel: Text(verbatim: "قلبان من 3")
        ) {}
        HWKicker(text: Text(verbatim: "اختر واحدة"), systemImage: "star", tint: .sun)
        HWAnswerOption(text: "المال الذي يصل إلى حسابك", state: .chosen, allowsMany: false) {}
        HWAnswerField("إجابتك", text: $typed, symbol: "د.إ")
    }
    .padding(22)
    .environment(\.layoutDirection, .rightToLeft)
    .background(HWPreviewGround())
    .hwTheme()
}
#endif
