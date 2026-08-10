import SwiftUI

/// The chrome every sheet in the app wears.
///
/// The design's sheets are identical above the content — `.grab`, then `.sheet-head` holding a
/// `.sheet-title` and a `.sheet-x` — and the body below is always the same scrolling list. So the chrome is
/// one component and only the *rows* are the caller's.
///
/// It paints the panel's ground and nothing around it: presentation is `.sheet { }` on the screen, so
/// SwiftUI owns the scrim, the corner radius, and the drag-to-dismiss. Duplicating those here would be a
/// second sheet implementation competing with the system's.
///
/// Accessibility comes with it: the title is a heading, the close button carries the one piece of copy the
/// component owns, and the content is a container so focus order is title → close → list (ADR-0012).
struct HWSheetChrome<Content: View>: View {
    @Environment(ThemeManager.self) private var theme

    private let title: LocalizedStringResource
    /// `nil` where the screen offers no explicit close — the drag still dismisses.
    private let onClose: (() -> Void)?
    private let content: Content

    init(
        title: LocalizedStringResource,
        onClose: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.onClose = onClose
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            grabber

            HStack(spacing: 10) {
                Text(title)
                    .font(.hw(.subheading))
                    .foregroundStyle(theme.palette.surface.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)

                if let onClose {
                    HWIconButton(HWComponentCopy.closeSheet, systemImage: "xmark", action: onClose)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 12)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(theme.palette.surface.background.ignoresSafeArea())
        .accessibilityElement(children: .contain)
    }

    /// `.grab{width:40px;height:4px;background:var(--line-2)}` — decorative, and hidden from VoiceOver
    /// because the sheet's own dismiss gesture is what it hints at.
    private var grabber: some View {
        RoundedRectangle(cornerRadius: HWRadius.hairline.points)
            .fill(theme.palette.surface.separatorStrong)
            .frame(width: 40, height: 4)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .accessibilityHidden(true)
    }
}

/// The design's `.sheet-list` / `.optlist` / `.opts` — the scrolling body of a sheet.
///
/// Three CSS classes, one shape: a scrolling list inset from the panel's edges, with the rows spaced by a
/// few points. It is here rather than left to the caller because the alternative is every sheet picking its
/// own inset, which is the divergence the whole layer exists to prevent.
///
/// `.overscroll-behavior:contain` becomes `scrollBounceBehavior(.basedOnSize)`: a short list does not
/// rubber-band, and a long one does.
struct HWSheetList<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 4) {
                content
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

/// What a sheet row carries before its name.
///
/// The design puts exactly one of two things there — a code (`.srow-iso`, `.opt-chip`) or a glyph
/// (`.opt-ico`) — never both and never neither in the same list. An enum says that; two optional strings
/// would leave "both at once" representable and make each caller's intent a guess.
enum HWSheetRowLeading: Sendable, Equatable {
    /// `.srow-iso` / `.opt-chip` — a currency code, an ISO code, a symbol.
    case code(String)
    /// `.opt-ico` — a glyph in a card-coloured square, as the category picker draws it.
    case symbol(String)
}

/// One row inside a sheet — the design's `.srow` and `.opt`, which are the same shape.
///
/// An optional leading code or glyph, a name, an optional trailing meta line, and the `.opt-tick` that
/// marks the current choice. Selection is drawn *and* announced: the sky wash alone is invisible to
/// VoiceOver, so the trait carries it (ADR-0012).
struct HWSheetRow: View {
    @Environment(ThemeManager.self) private var theme

    private let name: Text
    private let leading: HWSheetRowLeading?
    /// `.srow-code` / `.opt-meta` — the dial code, the symbol, the count.
    private let meta: Text?
    private let isSelected: Bool
    private let action: () -> Void

    init(
        name: Text,
        leading: HWSheetRowLeading? = nil,
        meta: Text? = nil,
        isSelected: Bool = false,
        action: @escaping () -> Void
    ) {
        self.name = name
        self.leading = leading
        self.meta = meta
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let leading {
                    switch leading {
                    case .code(let code):
                        HWCodeChip(code)
                    case .symbol(let systemImage):
                        Image(systemName: systemImage)
                            .font(.hw(.bodyLarge))
                            .foregroundStyle(theme.palette.accent.base)
                            .frame(width: 34, height: 34)
                            .hwBox(fill: theme.palette.surface.raised, radius: .small)
                            .accessibilityHidden(true)
                    }
                }

                name
                    .font(.hw(.bodyLarge).weight(.semibold))
                    .foregroundStyle(theme.palette.surface.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let meta {
                    meta
                        .font(.hw(.body).weight(.bold))
                        .foregroundStyle(theme.palette.surface.inkTertiary)
                }

                // Held in place rather than inserted, so picking a row does not reflow the list.
                Image(systemName: "checkmark")
                    .font(.hw(.caption).weight(.heavy))
                    .foregroundStyle(theme.palette.accent.base)
                    .opacity(isSelected ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 12)
            .frame(minHeight: HWTouchTarget.minimum)
            .hwBox(
                // `.srow.sel{background:var(--sky)}`, and nothing at all when it is not the choice.
                fill: isSelected ? theme.palette.accent.soft : Color.clear,
                radius: .medium
            )
            .contentShape(.rect)
        }
        .buttonStyle(HWPressStyle.compact)
        .accessibilityElement(children: .combine)
        .hwSelectionTraits(isSelected: isSelected)
    }
}

#if DEBUG
#Preview("Sheet chrome — with a close button and a list") {
    HWSheetChrome(title: "Choose a currency", onClose: {}) {
        HWSheetList {
            HWSheetRow(
                name: Text(verbatim: "UAE Dirham"),
                leading: .code("AED"),
                meta: Text(verbatim: "د.إ"),
                isSelected: true
            ) {}
            HWSheetRow(
                name: Text(verbatim: "Indian Rupee"),
                leading: .code("INR"),
                meta: Text(verbatim: "₹")
            ) {}
            HWSheetRow(
                name: Text(verbatim: "Philippine Peso"),
                leading: .code("PHP"),
                meta: Text(verbatim: "₱")
            ) {}
        }
    }
    .hwTheme()
}

#Preview("Sheet chrome — no close button, glyph rows, a bare row") {
    HWSheetChrome(title: "Category") {
        HWSheetList {
            HWSheetRow(name: Text(verbatim: "Groceries"), leading: .symbol("cart"), isSelected: true) {}
            HWSheetRow(name: Text(verbatim: "Commute"), leading: .symbol("bus")) {}
            HWSheetRow(name: Text(verbatim: "Something else")) {}
        }
    }
    .hwTheme()
}

#Preview("AX3 — the header and the rows grow") {
    HWSheetChrome(title: "Choose a currency", onClose: {}) {
        HWSheetList {
            HWSheetRow(name: Text(verbatim: "UAE Dirham"), leading: .code("AED"), isSelected: true) {}
            HWSheetRow(name: Text(verbatim: "Indian Rupee"), leading: .code("INR")) {}
        }
    }
    .dynamicTypeSize(.accessibility3)
    .hwTheme()
}

#Preview("RTL — the close button leads on the left") {
    HWSheetChrome(title: "اختر العملة", onClose: {}) {
        HWSheetList {
            HWSheetRow(name: Text(verbatim: "درهم إماراتي"), leading: .code("AED"), isSelected: true) {}
            HWSheetRow(name: Text(verbatim: "روبية هندية"), leading: .code("INR")) {}
        }
    }
    .environment(\.layoutDirection, .rightToLeft)
    .hwTheme()
}
#endif
