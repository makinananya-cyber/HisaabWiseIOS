import SwiftUI

/// The design's `.tip` card — a lightbulb, the tip, and **Show me another**.
///
/// The text is **server content with markdown emphasis** (``HWMarkdown``), so it goes through
/// `Text(verbatim:)`-shaped rendering rather than a localised key: the words are the content's and the emphasis is
/// the author's. The `{c}` token has already been substituted by the caller from server-supplied currency
/// metadata, which is what keeps ADR-0003's spacing rule to one owner.
struct HWTipCard: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The tip, tokens resolved and emphasis as markdown.
    private let text: String
    private let onAnother: () -> Void

    init(text: String, onAnother: @escaping () -> Void) {
        self.text = text
        self.onAnother = onAnother
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: "lightbulb")
                    .font(.hw(.body))
                    .foregroundStyle(theme.palette.accent.base)
                    .accessibilityHidden(true)

                Text("home.tip.caption")
                    .hwEyebrow()
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }

            Text(HWMarkdown.attributed(text))
                .font(.hw(.body))
                .foregroundStyle(theme.palette.surface.ink)
                .fixedSize(horizontal: false, vertical: true)
                // The tip changing is the one thing on this card that moves, and under Reduce Motion it is
                // replaced by arriving rather than by nothing (ADR-0012).
                .id(text)
                .transition(.opacity)

            HWLink("home.tip.another", action: onAnother)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(reduceMotion ? nil : HWMotion.easeInOut.animation(.standard), value: text)
    }
}

/// The design's `.mini` — the streak, the XP line, and a way into the next lesson.
///
/// A **button**, as the design has it: the whole card is the affordance, so the tap target is the card rather than
/// the word "Continue" inside it.
struct HWStreakCard: View {
    @Environment(ThemeManager.self) private var theme

    /// Days, from the server — counted against the server-owned day boundary, so a device-clock change cannot
    /// extend it (invariant 6).
    private let streak: Int
    /// "120 XP · next up, Needs vs. Wants" — composed server-side, because it joins two figures and a title.
    private let summary: String
    private let action: () -> Void

    init(streak: Int, summary: String, action: @escaping () -> Void) {
        self.streak = streak
        self.summary = summary
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                Text("home.learning.caption")
                    .hwEyebrow()
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .font(.hw(.subheading))
                        .foregroundStyle(theme.palette.feedback.danger)
                        .accessibilityHidden(true)

                    // Latin digits, unformatted — ADR-0011's decision, and a count is not money.
                    Text(verbatim: "\(streak)")
                        .font(.hw(.heading))
                        .foregroundStyle(theme.palette.surface.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(verbatim: summary)
                    .font(.hw(.caption))
                    .foregroundStyle(theme.palette.surface.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 4) {
                    Text("home.learning.continue")
                        .font(.hw(.caption).weight(.bold))
                        .foregroundStyle(theme.palette.accent.base)
                        .fixedSize(horizontal: false, vertical: true)
                    // `chevron.forward` mirrors under Arabic; `.right` would point back the way the reader came.
                    Image(systemName: "chevron.forward")
                        .font(.hw(.micro).weight(.bold))
                        .foregroundStyle(theme.palette.accent.base)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .hwBox(fill: theme.palette.surface.raised, radius: .large, border: theme.palette.surface.separator)
            .contentShape(.rect)
        }
        .buttonStyle(HWPressStyle.compact)
        // One control, read as "Learning, 4 day streak, 120 XP…, button". The streak is a *value* rather than part
        // of the label so that a change re-announces the number rather than the card's name (ADR-0012).
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("home.learning.caption"))
        .accessibilityValue(Text("home.learning.accessibilityValue \(streakText) \(summary)"))
    }

    /// The streak as a string, because every argument this app's copy takes is a `String` — a number would resolve
    /// to `%lld` and find nothing in the catalogue (`LocalisationTests`).
    private var streakText: String { "\(streak)" }
}

/// One "Read more about" row — the design's `.read`.
///
/// The glyph and the tint arrive as a **name and a slot**, not as a path and a hex: the design hardcodes both per
/// article, and a colour that reaches a use site by name is what keeps the later dark-mode swap a swap (ADR-0001).
/// The row's **contents**, without a control around them.
///
/// Split out because Home draws these inside a `NavigationLink`, which supplies its own button: a `Button` nested
/// in a link is two controls for one row, and the first attempt at avoiding that turned the label's hit-testing
/// off — which made the rows completely untappable, exactly the way `HWDateField`'s placeholder was in #15. The
/// lesson recorded there is that a label must offer a hit region, so this one carries the `contentShape` and the
/// *link* is the control.
struct HWReadRowLabel: View {
    @Environment(ThemeManager.self) private var theme

    let title: String
    let systemImage: String
    /// Which of the five accent slots, `1...5`.
    let accent: Int

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: systemImage)
                .font(.hw(.body))
                .foregroundStyle(tint.base)
                .frame(width: 32, height: 32)
                .hwBox(fill: tint.soft, radius: .small)
                .accessibilityHidden(true)

            Text(verbatim: title)
                .font(.hw(.body).weight(.semibold))
                .foregroundStyle(theme.palette.surface.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.forward")
                .font(.hw(.micro).weight(.bold))
                .foregroundStyle(theme.palette.surface.inkTertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(minHeight: HWTouchTarget.minimum)
        // **The hit region.** Without it the row draws and cannot be pressed, whether the control around it is a
        // button or a link.
        .contentShape(.rect)
    }

    /// The five Learn unit accents, reused for the articles. A slot outside the range wraps: the number arrives
    /// from a payload, and a sixth article is a server change rather than a client crash.
    private var tint: HWPalette.UnitAccent {
        let accents = theme.palette.units.all
        guard !accents.isEmpty else { return theme.palette.units.sky }
        return accents[(max(accent, 1) - 1) % accents.count]
    }
}

/// One "Read more about" row as a **button**, for a caller that is not already a link.
struct HWReadRow: View {
    private let title: String
    private let systemImage: String
    private let accent: Int
    private let action: () -> Void

    init(title: String, systemImage: String, accent: Int, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.accent = accent
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HWReadRowLabel(title: title, systemImage: systemImage, accent: accent)
        }
        .buttonStyle(HWPressStyle.compact)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityHint(Text("home.reads.hint"))
    }
}

#if DEBUG
#Preview("The three cards") {
    ScrollView {
        VStack(spacing: 18) {
            HWTipCard(
                text: "To find 10% of a number, move the dot one step left. ₹6,400 becomes ₹640. Double it and "
                    + "there is your **20% savings target**."
            ) {}

            HWStreakCard(streak: 4, summary: "120 XP · next up, Needs vs. Wants") {}

            VStack(spacing: 2) {
                HWReadRow(title: "Scam awareness", systemImage: "shield", accent: 3) {}
                HWReadRow(title: "Sending money home", systemImage: "globe", accent: 4) {}
                HWReadRow(title: "Borrowing and credit", systemImage: "stairs", accent: 1) {}
            }
        }
        .padding()
    }
    .background(HWPreviewGround())
    .hwTheme()
}

#Preview("AX3 — every card grows") {
    ScrollView {
        VStack(spacing: 18) {
            HWTipCard(text: "Keep **three months of rent, food and bills** saved for emergencies.") {}
            HWStreakCard(streak: 12, summary: "480 XP · next up, Borrowing and credit") {}
            HWReadRow(title: "Sending money home", systemImage: "globe", accent: 4) {}
        }
        .padding()
    }
    .dynamicTypeSize(.accessibility3)
    .background(HWPreviewGround())
    .hwTheme()
}

#Preview("RTL — the glyphs lead on the right and the chevrons mirror") {
    VStack(spacing: 18) {
        HWTipCard(text: "احتفظ بمصروف **ثلاثة أشهر** للطوارئ.") {}
        HWStreakCard(streak: 4, summary: "120 XP") {}
        HWReadRow(title: "الوعي بالاحتيال", systemImage: "shield", accent: 3) {}
    }
    .padding()
    .environment(\.layoutDirection, .rightToLeft)
    .background(HWPreviewGround())
    .hwTheme()
}
#endif
