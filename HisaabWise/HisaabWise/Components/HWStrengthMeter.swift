import SwiftUI

/// The design's `.meter` — four bars and a word, under the password box.
///
/// **It gates nothing and says so.** The only rule that refuses a password is 8+ characters (invariant 4); this
/// is feedback, which is why it takes a count rather than a verdict and why nothing about it is an error colour.
///
/// Purely presentational: `filled` out of `outOf`, and the word to draw. What the score *means* is
/// `PasswordStrength`'s, in `Models` — a component that computed it would be a component with an opinion about
/// passwords.
///
/// **Both appearances.** The design draws a strength meter on registration's galaxy ground and on Account's
/// light one, and the two are the same four bars over different colours (ADR-0021) — Account's password step
/// (#23) is the second caller that settled it.
struct HWStrengthMeter: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let filled: Int
    private let outOf: Int
    /// The `.meter-label` — "Weak", "Strong". `nil` draws the bars alone.
    private let label: LocalizedStringResource?
    /// Which of the design's two surfaces the meter sits on (ADR-0021). Account is the second caller the
    /// appearance was waiting for.
    private let appearance: HWAppearance

    init(filled: Int, outOf: Int, label: LocalizedStringResource?, appearance: HWAppearance = .brand) {
        self.filled = filled
        self.outOf = outOf
        self.label = label
        self.appearance = appearance
    }

    /// `.meter i{height:3px}`.
    private static let barHeight: CGFloat = 3

    /// The design's four `LEVELS` colours, resolved to the roles that hold exactly those values: `--venus`,
    /// `--universe`, `--planetary`, `--sky`.
    ///
    /// The lit bars all take the colour of the level *reached* — `bars.forEach(… --fill: lvl.color)` — so a
    /// strong password's four bars are all sky rather than a gradient through the four. Transcribed, because the
    /// alternative reads as a progress bar rather than as a verdict.
    /// **On `surface` the fourth level cannot be `--sky`, and that is the one departure.** The design's fourth
    /// colour is the palest of the four, which reads as *strongest* on the galaxy ground and as almost nothing on
    /// an off-white one. So the in-app ramp runs the other way — muted, base, deep, and the ink — which keeps the
    /// design's decision (darker is stronger *against this ground*) rather than its four hex values (#23).
    private var fill: Color {
        switch (appearance, filled) {
        case (.brand, ...1): theme.palette.brand.inkSecondary
        case (.brand, 2): theme.palette.accent.muted
        case (.brand, 3): theme.palette.accent.base
        case (.brand, _): theme.palette.brand.inkAccent
        case (.surface, ...1): theme.palette.accent.muted
        case (.surface, 2): theme.palette.accent.base
        case (.surface, 3): theme.palette.accent.deep
        case (.surface, _): theme.palette.surface.ink
        }
    }

    /// `.meter i{background:var(--line-2)}` — the unlit bar.
    private var track: Color {
        appearance == .brand ? theme.palette.brand.separator : theme.palette.surface.separatorStrong
    }

    /// `.meter span{color:var(--ink-3)}`.
    private var wordInk: Color {
        appearance == .brand ? theme.palette.brand.inkSecondary : theme.palette.surface.inkSecondary
    }

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<max(outOf, 0), id: \.self) { index in
                Capsule()
                    .fill(index < filled ? fill : track)
                    .frame(height: Self.barHeight)
            }

            if let label {
                Text(label)
                    .font(.hw(.caption))
                    .foregroundStyle(wordInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // The bars fill left-to-right in the design; under Reduce Motion the fill still changes, it just
        // arrives rather than sweeping (ADR-0012).
        .animation(
            reduceMotion ? HWMotion.easeInOut.animation(.quick) : HWMotion.easeOut.animation(.standard),
            value: filled
        )
        // **One element, and the word is the value.** Four bars announced individually would be four
        // meaningless "1 of 4"s; the label is the whole of what the meter says, so it is what is read — and it
        // is read as a *value* of "Password strength" so that a change re-announces the word rather than the
        // name (ADR-0012).
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("component.strength.label"))
        .accessibilityValue(label.map { Text($0) } ?? Text("component.strength.none"))
    }
}

#if DEBUG
#Preview("Strength meter — the four levels and none") {
    VStack(alignment: .leading, spacing: 18) {
        HWStrengthMeter(filled: 0, outOf: 4, label: nil)
        HWStrengthMeter(filled: 1, outOf: 4, label: "Weak")
        HWStrengthMeter(filled: 2, outOf: 4, label: "Fair")
        HWStrengthMeter(filled: 3, outOf: 4, label: "Good")
        HWStrengthMeter(filled: 4, outOf: 4, label: "Strong")
    }
    .padding(22)
    .background(HWPreviewGround(appearance: .brand))
    .hwTheme()
}

#Preview("Strength meter — the in-app ramp, where paler is weaker") {
    VStack(alignment: .leading, spacing: 18) {
        HWStrengthMeter(filled: 0, outOf: 4, label: nil, appearance: .surface)
        HWStrengthMeter(filled: 1, outOf: 4, label: "Weak", appearance: .surface)
        HWStrengthMeter(filled: 2, outOf: 4, label: "Fair", appearance: .surface)
        HWStrengthMeter(filled: 3, outOf: 4, label: "Good", appearance: .surface)
        HWStrengthMeter(filled: 4, outOf: 4, label: "Strong", appearance: .surface)
    }
    .padding(22)
    .background(HWPreviewGround())
    .hwTheme()
}

#Preview("AX3 — the word wraps beside the bars") {
    HWStrengthMeter(filled: 3, outOf: 4, label: "Good")
        .padding(22)
        .dynamicTypeSize(.accessibility3)
        .background(HWPreviewGround(appearance: .brand))
        .hwTheme()
}

#Preview("RTL — the bars fill from the right") {
    HWStrengthMeter(filled: 2, outOf: 4, label: "مقبولة")
        .padding(22)
        .environment(\.layoutDirection, .rightToLeft)
        .background(HWPreviewGround(appearance: .brand))
        .hwTheme()
}
#endif
