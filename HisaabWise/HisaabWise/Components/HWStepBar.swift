import SwiftUI

/// The design's `.stepbar` — where you are in a multi-step form, and the way back.
///
/// Three parts, in reading order: an optional back affordance, a run of `.dots`, and the `.steplab` that says
/// "Step 2 of 3" in words. The dots and the label say the same thing twice on purpose — the dots are for the eye
/// and the label is for everything else, which is why the dots are hidden from VoiceOver rather than each
/// carrying a position it would announce.
///
/// **Both appearances now.** It was brand-only while registration was the app's only multi-step form; Account's
/// password change is the second (#23), and the design draws its `.steps` on the light ground with the same
/// three shapes and different colours. ADR-0021's point holds — the arms are transcribed separately below rather
/// than one being derived from the other.
struct HWStepBar: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How many steps there are, and which one is current — zero-based, so `0` is the first.
    private let stepCount: Int
    private let currentIndex: Int
    /// `.steplab` — "Step 2 of 3", as copy rather than assembled from the two numbers (ADR-0011).
    private let label: LocalizedStringResource
    /// `nil` on the first step, where the design draws `.stepback[hidden]`.
    private let onBack: (() -> Void)?
    /// VoiceOver's reading of the back affordance, which is icon-only. The design gives each step its own —
    /// "Back to your details", "Back to your money details" — so it is the caller's.
    private let backLabel: LocalizedStringResource
    /// Which of the design's two surfaces the bar sits on (ADR-0021).
    private let appearance: HWAppearance

    init(
        stepCount: Int,
        currentIndex: Int,
        label: LocalizedStringResource,
        backLabel: LocalizedStringResource,
        appearance: HWAppearance = .brand,
        onBack: (() -> Void)? = nil
    ) {
        self.stepCount = stepCount
        self.currentIndex = currentIndex
        self.label = label
        self.backLabel = backLabel
        self.appearance = appearance
        self.onBack = onBack
    }

    /// `.dots i{width:7px}` and `.dots i.on{width:22px}` — the current step's dot stretches into a bar.
    private static let dotSize: CGFloat = 7
    private static let dotWidthWhenCurrent: CGFloat = 22

    var body: some View {
        HStack(spacing: 11) {
            if let onBack {
                back(onBack)
            }

            dots

            Text(label)
                .hwEyebrow(appearance)
                .opacity(0.75)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .trailing)
                // The one part of the bar that says where you are in words, so it is what a screen reader
                // reads — and it is a header, because it is the first thing on the step.
                .accessibilityAddTraits(.isHeader)
        }
    }

    /// `.stepback` — a 34pt tinted square holding a backward chevron.
    ///
    /// `chevron.backward` rather than `.left`: under Arabic the glyph mirrors with the layout, so "back" keeps
    /// pointing the way the user came from (ADR-0011).
    private func back(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "chevron.backward")
                .font(.hw(.caption).weight(.bold))
                .foregroundStyle(currentDot)
                .frame(width: HWTouchTarget.minimum, height: HWTouchTarget.minimum)
                .contentShape(.rect)
        }
        .buttonStyle(HWPressStyle.compact)
        .accessibilityLabel(Text(backLabel))
    }

    /// `.dots` — decoration, and said to be: the label beside it carries the same fact in words, so a VoiceOver
    /// user hearing both would hear the position twice.
    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(0..<max(stepCount, 0), id: \.self) { index in
                Capsule()
                    .fill(colour(at: index))
                    .frame(width: index == currentIndex ? Self.dotWidthWhenCurrent : Self.dotSize, height: Self.dotSize)
            }
        }
        .animation(
            // The dot's stretch is movement rather than a state colour, so under Reduce Motion the width
            // change is not eased — it is replaced by the colour change alone, which still says which step
            // this is (ADR-0012).
            reduceMotion ? nil : HWMotion.easeOut.animation(.standard),
            value: currentIndex
        )
        .accessibilityHidden(true)
    }

    /// `.dots i` unvisited, `.past` behind, `.on` current.
    private func colour(at index: Int) -> Color {
        if index == currentIndex { return currentDot }
        return index < currentIndex ? theme.palette.accent.muted : unvisitedDot
    }

    /// `.steps i.on{background:var(--planetary)}` in-app; the lit sky ink on the galaxy ground.
    ///
    /// The two are different roles for the same reason `HWTextField`'s border is: `--planetary` is the accent a
    /// light surface reads, and on galaxy it is barely a shade off the background.
    private var currentDot: Color {
        appearance == .brand ? theme.palette.brand.inkAccent : theme.palette.accent.base
    }

    /// `.steps i{background:var(--line-2)}` — the step not reached yet.
    private var unvisitedDot: Color {
        appearance == .brand ? theme.palette.brand.separator : theme.palette.surface.separatorStrong
    }
}

#if DEBUG
#Preview("Step bar — the three steps") {
    VStack(spacing: 28) {
        HWStepBar(stepCount: 3, currentIndex: 0, label: "Step 1 of 3", backLabel: "Back")
        HWStepBar(stepCount: 3, currentIndex: 1, label: "Step 2 of 3", backLabel: "Back to your details") {}
        HWStepBar(stepCount: 3, currentIndex: 2, label: "Step 3 of 3", backLabel: "Back to your money") {}
    }
    .padding(22)
    .background(HWPreviewGround(appearance: .brand))
    .hwTheme()
}

#Preview("Step bar — in-app, on the password change") {
    VStack(spacing: 28) {
        HWStepBar(
            stepCount: 3,
            currentIndex: 0,
            label: "Step 1 of 3",
            backLabel: "Back",
            appearance: .surface
        )
        HWStepBar(
            stepCount: 3,
            currentIndex: 1,
            label: "Step 2 of 3",
            backLabel: "Back to your current password",
            appearance: .surface
        ) {}
    }
    .padding(22)
    .background(HWPreviewGround())
    .hwTheme()
}

#Preview("AX3 — the label wraps, the bar grows") {
    HWStepBar(stepCount: 3, currentIndex: 1, label: "Step 2 of 3", backLabel: "Back to your details") {}
        .padding(22)
        .dynamicTypeSize(.accessibility3)
        .background(HWPreviewGround(appearance: .brand))
        .hwTheme()
}

#Preview("RTL — the chevron and the dots mirror") {
    HWStepBar(stepCount: 3, currentIndex: 1, label: "الخطوة 2 من 3", backLabel: "رجوع") {}
        .padding(22)
        .environment(\.layoutDirection, .rightToLeft)
        .background(HWPreviewGround(appearance: .brand))
        .hwTheme()
}
#endif
