import SwiftUI

/// The design's savings meter — one bar, red at the left and green at the goal, with a pin that slides along it
/// and a label that follows.
///
/// **Hand-built, and that is the decision rather than the shortcut** (ADR-0016). The donut is Swift Charts because
/// `SectorMark` is a mark the framework knows and publishes descriptors for. This is not a mark: it is a gradient
/// track, a pin, a label that stays inside the card at either end, and a pill — a shape the design invented.
/// Expressing it as a `RuleMark` with annotations would fight the framework for a layout it does not have, and
/// would still need every accessibility affordance written by hand.
///
/// **Nothing here is computed.** `position` arrives clamped, `percentageLabel` arrives formatted, and the verdict
/// arrives as a verdict — the prototype worked the last one out two different ways, which is defect D11. What this
/// view does with `position` is place a pin, which is geometry.
struct HWSavingsMeter: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How the month is going. Drives the pill's colour and nothing else — the *sentence* is the screen's, from
    /// the catalogue, because copy translates and a colour does not.
    enum Verdict: Sendable, Equatable {
        case low
        case onTrack
        case met
    }

    /// Where the pin sits, `0...1`, from the server.
    private let position: Double
    /// "₹23,000 saved" — the floating label above the pin.
    private let savedLabel: String
    /// The `0` at the left end and the goal at the right, both server-formatted.
    private let zeroLabel: String
    private let goalLabel: String
    /// "177% of goal" — the pill.
    private let percentageLabel: String
    private let verdict: Verdict
    /// What VoiceOver reads instead of the bar. One sentence, composed by the screen from catalogue copy and the
    /// server's display strings — a gradient with a pin on it has nothing a screen reader can do with it.
    private let accessibilityDescription: Text

    init(
        position: Double,
        savedLabel: String,
        zeroLabel: String,
        goalLabel: String,
        percentageLabel: String,
        verdict: Verdict,
        accessibilityDescription: Text
    ) {
        self.position = position
        self.savedLabel = savedLabel
        self.zeroLabel = zeroLabel
        self.goalLabel = goalLabel
        self.percentageLabel = percentageLabel
        self.verdict = verdict
        self.accessibilityDescription = accessibilityDescription
    }

    /// `.meter{height:14px}`.
    private static let trackHeight: CGFloat = 14
    /// `.meter-now` — the pin.
    private static let pinSize = CGSize(width: 6, height: 24)

    /// Clamped **again**, here. The server sends it clamped; a pin drawn at 1.4 would sit outside the card, and a
    /// view that trusts a number it could check is a view that draws the one bad payload wrongly.
    private var clamped: Double { min(max(position, 0), 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            bar
                // Replaced above the size threshold by the same figures as rows (ADR-0012): a pin, a floating
                // label, and a pill inside a 14pt bar have nowhere to grow, and shrinking the labels to fit is
                // how a screen opts out of Dynamic Type while appearing to support it.
                .hwVisualisation {
                    alternative
                }

            ends

            foot
        }
    }

    // MARK: - The bar

    private var bar: some View {
        // `GeometryReader`, because the pin's place is a fraction of a width only the layout knows. The design does
        // the same thing with `getBoundingClientRect()`.
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                let width = proxy.size.width

                ZStack(alignment: .topLeading) {
                    track
                    pin(in: width)
                }
                .frame(height: Self.pinSize.height, alignment: .center)
            }
            .frame(height: Self.pinSize.height)
        }
        // **One element, and the bar is not it.** The track, the pin, and the label are three views drawing one
        // fact, so they are collapsed and the sentence the screen composed is read in their place.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("home.savings.meter.accessibilityLabel"))
        .accessibilityValue(accessibilityDescription)
    }

    /// The red→green ombré. The stops are the meter roles, which exist for this and for the four-segment split bar
    /// on Reports — a hand-mixed gradient here would be a second set of stops nobody could keep in step.
    private var track: some View {
        Capsule()
            .fill(
                // `.leading`/`.trailing` rather than `.left`/`.right`: a `UnitPoint` of `.leading` **is** mirrored
                // by the layout direction, so the "nothing saved" end of the gradient stays at the same end as the
                // pin's origin under Arabic. Fixed points would have left the red end on the physical left while
                // the pin travelled from the right.
                LinearGradient(
                    colors: theme.palette.meter.stops,
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: Self.trackHeight)
            .frame(maxHeight: .infinity)
            .accessibilityHidden(true)
    }

    /// `.meter-now` — a light pin, centred on its position.
    ///
    /// **`padding(.leading:)` rather than `offset(x:)`, and that is the RTL fix.** An offset's `x` is always
    /// screen-rightward whatever the layout direction, so under Arabic — where `.topLeading` has already moved the
    /// origin to the right edge — a positive offset pushed the pin a full track-width outside the card. Leading
    /// padding mirrors with the layout, which is what the design's `left: at%` does inside a `dir="rtl"` document.
    private func pin(in width: CGFloat) -> some View {
        Capsule()
            .fill(theme.palette.surface.background)
            .frame(width: Self.pinSize.width, height: Self.pinSize.height)
            .hwElevation(.small)
            .padding(.leading, max(0, clamped * width - Self.pinSize.width / 2))
            .animation(reduceMotion ? nil : HWMotion.easeOut.animation(.slow), value: clamped)
            .accessibilityHidden(true)
    }

    /// `.meter-ends` — the zero and the goal, one at each end.
    private var ends: some View {
        HStack {
            Text(verbatim: zeroLabel)
            Spacer(minLength: 12)
            Text(verbatim: goalLabel)
        }
        .hwLabel()
        .fixedSize(horizontal: false, vertical: true)
        // Read as part of the bar's own sentence, which already names the goal.
        .accessibilityHidden(true)
    }

    /// `.meter-foot` — the saved figure on the left and the percentage pill on the right.
    private var foot: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(verbatim: savedLabel)
                .font(.hw(.body).weight(.semibold))
                .foregroundStyle(theme.palette.surface.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            pill
        }
        // The saved figure and the pill are two readings of the same thing, and the bar above already says both.
        .accessibilityHidden(true)
    }

    /// `.mf-r` and its `.warn` / `.low` variants.
    private var pill: some View {
        Text(verbatim: percentageLabel)
            .font(.hw(.caption).weight(.bold))
            .foregroundStyle(theme.palette.brand.ink)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .hwBox(fill: pillColour, radius: .small)
    }

    private var pillColour: Color {
        switch verdict {
        case .low: theme.palette.feedback.danger
        case .onTrack: theme.palette.accent.base
        case .met: theme.palette.meter.reached
        }
    }

    // MARK: - The alternative

    /// The same four facts as rows, for accessibility sizes. Text, so it scales the whole way to AX5.
    private var alternative: some View {
        VStack(alignment: .leading, spacing: 6) {
            row("home.savings.saved.label", value: savedLabel)
            row("home.savings.goal.label", value: goalLabel)
            row("home.savings.progress.label", value: percentageLabel)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // One element carrying the sentence the bar carries, so the two forms read identically.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("home.savings.meter.accessibilityLabel"))
        .accessibilityValue(accessibilityDescription)
    }

    private func row(_ label: LocalizedStringResource, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .hwLabel()
                .fixedSize(horizontal: false, vertical: true)

            Text(verbatim: value)
                .font(.hw(.body).weight(.semibold))
                .foregroundStyle(theme.palette.surface.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

#if DEBUG
private func previewMeter(_ position: Double, _ percentage: String, _ verdict: HWSavingsMeter.Verdict) -> some View {
    HWSavingsMeter(
        position: position,
        savedLabel: "₹23,000 saved",
        zeroLabel: "₹0",
        goalLabel: "₹13,000",
        percentageLabel: percentage,
        verdict: verdict,
        accessibilityDescription: Text(verbatim: "₹23,000 of a ₹13,000 goal, \(percentage)")
    )
}

#Preview("Savings meter — the three verdicts and both ends") {
    VStack(spacing: 30) {
        previewMeter(0, "0% of goal", .low)
        previewMeter(0.56, "56% of goal", .onTrack)
        previewMeter(1, "177% of goal", .met)
    }
    .padding()
    .background(HWPreviewGround())
    .hwTheme()
}

#Preview("AX3 — the bar is replaced by rows") {
    previewMeter(0.56, "56% of goal", .onTrack)
        .padding()
        .dynamicTypeSize(.accessibility3)
        .background(HWPreviewGround())
        .hwTheme()
}

#Preview("RTL — the pin travels from the right") {
    previewMeter(0.56, "56% of goal", .onTrack)
        .padding()
        .environment(\.layoutDirection, .rightToLeft)
        .background(HWPreviewGround())
        .hwTheme()
}
#endif
