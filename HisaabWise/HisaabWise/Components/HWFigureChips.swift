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

    /// `.sum-split{display:flex;gap:10px}` with `flex:1` on each chip — **three across while the three figures
    /// fit, and a column the moment they do not**.
    ///
    /// **A `ViewThatFits`, where this asked `dynamicTypeSize.isAccessibilitySize` and stacked above the
    /// threshold.** That was the right instinct at the wrong resolution: how many figures fit across a card is a
    /// question about the *figures*, and text size is only one of the things that decides it. A month with
    /// `₹22,260` of variable spending in it came back with the middle chip reading `₹22,26` on one line and `0` on
    /// the next — a broken number, at the default text size, on a screen about money. `ViewThatFits` asks the
    /// question that actually matters, and every accessibility size still gets the column because at those sizes
    /// the row genuinely cannot fit: the same outcome as the threshold, from the real cause.
    ///
    /// Neither branch may truncate or shrink to fit (`LocalisationTests`), so choosing the layout **is** the fix —
    /// and choosing it needs the row to be able to say it does not fit. Two things make that work, and both are
    /// easy to get wrong in a way that looks fixed:
    ///
    /// - **The figure inside each chip refuses to wrap** (see ``HWFigureChip``). Without that a chip absorbs any
    ///   width by breaking its number, so the row reports that it fits at every width and `ViewThatFits` never
    ///   reaches the column.
    /// - **`frame(maxWidth: .infinity)` goes outside the choice, not on the candidates.** A candidate that says it
    ///   will take any width also reports that it fits at any width. The candidates state what they *need*; the
    ///   chosen one is then stretched to fill the card.
    ///
    /// A `Grid` stood here before either of those and is what hung the last chip off the side of the card: it
    /// sizes columns to the widest cell's ideal width and then grows past its parent rather than compressing. The
    /// equal *heights* it was there for come from the row's `fixedSize` instead — each chip asks for the full
    /// height offered and the row offers the tallest chip's — so a caption wrapping one line still leaves three
    /// boxes of one height.
    var body: some View {
        ViewThatFits(in: .horizontal) {
            row
            column
        }
        .frame(maxWidth: .infinity)
    }

    private var row: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(splits) { split in
                HWFigureChip(split)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var column: some View {
        VStack(spacing: 10) {
            ForEach(splits) { split in
                HWFigureChip(split)
            }
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
            // `countTo($('#sum-fixed'), …)` — the design counts all three of these up, and it is the same
            // component the big total above them uses (``HWCountingFigure``).
            //
            // **`fixedSize` on *both* axes — the figure does not wrap, and that is what makes the row/column
            // choice above possible.** A monetary figure broken across two lines reads as two numbers: the
            // over-budget month came back with this chip saying `₹22,26` over `0`. Refusing to wrap turns "this
            // does not fit" from something the chip absorbs silently into something the chip *demands*, which is
            // what ``HWFigureChips/body``'s `ViewThatFits` needs in order to see it and stack instead. It is not a
            // truncation and not a shrink-to-fit — nothing is lost, the layout changes (ADR-0011, ADR-0012). The
            // caption below is still free to wrap, because a word wrapping is not a number breaking.
            HWCountingFigure(figure: split.value)
                .font(.hw(.bodyLarge).weight(.heavy))
                .foregroundStyle(theme.palette.brand.ink)
                .fixedSize()

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
