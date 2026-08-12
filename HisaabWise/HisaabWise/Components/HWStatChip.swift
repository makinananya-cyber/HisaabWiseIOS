import SwiftUI

/// The design's `.stat` — the small white pill Learn puts its streak and its XP in.
///
/// A glyph, a figure, a hairline border, and the smallest elevation. Two tones in the design and no more:
/// `.stat--streak` in the sun ink over a sun glyph, `.stat--xp` in the accent over a muted one. `.stat--crown`
/// exists in the stylesheet and is never rendered by anything, so it is not converted.
///
/// **The figure arrives as a string and this component never spells one.** `AccessibilityTests` forbids a
/// component from naming `Money.minor`, and the same reasoning covers a plain count: 12,400 XP has a thousands
/// separator the client owns no formatter for (ADR-0003), so the pill draws what the server sent. The sentence
/// VoiceOver reads is a second server string, because "4-day streak" is a count *and* a plural (ADR-0011).
struct HWStatChip: View {
    @Environment(ThemeManager.self) private var theme

    /// Which of the design's two stat tones.
    ///
    /// A component-owned enum rather than a pair of colours, for the reason ``HWSavingsMeter/Verdict`` is one:
    /// the caller says what the figure *is* and the component says what that looks like.
    enum Tone: Sendable, Equatable, CaseIterable {
        /// `.stat--streak` — the flame, in the sun accent.
        case streak
        /// `.stat--xp` — the star, in the app's accent.
        case experience

        /// The glyph, **which the tone owns rather than the caller**.
        ///
        /// It was a separate `systemImage:` argument until review, which made `.streak` with a star a
        /// representable state: the tone already decides the flame's colour, so it has to decide the flame.
        var systemImage: String {
            switch self {
            case .streak: "flame"
            case .experience: "star"
            }
        }
    }

    private let tone: Tone
    /// "4" · "1,500" — server-formatted, and the only thing drawn.
    private let value: String
    /// "4-day streak" · "1,500 experience points" — the whole reading, composed server-side.
    private let accessibilityLabel: String

    init(tone: Tone, value: String, accessibilityLabel: String) {
        self.tone = tone
        self.value = value
        self.accessibilityLabel = accessibilityLabel
    }

    /// `.stat--streak{color:var(--sun-deep)}` and `.stat--xp{color:var(--planetary)}`.
    private var ink: Color {
        switch tone {
        case .streak: theme.palette.units.sun.deep
        case .experience: theme.palette.accent.base
        }
    }

    /// `.stat--streak svg{color:var(--sun)}` and `.stat--xp svg{color:var(--universe)}` — the glyph is a shade
    /// lighter than the figure beside it in both.
    private var glyphInk: Color {
        switch tone {
        case .streak: theme.palette.units.sun.base
        case .experience: theme.palette.accent.muted
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: tone.systemImage)
                .font(.hw(.body))
                .foregroundStyle(glyphInk)

            Text(verbatim: value)
                .font(.hw(.body).weight(.heavy))
                .foregroundStyle(ink)
                // `font-variant-numeric:tabular-nums`, so a figure changing width does not move the pill.
                .monospacedDigit()
                // Wraps rather than being cut off at accessibility sizes (ADR-0011).
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .hwBox(
            fill: theme.palette.surface.raised,
            radius: .medium,
            border: theme.palette.surface.separator,
            elevation: .small
        )
        // **One element carrying one sentence.** A glyph and a bare number read as "4" on their own, which tells
        // a VoiceOver user nothing — the design leans on a `title` attribute for exactly this and gets it wrong
        // for touch. The glyph is inside the element rather than hidden beside it.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: accessibilityLabel))
    }
}

#if DEBUG
@MainActor
private func previewChips() -> some View {
    HStack(spacing: 8) {
        HWStatChip(tone: .streak, value: "4", accessibilityLabel: "4-day streak")
        Spacer(minLength: 0)
        HWStatChip(tone: .experience, value: "1,500", accessibilityLabel: "1,500 experience points")
    }
}

#Preview("Stat chips — a streak and an XP total") {
    previewChips()
        .padding()
        .background(HWPreviewGround())
        .hwTheme()
}

#Preview("AX3 — the figures grow and the pills grow with them") {
    previewChips()
        .padding()
        .dynamicTypeSize(.accessibility3)
        .background(HWPreviewGround())
        .hwTheme()
}

#Preview("RTL — the streak leads from the right") {
    previewChips()
        .padding()
        .environment(\.layoutDirection, .rightToLeft)
        .background(HWPreviewGround())
        .hwTheme()
}
#endif
