import SwiftUI

/// The design's `.sum-note` — the line under a galaxy summary card's figures that explains them.
///
/// A glyph and a sentence over a hairline rule, in `brand` roles because it sits **inside** the galaxy card
/// (``HWSpendSummary``'s footer slot) on a light screen — the same arrangement ``HWBudgetBar`` occupies on
/// Expenses.
///
/// The sentence is the caller's, and it is a whole one: which of the two the month gets is a statement about the
/// budget rule and arrives as a flag (`ReportsMonthScreen.Totals.isAdapted`), while the words are the app's
/// (ADR-0011). The design assembles it with string concatenation and `<b>` tags, which no translation can
/// reorder.
struct HWSummaryNote: View {
    @Environment(ThemeManager.self) private var theme

    /// The sentence, already resolved by the screen from catalogue copy and the server's figures.
    let note: Text

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Image(systemName: "info.circle")
                .font(.hw(.body))
                .foregroundStyle(theme.palette.brand.inkAccent)
                // The glyph repeats the sentence's job; the sentence is what is read.
                .accessibilityHidden(true)

            note
                .font(.hw(.caption))
                .foregroundStyle(theme.palette.brand.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 13)
        // `border-top:1px solid rgba(208,227,255,.18)` — the rule that separates the note from the chips above.
        .overlay(alignment: .top) {
            Rectangle()
                .fill(theme.palette.brand.separator)
                .frame(height: 1)
                .accessibilityHidden(true)
        }
        .padding(.top, 15)
        .accessibilityElement(children: .combine)
    }
}

/// The design's `.bud-*` card — what went on wants in a **closed** month, against what the engine allowed.
///
/// **Not ``HWBudgetBar``, and the design is why.** Expenses draws these two figures as a caption and a track
/// inside its galaxy summary (`.budget`); a month report draws them as a card of their own on the light ground,
/// with the figure at display size over a 9pt track and a sentence underneath (`.bud-val` · `.bud-row` ·
/// `.bud-foot`). Two treatments in the stylesheet, two components here — a single component with an appearance
/// argument would be one control with two layouts, which is the thing `Components.swift` warns about from the
/// other direction.
///
/// **Nothing here is computed**: `fill` arrives clamped, the percentage arrives formatted, and `isOver` arrives as
/// a verdict (defect D11).
///
/// **Over-allowance is said three ways at once**, as it is on Expenses, because each of them is invisible to
/// somebody: the fill turns to the danger pair, the percentage does too, and the accessibility value says it in
/// words.
struct HWAllowanceBar: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// `.bud-num` — what went on wants, server-formatted.
    let amount: String

    /// `.bud-of` — "of ₹8,630 allowed", one catalogue sentence with the server's figure in it.
    let allowance: Text

    /// `.bud-pct` — "63%". A string, so the figure and the width of the bar cannot round differently.
    let percentageLabel: String

    /// How much of the track is filled, `0...1`, from the server.
    let fill: Double

    /// `.card.over` — the server's verdict.
    let isOver: Bool

    /// What VoiceOver reads instead of the track: one sentence the screen composed from catalogue copy and the
    /// server's display strings.
    let accessibilityDescription: Text

    /// `.bar{height:9px}`.
    private static let trackHeight: CGFloat = 9

    /// Clamped **again**, here. The server sends it clamped; a fill drawn at 1.4 would run outside the card, and a
    /// view that trusts a number it could check is a view that draws the one bad payload wrongly.
    private var clamped: Double { min(max(fill, 0), 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            figures

            row
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // One element carrying the whole fact, and the track is not it.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: amount))
        .accessibilityValue(accessibilityDescription)
    }

    /// `.bud-val` — the figure and the allowance beside it.
    private var figures: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(verbatim: amount)
                .font(.hw(.heading))
                .foregroundStyle(theme.palette.surface.ink)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)

            allowance
                .font(.hw(.caption))
                .foregroundStyle(theme.palette.surface.inkTertiary)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// `.bud-row` — the track and the percentage.
    ///
    /// **Only the track stands aside above the accessibility threshold, not the row** (ADR-0012). The figures above
    /// it are the amount and the allowance; the *percentage* is only here, so replacing the whole row — which is
    /// what this did until review — took "63%" off the screen at exactly the sizes where it is wanted most. The
    /// track's own replacement is nothing, because the percentage beside it says the same thing in words.
    private var row: some View {
        HStack(spacing: 11) {
            track
                .hwVisualisation { EmptyView() }

            Text(verbatim: percentageLabel)
                .font(.hw(.body).weight(.heavy))
                .foregroundStyle(isOver ? theme.palette.feedback.danger : theme.palette.accent.base)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var track: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(theme.palette.surface.backgroundSecondary)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(
                            // `.leading`/`.trailing` rather than fixed points: the gradient runs the way the bar
                            // fills, which under Arabic is the other way (ADR-0011).
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
        // `transition:transform 1s var(--ease-out)` — the fill grows into place. Under Reduce Motion it is
        // *there*, rather than growing slower (ADR-0012). The design's `shimmer` sweep is dropped rather than
        // gated, on the reasoning `Components.swift` records for the `START` flag's bob: an attention loop's only
        // honest replacement is the thing itself, and this bar is a record of a month that has closed.
        .animation(reduceMotion ? nil : HWMotion.easeOut.animation(.slow), value: clamped)
        .accessibilityHidden(true)
    }

    /// `linear-gradient(90deg,var(--planetary),var(--universe))`.
    private var stops: [Color] { [theme.palette.accent.base, theme.palette.accent.muted] }

    /// `.card.over .bar i{background:linear-gradient(90deg,#D6412F,#F2554E)}`.
    ///
    /// The darker end has no custom property behind it in the design, so the pair becomes the two tokens it sits
    /// between: the in-app danger and the savings ombré's own `--r1`, which the meter already owns. Resolved
    /// through roles so the later palette swap reaches both (ADR-0001).
    private var overStops: [Color] { [theme.palette.feedback.danger, theme.palette.meter.nothing] }
}

/// The design's `.facts` — the "For the record" grid: two columns of a label, a figure, and a qualifying line.
///
/// **One column above the accessibility threshold**, which is reading the size to choose a *layout* rather than a
/// clamp (ADR-0012) — the same call ``HWYearHeader`` and ``HWSpendSummary``'s chips make. Two 170pt tiles at AX3
/// break a figure across lines, and a figure broken across lines reads as a different figure.
struct HWFactGrid: View {
    @Environment(\.dynamicTypeSize) private var size

    let facts: [HWFact.Item]

    var body: some View {
        Group {
            if size.isAccessibilitySize {
                VStack(spacing: 9) {
                    ForEach(facts) { fact in
                        HWFact(fact)
                    }
                }
            } else {
                // A fixed two-column grid, as the design's `1fr 1fr` is. `LazyVGrid` rather than a `Grid`, so a
                // seventh fact wraps onto a third row without the grid being told how many rows to have.
                LazyVGrid(columns: [GridItem(spacing: 9), GridItem(spacing: 9)], spacing: 9) {
                    ForEach(facts) { fact in
                        HWFact(fact)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// One `.fact` — a label, the figure under it, and the line that qualifies it.
struct HWFact: View {
    @Environment(ThemeManager.self) private var theme

    /// One fact's three strings.
    ///
    /// The **label** is app copy naming a rule, chosen by the screen from the payload's `kind` (ADR-0011). The
    /// **value** and the **note** are the server's: one is a figure or a category name, and the other is a
    /// sentence with a figure inside it.
    struct Item: Identifiable, Sendable {
        /// The payload's own `kind`, so a grid's rows are identified by what they are about rather than by their
        /// position.
        let id: String
        let label: LocalizedStringResource
        let value: String
        let note: String?
    }

    private let item: Item

    init(_ item: Item) {
        self.item = item
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(item.label)
                .hwEyebrow()
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 2)

            Text(verbatim: item.value)
                .font(.hw(.subheading))
                .foregroundStyle(theme.palette.surface.ink)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)

            if let note = item.note {
                Text(verbatim: note)
                    .font(.hw(.caption))
                    .foregroundStyle(theme.palette.surface.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 13)
        .padding(.top, 13)
        .padding(.bottom, 12)
        .hwBox(
            fill: theme.palette.surface.backgroundSecondary,
            radius: .large,
            border: theme.palette.surface.separator
        )
        // Read as one thing, with the figure as the **value** so a re-read in another currency re-announces the
        // number rather than the label (ADR-0012), and the qualifying line as the hint.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(item.label))
        .accessibilityValue(Text(verbatim: item.value))
        .accessibilityHint(item.note.map { Text(verbatim: $0) } ?? Text(verbatim: ""))
    }
}

#if DEBUG
private let previewFacts: [HWFact.Item] = [
    .init(id: "salary", label: "Salary that month", value: "₹65,000", note: "No extra income"),
    .init(id: "goal", label: "Savings goal", value: "₹13,000", note: "Set at the start of the month"),
    .init(id: "saved", label: "Actually saved", value: "₹11,830", note: "18% of everything that came in"),
    .init(id: "biggestCost", label: "Biggest cost", value: "Rent", note: "₹26,960 that month"),
    .init(id: "needs", label: "Needs", value: "₹47,740", note: "Rent, bills and food"),
    .init(id: "leftOver", label: "Left over", value: "₹11,830", note: "Income minus everything spent"),
]

@MainActor
private func previewAllowance(_ fill: Double, _ percentage: String, isOver: Bool) -> some View {
    HWAllowanceBar(
        amount: isOver ? "₹21,400" : "₹5,430",
        allowance: Text(verbatim: "of ₹8,630 allowed"),
        percentageLabel: percentage,
        fill: fill,
        isOver: isOver,
        accessibilityDescription: Text(verbatim: "of ₹8,630 allowed, \(percentage)")
    )
}

#Preview("The allowance bar — within, and passed") {
    VStack(alignment: .leading, spacing: 30) {
        previewAllowance(0.6292, "63%", isOver: false)
        previewAllowance(1, "248%", isOver: true)
    }
    .padding()
    .background(HWPreviewGround())
    .hwTheme()
}

#Preview("The facts grid — six of them, two up") {
    HWFactGrid(facts: previewFacts)
        .padding()
        .background(HWPreviewGround())
        .hwTheme()
}

#Preview("The summary note, on the card it belongs inside") {
    HWSpendSummary(
        caption: "Total spent",
        total: "₹53,170",
        splits: [.init("Fixed", "₹32,960"), .init("Variable", "₹20,210"), .init("Extra in", "₹0")]
    ) {
        HWSummaryNote(
            note: Text(
                verbatim: """
                    Rent, bills and food came to ₹47,740 — more than half your ₹65,000 income, so the rest was \
                    split evenly between wants and savings.
                    """
            )
        )
    }
    .padding()
    .background(HWPreviewGround())
    .hwTheme()
}

#Preview("AX3 — the grid becomes one column and the track stands aside") {
    ScrollView {
        VStack(alignment: .leading, spacing: 24) {
            previewAllowance(0.6292, "63%", isOver: false)
            HWFactGrid(facts: previewFacts)
        }
        .padding()
    }
    .dynamicTypeSize(.accessibility3)
    .background(HWPreviewGround())
    .hwTheme()
}

#Preview("RTL — the bar fills from the right and the tiles mirror") {
    VStack(alignment: .leading, spacing: 24) {
        previewAllowance(0.6292, "63%", isOver: false)
        HWFactGrid(facts: Array(previewFacts.prefix(2)))
    }
    .padding()
    .environment(\.layoutDirection, .rightToLeft)
    .background(HWPreviewGround())
    .hwTheme()
}
#endif
