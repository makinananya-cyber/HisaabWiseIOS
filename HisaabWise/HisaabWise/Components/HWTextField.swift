import SwiftUI

/// The design's `.field-box` — one field, configured.
///
/// The amount field and the email field are this component with different arguments, which is the whole
/// reason it exists: the design draws them as one shape (`.field-box` / `.ctrl`, a rounded box with a
/// leading `.field-ico`, a `.fld-lab` above, and a `.msg` below), and two screens that each rolled their
/// own would diverge on the focus ring first and the error state second.
///
/// **Presentational.** It takes a binding, values, and nothing else. Validation is the caller's: the
/// field draws the error it is handed and never decides what is wrong.
///
/// The keyboard surface — ``keyboardType`` and ``textContentType`` — is UIKit-typed because SwiftUI's own
/// modifiers are. No representable, no UIKit view (Rule 1).
struct HWTextField: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isFocused: Bool

    /// The `.fld-lab` above the box. Always app copy — a field's name is never a server string.
    private let label: LocalizedStringResource
    @Binding private var text: String
    private let placeholder: LocalizedStringResource?
    /// The `.field-ico` slot. `nil` draws the box without one, as the design's plain `.ctrl` does.
    private let systemImage: String?
    private let keyboardType: UIKeyboardType
    private let textContentType: UITextContentType?
    /// `.field.bad` — the border turns danger and the message appears. `nil` is a valid field.
    private let error: LocalizedStringResource?

    init(
        _ label: LocalizedStringResource,
        text: Binding<String>,
        placeholder: LocalizedStringResource? = nil,
        systemImage: String? = nil,
        keyboardType: UIKeyboardType = .default,
        textContentType: UITextContentType? = nil,
        error: LocalizedStringResource? = nil
    ) {
        self.label = label
        self._text = text
        self.placeholder = placeholder
        self.systemImage = systemImage
        self.keyboardType = keyboardType
        self.textContentType = textContentType
        self.error = error
    }

    /// `.ctrl{min-height:54px}` — a minimum, so the box grows with the text rather than clipping it.
    static let minimumHeight: CGFloat = 54

    private var isInvalid: Bool { error != nil }

    /// `.ctrl:focus-within{border-color:var(--universe)}`, and `.bad .ctrl` overriding it with danger.
    private var borderColour: Color {
        if isInvalid { return theme.palette.feedback.danger }
        return isFocused ? theme.palette.accent.muted : theme.palette.surface.separator
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label)
                .hwLabel()
                // The field below carries this as its own VoiceOver label, so announcing it twice is the
                // noise ADR-0012 warns about.
                .accessibilityHidden(true)

            box
                .animation(HWMotion.easeInOut.animation(.standard), value: isFocused)
                .animation(HWMotion.easeInOut.animation(.standard), value: isInvalid)

            if let error {
                Text(error)
                    .font(.hw(.caption))
                    .foregroundStyle(theme.palette.feedback.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    // The design shakes the box to draw the eye. Under Reduce Motion the message
                    // cross-fades in instead of sliding — replaced, not removed (ADR-0012).
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                    // Read as the field's hint, at the moment the field is focused, rather than as a
                    // separate element a VoiceOver user has to go looking for.
                    .accessibilityHidden(true)
            }
        }
        .animation(HWMotion.easeOut.animation(.standard), value: isInvalid)
    }

    private var box: some View {
        HStack(spacing: 10) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.hw(.bodyLarge))
                    .foregroundStyle(isInvalid ? theme.palette.feedback.danger : theme.palette.accent.muted)
                    // The glyph restates the label beside it.
                    .accessibilityHidden(true)
            }

            TextField(text: $text) {
                Text(placeholder ?? label)
            }
            .textFieldStyle(.plain)
            .font(.hw(.bodyLarge).weight(.regular))
            .foregroundStyle(theme.palette.surface.ink)
            .tint(theme.palette.accent.base)
            .keyboardType(keyboardType)
            .textContentType(textContentType)
            .focused($isFocused)
            // Labelled here rather than by grouping the whole stack: an `accessibilityElement` over a
            // `TextField` collapses it into one static element and VoiceOver can no longer edit it.
            .accessibilityLabel(Text(label))
            .accessibilityHint(error.map { Text($0) } ?? Text(verbatim: ""))
        }
        .padding(.horizontal, 14)
        .frame(minHeight: Self.minimumHeight)
        .hwBox(
            fill: isFocused ? theme.palette.surface.raised : theme.palette.surface.backgroundSecondary,
            radius: .medium,
            border: borderColour,
            borderWidth: 1.5
        )
    }
}

#if DEBUG
#Preview("Fields — the same component, configured") {
    @Previewable @State var email = "neeraj@example.ae"
    @Previewable @State var amount = "250"
    @Previewable @State var blank = ""

    ScrollView {
        VStack(spacing: 16) {
            HWTextField(
                "Email",
                text: $email,
                placeholder: "you@example.com",
                systemImage: "envelope",
                keyboardType: .emailAddress,
                textContentType: .emailAddress
            )
            HWTextField("Amount", text: $amount, systemImage: "creditcard", keyboardType: .decimalPad)
            HWTextField("Note", text: $blank, placeholder: "What was it for?")
            HWTextField(
                "Email",
                text: $blank,
                systemImage: "envelope",
                keyboardType: .emailAddress,
                error: "That does not look like an email address."
            )
        }
        .padding()
    }
    .background(HWPreviewGround())
    .hwTheme()
}

#Preview("AX3 — the box grows with the text") {
    @Previewable @State var amount = "250"

    HWTextField(
        "Amount",
        text: $amount,
        systemImage: "creditcard",
        keyboardType: .decimalPad,
        error: "Enter an amount greater than zero."
    )
    .padding()
    .dynamicTypeSize(.accessibility3)
    .background(HWPreviewGround())
    .hwTheme()
}

#Preview("RTL — the icon leads on the right") {
    @Previewable @State var email = ""

    HWTextField(
        "البريد الإلكتروني",
        text: $email,
        systemImage: "envelope",
        keyboardType: .emailAddress,
        error: "هذا ليس بريداً إلكترونياً صحيحاً."
    )
    .padding()
    .environment(\.layoutDirection, .rightToLeft)
    .background(HWPreviewGround())
    .hwTheme()
}
#endif
