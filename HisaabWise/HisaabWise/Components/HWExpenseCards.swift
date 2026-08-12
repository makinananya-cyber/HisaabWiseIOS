import SwiftUI

/// The design's `.summary` — the galaxy card Expenses opens with: what was spent, the three-way split, and room
/// for the wants bar underneath.
///
/// **A brand-coloured card on a surface screen**, which is not a contradiction and is worth naming: ADR-0021's
/// two appearances are two *surfaces*, and the design paints a galaxy gradient panel on the light ground here
/// exactly as it paints a milky wordmark tile on the dark one. So every role inside is a `brand` role while the
/// card sits on `surface`. That is why this is its own component rather than ``HWCard`` with a fill argument: a
/// card that took a ground would leave every caller to work out which ink went with it.
///
/// The trailing slot holds ``HWBudgetBar``. A `ViewBuilder` rather than the bar's own arguments, for the reason
/// `HWTopBar` gives for its trailing slot: it holds a *control-shaped thing*, and a card that took one as data
/// would be picking which.
struct HWSpendSummary<Footer: View>: View {
    @Environment(ThemeManager.self) private var theme

    /// One `.chip` — a figure over a caption.
    ///
    /// The chip itself is ``HWFigureChips``, because Reports' `.hero-split` is the same three-up row of the same
    /// class (#21) and a second private copy of it here is the duplication `Components.swift` warns about. The
    /// name stays as an alias so a caller says `HWSpendSummary.Split` about a summary's own chips.
    typealias Split = HWFigureChips.Split

    /// `.sum-cap` — "Spent this month".
    private let caption: LocalizedStringResource
    /// `.sum-num` with its `.sum-cur` — one display string, symbol included.
    ///
    /// The design prints the symbol and the digits as two elements so it can animate the number alone. One
    /// string here, because `Money.display` is one string and splitting it would mean the client deciding where
    /// a symbol ends — which under Arabic, and for a multi-letter code like `AED`, is a decision it would get
    /// wrong (ADR-0003).
    private let total: String
    private let splits: [Split]
    private let footer: Footer

    init(
        caption: LocalizedStringResource,
        total: String,
        splits: [Split],
        @ViewBuilder footer: () -> Footer
    ) {
        self.caption = caption
        self.total = total
        self.splits = splits
        self.footer = footer()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(caption)
                .hwEyebrow(.brand)
                .fixedSize(horizontal: false, vertical: true)

            Text(verbatim: total)
                .font(.hw(.display))
                .foregroundStyle(theme.palette.brand.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
                // The figure is a *value* of the caption above it, so a reload re-announces the number rather
                // than the words (ADR-0012).
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(caption))
                .accessibilityValue(Text(verbatim: total))

            HWFigureChips(splits)
                .padding(.top, 16)

            footer
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 18)
        .hwBox(fill: ground, radius: .extraLarge, elevation: .large)
        .accessibilityElement(children: .contain)
    }

    /// `background:linear-gradient(145deg,var(--galaxy),#123273 55%,var(--planetary))`.
    ///
    /// **Three stops become two**, the way the brand primary button's do: the middle one is a shade of galaxy
    /// used only for depth, and it has no palette role because nothing else in the design asks for it. The wash
    /// between the two ends is what the card is; the intermediate stop is not information.
    private var ground: LinearGradient {
        LinearGradient(
            colors: [theme.palette.brand.background, theme.palette.accent.base],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

extension HWSpendSummary where Footer == EmptyView {
    /// A summary card with nothing under the chips — the shape a screen without a budget bar would use.
    init(caption: LocalizedStringResource, total: String, splits: [Split]) {
        self.init(caption: caption, total: total, splits: splits) { EmptyView() }
    }
}

/// The design's `.cat` — one category row's **contents**, without a control around them.
///
/// Distinct from ``HWRow`` in the two ways the design distinguishes them, and that is why it is its own entry
/// rather than an argument on that one: the **income** variant inverts the tile to the galaxy fill and takes the
/// accent for its figure, and the figure is a *total* rather than a settings value, so it takes the ink weight
/// the design gives a number rather than the accent it gives a choice.
///
/// Split into a label and a button for the reason ``HWReadRowLabel`` is: Expenses draws these inside a
/// `NavigationLink`, which supplies its own button, and a `Button` nested in a link is two controls for one row.
/// The lesson ADR-0032 recorded — that the first attempt at avoiding that turned the label's hit-testing off and
/// made every row untappable — is why the *label* carries the `contentShape` and the control is whatever wraps it.
struct HWCategoryRowLabel: View {
    @Environment(ThemeManager.self) private var theme

    let name: String
    /// `.cat-sub` — "Add each shop as you go". Server content.
    let hint: String
    /// `.cat-amt` — the running total, **server-formatted and already signed** where money is coming in
    /// (ADR-0003): the design's own `(c.income ? '+' : '')` puts the sign on the wrong side of an Arabic string.
    let total: String
    let systemImage: String
    /// `.cat--income` — money in rather than out, which inverts the tile.
    var isIncoming: Bool = false

    var body: some View {
        HStack(spacing: 11) {
            tile

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: name)
                    .font(.hw(.bodyLarge).weight(.bold))
                    .foregroundStyle(theme.palette.surface.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text(verbatim: hint)
                    .font(.hw(.caption))
                    .foregroundStyle(theme.palette.surface.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(verbatim: total)
                .font(.hw(.bodyLarge).weight(.heavy))
                .foregroundStyle(isIncoming ? theme.palette.accent.base : theme.palette.surface.ink)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)

            // `chevron.forward` rather than `chevron.right`: the glyph mirrors and the named direction would not.
            Image(systemName: "chevron.forward")
                .font(.hw(.micro).weight(.bold))
                .foregroundStyle(theme.palette.accent.muted)
                // The chevron says "this opens", which the control's own trait already says.
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        .frame(minHeight: HWTouchTarget.minimum)
        .hwBox(fill: theme.palette.surface.raised, radius: .large, elevation: .small)
        // **The hit region.** Without it the row draws and cannot be pressed, whether the control around it is a
        // button or a link (ADR-0032).
        .contentShape(.rect)
    }

    /// `.cat-ico{background:var(--tint)}`, and `.cat--income .cat-ico{background:var(--galaxy);color:var(--sky)}`.
    private var tile: some View {
        Image(systemName: systemImage)
            .font(.hw(.subheading))
            .foregroundStyle(isIncoming ? theme.palette.accent.soft : theme.palette.accent.base)
            .frame(width: 40, height: 40)
            .hwBox(
                fill: isIncoming ? theme.palette.accent.deep : theme.palette.accent.tint,
                radius: .medium
            )
            .accessibilityHidden(true)
    }
}

/// One category row as a **button**, for a caller that is not already a link.
struct HWCategoryRow: View {
    private let label: HWCategoryRowLabel
    private let action: () -> Void

    init(
        name: String,
        hint: String,
        total: String,
        systemImage: String,
        isIncoming: Bool = false,
        action: @escaping () -> Void
    ) {
        label = HWCategoryRowLabel(
            name: name,
            hint: hint,
            total: total,
            systemImage: systemImage,
            isIncoming: isIncoming
        )
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            label
        }
        .buttonStyle(HWPressStyle())
        // The name labels it, the total is its value, and the hint is the third thing — three separate swipes for
        // one row is the focus-order failure ADR-0012 is about.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: label.name))
        .accessibilityValue(Text(verbatim: label.total))
        .accessibilityHint(Text(verbatim: label.hint))
    }
}

/// The design's `.hero` — the card at the top of a category's detail page.
///
/// The same three facts as the row that opened it, at the size of a page heading: the glyph, the name over its
/// hint, and the running total with the month under it. It is **not** a control — the row was; this is where the
/// row went — so it carries the heading trait rather than a button one.
struct HWCategoryHero: View {
    @Environment(ThemeManager.self) private var theme

    private let name: String
    private let hint: String
    private let total: String
    /// `.hero-amt small` — "August". The month the figure belongs to, which is the one thing the row did not say.
    private let monthLabel: String
    private let systemImage: String
    private let isIncoming: Bool

    init(
        name: String,
        hint: String,
        total: String,
        monthLabel: String,
        systemImage: String,
        isIncoming: Bool = false
    ) {
        self.name = name
        self.hint = hint
        self.total = total
        self.monthLabel = monthLabel
        self.systemImage = systemImage
        self.isIncoming = isIncoming
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.hw(.heading))
                .foregroundStyle(isIncoming ? theme.palette.accent.soft : theme.palette.accent.base)
                .frame(width: 52, height: 52)
                .hwBox(
                    fill: isIncoming ? theme.palette.accent.deep : theme.palette.accent.tint,
                    radius: .large
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: name)
                    .font(.hw(.subheading))
                    .foregroundStyle(theme.palette.surface.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text(verbatim: hint)
                    .font(.hw(.caption))
                    .foregroundStyle(theme.palette.surface.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 2) {
                Text(verbatim: total)
                    .font(.hw(.subheading))
                    .foregroundStyle(isIncoming ? theme.palette.accent.base : theme.palette.surface.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text(verbatim: monthLabel)
                    .hwLabel()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .hwBox(
            fill: theme.palette.surface.raised,
            radius: .extraLarge,
            border: theme.palette.surface.separator,
            elevation: .medium
        )
        // One element, read as "Transport, ₹440, August" — and a **header**, because this is what the pushed
        // page is called.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: name))
        .accessibilityValue(Text(verbatim: total))
        .accessibilityHint(Text(verbatim: hint))
        .accessibilityAddTraits(.isHeader)
    }
}

#if DEBUG
#Preview("The summary card, with its budget bar") {
    HWSpendSummary(
        caption: "Spent this month",
        total: "₹5,539",
        splits: [
            .init("Fixed", "₹3,529"),
            .init("Variable", "₹2,010"),
            .init("Income", "₹900"),
        ]
    ) {
        HWBudgetBar(
            caption: "Wants budget",
            amount: Text(verbatim: "₹1,150 of ₹19,770"),
            percentageLabel: "6%",
            fill: 0.06,
            isOver: false,
            accessibilityDescription: Text(verbatim: "₹1,150 of ₹19,770, 6%")
        )
    }
    .padding(18)
    .background(HWPreviewGround())
    .hwTheme()
}

#Preview("Category rows and a hero") {
    ScrollView {
        VStack(spacing: 8) {
            HWCategoryRow(
                name: "Groceries",
                hint: "Add each shop as you go",
                total: "₹860",
                systemImage: "basket"
            ) {}
            HWCategoryRow(
                name: "Additional Income",
                hint: "Money coming in",
                total: "+₹900",
                systemImage: "arrow.down.to.line",
                isIncoming: true
            ) {}
            HWCategoryRow(
                name: "Rent",
                hint: "Fixed each month",
                total: "₹3,000",
                systemImage: "house"
            ) {}

            HWCategoryHero(
                name: "Commute",
                hint: "Pick how you travelled",
                total: "₹440",
                monthLabel: "August",
                systemImage: "bus"
            )
            .padding(.top, 14)
        }
        .padding(18)
    }
    .background(HWPreviewGround())
    .hwTheme()
}

#Preview("AX3 — the chips level up and every row grows") {
    ScrollView {
        VStack(spacing: 14) {
            HWSpendSummary(
                caption: "Spent this month",
                total: "₹5,539",
                splits: [.init("Fixed", "₹3,529"), .init("Variable", "₹2,010"), .init("Income", "₹900")]
            )
            HWCategoryRow(
                name: "Additional Income",
                hint: "Money coming in",
                total: "+₹900",
                systemImage: "arrow.down.to.line",
                isIncoming: true
            ) {}
            HWCategoryHero(
                name: "Utilities",
                hint: "Fixed each month",
                total: "₹529",
                monthLabel: "August",
                systemImage: "bolt"
            )
        }
        .padding(18)
    }
    .dynamicTypeSize(.accessibility3)
    .background(HWPreviewGround())
    .hwTheme()
}

// Latin digits under `ar` — ADR-0011's decision, matching the server's own formatting.
#Preview("RTL — the tiles lead on the right and the chevrons mirror") {
    VStack(spacing: 14) {
        HWSpendSummary(
            caption: "المصروف هذا الشهر",
            total: "₹5,539",
            splits: [.init("Fixed", "₹3,529"), .init("Variable", "₹2,010"), .init("Income", "₹900")]
        )
        HWCategoryRow(
            name: "البقالة",
            hint: "أضف كل تسوق أولاً بأول",
            total: "₹860",
            systemImage: "basket"
        ) {}
        HWCategoryHero(
            name: "الإيجار",
            hint: "ثابت كل شهر",
            total: "₹3,000",
            monthLabel: "أغسطس",
            systemImage: "house"
        )
    }
    .padding(18)
    .environment(\.layoutDirection, .rightToLeft)
    .background(HWPreviewGround())
    .hwTheme()
}
#endif
