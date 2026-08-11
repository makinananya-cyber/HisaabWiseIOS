import SwiftUI

/// The design's phone field — the `.dial` trigger, the `.sep` hairline, and the number.
///
/// Two controls in one box: a button that opens the country picker and a field for the national digits. They are
/// drawn as one field because that is what the user is entering — one phone number — and kept as two controls
/// because that is what they are, which is what lets VoiceOver reach each of them.
///
/// **The two halves are stored separately and joined once**, in `PhoneNumber.e164`. A single free-text box would
/// leave the client guessing whether `050…` is a UAE mobile or the start of an international number.
///
/// **Brand only** — the design has one phone field, on registration.
struct HWPhoneField: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isFocused: Bool

    private let label: LocalizedStringResource
    @Binding private var digits: String
    /// `.iso-chip` — the ISO 3166-1 alpha-2 code, `IN`. Empty while the country list is still loading.
    private let countryCode: String
    /// `.dial-code` — `+91`, with the plus.
    private let dialCode: String
    /// VoiceOver's reading of the dial trigger — "Change country code" in the design's own `aria-label`.
    private let dialLabel: LocalizedStringResource
    private let error: LocalizedStringResource?
    private let onChangeCountry: () -> Void

    init(
        _ label: LocalizedStringResource,
        digits: Binding<String>,
        countryCode: String,
        dialCode: String,
        dialLabel: LocalizedStringResource,
        error: LocalizedStringResource? = nil,
        onChangeCountry: @escaping () -> Void
    ) {
        self.label = label
        self._digits = digits
        self.countryCode = countryCode
        self.dialCode = dialCode
        self.dialLabel = dialLabel
        self.error = error
        self.onChangeCountry = onChangeCountry
    }

    private var isInvalid: Bool { error != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label)
                .hwLabel(.brand)
                .accessibilityHidden(true)

            box
                .animation(reduceMotion ? nil : HWMotion.easeInOut.animation(.standard), value: isFocused)
                .animation(reduceMotion ? nil : HWMotion.easeInOut.animation(.standard), value: isInvalid)

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
            dial

            // `.sep` — a hairline between the two halves, inset from the box's edges. Decoration.
            Rectangle()
                .fill(theme.palette.brand.separator)
                .frame(width: 1)
                .padding(.vertical, 12)
                .accessibilityHidden(true)

            TextField(text: $digits) { Text(label) }
                .textFieldStyle(.plain)
                .font(.hw(.bodyLarge).weight(.regular))
                .foregroundStyle(theme.palette.brand.ink)
                .tint(theme.palette.brand.inkAccent)
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($isFocused)
                .accessibilityLabel(Text(label))
                .accessibilityHint(error.map { Text($0) } ?? Text(verbatim: ""))
        }
        .padding(.trailing, 14)
        .frame(minHeight: HWTextField.minimumHeight)
        .hwBox(
            fill: theme.palette.brand.raised,
            radius: .large,
            border: isInvalid ? theme.palette.brand.danger : borderColour,
            borderWidth: 1.5
        )
    }

    /// `.dial` — the ISO chip, the dial code, and a chevron, as one button.
    private var dial: some View {
        Button(action: onChangeCountry) {
            HStack(spacing: 7) {
                HWCodeChip(countryCode, appearance: .brand)

                Text(verbatim: dialCode)
                    .font(.hw(.bodyLarge).weight(.semibold))
                    .foregroundStyle(theme.palette.brand.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Image(systemName: "chevron.down")
                    .font(.hw(.caption).weight(.bold))
                    .foregroundStyle(theme.palette.brand.inkSecondary)
            }
            .padding(.leading, 13)
            .padding(.vertical, 8)
            .frame(minHeight: HWTouchTarget.minimum)
            .contentShape(.rect)
        }
        .buttonStyle(HWPressStyle.compact)
        // One control, announced as "Country code, +91, button" — the chip and the code read together as its
        // value, because separately they are two codes with no relationship a listener could hear.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(dialLabel))
        .accessibilityValue(Text("component.phone.accessibilityValue \(dialCode) \(countryCode)"))
        .accessibilityHint(Text("component.combo.hint"))
    }

    private var borderColour: Color {
        isFocused ? theme.palette.brand.separatorStrong : theme.palette.brand.separator
    }
}

#if DEBUG
#Preview("Phone field — typed, empty, invalid") {
    @Previewable @State var typed = "501234567"
    @Previewable @State var blank = ""
    @Previewable @State var short = "12"

    VStack(spacing: 16) {
        HWPhoneField(
            "Phone number",
            digits: $typed,
            countryCode: "AE",
            dialCode: "+971",
            dialLabel: "Change country code"
        ) {}

        HWPhoneField(
            "Phone number",
            digits: $blank,
            countryCode: "IN",
            dialCode: "+91",
            dialLabel: "Change country code"
        ) {}

        HWPhoneField(
            "Phone number",
            digits: $short,
            countryCode: "PH",
            dialCode: "+63",
            dialLabel: "Change country code",
            error: "Enter a valid phone number."
        ) {}
    }
    .padding(22)
    .background(HWPreviewGround(appearance: .brand))
    .hwTheme()
}

#Preview("AX3 — the dial trigger and the number both grow") {
    @Previewable @State var typed = "501234567"

    HWPhoneField(
        "Phone number",
        digits: $typed,
        countryCode: "AE",
        dialCode: "+971",
        dialLabel: "Change country code"
    ) {}
        .padding(22)
        .dynamicTypeSize(.accessibility3)
        .background(HWPreviewGround(appearance: .brand))
        .hwTheme()
}

#Preview("RTL — the dial trigger leads on the right") {
    @Previewable @State var typed = "501234567"

    HWPhoneField(
        "رقم الهاتف",
        digits: $typed,
        countryCode: "AE",
        dialCode: "+971",
        dialLabel: "تغيير رمز البلد"
    ) {}
        .padding(22)
        .environment(\.layoutDirection, .rightToLeft)
        .background(HWPreviewGround(appearance: .brand))
        .hwTheme()
}
#endif
