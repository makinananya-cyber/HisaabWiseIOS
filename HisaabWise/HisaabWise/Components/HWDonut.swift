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
    private static let angularInset = 1.5
    /// The design draws the ring at 132×132.
    private static let diameter: CGFloat = 132

    /// What `chartAngleSelection` writes: a position in the value domain, not a slice.
    @State private var selectedValue: Double?

    var body: some View {
        chart
            // The ring is capped and then **replaced** above the threshold, and the replacement doubles as the
            // chart's accessibility representation — so VoiceOver reads the category list whether or not the list
            // is what is drawn (ADR-0012, `HWScaling`).
            .hwVisualisation {
                HWCategoryList(slices: slices, isolated: isolated, onIsolate: onIsolate)
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

/// The category rows: the design's `.key`, and the layout that **replaces** the donut above the size threshold.
///
/// One view doing both jobs is deliberate. The design draws the key beside the ring at ordinary sizes, and
/// ADR-0012 requires an equivalent text layout at accessibility sizes — which is the same list. Writing it twice
/// would be two lists that drift, and the second one only for the users who cannot see the first.
struct HWCategoryList: View {
    @Environment(ThemeManager.self) private var theme

    let slices: [HWDonut.Slice]
    let isolated: String?
    let onIsolate: (String?) -> Void

    var body: some View {
        VStack(spacing: 2) {
            ForEach(slices) { slice in
                Button {
                    onIsolate(slice.id)
                } label: {
                    row(slice)
                }
                .buttonStyle(HWPressStyle.compact)
                // Read as one thing — "Rent, ₹3,000, 54%" — and its isolated state announced rather than left to
                // the tint, which VoiceOver cannot see (ADR-0012).
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: slice.name))
                .accessibilityValue(Text(verbatim: "\(slice.amount), \(slice.shareLabel)"))
                .hwSelectionTraits(isSelected: isolated == slice.id)
            }
        }
    }

    private func row(_ slice: HWDonut.Slice) -> some View {
        HStack(spacing: 10) {
            // `.key-dot`
            Circle()
                .fill(colour(for: slice))
                .frame(width: 9, height: 9)
                .accessibilityHidden(true)

            Text(verbatim: slice.name)
                .font(.hw(.body))
                .foregroundStyle(theme.palette.surface.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(verbatim: slice.shareLabel)
                .font(.hw(.body).weight(.bold))
                .foregroundStyle(theme.palette.surface.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(minHeight: HWTouchTarget.minimum)
        .hwBox(
            // `.key-row.on` — the isolated row takes the sky wash, which is the same signal the ring gives.
            fill: isolated == slice.id ? theme.palette.accent.soft : Color.clear,
            radius: .medium
        )
        .contentShape(.rect)
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

#Preview("Donut — whole ring and one slice isolated") {
    @Previewable @State var isolated: String?

    VStack(spacing: 24) {
        HWDonut(slices: previewSlices, isolated: isolated, onIsolate: { isolated = $0 }) {
            VStack(spacing: 1) {
                Text(verbatim: "Total spent").hwLabel()
                Text(verbatim: "₹5,539").font(.hw(.subheading))
            }
        }

        HWCategoryList(slices: previewSlices, isolated: isolated, onIsolate: { isolated = $0 })
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
    HWCategoryList(slices: previewSlices, isolated: "groceries", onIsolate: { _ in })
        .padding()
        .environment(\.layoutDirection, .rightToLeft)
        .background(HWPreviewGround())
        .hwTheme()
}
#endif
