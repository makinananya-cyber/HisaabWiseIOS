import SwiftUI

/// The design's `.m-badge` — the filled pill saying how a month went against its goal.
///
/// **The label is the server's and the colour is the palette's**, which is the split every verdict in this app
/// is drawn with: "91% of goal" is a figure and a sentence (ADR-0003, ADR-0011), and hit / near / miss is a
/// threshold decision the client must not be able to make (defect D11, §4.2).
///
/// Filled rather than tinted, because the design fills it: a pastel wash with its own dark ink, which is the one
/// pair on this palette where the ink travels with the fill — see ``HWPalette/VerdictTone``.
struct HWVerdictBadge: View {
    @Environment(ThemeManager.self) private var theme

    let verdict: HWVerdictTint
    /// "91% of goal" — server-formatted, and the only thing drawn.
    let label: String

    var body: some View {
        let tone = theme.palette.verdicts.tone(verdict)

        return Text(verbatim: label)
            .font(.hw(.caption).weight(.heavy))
            .tracking(0.3)
            .foregroundStyle(tone.ink)
            // `font-variant-numeric:tabular-nums`, so a percentage changing width does not move the badge.
            .monospacedDigit()
            // Wraps rather than being cut off at accessibility sizes (ADR-0011).
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .hwBox(fill: tone.soft, radius: .small)
    }
}

#if DEBUG
/// Every case the type has, so a fourth added to `HWVerdictTint` shows up in the canvas without anybody
/// remembering to list it.
@MainActor
private func previewBadges() -> some View {
    VStack(alignment: .leading, spacing: 10) {
        ForEach(HWVerdictTint.allCases, id: \.self) { verdict in
            HWVerdictBadge(verdict: verdict, label: "108% of goal")
        }
    }
}

#Preview("Verdict badges — the three the table produces, with their own percentages") {
    VStack(alignment: .leading, spacing: 10) {
        HWVerdictBadge(verdict: .hit, label: "108% of goal")
        HWVerdictBadge(verdict: .near, label: "91% of goal")
        HWVerdictBadge(verdict: .miss, label: "61% of goal")
    }
    .padding()
    .background(HWPreviewGround())
    .hwTheme()
}

#Preview("On the galaxy card, where the trend's replacement rows draw them") {
    previewBadges()
        .padding()
        .background(HWPreviewGround(appearance: .brand))
        .hwTheme()
}

#Preview("AX3 — the percentage wraps and the pill grows with it") {
    previewBadges()
        .padding()
        .dynamicTypeSize(.accessibility3)
        .background(HWPreviewGround())
        .hwTheme()
}

#Preview("RTL") {
    previewBadges()
        .padding()
        .environment(\.layoutDirection, .rightToLeft)
        .background(HWPreviewGround())
        .hwTheme()
}
#endif
