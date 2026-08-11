import SwiftUI

/// The design's `.budget` — the wants allowance, what has gone against it, and an explicit over state.
///
/// A caption, the two figures beside it, a 7pt track with a gradient fill, and a percentage at the trailing
/// edge. It sits **inside** the galaxy summary card, so every colour here is a brand role: the design's
/// `rgba(sky,.2)` track and its `--venus`→`--sky` fill.
///
/// **Nothing here is computed.** `fill` arrives clamped, `percentageLabel` arrives formatted, and `isOver`
/// arrives as a verdict. The design worked the last one out as `b.used > b.wants` in the browser, having
/// re-implemented the 50/30/20 engine there to get `b.wants` — which is exactly the two-owners situation
/// invariant 3 exists to prevent, and defect D11 is what it looks like when the two disagree.
///
/// **Over-budget is said three ways at once**, because one of them is invisible to somebody: the fill turns to
/// the danger pair, the percentage does too, and the accessibility value says it in words. A bar that only
/// changed colour would be a state a colour-blind reader and a screen-reader user both miss.
struct HWBudgetBar: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// `.budget-cap` — "Wants budget".
    private let caption: LocalizedStringResource
    /// `.budget-amt` — "₹1,150 of ₹19,770", as one catalogue sentence with numbered arguments: the two figures
    /// are the server's and the word between them is the translation's (ADR-0011).
    private let amount: Text
    /// `.budget-pct` — "88%". A string, so the figure the user reads and the width of the bar cannot round
    /// differently.
    private let percentageLabel: String
    /// How much of the track is filled, `0...1`, from the server.
    private let fill: Double
    /// `.budget.over` — the server's verdict.
    private let isOver: Bool
    /// What VoiceOver reads instead of the track. One sentence, composed by the screen from catalogue copy and
    /// the server's display strings — a gradient in a 7pt capsule has nothing a screen reader can do with it.
    private let accessibilityDescription: Text

    init(
        caption: LocalizedStringResource,
        amount: Text,
        percentageLabel: String,
        fill: Double,
        isOver: Bool,
        accessibilityDescription: Text
    ) {
        self.caption = caption
        self.amount = amount
        self.percentageLabel = percentageLabel
        self.fill = fill
        self.isOver = isOver
        self.accessibilityDescription = accessibilityDescription
    }

    /// `.bar{height:7px}`.
    private static let trackHeight: CGFloat = 7

    /// Clamped **again**, here. The server sends it clamped; a fill drawn at 1.4 would run outside the card, and
    /// a view that trusts a number it could check is a view that draws the one bad payload wrongly.
    private var clamped: Double { min(max(fill, 0), 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            top

            row
                // **Replaced above the accessibility threshold, and replaced by nothing** (ADR-0012). The
                // figures are already on screen as text in `top` — a 7pt bar has nowhere to grow, and the
                // alternative every other visualisation needs is a list this one already has above it. So the
                // track simply goes, which is what Home's ring does at AX sizes for the same reason.
                .hwVisualisation { EmptyView() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 14)
        // `.budget{border-top:1px solid rgba(sky,.18)}` — the rule that separates the bar from the chips above.
        .overlay(alignment: .top) {
            Rectangle()
                .fill(theme.palette.brand.separator)
                .frame(height: 1)
                .accessibilityHidden(true)
        }
        // One element carrying the whole fact, and the track is not it: a caption, two figures, a gradient, and
        // a percentage are five views saying one thing.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(caption))
        .accessibilityValue(accessibilityDescription)
    }

    /// `.budget-top` — the caption at one end, the two figures at the other.
    private var top: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(caption)
                .hwEyebrow(.brand)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            amount
                .font(.hw(.caption).weight(.semibold))
                // `.budget.over .budget-amt b{color:#FFC9C0}` — the brand surface's own danger value, which is
                // a different colour from the in-app one (ADR-0021).
                .foregroundStyle(isOver ? theme.palette.brand.danger : theme.palette.brand.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.trailing)
        }
    }

    /// `.budget-row` — the track and the percentage.
    private var row: some View {
        HStack(spacing: 11) {
            track

            Text(verbatim: percentageLabel)
                .font(.hw(.caption).weight(.heavy))
                .foregroundStyle(isOver ? theme.palette.brand.danger : theme.palette.brand.inkAccent)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var track: some View {
        // `GeometryReader`, because the fill's width is a fraction of a width only the layout knows — the same
        // reason the savings meter reads one.
        GeometryReader { proxy in
            Capsule()
                .fill(theme.palette.brand.separator)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(
                            // `.leading`/`.trailing` rather than fixed points: the gradient runs the way the
                            // bar fills, which under Arabic is the other way (ADR-0011).
                            LinearGradient(
                                colors: isOver ? overStops : stops,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: clamped * proxy.size.width)
                }
        }
        .frame(height: Self.trackHeight)
        // `transition:transform 1.1s var(--ease-out)` — the fill grows into place. Under Reduce Motion it is
        // *there*, rather than growing slower: a bar sliding across the screen is the kind of movement the
        // setting exists for (ADR-0012).
        .animation(reduceMotion ? nil : HWMotion.easeOut.animation(.slow), value: clamped)
        .accessibilityHidden(true)
    }

    /// `linear-gradient(90deg,var(--venus),var(--sky))`.
    private var stops: [Color] { [theme.palette.accent.muted, theme.palette.accent.soft] }

    /// `.budget.over .bar i{background:linear-gradient(90deg,#FFC9C0,#FFE0DB)}` — the brand danger value and a
    /// lighter tint of it. Resolved through roles, so the later palette swap reaches both (ADR-0001).
    private var overStops: [Color] { [theme.palette.brand.danger, theme.palette.feedback.dangerSoft] }
}

#if DEBUG
@MainActor
private func previewBar(_ fill: Double, _ percentage: String, isOver: Bool) -> some View {
    HWBudgetBar(
        caption: "Wants budget",
        amount: Text(verbatim: isOver ? "₹21,400 of ₹19,770" : "₹1,150 of ₹19,770"),
        percentageLabel: percentage,
        fill: fill,
        isOver: isOver,
        accessibilityDescription: Text(verbatim: "₹1,150 of ₹19,770, \(percentage)")
    )
}

#Preview("Budget bar — under, near, and over") {
    VStack(spacing: 26) {
        previewBar(0.06, "6%", isOver: false)
        previewBar(0.92, "92%", isOver: false)
        previewBar(1, "108%", isOver: true)
    }
    .padding(22)
    .background(HWPreviewGround(appearance: .brand))
    .hwTheme()
}

#Preview("AX3 — the track stands aside and the figures remain") {
    previewBar(1, "108%", isOver: true)
        .padding(22)
        .dynamicTypeSize(.accessibility3)
        .background(HWPreviewGround(appearance: .brand))
        .hwTheme()
}

#Preview("RTL — the bar fills from the right") {
    previewBar(0.42, "42%", isOver: false)
        .padding(22)
        .environment(\.layoutDirection, .rightToLeft)
        .background(HWPreviewGround(appearance: .brand))
        .hwTheme()
}
#endif
