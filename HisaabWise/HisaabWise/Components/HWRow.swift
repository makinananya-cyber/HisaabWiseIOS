import SwiftUI

/// The design's `.row` — an icon, a name, an optional subtitle, an optional value, and a chevron.
///
/// Account's settings list is made of these, and so is every list of things a tap opens. The shape is
/// fixed by the CSS: `.row-ico` in a tinted square, `.row-txt` stacking `.row-name` over `.row-sub`,
/// `.row-val` at the trailing edge, `.row-chev` last. Each of those is optional here because each is
/// optional there — Account draws rows with a value and rows without one.
struct HWRow: View {
    @Environment(ThemeManager.self) private var theme

    private let systemImage: String
    private let name: Text
    private let subtitle: Text?
    private let value: Text?
    /// `.row-chev`, which the design omits on a row that acts rather than navigates.
    private let showsDisclosure: Bool
    private let action: () -> Void

    init(
        systemImage: String,
        name: Text,
        subtitle: Text? = nil,
        value: Text? = nil,
        showsDisclosure: Bool = true,
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.name = name
        self.subtitle = subtitle
        self.value = value
        self.showsDisclosure = showsDisclosure
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                icon

                VStack(alignment: .leading, spacing: 2) {
                    name
                        .font(.hw(.bodyLarge).weight(.bold))
                        .foregroundStyle(theme.palette.surface.ink)
                    if let subtitle {
                        subtitle
                            .font(.hw(.caption))
                            .foregroundStyle(theme.palette.surface.inkTertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let value {
                    value
                        .font(.hw(.body).weight(.bold))
                        .foregroundStyle(theme.palette.accent.base)
                        .multilineTextAlignment(.trailing)
                        // Wraps onto a second line rather than truncating at accessibility sizes.
                        .fixedSize(horizontal: false, vertical: true)
                }

                if showsDisclosure {
                    // `chevron.forward` rather than `chevron.right`: the glyph mirrors under RTL and the
                    // named direction would not.
                    Image(systemName: "chevron.forward")
                        .font(.hw(.caption))
                        .foregroundStyle(theme.palette.accent.muted)
                        // The chevron says "this opens", which the button trait already says.
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 12)
            .frame(minHeight: HWTouchTarget.minimum)
            .hwBox(fill: theme.palette.surface.raised, radius: .large, elevation: .small)
            .contentShape(.rect)
        }
        .buttonStyle(HWPressStyle())
        // Name, then subtitle, then value, as one element — three separate swipes for one row is the
        // focus-order failure ADR-0012 is about.
        .accessibilityElement(children: .combine)
    }

    /// `.row-ico{background:var(--tint);color:var(--planetary)}`
    private var icon: some View {
        Image(systemName: systemImage)
            .font(.hw(.subheading))
            .foregroundStyle(theme.palette.accent.base)
            .frame(width: 40, height: 40)
            .hwBox(fill: theme.palette.accent.tint, radius: .small)
            .accessibilityHidden(true)
    }
}

/// The design's `.key-row` — a colour dot, a name, and a share.
///
/// The donut's legend, and the same shape wherever a category is named beside its slice. Distinct from
/// ``HWRow`` in the two ways that matter: it carries a **colour slot** rather than a glyph, and its
/// trailing figure is a percentage the server computed rather than a value the row derived (ADR-0020).
///
/// Always tappable, because `.key-row` is a `<button>` in the design — tapping one isolates its wedge in
/// the donut. The dot is decorative to VoiceOver on purpose: a colour is not information a screen reader
/// can use, so the name and the share carry the row.
struct HWKeyRow: View {
    @Environment(ThemeManager.self) private var theme

    private let colour: Color
    private let name: Text
    private let share: Text
    /// `.key-row.on` — the isolated wedge.
    private let isSelected: Bool
    private let action: () -> Void

    init(
        colour: Color,
        name: Text,
        share: Text,
        isSelected: Bool = false,
        action: @escaping () -> Void
    ) {
        self.colour = colour
        self.name = name
        self.share = share
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: HWRadius.hairline.points)
                    .fill(colour)
                    .frame(width: 9, height: 9)
                    .accessibilityHidden(true)

                name
                    .font(.hw(.caption))
                    .foregroundStyle(theme.palette.surface.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)

                share
                    .font(.hw(.caption).weight(.heavy))
                    .foregroundStyle(theme.palette.surface.inkSecondary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            // The design draws these ~24pt tall, which is the tightest thing in it that is also tappable.
            // Six of them at 44 is a taller legend than the design's, and the alternative — a tap target
            // that fails the per-screen Accessibility Inspector gate — is not a trade ADR-0012 allows.
            // Home's layout absorbs it; the accessibility-size alternative layout is issue #8's.
            .frame(minHeight: HWTouchTarget.minimum)
            .hwBox(
                // `.key-row.on{background:var(--bg-2)}`, and nothing at all when it is not isolated.
                fill: isSelected ? theme.palette.surface.backgroundSecondary : Color.clear,
                radius: .small
            )
            .contentShape(.rect)
        }
        .buttonStyle(HWPressStyle.compact)
        .accessibilityElement(children: .combine)
        .hwSelectionTraits(isSelected: isSelected)
    }
}

#if DEBUG
#Preview("Rows — every combination of the optional slots") {
    ScrollView {
        VStack(spacing: 8) {
            HWRow(
                systemImage: "globe",
                name: Text(verbatim: "Language"),
                subtitle: Text(verbatim: "Used across the app"),
                value: Text(verbatim: "English")
            ) {}
            HWRow(systemImage: "banknote", name: Text(verbatim: "Currency"), value: Text(verbatim: "AED")) {}
            HWRow(systemImage: "lock", name: Text(verbatim: "Change password")) {}
            HWRow(
                systemImage: "arrow.down.doc",
                name: Text(verbatim: "Download the curriculum"),
                showsDisclosure: false
            ) {}
        }
        .padding()
    }
    .background(HWPreviewGround())
    .hwTheme()
}

#Preview("Key rows — the donut's legend") {
    let palette = HWPalette.standard

    VStack(spacing: 1) {
        HWKeyRow(
            colour: palette.categories.rent,
            name: Text(verbatim: "Rent"),
            share: Text(verbatim: "38%"),
            isSelected: true
        ) {}
        HWKeyRow(
            colour: palette.categories.groceries,
            name: Text(verbatim: "Groceries"),
            share: Text(verbatim: "21%")
        ) {}
        HWKeyRow(
            colour: palette.categories.transport,
            // "Commute" rather than the category's own name: `LayeringTests` scans this layer for
            // `Transport`, and a preview string should not be what trips it.
            name: Text(verbatim: "Commute"),
            share: Text(verbatim: "14%")
        ) {}
    }
    .padding()
    .background(HWPreviewGround())
    .hwTheme()
}

#Preview("AX3 — rows grow and the value wraps") {
    VStack(spacing: 8) {
        HWRow(
            systemImage: "globe",
            name: Text(verbatim: "Language"),
            subtitle: Text(verbatim: "Used across the app"),
            value: Text(verbatim: "English")
        ) {}
        HWKeyRow(
            colour: HWPalette.standard.categories.rent,
            name: Text(verbatim: "Rent"),
            share: Text(verbatim: "38%")
        ) {}
    }
    .padding()
    .dynamicTypeSize(.accessibility3)
    .background(HWPreviewGround())
    .hwTheme()
}

// Latin digits under `ar` — ADR-0011's decision, matching the server's own formatting.
#Preview("RTL — the chevron points the other way") {
    VStack(spacing: 8) {
        HWRow(
            systemImage: "globe",
            name: Text(verbatim: "اللغة"),
            subtitle: Text(verbatim: "في كل التطبيق"),
            value: Text(verbatim: "العربية")
        ) {}
        HWKeyRow(
            colour: HWPalette.standard.categories.rent,
            name: Text(verbatim: "الإيجار"),
            share: Text(verbatim: "38%")
        ) {}
    }
    .padding()
    .environment(\.layoutDirection, .rightToLeft)
    .background(HWPreviewGround())
    .hwTheme()
}
#endif
