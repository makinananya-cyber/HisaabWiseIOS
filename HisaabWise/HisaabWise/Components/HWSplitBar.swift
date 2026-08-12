import SwiftUI

/// Which of the four parts of a month's income a segment is — the design's `.split i` colours, as a closed
/// vocabulary.
///
/// **Four, because Product Spec §4.2 [FIX] says four.** The design's fourth part was "left unspent", which a
/// residual definition of `saved` makes identically zero: all spending is needs or wants, so income minus both
/// *is* what was saved and there is nothing left to draw. ``surplus`` — what was saved above the goal — replaces
/// it.
///
/// A named set rather than a slot number, for ``HWVerdictTint``'s reason: these are not six interchangeable
/// category colours but four quantities with four meanings, and the palette roles they take say so — needs and
/// wants borrow the category slots the donut gives them, and both savings parts come from the meter's own ombré.
enum HWSplitPortion: Sendable, Hashable, CaseIterable {
    /// Rent, utilities, groceries — `var(--s1)`, the slot the donut gives Rent.
    case needs
    /// What actually went on wants — `var(--s5)`, Entertainment's slot.
    case wants
    /// The part of the goal that was reached — `var(--r5)`, the top of the savings ombré.
    case saved
    /// What was saved beyond the goal.
    ///
    /// **The one colour that is not transcribed**, because the segment it replaces described something else: the
    /// design paints "left unspent" in a flat `#C6D5EA` grey, and a surplus is *savings*. So it takes the
    /// neighbouring stop of the same ombré `saved` comes from — `var(--r4)` — which reads as "the same thing,
    /// more of it" rather than as a fourth unrelated colour.
    case surplus
}

/// The design's `.split` and `.split-key` — where a closed month's income went, as one bar and the list that
/// names its parts.
///
/// **Nothing here is computed.** Each part arrives with its share of the income as a fraction and its figure as a
/// display string (ADR-0020); the design divided four amounts by their total in the browser, having first
/// re-implemented the 50/30/20 engine there to get two of them (invariant 3).
///
/// **The bar is replaced above the accessibility threshold by the key list that is already under it** (ADR-0012),
/// which is the call ``HWDonut`` makes for the same reason: the design draws the key at every size, so passing it
/// as the alternative as well would draw it twice at accessibility sizes, and passing it *only* as the
/// alternative would leave the parts unnamed at ordinary ones. Above the threshold the bar is gone — not smaller —
/// and what remains is a labelled list of four rows, each with its name, its figure, and its aim.
struct HWSplitBar: View {
    @Environment(ThemeManager.self) private var theme

    /// One part: what it is called, what it came to, what it was aiming at, and how much of the bar it fills.
    struct Segment: Identifiable, Sendable {
        let portion: HWSplitPortion
        var id: HWSplitPortion { portion }

        /// "Needs" — app copy naming a rule, so it comes from the screen's catalogue rather than from a payload
        /// (ADR-0011), exactly as ``HWFigureChips/Split``'s caption does.
        let name: LocalizedStringResource

        /// The part's figure, server-formatted.
        let amount: String

        /// "aim ₹32,500" — one catalogue sentence with the server's figure in it, or `nil` for the surplus, which
        /// has no aim of its own.
        let target: Text?

        /// The part's share of the income, `0...1`, from the server. Geometry — the name is
        /// ``HWProportionBar/Segment``'s for the same reason: it is a stripe's extent as a fraction of its track.
        let width: Double
    }

    let segments: [Segment]

    /// What VoiceOver reads for the bar as a whole, and the heading of the list that replaces it. The screen's,
    /// from the catalogue.
    let accessibilityLabel: LocalizedStringResource

    /// `.split{height:32px;gap:2px;border-radius:11px}`.
    private static let height: CGFloat = 32
    private static let spacing: CGFloat = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            bar
                // Replaced by the key below, which is already on screen — see the note on the type.
                .hwVisualisation { EmptyView() }

            key
        }
    }

    // MARK: - The bar

    private var bar: some View {
        // `GeometryReader`, because a part's width is a fraction of a width only the layout knows — the same
        // reason ``HWProportionBar`` reads one.
        GeometryReader { proxy in
            HStack(spacing: Self.spacing) {
                ForEach(segments) { segment in
                    RoundedRectangle(cornerRadius: HWRadius.hairline.points)
                        .fill(colour(for: segment.portion))
                        .frame(width: width(of: segment, in: proxy.size.width))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: Self.height)
        .clipShape(.rect(cornerRadius: HWRadius.small.points))
        // The bar says nothing the key does not say in words, and the key is drawn at every size.
        .accessibilityHidden(true)
    }

    /// The part's own width, with the gaps taken off the total first — otherwise four parts summing to 1 plus
    /// three 2pt gaps is six points wider than the card.
    private func width(of segment: Segment, in total: CGFloat) -> CGFloat {
        let gaps = Self.spacing * CGFloat(max(segments.count - 1, 0))
        return max(0, (total - gaps) * min(max(segment.width, 0), 1))
    }

    // MARK: - The key

    /// `.split-key` — one `.sk` row per part: a dot, the name, the figure, and the aim.
    private var key: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(segments) { segment in
                row(segment)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(accessibilityLabel))
    }

    private func row(_ segment: Segment) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            // `.sk-dot`
            RoundedRectangle(cornerRadius: HWRadius.hairline.points)
                .fill(colour(for: segment.portion))
                .frame(width: 9, height: 9)
                .accessibilityHidden(true)

            Text(segment.name)
                .font(.hw(.body).weight(.semibold))
                .foregroundStyle(theme.palette.surface.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(verbatim: segment.amount)
                .font(.hw(.body).weight(.heavy))
                .foregroundStyle(theme.palette.surface.ink)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)

            if let target = segment.target {
                target
                    .font(.hw(.caption))
                    .foregroundStyle(theme.palette.surface.inkTertiary)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.trailing)
            }
        }
        // One element per part: "Needs" — "₹47,740" — "aim ₹32,500". The figure is the **value**, so a re-read in
        // another currency re-announces the number rather than the name (ADR-0012), and the aim is the *hint*
        // rather than being joined onto it — a sentence assembled from fragments is untranslatable (ADR-0011),
        // and the aim already arrives as a whole catalogue sentence from the screen.
        //
        // An absent hint is an empty one, which is the form ``HWTextField`` uses for its optional error:
        // `accessibilityHint` takes a
        // non-optional and a `Text("")` adds nothing to the reading.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(segment.name))
        .accessibilityValue(Text(verbatim: segment.amount))
        .accessibilityHint(segment.target ?? Text(verbatim: ""))
    }

    /// The four palette roles, by portion. Needs and wants take the category slots the donut gives them; both
    /// savings parts come from the meter's own ombré — see ``HWSplitPortion``.
    private func colour(for portion: HWSplitPortion) -> Color {
        switch portion {
        case .needs: theme.palette.categories.rent
        case .wants: theme.palette.categories.entertainment
        case .saved: theme.palette.meter.reached
        case .surplus: theme.palette.meter.high
        }
    }
}

#if DEBUG
/// February's split: needs past half the income, so the engine adapted — and a surplus of nothing.
private let previewSegments: [HWSplitBar.Segment] = [
    .init(portion: .needs, name: "Needs", amount: "₹47,740",
          target: Text(verbatim: "aim ₹32,500"), width: 0.7345),
    .init(portion: .wants, name: "Wants", amount: "₹5,430",
          target: Text(verbatim: "aim ₹8,630"), width: 0.0835),
    .init(portion: .saved, name: "Savings", amount: "₹11,830",
          target: Text(verbatim: "aim ₹8,630"), width: 0.182),
    .init(portion: .surplus, name: "Above goal", amount: "₹0", target: nil, width: 0),
]

/// And a month with nothing logged, where the surplus is most of the bar.
private let previewSurplus: [HWSplitBar.Segment] = [
    .init(portion: .needs, name: "Needs", amount: "₹0", target: Text(verbatim: "aim ₹32,500"), width: 0),
    .init(portion: .wants, name: "Wants", amount: "₹0", target: Text(verbatim: "aim ₹19,500"), width: 0),
    .init(portion: .saved, name: "Savings", amount: "₹13,000",
          target: Text(verbatim: "aim ₹13,000"), width: 0.2),
    .init(portion: .surplus, name: "Above goal", amount: "₹52,000", target: nil, width: 0.8),
]

@MainActor
private func previewBars() -> some View {
    VStack(alignment: .leading, spacing: 28) {
        HWSplitBar(segments: previewSegments, accessibilityLabel: "Needs, wants and savings split")
        HWSplitBar(segments: previewSurplus, accessibilityLabel: "Needs, wants and savings split")
    }
}

#Preview("Split bar — a month that adapted, and a month with nothing in it") {
    previewBars()
        .padding()
        .background(HWPreviewGround())
        .hwTheme()
}

#Preview("AX3 — the bar stands aside and the four parts remain as rows") {
    previewBars()
        .padding()
        .dynamicTypeSize(.accessibility3)
        .background(HWPreviewGround())
        .hwTheme()
}

#Preview("RTL — the parts fill from the right") {
    previewBars()
        .padding()
        .environment(\.layoutDirection, .rightToLeft)
        .background(HWPreviewGround())
        .hwTheme()
}
#endif
