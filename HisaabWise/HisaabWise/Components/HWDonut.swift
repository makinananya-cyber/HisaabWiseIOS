import Charts
import SwiftUI

/// The design's spending donut — `SectorMark`, tap to isolate, and a centre readout.
///
/// **Swift Charts rather than a hand-rolled ring** (ADR-0016), and the reason is accessibility rather than
/// convenience: `SectorMark` gives every segment a per-mark descriptor, so VoiceOver moves through the slices as
/// data. A hand-rolled arc is one shape with one label, and adding descriptors to it means re-implementing what
/// the framework already publishes.
///
/// **The savings meter is the opposite call, in the same ADR.** A bar with a sliding pin and a floating pill is
/// not a chart mark, and expressing it as one fights the framework for a shape it does not have. The rule is: a
/// *mark* the framework knows about, drawn by the framework; a *shape* the design invented, drawn by hand.
///
/// **It computes nothing.** Each slice arrives with its fraction and its percentage label already worked out
/// (ADR-0020). The one piece of arithmetic here maps a *selected angle* back to a slice, which is hit-testing —
/// no figure the user reads comes out of it.
struct HWDonut: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// One slice: enough to draw it, isolate it, and describe it.
    struct Slice: Identifiable, Sendable, Hashable {
        let id: String
        let name: String
        /// `0...1`, from the server. Geometry, not a displayed figure.
        let share: Double
        /// "38%" — what the key row and the isolated readout show.
        let shareLabel: String
        /// The server-formatted amount.
        let amount: String
        /// Which category colour slot, `1...6`.
        let slot: Int
    }

    private let slices: [Slice]
    /// The isolated slice's id, or `nil` for the whole ring. Owned by the caller, because isolating a slice also
    /// changes the centre readout and the key rows — three things reading one piece of state.
    private let isolated: String?
    private let onIsolate: (String?) -> Void
    /// What sits in the hole: the caller's, because it is a caption over a figure and both come from the payload.
    private let centre: AnyView

    init<Centre: View>(
        slices: [Slice],
        isolated: String?,
        onIsolate: @escaping (String?) -> Void,
        @ViewBuilder centre: () -> Centre
    ) {
        self.slices = slices
        self.isolated = isolated
        self.onIsolate = onIsolate
        self.centre = AnyView(centre())
    }

    /// `viewBox="0 0 132 132"` with a 15-unit stroke on r=51 — a ring whose hole is about 68% of its diameter.
    private static let innerRadiusRatio = 0.68
    /// `GAP = 3` surface units between segments, as an inset in the same units the chart works in.
    ///
    /// The gaps are the design's — it draws `stroke-dasharray` short by `GAP` on every segment — so the ring is
    /// deliberately not a closed circle. Looked at in the Simulator the seam between the last slice and the first
    /// reads slightly wider than the others, because it is the one gap with the same colour on neither side.
    private static let angularInset = 1.5
    /// The design draws the ring at 132×132.
    static let diameter: CGFloat = 132

    /// The diameter of the hole the centre readout sits in — `diameter × innerRadiusRatio`, ≈ 90pt. The readout
    /// is constrained to it so a long figure ("AED 12,345") scales down inside the ring rather than growing wide
    /// enough to sit on top of it, which is what a month of real spending made it do.
    static let innerDiameter: CGFloat = diameter * innerRadiusRatio

    /// `stroke-width="15"` — the ring's thickness, shared with the empty ring so the two are the same shape.
    static let ringWidth: CGFloat = 15

    /// What `chartAngleSelection` writes: a position in the value domain, not a slice.
    @State private var selectedValue: Double?

    var body: some View {
        chart
            // The ring is capped and then **replaced** above the threshold, and the replacement doubles as the
            // chart's accessibility representation — so VoiceOver reads the category list whether or not the list
            // is what is drawn (ADR-0012, `HWScaling`).
            // `describesItself` — every `SectorMark` carries a label and a value, and that is the whole reason
            // this is Swift Charts rather than a hand-rolled arc (ADR-0016). Installing a representation over the
            // chart would have replaced those descriptors, so they were read by nothing at any size.
            //
            // **And the replacement is nothing at all**, because the equivalent layout is already on the screen:
            // the design draws the category key beside the ring at every size, so `HomeView` owns it and above the
            // threshold the ring is simply absent. Passing the key here as well drew it twice at accessibility
            // sizes — and passing it *only* here left the categories invisible at ordinary ones, which is the
            // trade the first two attempts each got one half of.
            .hwVisualisation(describesItself: true) {
                EmptyView()
            }
    }

    private var chart: some View {
        Chart(slices) { slice in
            SectorMark(
                angle: .value(Text(verbatim: slice.name), slice.share),
                innerRadius: .ratio(Self.innerRadiusRatio),
                angularInset: Self.angularInset
            )
            .cornerRadius(2)
            .foregroundStyle(colour(for: slice))
            // `.dim` — the design fades the others rather than hiding them, so the ring keeps its shape while
            // one slice is being read.
            .opacity(isolated == nil || isolated == slice.id ? 1 : 0.28)
            // The per-mark descriptors that are the reason for using `SectorMark` at all.
            .accessibilityLabel(slice.name)
            .accessibilityValue(Text(verbatim: "\(slice.amount), \(slice.shareLabel)"))
        }
        .chartLegend(.hidden)
        // Selection by angle, which is what a donut can offer: `chartAngleSelection` reports where in the value
        // domain the tap landed, and `slice(at:in:)` turns that into a slice.
        .chartAngleSelection(value: $selectedValue)
        .onChange(of: selectedValue) { _, value in
            // **Cleared every time**, and the `nil` case passed on rather than swallowed. Leaving the last angle
            // in `@State` meant a tap on the same arc after un-isolating from a key row changed nothing —
            // `onChange` never fired — and swallowing a `nil` left the ring isolated while the chart believed
            // nothing was selected, so un-isolating by tapping outside took two presses.
            let id = Self.slice(at: value, in: slices)?.id
            if value != nil { selectedValue = nil }
            onIsolate(id)
        }
        .frame(width: Self.diameter, height: Self.diameter)
        .overlay { centre }
        .animation(reduceMotion ? nil : HWMotion.easeOut.animation(.standard), value: isolated)
        // One element for the ring itself; the descriptors above are its children, and the centre readout is
        // drawn over it rather than inside it.
        .accessibilityElement(children: .contain)
    }

    /// Which slice a selected angle value belongs to.
    ///
    /// `chartAngleSelection` gives a position in the **value** domain — the sum of the shares before the tap —
    /// not an index, so the shares are accumulated until the position is passed. `static` and pure so the mapping
    /// is testable: "tapping at 0.6 of the way round selects the category that spans it" is a rule, and a rule
    /// worth writing is worth asserting.
    static func slice(at value: Double?, in slices: [Slice]) -> Slice? {
        guard let value, value >= 0 else { return nil }
        var accumulated = 0.0
        for slice in slices {
            accumulated += slice.share
            if value <= accumulated { return slice }
        }
        // Past the end: rounding in the shares can leave a sliver beyond the last boundary, and a tap there
        // belongs to the last slice rather than to nothing.
        return slices.last
    }

    /// The six category colour slots, by palette role. A slot outside the range wraps rather than crashing: the
    /// number arrives from a payload, and a seventh category is a server change, not a client crash.
    private func colour(for slice: Slice) -> Color {
        let palette = theme.palette.categories.all
        guard !palette.isEmpty else { return theme.palette.accent.base }
        return palette[(max(slice.slot, 1) - 1) % palette.count]
    }
}

/// The design's `drawEmptyDonut()` — the ring a brand-new account gets.
///
/// **A real ring, not a glyph.** The design draws the same circle in `--empty` and keeps the centre readout with
/// zeroes in it, so the card the user meets on their first day is the card they will keep seeing rather than a
/// different one. Hand-drawn because there is nothing to slice: a `SectorMark` with one value would be a chart
/// describing an absence.
struct HWEmptyRing<Centre: View>: View {
    @Environment(ThemeManager.self) private var theme

    private let centre: Centre

    init(@ViewBuilder centre: () -> Centre) {
        self.centre = centre()
    }

    var body: some View {
        Circle()
            // The same geometry the donut uses, so the two cards are the same size and the swap is not a jump.
            .stroke(theme.palette.feedback.emptyTrack, lineWidth: HWDonut.ringWidth)
            .frame(width: HWDonut.diameter - HWDonut.ringWidth, height: HWDonut.diameter - HWDonut.ringWidth)
            .frame(width: HWDonut.diameter, height: HWDonut.diameter)
            .overlay { centre }
            // The ring says nothing a screen reader needs; the readout inside it says all of it.
            .accessibilityHidden(true)
            .accessibilityElement(children: .contain)
    }
}

/// The category rows: the design's `.key`, and the layout that **replaces** the donut above the size threshold.
///
/// One view doing both jobs is deliberate. The design draws the key beside the ring at ordinary sizes, and
/// ADR-0012 requires an equivalent text layout at accessibility sizes — which is the same list. Writing it twice
/// would be two lists that drift, and the second one only for the users who cannot see the first.
///
/// **The rows are not controls.** Each one used to be a `Button` that isolated its slice, duplicating what a tap on
/// the ring already does — six extra tab stops for a reading that the ring beside them offers, and a legend that
/// looked pressable without saying what pressing it would do. The key is a *key*: it names the colours in the ring
/// and states each share. Isolating a slice is the ring's own affordance, and ``isolated`` is still read here so
/// that a slice picked there is marked in the list too.
struct HWCategoryList: View {
    @Environment(ThemeManager.self) private var theme

    let slices: [HWDonut.Slice]
    /// The slice the ring has isolated, so the row for it takes the same wash. Read, never written.
    let isolated: String?

    var body: some View {
        VStack(spacing: 1) {
            ForEach(slices) { slice in
                row(slice)
                    // Read as one thing — "Rent, ₹3,000, 54%" — and the isolated state announced rather than
                    // left to the tint, which VoiceOver cannot see (ADR-0012). Still a single element even
                    // though it is no longer a control: three views state one fact.
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: slice.name))
                    .accessibilityValue(Text(verbatim: "\(slice.amount), \(slice.shareLabel)"))
                    .hwSelectionTraits(isSelected: isolated == slice.id)
            }
        }
    }

    private func row(_ slice: HWDonut.Slice) -> some View {
        HStack(spacing: 9) {
            // `.key-dot{width:9px;height:9px;border-radius:3px}` — a rounded square rather than a circle, which
            // is what the design draws and what keeps six of them reading as a key rather than as bullet points.
            RoundedRectangle(cornerRadius: HWRadius.hairline.points)
                .fill(colour(for: slice))
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)

            Text(verbatim: slice.name)
                .font(.hw(.body).weight(.semibold))
                .foregroundStyle(theme.palette.surface.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(verbatim: slice.shareLabel)
                .font(.hw(.body).weight(.heavy))
                .foregroundStyle(theme.palette.surface.ink)
                // `font-variant-numeric:tabular-nums` — six percentages in a column line up.
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
        }
        // `.key-row{padding:5px 6px}`. No 44pt minimum: these are no longer targets, and forcing one would
        // stretch a six-row key to 264pt beside a 132pt ring.
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .hwBox(
            // `.key-row.on` — the isolated row takes the sky wash, which is the same signal the ring gives.
            fill: isolated == slice.id ? theme.palette.accent.soft : Color.clear,
            radius: .small
        )
    }

    private func colour(for slice: HWDonut.Slice) -> Color {
        let palette = theme.palette.categories.all
        guard !palette.isEmpty else { return theme.palette.accent.base }
        return palette[(max(slice.slot, 1) - 1) % palette.count]
    }
}

#if DEBUG
private let previewSlices: [HWDonut.Slice] = [
    .init(id: "rent", name: "Rent", share: 0.5416, shareLabel: "54%", amount: "₹3,000", slot: 1),
    .init(id: "groceries", name: "Groceries", share: 0.1552, shareLabel: "16%", amount: "₹860", slot: 2),
    // "Travel" rather than the design's "Transport": `LayeringTests` scans this layer for the word
    // `Transport`, and a preview's sample data is not worth weakening the scan for.
    .init(id: "transport", name: "Travel", share: 0.0794, shareLabel: "8%", amount: "₹440", slot: 3),
    .init(id: "utilities", name: "Utilities", share: 0.0955, shareLabel: "10%", amount: "₹529", slot: 4),
    .init(id: "entertainment", name: "Entertainment", share: 0.0542, shareLabel: "5%", amount: "₹300", slot: 5),
    .init(id: "other", name: "Other", share: 0.0740, shareLabel: "7%", amount: "₹410", slot: 6),
]

/// The pair as Home draws them — the ring on the leading side, the key beside it — so a tap on a wedge can be
/// seen marking the matching row.
#Preview("Donut — the ring and its key, side by side") {
    @Previewable @State var isolated: String?

    HStack(alignment: .center, spacing: 14) {
        HWDonut(slices: previewSlices, isolated: isolated, onIsolate: { isolated = $0 }) {
            VStack(spacing: 1) {
                Text(verbatim: "Total spent").hwLabel()
                Text(verbatim: "₹5,539").font(.hw(.subheading))
            }
        }

        HWCategoryList(slices: previewSlices, isolated: isolated)
    }
    .padding()
    .background(HWPreviewGround())
    .hwTheme()
}

#Preview("AX3 — the ring is replaced by the list") {
    HWDonut(slices: previewSlices, isolated: "rent", onIsolate: { _ in }) {
        Text(verbatim: "₹5,539")
    }
    .padding()
    .dynamicTypeSize(.accessibility3)
    .background(HWPreviewGround())
    .hwTheme()
}

#Preview("RTL — the rows mirror and the ring keeps its direction") {
    HWCategoryList(slices: previewSlices, isolated: "groceries")
        .padding()
        .environment(\.layoutDirection, .rightToLeft)
        .background(HWPreviewGround())
        .hwTheme()
}
#endif
