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

    /// **14, where the design writes `.bar{height:7px}`** — the owner asked for a bigger bar, and 7 is what made
    /// the ask reasonable: at that height the venus→sky fill is a hairline, the 6% state is a dot, and the light
    /// that travels across it (``shimmer``) has nowhere to be seen. Double is still a bar rather than a panel, and
    /// it is the same move the savings meter's track made from 14 to its own design value of 22.
    private static let trackHeight: CGFloat = 14

    /// Whether the fill is currently held at empty, waiting to grow.
    ///
    /// **The design fills the bar from empty and lets it grow into place** — `.bar i{transform:scaleX(0)}` with
    /// `transition:transform 1.1s var(--ease-out) .25s`, and `paintSummary()` setting the real `scaleX` on the
    /// next frame. It is state rather than a transition because there is nothing to transition *from*: the value
    /// does not change while the screen is open, so the `.animation(value:)` below was watching a number that
    /// never moved and the bar was simply already full.
    ///
    /// **False by default — the filled bar is the resting state and empty is the departure from it**, which is
    /// the inversion ``HWCountingFigure`` explains at length and which was made here for the same reason: a
    /// context that does not run `onAppear` should show the extent the payload says, not an empty budget.
    @State private var isParked = false

    /// Clamped **again**, here. The server sends it clamped; a fill drawn at 1.4 would run outside the card, and
    /// a view that trusts a number it could check is a view that draws the one bad payload wrongly.
    private var clamped: Double { min(max(fill, 0), 1) }

    /// How much of the track is filled *this frame* — nothing, while it is parked.
    private var drawnFill: Double { isParked ? 0 : clamped }

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
        // Parked and released on every appearance, so coming back to Expenses — from another tab, or out of a
        // category — fills the bar again rather than finding it already full. The same pair, in the same order and
        // for the same reasons, as ``HWCountingFigure/park()``.
        //
        // Under Reduce Motion nothing is parked and the bar is at its extent from the first paint. Nothing
        // replaces the growth, and nothing needs to: the extent is printed twice beside it — as the two figures
        // above and as the percentage at the trailing edge (ADR-0012).
        .onAppear {
            guard !reduceMotion else { return }

            Task { @MainActor in
                var snap = Transaction()
                snap.disablesAnimations = true
                withTransaction(snap) { isParked = true }

                await Task.yield()

                // `transition:… 1.1s var(--ease-out) .25s` — the scale's longest step and the design's own delay.
                withAnimation(HWMotion.easeOut.animation(.slow).delay(0.25)) { isParked = false }
            }
        }
    }

    /// `.budget-top` — the caption at one end, the two figures at the other.
    private var top: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(caption)
                .hwEyebrow(.brand)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            amount
                // `.budget-amt{font-size:12.5px;font-weight:600}` at the scale's `caption` step, and
                // `font-variant-numeric:tabular-nums`, which the design sets on every figure in this card.
                .font(.hw(.caption).weight(.semibold))
                .monospacedDigit()
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
                .monospacedDigit()
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
                        .frame(width: drawnFill * proxy.size.width)
                        // **Hidden at nothing, rather than drawn at nothing.** A `Capsule` given a width of zero
                        // still paints a dot the height of the track, so an empty bar came back with a 14pt blob
                        // sitting on its leading end — which reads as a fault rather than as a bar with nothing in
                        // it. Found by looking at a render of the parked frame.
                        .opacity(drawnFill > 0 ? 1 : 0)
                }
                // `.bar::after` — the light crossing the whole track, filled part and empty part alike, which is
                // where the design draws it (`inset:0` on `.bar`, not on `.bar i`).
                .overlay { shimmer(width: proxy.size.width) }
                // `.bar{overflow:hidden}` — both the fill and the travelling light are cut to the capsule.
                .clipShape(Capsule())
        }
        .frame(height: Self.trackHeight)
        // The growth itself is driven by `hasGrown` in `onAppear`; this is what carries a fill that *changes*
        // while the screen is open, which is every write (ADR-0020). Under Reduce Motion the new extent is
        // simply there rather than sliding to it (ADR-0012).
        .animation(reduceMotion ? nil : HWMotion.easeOut.animation(.slow), value: clamped)
        .accessibilityHidden(true)
    }

    /// `.bar::after` — the band of light that crosses the bar every few seconds and waits.
    ///
    /// ```css
    /// .bar::after{inset:0;background:linear-gradient(90deg,transparent,rgba(255,249,240,.34),transparent);
    ///   transform:translateX(-100%);animation:shimmer 3.4s var(--ease-io) 1.4s infinite}
    /// @keyframes shimmer{0%{translateX(-100%)}55%,100%{translateX(100%)}}
    /// ```
    ///
    /// **The same shape as ``HWButtonSweep``, and a `keyframeAnimator` for the same reason**: the design's cycle
    /// is mostly *pause*, and one repeating `.animation` interpolated evenly across 3.4 seconds turns a crossing
    /// into a band drifting forever. Three keyframes give it the shape the CSS has — parked off the leading edge,
    /// one crossing over 55% of the cycle, then parked off the trailing edge until it restarts. It differs from
    /// the button's in the two ways the design differs: the band is the control's own width rather than a 60pt
    /// glint, and it is not tilted.
    ///
    /// **Suppressed under Reduce Motion with nothing put in its place**, which is the exemption ``HWButtonSweep``
    /// records: the light says nothing. It marks no change, confirms no action, and reports no state — the bar's
    /// extent, its two figures, and the over-budget verdict are all on screen without it. A band frozen mid-cross
    /// would read as a rendering fault.
    private func shimmer(width: CGFloat) -> some View {
        LinearGradient(
            colors: [
                theme.palette.brand.ink.opacity(0),
                theme.palette.brand.ink.opacity(0.34),
                theme.palette.brand.ink.opacity(0),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .keyframeAnimator(initialValue: -width, repeating: !reduceMotion) { content, x in
            content.offset(x: x)
        } keyframes: { _ in
            KeyframeTrack {
                // `animation-delay:1.4s`, then `0% → 55%` of a 3.4s cycle, then parked for the rest.
                LinearKeyframe(-width, duration: 1.4)
                CubicKeyframe(width, duration: 1.87)
                LinearKeyframe(width, duration: 1.53)
            }
        }
        // The offset does not mirror, which is accepted for the reason `HWButtonSweep` gives: a band of light
        // with no leading edge carries no direction to read.
        .allowsHitTesting(false)
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
