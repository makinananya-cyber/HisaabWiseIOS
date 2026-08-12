import Charts
import SwiftUI

/// The design's `.trend` — one bar per closed month, coloured hit / near / miss, against a dashed goal line.
///
/// **`BarMark` plus a `RuleMark`, which is ADR-0016's own instruction** and the same rule the donut and the
/// savings meter are split by: a *mark* the framework knows about is drawn by the framework, a *shape* the design
/// invented is drawn by hand. A bar chart with a threshold line is two marks Swift Charts has, and it publishes a
/// per-mark descriptor for each — which is the whole reason the donut is a chart and the meter is not.
///
/// **It computes nothing, and there is deliberately nothing here it could compute with.** Each bar arrives with
/// its height as a fraction of the plot area, its verdict as a verdict, and its percentage as a sentence — no
/// `saved`, no `goal`, and no division. That is defect D11's fix expressed as a type: the prototype worked the
/// verdict out here, in the browser, with a threshold table that disagreed with Home's.
///
/// **The design's two entrance animations are dropped rather than gated**, on the reasoning `Components.swift`
/// already records for the `START` flag's bob and the heart pulse: the bars grow in staggered from zero and the
/// goal line fades in nine tenths of a second later, and an entrance's only honest replacement under Reduce
/// Motion is the thing already being there (ADR-0012). Nothing here animates, so nothing here has a replacement
/// to owe.
struct HWTrendChart: View {
    @Environment(ThemeManager.self) private var theme

    /// One `.tbar`: enough to draw it, colour it, and describe it.
    struct Bar: Identifiable, Sendable, Hashable {
        /// The month's identity, and the chart's x value — **not the label**, because two Februaries in two
        /// years share a label and would collapse into one category.
        let id: String
        /// "Feb" — the axis label, formatted server-side (invariant 6).
        let label: String
        /// `0...1` of the plot area, from the server. Geometry, not a displayed figure.
        let height: Double
        let verdict: HWVerdictTint
        /// "91% of goal" — what the replacement rows show.
        let percentageLabel: String
        /// "February 2026, 91% of goal, ₹11,830 saved" — the per-mark descriptor. The design puts this in a
        /// `title` attribute, which touch never surfaces.
        let accessibilityLabel: String
    }

    private let bars: [Bar]
    /// Where the dashed line sits, `0...1`, from the server — so the line and the bars cannot be scaled
    /// differently.
    private let goalHeight: Double
    /// What VoiceOver reads for the chart as a whole, and the heading of the replacement list. The screen's, from
    /// the catalogue.
    private let accessibilityLabel: LocalizedStringResource

    init(bars: [Bar], goalHeight: Double, accessibilityLabel: LocalizedStringResource) {
        self.bars = bars
        self.goalHeight = goalHeight
        self.accessibilityLabel = accessibilityLabel
    }

    /// `.trend{height:74px}`.
    private static let plotHeight: CGFloat = 74
    /// `.tbar i{width:58%}` — the bar inside its slot.
    private static let barRatio = 0.58

    var body: some View {
        chart
            // Replaced above the size threshold by the same months as rows (ADR-0012): a 74pt plot with 9pt
            // labels under it has nowhere to grow, and shrinking the labels to fit is how a screen opts out of
            // Dynamic Type while appearing to support it.
            //
            // `describesItself` — every `BarMark` carries a label and a value, which is why this is Swift Charts
            // (ADR-0016). Installing a representation over the chart would replace those descriptors, so they
            // would be read by nothing at any size: below the threshold the representation supersedes them and
            // above it the chart is not drawn.
            .hwVisualisation(describesItself: true) {
                alternative
            }
    }

    private var chart: some View {
        // **Resolved here and re-injected below.** Swift Charts does not carry the app's `@Environment` *objects*
        // into the content of `.chartXAxis` — an `AxisValueLabel` that reads `ThemeManager` traps with "No
        // Observable object of type ThemeManager found" even though the whole chart was rendered inside one, which
        // `ReportsViewTests` found by photographing the page. So the manager is read where a view may read it —
        // in this `body` — and put back around the label, which keeps the eyebrow style's one owner rather than
        // spelling its four attributes out a second time here.
        let theme = self.theme

        return Chart {
            ForEach(bars) { bar in
                BarMark(
                    x: .value(Text(verbatim: bar.label), bar.id),
                    y: .value(Text(verbatim: bar.percentageLabel), bar.height),
                    width: .ratio(Self.barRatio)
                )
                // `border-radius:5px 5px 2px 2px` — rounded at the top, nearly square where it meets the axis.
                // One radius, because `cornerRadius` is per-mark rather than per-corner; the top is the corner
                // the eye reads.
                .cornerRadius(4)
                .foregroundStyle(theme.palette.meter.stop(for: bar.verdict))
                // The per-mark descriptors that are the reason for using `BarMark` at all.
                .accessibilityLabel(Text(verbatim: bar.accessibilityLabel))
                .accessibilityValue(Text(verbatim: bar.percentageLabel))
            }

            // `.trend-avg` — the goal, as the line the bars are read against. The design leaves it unlabelled
            // because the caption above the chart says what it is, and this keeps that: a `RuleMark` annotation
            // would be a second sentence saying "goal" beside a card that already says it.
            //
            // The y value's own dimension name is the chart's label, and it is read by nothing: the mark is
            // hidden from VoiceOver, and Charts surfaces a dimension name only through a descriptor this mark
            // does not have. Passing the chart's own is better than inventing a second string for a slot with no
            // reader.
            RuleMark(y: .value(accessibilityLabel, goalHeight))
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .foregroundStyle(theme.palette.brand.ink.opacity(0.55))
                .accessibilityHidden(true)
        }
        // The bars arrive as fractions of the plot, so the domain is fixed: the server owns the scale, and a
        // chart that auto-scaled to its own tallest bar would move the goal line relative to them.
        .chartYScale(domain: 0...1)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    // The payload's own label for that month, looked up by the id the axis is keyed on.
                    Text(verbatim: label(for: value.as(String.self)))
                        .hwEyebrow(.brand)
                        .fixedSize(horizontal: false, vertical: true)
                        .environment(theme)
                }
            }
        }
        .chartLegend(.hidden)
        .frame(height: Self.plotHeight)
        // One element for the chart; the marks above are its children.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(accessibilityLabel))
    }

    private func label(for id: String?) -> String {
        bars.first { $0.id == id }?.label ?? ""
    }

    /// The same months as rows: the label, the percentage, and the verdict badge.
    ///
    /// Text and a badge, so it scales the whole way to AX5 — and it is what a VoiceOver user gets above the
    /// threshold, with the same sentence the marks carry below it.
    private var alternative: some View {
        VStack(spacing: 6) {
            ForEach(bars) { bar in
                row(bar)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(accessibilityLabel))
    }

    private func row(_ bar: Bar) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(verbatim: bar.label)
                .font(.hw(.body).weight(.bold))
                .foregroundStyle(theme.palette.brand.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            HWVerdictBadge(verdict: bar.verdict, label: bar.percentageLabel)
        }
        // One element per month, carrying the sentence the mark carries — so the two forms of the chart read
        // identically (ADR-0012).
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: bar.accessibilityLabel))
    }
}

#if DEBUG
private let previewBars: [HWTrendChart.Bar] = [
    .init(id: "2026-02", label: "Feb", height: 0.4899, verdict: .near, percentageLabel: "91% of goal",
          accessibilityLabel: "February 2026, 91% of goal, ₹11,830 saved"),
    .init(id: "2026-03", label: "Mar", height: 0.3284, verdict: .miss, percentageLabel: "61% of goal",
          accessibilityLabel: "March 2026, 61% of goal, ₹7,930 saved"),
    .init(id: "2026-04", label: "Apr", height: 0.5814, verdict: .hit, percentageLabel: "108% of goal",
          accessibilityLabel: "April 2026, 108% of goal, ₹14,040 saved"),
    .init(id: "2026-05", label: "May", height: 0.4791, verdict: .near, percentageLabel: "89% of goal",
          accessibilityLabel: "May 2026, 89% of goal, ₹11,570 saved"),
    .init(id: "2026-06", label: "Jun", height: 0.9259, verdict: .hit, percentageLabel: "172% of goal",
          accessibilityLabel: "June 2026, 172% of goal, ₹22,360 saved"),
    .init(id: "2026-07", label: "Jul", height: 0.3714, verdict: .miss, percentageLabel: "69% of goal",
          accessibilityLabel: "July 2026, 69% of goal, ₹8,970 saved"),
]

#Preview("Trend — six months against the goal line") {
    HWTrendChart(bars: previewBars, goalHeight: 0.5383, accessibilityLabel: "Savings goal reached each month")
        .padding()
        .background(HWPreviewGround(appearance: .brand))
        .hwTheme()
}

#Preview("AX3 — the chart is replaced by the months as rows") {
    HWTrendChart(bars: previewBars, goalHeight: 0.5383, accessibilityLabel: "Savings goal reached each month")
        .padding()
        .dynamicTypeSize(.accessibility3)
        .background(HWPreviewGround(appearance: .brand))
        .hwTheme()
}

#Preview("RTL — time still reads oldest to newest, mirrored") {
    HWTrendChart(bars: previewBars, goalHeight: 0.5383, accessibilityLabel: "Savings goal reached each month")
        .padding()
        .environment(\.layoutDirection, .rightToLeft)
        .background(HWPreviewGround(appearance: .brand))
        .hwTheme()
}
#endif
