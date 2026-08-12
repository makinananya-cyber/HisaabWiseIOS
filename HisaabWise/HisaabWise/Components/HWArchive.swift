import SwiftUI

/// The design's `.hero` — the galaxy card Reports opens with: what the archive adds up to, the trend chart, and
/// three figures under it.
///
/// **A brand-coloured card on a surface screen**, for the reason ``HWSpendSummary`` records: ADR-0021's two
/// appearances are two *surfaces*, and the design paints a galaxy gradient panel on the light ground here exactly
/// as it paints a milky wordmark tile on the dark one. So every role inside is a `brand` role while the card sits
/// on `surface`.
///
/// The chart is a `ViewBuilder` slot rather than the trend's own arguments, the way `HWSpendSummary` takes its
/// budget bar: the card is a card, and one that took a chart as data would be picking which chart.
struct HWArchiveHero<Chart: View>: View {
    @Environment(ThemeManager.self) private var theme

    /// `.hero-cap` — "How close you got to your savings goal". App copy: it explains the chart.
    private let caption: LocalizedStringResource
    /// `.hero-sub` — "Goal met in 2 of 6 months · the dashed line is the goal".
    ///
    /// A `Text` rather than a `String` or a resource, because it is **both**: the count and its plural are the
    /// server's sentence and the explanation around them is the app's copy, so the caller resolves the one into
    /// the other. Resolving it to a `String` here would resolve it against the *device's* locale rather than the
    /// app's chosen language, which is the trap `HWAnnouncement` exists for (ADR-0011, ADR-0024).
    private let subtitle: Text
    /// `.hero-split` — the three figures.
    private let splits: [HWFigureChips.Split]
    private let chart: Chart

    init(
        caption: LocalizedStringResource,
        subtitle: Text,
        splits: [HWFigureChips.Split],
        @ViewBuilder chart: () -> Chart
    ) {
        self.caption = caption
        self.subtitle = subtitle
        self.splits = splits
        self.chart = chart()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(caption)
                .hwEyebrow(.brand)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            subtitle
                .font(.hw(.caption))
                .foregroundStyle(theme.palette.brand.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)

            chart
                .padding(.top, 16)

            HWFigureChips(splits)
                .padding(.top, 15)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.top, 19)
        .padding(.bottom, 16)
        .hwBox(fill: ground, radius: .extraLarge, elevation: .large)
        .accessibilityElement(children: .contain)
    }

    /// `background:linear-gradient(145deg,var(--galaxy),#123273 55%,var(--planetary))` — the same wash
    /// `HWSpendSummary` draws, and **three stops become two** for the same reason: the middle one is a shade of
    /// galaxy used only for depth, and it has no palette role because nothing else in the design asks for one.
    private var ground: LinearGradient {
        LinearGradient(
            colors: [theme.palette.brand.background, theme.palette.accent.base],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

/// The design's `.yr` — a year, a hairline rule, and what was saved across it.
///
/// The total is the **server's** (ADR-0020): the design filtered the whole archive by year and reduced it, once
/// per header, while rendering the list.
struct HWYearHeader: View {
    @Environment(ThemeManager.self) private var theme

    /// Read to decide whether the header is a row or two lines — see ``body``. **Not a clamp**: this reads the
    /// size to choose a *layout*, which is what ADR-0012 asks for.
    @Environment(\.dynamicTypeSize) private var size

    /// "2026" — a label, not a number.
    let year: String
    /// "₹76,700 saved" — app copy with the server's figure in it, composed by the screen.
    let saved: Text

    /// **A row until the total has to break to fit, and then two lines.**
    ///
    /// Found by looking, as `HWSpendSummary`'s chips were: at AX3 the year, the rule, and the total shared one
    /// line and `₹76,700 saved` wrapped as `₹76,70` / `0 saved` — a *figure* broken across lines, which reads as
    /// a different figure. Shrinking it is not an option (ADR-0012) and truncating it is not either, so the rule
    /// goes and the total gets the whole width.
    var body: some View {
        Group {
            if size.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 2) {
                    yearLabel
                    total
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .center, spacing: 10) {
                    yearLabel

                    // `.yr i` — the rule between the year and its total. Decorative: the two ends say everything.
                    Rectangle()
                        .fill(theme.palette.surface.separator)
                        .frame(height: 1)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)

                    total
                }
            }
        }
        // "2026, ₹76,700 saved" as one heading, which is what a year divider is.
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var yearLabel: some View {
        Text(verbatim: year)
            .hwEyebrow()
            .fixedSize(horizontal: false, vertical: true)
    }

    private var total: some View {
        saved
            .font(.hw(.caption))
            .foregroundStyle(theme.palette.surface.inkTertiary)
            .monospacedDigit()
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The design's `.month` — one closed month's **contents**: when, what it cost, how the goal went, and how it was
/// shaped.
///
/// **A label rather than a control**, which is ``HWCategoryRowLabel``'s split and here for the same reason: the
/// month detail is a *pushed page* (#22), so the row is drawn inside a `NavigationLink` that supplies its own
/// button — and a `Button` nested in a link is two controls for one row. The caller combines it into one
/// accessibility element and adds the hint, exactly as `ExpensesView` does for a category.
///
/// **The chevron arrives with the destination**, which is why it is a parameter rather than always drawn: #21
/// shipped this row with nowhere to go, and a chevron pointing at an unwritten screen is a promise in a smaller
/// font. #22 wrote the page, so the flag is on and the hint copy that describes the tap arrives with the tap.
struct HWMonthRowLabel: View {
    @Environment(ThemeManager.self) private var theme

    /// Read to decide where the verdict badge sits — see ``content``. **Not a clamp**: this reads the size to
    /// choose a *layout*, which is what ADR-0012 asks for.
    @Environment(\.dynamicTypeSize) private var size

    /// `.m-name` — "February".
    let name: String
    /// `.m-name em` — "2026", the group's own year, printed beside the month as the design prints it.
    let year: String
    /// `.m-spent` — "Spent ₹53,170", composed by the screen from catalogue copy and the server's figure.
    ///
    /// The design bolds the figure inside the sentence. That emphasis is dropped rather than converted: markdown
    /// inside app copy is a second thing the translation has to carry correctly, and it buys a half-shade of
    /// weight on a line that is already the row's quietest.
    let spent: Text
    let verdict: HWVerdictTint
    /// "91% of goal" — the badge's text, server-formatted.
    let percentageLabel: String
    /// `.m-bar` — the month's shape. Empty for a month with nothing logged.
    let segments: [HWProportionBar.Segment]

    /// `.m-chev` — whether the row is drawn as something that opens. The control itself is whatever wraps it.
    var showsChevron: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            // **The badge moves below the month above the threshold.** Sharing one line with it left the name
            // about 130pt at AX3, and `March` came back as `Marc` / `h` — a word broken mid-way, which neither
            // shrinking nor truncating may fix (ADR-0012). Reading the size to choose a *layout* is what
            // `HWSpendSummary`'s chips do for the same reason.
            if size.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 11) {
                        when
                        if showsChevron {
                            chevron
                        }
                    }

                    HWVerdictBadge(verdict: verdict, label: percentageLabel)
                }
            } else {
                HStack(alignment: .center, spacing: 11) {
                    when

                    HWVerdictBadge(verdict: verdict, label: percentageLabel)

                    if showsChevron {
                        chevron
                    }
                }
            }

            if !segments.isEmpty {
                HWProportionBar(segments: segments)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 15)
        .padding(.top, 14)
        .padding(.bottom, 13)
        .hwBox(
            fill: theme.palette.surface.raised,
            radius: .extraLarge,
            border: theme.palette.surface.separator,
            elevation: .small
        )
        // **The hit region.** Without it the row draws and cannot be pressed, whether the control around it is a
        // button or a link (ADR-0032).
        .contentShape(.rect)
    }

    /// `.m-when` — the month, its year, and what it cost.
    private var when: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(verbatim: name)
                    .font(.hw(.bodyLarge).weight(.heavy))
                    .foregroundStyle(theme.palette.surface.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text(verbatim: year)
                    .font(.hw(.caption).weight(.semibold))
                    .foregroundStyle(theme.palette.surface.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            spent
                .font(.hw(.caption))
                .foregroundStyle(theme.palette.surface.inkSecondary)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// `.m-chev` — the tinted tile with the forward chevron in it.
    ///
    /// `chevron.forward` rather than `chevron.right`: the glyph mirrors under RTL and the named direction would
    /// not (ADR-0011).
    ///
    /// Hidden from VoiceOver, because the control around the row already carries the button trait.
    private var chevron: some View {
        Image(systemName: "chevron.forward")
            .font(.hw(.caption).weight(.bold))
            .foregroundStyle(theme.palette.accent.base)
            .frame(width: 26, height: 26)
            .hwBox(fill: theme.palette.surface.backgroundSecondary, radius: .hairline)
            // The chevron says "this opens", which the button trait already says.
            .accessibilityHidden(true)
    }
}

/// The design's `.m-bar` — a month's shape as stripes of the six category colours, in proportion.
///
/// **Drawn at every size, and hidden from VoiceOver**, which is the one visualisation in the app that is neither
/// clamped nor replaced (ADR-0012). The clamp pattern exists for fixed-layout figures — a donut's centre readout,
/// a meter's pin and pill, a week strip's seven labels — that break when the type grows. There is no type in
/// here: it is 7pt of colour with no label, no axis, and no legend, so there is nothing to grow and nothing to
/// overlap. Its replacement would be itself.
///
/// The design gives it no `aria-label` and no `role`, which is the same judgement: the row it sits in already
/// says the month, the figure, and the verdict in words.
struct HWProportionBar: View {
    @Environment(ThemeManager.self) private var theme

    /// One stripe: which category colour slot, and its share of the width.
    struct Segment: Identifiable, Sendable, Hashable {
        /// `1...6`, from the payload. A **slot**, so the later dark-mode swap stays a swap (ADR-0001).
        let slot: Int
        /// `0...1`, from the server — the design divides a category's total by the month's.
        let width: Double

        var id: Int { slot }
    }

    let segments: [Segment]

    /// `.m-bar{height:7px;gap:2px}`.
    private static let height: CGFloat = 7
    private static let spacing: CGFloat = 2

    var body: some View {
        // `GeometryReader`, because a stripe's width is a fraction of a width only the layout knows — the same
        // reason the savings meter needs one for its pin.
        GeometryReader { proxy in
            HStack(spacing: Self.spacing) {
                ForEach(segments) { segment in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(colour(for: segment))
                        .frame(width: width(of: segment, in: proxy.size.width))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: Self.height)
        .accessibilityHidden(true)
    }

    /// The stripe's own width, with the gaps between stripes taken off the total first — otherwise six stripes
    /// summing to 1 plus five 2pt gaps is ten points wider than the row.
    private func width(of segment: Segment, in total: CGFloat) -> CGFloat {
        let gaps = Self.spacing * CGFloat(max(segments.count - 1, 0))
        return max(0, (total - gaps) * min(max(segment.width, 0), 1))
    }

    /// The six category colour slots, by palette role. A slot outside the range wraps rather than crashing: the
    /// number arrives from a payload, and a seventh category is a server change, not a client crash — the same
    /// rule ``HWDonut`` applies to its slices.
    private func colour(for segment: Segment) -> Color {
        let palette = theme.palette.categories.all
        guard !palette.isEmpty else { return theme.palette.accent.base }
        return palette[(max(segment.slot, 1) - 1) % palette.count]
    }
}

#if DEBUG
private let previewSegments: [HWProportionBar.Segment] = [
    .init(slot: 1, width: 0.408), .init(slot: 2, width: 0.26), .init(slot: 3, width: 0.069),
    .init(slot: 4, width: 0.158), .init(slot: 5, width: 0.052), .init(slot: 6, width: 0.053),
]

@MainActor
private func previewRows(showsChevron: Bool) -> some View {
    VStack(spacing: 10) {
        HWMonthRowLabel(
            name: "July", year: "2026", spent: Text(verbatim: "Spent ₹62,030"),
            verdict: .miss, percentageLabel: "69% of goal", segments: previewSegments,
            showsChevron: showsChevron
        )
        HWMonthRowLabel(
            name: "June", year: "2026", spent: Text(verbatim: "Spent ₹55,640"),
            verdict: .hit, percentageLabel: "172% of goal", segments: previewSegments,
            showsChevron: showsChevron
        )
        HWMonthRowLabel(
            name: "January", year: "2026", spent: Text(verbatim: "Spent ₹0"),
            verdict: .miss, percentageLabel: "0% of goal", segments: [],
            showsChevron: showsChevron
        )
    }
}

#Preview("Archive rows — as the archive draws them, inside a link") {
    VStack(spacing: 14) {
        HWYearHeader(year: "2026", saved: Text(verbatim: "₹76,700 saved"))
        previewRows(showsChevron: true)
    }
    .padding()
    .background(HWPreviewGround())
    .hwTheme()
}

#Preview("Archive rows — without the chevron, which is what #21 shipped") {
    previewRows(showsChevron: false)
        .padding()
        .background(HWPreviewGround())
        .hwTheme()
}

#Preview("The hero — with something standing in for the chart") {
    HWArchiveHero(
        caption: "How close you got to your savings goal",
        subtitle: Text(verbatim: "Goal met in 2 of 6 months · the dashed line is the goal"),
        splits: [.init("Months", "6"), .init("Avg. spend", "₹57,050"), .init("Total saved", "₹76,700")]
    ) {
        HWProportionBar(segments: previewSegments)
    }
    .padding()
    .background(HWPreviewGround())
    .hwTheme()
}

#Preview("AX3 — the rows grow and the chips stack") {
    ScrollView {
        VStack(spacing: 14) {
            HWYearHeader(year: "2026", saved: Text(verbatim: "₹76,700 saved"))
            previewRows(showsChevron: true)
        }
        .padding()
    }
    .dynamicTypeSize(.accessibility3)
    .background(HWPreviewGround())
    .hwTheme()
}

#Preview("RTL — the chevron and the stripes mirror") {
    VStack(spacing: 14) {
        HWYearHeader(year: "2026", saved: Text(verbatim: "₹76,700 saved"))
        previewRows(showsChevron: true)
    }
    .padding()
    .environment(\.layoutDirection, .rightToLeft)
    .background(HWPreviewGround())
    .hwTheme()
}
#endif
