import SwiftUI

/// The design's `.field-box.combo` — a field-shaped **button** that opens a picker.
///
/// It looks like ``HWTextField`` and is not one: nothing can be typed into it, because what it holds is a choice
/// from a server-served list. The shape is shared deliberately — a currency and a salary sit next to each other
/// on the same form, and two different boxes would read as two different kinds of thing.
///
/// The caption above the value is the design's `.combo-cap`, always drawn: unlike a text field's floating label
/// there is nothing for it to float over, so a combo says what it is before and after a choice is made.
///
/// **Brand only, for now.** The design's in-app pickers — Add Expense's category and date — are the same shape on
/// the light surface, and they arrive with #18 where there is a caller to shape them. The same reasoning
/// `HWButton` applies to the destructive variant it has not drawn yet.
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
    private let action: () -> Void

    init(
        _ caption: LocalizedStringResource,
        value: Text?,
        placeholder: LocalizedStringResource,
        systemImage: String? = nil,
        badge: String? = nil,
        error: LocalizedStringResource? = nil,
        action: @escaping () -> Void
    ) {
        self.caption = caption
        self.value = value
        self.placeholder = placeholder
        self.systemImage = systemImage
        self.badge = badge
        self.error = error
        self.action = action
    }

    private var isInvalid: Bool { error != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
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
                    .foregroundStyle(theme.palette.brand.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : HWMotion.easeOut.animation(.standard), value: isInvalid)
    }

    private var box: some View {
        HStack(spacing: 10) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.hw(.bodyLarge))
                    .foregroundStyle(isInvalid ? theme.palette.brand.danger : theme.palette.brand.inkSecondary)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(caption)
                    .hwLabel(.brand)

                (value ?? Text(placeholder))
                    .font(.hw(.bodyLarge).weight(.regular))
                    .foregroundStyle(
                        value == nil
                            ? theme.palette.brand.inkSecondary.opacity(0.8)
                            : theme.palette.brand.ink
                    )
                    // `.combo--tall .combo-val{white-space:normal}` — a security question is a sentence and
                    // wraps into a taller box rather than being cut off (ADR-0011).
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let badge {
                HWCodeChip(badge, appearance: .brand)
            }

            // `.chev` — `chevron.down`, which carries no left/right to mirror.
            Image(systemName: "chevron.down")
                .font(.hw(.caption).weight(.bold))
                .foregroundStyle(theme.palette.brand.inkSecondary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: HWTextField.minimumHeight, alignment: .leading)
        .hwBox(
            fill: theme.palette.brand.raised,
            radius: .large,
            border: isInvalid ? theme.palette.brand.danger : theme.palette.brand.separator,
            borderWidth: 1.5
        )
        .contentShape(.rect)
    }
}

#if DEBUG
#Preview("Combo — chosen, unchosen, and invalid") {
    VStack(spacing: 16) {
        HWCombo(
            "Currency",
            value: Text(verbatim: "Indian Rupee · INR"),
            placeholder: "Choose a currency",
            systemImage: "globe",
            badge: "₹"
        ) {}

        HWCombo("Question 1", value: nil, placeholder: "Choose a question", systemImage: "questionmark.circle") {}

        HWCombo(
            "Question 2",
            value: Text(verbatim: "What was the name of your first school?"),
            placeholder: "Choose a question",
            systemImage: "questionmark.circle",
            error: "Choose a second, different question."
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
        systemImage: "questionmark.circle"
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
        badge: "د.إ"
    ) {}
        .padding(22)
        .environment(\.layoutDirection, .rightToLeft)
        .background(HWPreviewGround(appearance: .brand))
        .hwTheme()
}
#endif
