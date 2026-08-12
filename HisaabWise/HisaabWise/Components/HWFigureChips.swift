import SwiftUI

/// The design's `.chip` — a figure over a caption, in a tinted box on the galaxy ground.
///
/// **One owner, because the design has one class and two callers.** `.sum-split` on Expenses and `.hero-split`
/// on Reports are the same three-up row of the same chip, and a second private copy inside the second card is
/// how two controls come to look alike until one of them changes (`Components.swift`).
///
/// The figure is a `String` and this never spells one: it is a server-formatted amount or a server-formatted
/// count (ADR-0003). The caption is app copy, because it names a rule — "Fixed", "Total saved" — rather than
/// anything the server stores.
struct HWFigureChips: View {
    /// Read to decide whether the chips are a row or a column — see ``body``. **Not a clamp**: this reads the
    /// size to choose a *layout*, which is what ADR-0012 asks for, and `AccessibilityTests` bans only the range
    /// form of `dynamicTypeSize` that caps it.
    @Environment(\.dynamicTypeSize) private var size

    /// One chip.
    struct Split: Sendable, Identifiable {
        /// `.chip span` — "Fixed", "Variable", "Income", "Months". App copy: it names a rule, not a thing the
        /// server stores.
        let label: LocalizedStringResource
        /// `.chip b` — the figure, server-formatted (ADR-0003).
        let value: String

        var id: String { label.key }

        init(_ label: LocalizedStringResource, _ value: String) {
            self.label = label
            self.value = value
        }
    }

    private let splits: [Split]

    init(_ splits: [Split]) {
        self.splits = splits
    }

    /// The chips, sharing the width equally, **until they cannot**.
    ///
    /// A row of three at accessibility sizes leaves each about 100pt, and `₹3,529` came back as three lines
    /// reading "₹3, / 52 / 9" with `VARI / ABL / E` beside it. Found by looking at a render, and fixed the way
    /// `HomeView.duo` fixes the same thing for its two-up grid: **the row becomes a column** above the threshold,
    /// where each chip has the whole width and the figures read.
    ///
    /// Below it, a `Grid` rather than an `HStack`, so all three take the height of the tallest — "Variable" wraps
    /// one word sooner than "Income" and an `HStack` would leave three boxes of three heights.
    var body: some View {
        if size.isAccessibilitySize {
            VStack(spacing: 10) {
                ForEach(splits) { split in
                    HWFigureChip(split)
                }
            }
            .frame(maxWidth: .infinity)
        } else {
            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    ForEach(splits) { split in
                        HWFigureChip(split)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

/// One `.chip`.
struct HWFigureChip: View {
    @Environment(ThemeManager.self) private var theme

    private let split: HWFigureChips.Split

    init(_ split: HWFigureChips.Split) {
        self.split = split
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: split.value)
                .font(.hw(.bodyLarge).weight(.heavy))
                .foregroundStyle(theme.palette.brand.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text(split.label)
                .hwEyebrow(.brand)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .hwBox(
            fill: theme.palette.brand.raised,
            radius: .medium,
            border: theme.palette.brand.separator
        )
        // "Fixed, ₹3,529" as one element rather than two swipes. The *label* is the caption and the figure is
        // the value, so a changed figure re-announces the number (ADR-0012).
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(split.label))
        .accessibilityValue(Text(verbatim: split.value))
    }
}

#if DEBUG
private let previewSplits: [HWFigureChips.Split] = [
    .init("Months", "6"),
    .init("Avg. spend", "₹57,050"),
    .init("Total saved", "₹76,700"),
]

#Preview("Figure chips — three across") {
    HWFigureChips(previewSplits)
        .padding()
        .background(HWPreviewGround(appearance: .brand))
        .hwTheme()
}

#Preview("AX3 — the row becomes a column") {
    HWFigureChips(previewSplits)
        .padding()
        .dynamicTypeSize(.accessibility3)
        .background(HWPreviewGround(appearance: .brand))
        .hwTheme()
}

#Preview("RTL — the first chip leads from the right") {
    HWFigureChips(previewSplits)
        .padding()
        .environment(\.layoutDirection, .rightToLeft)
        .background(HWPreviewGround(appearance: .brand))
        .hwTheme()
}
#endif
