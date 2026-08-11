import SwiftUI

/// The design's `.field-box.combo` — a field-shaped **button** that opens a picker.
///
/// It looks like ``HWTextField`` and is not one: nothing can be typed into it, because what it holds is a choice
/// from a server-served list. The shape is shared deliberately — a currency and a salary sit next to each other
/// on the same form, and two different boxes would read as two different kinds of thing.
///
/// **The caption sits in a different place on each surface, and the design puts it there.** On `brand` it is
/// `.combo-cap`, *inside* the box above the value: registration's form has no separate field labels, so the box
/// has to say what it is before and after a choice is made. On `surface` the design's field is `.fld` — a
/// `.fld-lab` **above** a plain `.ctrl` holding only the value — which is what ``HWTextField`` already draws
/// there, and Expenses puts the two side by side inside one card. A combo that captioned itself in that card
/// would be the one control whose label was somewhere else.
///
/// So the appearance selects a layout as well as a palette, which is unusual enough to say out loud: it is the
/// second caller (#18) settling a question one caller could only have guessed at.
struct HWCombo: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// `.combo-cap` — "Currency", "Question 1".
    private let caption: LocalizedStringResource
    /// `.combo-val` — the chosen value. `nil` is the design's `.combo-val.ph` state, drawn as the placeholder.
    ///
    /// A `Text` rather than a string because a currency's name comes from server content while a placeholder is
    /// app copy, and the caller is the only thing that knows which it is holding (ADR-0020).
    private let value: Text?
    private let placeholder: LocalizedStringResource
    private let systemImage: String?
    /// `.combo-sym` — the tinted chip at the trailing edge, holding a currency symbol. `nil` draws none.
    private let badge: String?
    /// `.field.bad` — the border turns danger and the message appears below.
    private let error: LocalizedStringResource?
    /// Which of the design's two surfaces this sits on (ADR-0021), and — unusually — which of its two layouts.
    private let appearance: HWAppearance
    /// `.ctrl.open` — the sheet this opens is on screen, which the design marks by lighting the border and
    /// rotating the chevron. `aria-expanded` in the design, so it is announced rather than only drawn.
    private let isOpen: Bool
    private let action: () -> Void

    init(
        _ caption: LocalizedStringResource,
        value: Text?,
        placeholder: LocalizedStringResource,
        systemImage: String? = nil,
        badge: String? = nil,
        error: LocalizedStringResource? = nil,
        appearance: HWAppearance = .surface,
        isOpen: Bool = false,
        action: @escaping () -> Void
    ) {
        self.caption = caption
        self.value = value
        self.placeholder = placeholder
        self.systemImage = systemImage
        self.badge = badge
        self.error = error
        self.appearance = appearance
        self.isOpen = isOpen
        self.action = action
    }

    private var isInvalid: Bool { error != nil }
    private var isBrand: Bool { appearance == .brand }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if !isBrand {
                // `.fld-lab` — above the box on `surface`, matching the `HWTextField` beside it.
                Text(caption)
                    .hwLabel(appearance)
                    .accessibilityHidden(true)
            }

            Button(action: action) {
                box
            }
            .buttonStyle(HWPressStyle.compact)
            // **One element carrying caption, value, and role.** VoiceOver reads "Currency, Indian Rupee ·
            // INR, button" rather than three separate static texts a user has to assemble — and the
            // `aria-haspopup="listbox"` in the design becomes the button trait plus the hint (ADR-0012).
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(caption))
            .accessibilityValue(value ?? Text(placeholder))
            // The affordance hint always, never replaced by the error: a user who has just been told the field is
            // wrong is the one who most needs to know it opens a list. The message itself is a reachable element
            // below (see `HWTextField` for why it is not hint-only).
            .accessibilityHint(Text("component.combo.hint"))

            if let error {
                Text(error)
                    .font(.hw(.caption))
                    .foregroundStyle(danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : HWMotion.easeOut.animation(.standard), value: isInvalid)
    }

    private var box: some View {
        HStack(spacing: 10) {
            if let systemImage {
                // `.ctrl svg.lead{color:var(--universe)}` on surface; `--muted`, lifting to `--sky`, on brand.
                Image(systemName: systemImage)
                    .font(.hw(.bodyLarge))
                    .foregroundStyle(isInvalid ? danger : glyphInk)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 2) {
                if isBrand {
                    // `.combo-cap` — inside the box, and only there.
                    Text(caption).hwLabel(.brand)
                }

                (value ?? Text(placeholder))
                    .font(.hw(.bodyLarge).weight(value == nil ? .regular : .semibold))
                    .foregroundStyle(value == nil ? placeholderInk : primaryInk)
                    // `.combo--tall .combo-val{white-space:normal}` — a security question is a sentence and
                    // wraps into a taller box rather than being cut off (ADR-0011).
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let badge {
                HWCodeChip(badge, appearance: appearance)
            }

            // `.chev` — `chevron.down`, which carries no left/right to mirror. `.ctrl.open .chev` rotates it,
            // which is the one movement this control makes.
            Image(systemName: "chevron.down")
                .font(.hw(.caption).weight(.bold))
                .foregroundStyle(glyphInk)
                .rotationEffect(.degrees(isOpen ? 180 : 0))
                .animation(reduceMotion ? nil : HWMotion.easeBack.animation(.standard), value: isOpen)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: HWTextField.minimumHeight, alignment: .leading)
        .hwBox(fill: boxFill, radius: .large, border: borderColour, borderWidth: 1.5)
        .contentShape(.rect)
    }

    /// `.ctrl{background:var(--bg-2)}`, lifting to `--card` while the sheet is open — the same pair
    /// ``HWTextField`` uses for focus on this surface, because an open sheet *is* this control's focus.
    private var boxFill: Color {
        guard !isBrand else { return theme.palette.brand.raised }
        return isOpen ? theme.palette.surface.raised : theme.palette.surface.backgroundSecondary
    }

    private var borderColour: Color {
        if isInvalid { return danger }
        return switch appearance {
        case .brand: theme.palette.brand.separator
        // Transparent until the sheet opens, as `.ctrl` is: the box is defined by its fill there.
        case .surface: isOpen ? theme.palette.accent.muted : Color.clear
        }
    }

    private var danger: Color {
        isBrand ? theme.palette.brand.danger : theme.palette.feedback.danger
    }

    private var primaryInk: Color {
        isBrand ? theme.palette.brand.ink : theme.palette.surface.ink
    }

    /// `.ctrl .val.ph{color:var(--ink-3)}` — the unchosen state, which has to be visibly lighter than a
    /// choice without becoming unreadable.
    private var placeholderInk: Color {
        isBrand ? theme.palette.brand.inkSecondary.opacity(0.8) : theme.palette.surface.inkTertiary
    }

    private var glyphInk: Color {
        isBrand ? theme.palette.brand.inkSecondary : theme.palette.accent.muted
    }
}

#if DEBUG
#Preview("Combo — the surface form, with its label above the box") {
    VStack(spacing: 18) {
        HWCombo(
            "Mode of transport",
            value: Text(verbatim: "Metro / subway"),
            placeholder: "Choose a mode",
            systemImage: "bus"
        ) {}

        HWCombo(
            "What was it for?",
            value: nil,
            placeholder: "Choose a type",
            systemImage: "questionmark.circle"
        ) {}

        // The open state: the border lights and the chevron has turned over.
        HWCombo(
            "Mode of transport",
            value: Text(verbatim: "Ride-hailing app"),
            placeholder: "Choose a mode",
            systemImage: "bus",
            isOpen: true
        ) {}

        HWCombo(
            "What was it for?",
            value: nil,
            placeholder: "Choose a type",
            systemImage: "questionmark.circle",
            error: "Please choose one."
        ) {}
    }
    .padding(22)
    .background(HWPreviewGround())
    .hwTheme()
}

#Preview("Combo — chosen, unchosen, and invalid") {
    VStack(spacing: 16) {
        HWCombo(
            "Currency",
            value: Text(verbatim: "Indian Rupee · INR"),
            placeholder: "Choose a currency",
            systemImage: "globe",
            badge: "₹",
            appearance: .brand
        ) {}

        HWCombo(
            "Question 1",
            value: nil,
            placeholder: "Choose a question",
            systemImage: "questionmark.circle",
            appearance: .brand
        ) {}

        HWCombo(
            "Question 2",
            value: Text(verbatim: "What was the name of your first school?"),
            placeholder: "Choose a question",
            systemImage: "questionmark.circle",
            error: "Choose a second, different question.",
            appearance: .brand
        ) {}
    }
    .padding(22)
    .background(HWPreviewGround(appearance: .brand))
    .hwTheme()
}

#Preview("AX3 — the question wraps inside a taller box") {
    HWCombo(
        "Question 1",
        value: Text(verbatim: "What was the name of your first employer?"),
        placeholder: "Choose a question",
        systemImage: "questionmark.circle",
        appearance: .brand
    ) {}
        .padding(22)
        .dynamicTypeSize(.accessibility3)
        .background(HWPreviewGround(appearance: .brand))
        .hwTheme()
}

#Preview("RTL — the glyph leads on the right, the chip trails on the left") {
    HWCombo(
        "العملة",
        value: Text(verbatim: "درهم إماراتي · AED"),
        placeholder: "اختر العملة",
        systemImage: "globe",
        badge: "د.إ",
        appearance: .brand
    ) {}
        .padding(22)
        .environment(\.layoutDirection, .rightToLeft)
        .background(HWPreviewGround(appearance: .brand))
        .hwTheme()
}
#endif
