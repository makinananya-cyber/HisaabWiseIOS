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
    /// The greyed text inside an empty box. **`nil` draws nothing**, which is the design's own behaviour:
    /// `.input-wrap input::placeholder{color:transparent}` hides it and floats the label into its place instead.
    /// Here the label always sits *above* the box, so a placeholder repeating it would print the field's name
    /// twice — which is what this component did until #15.
    private let placeholder: LocalizedStringResource?
    /// The `.field-ico` slot. `nil` draws the box without one, as the design's plain `.ctrl` does.
    private let systemImage: String?
    private let keyboardType: UIKeyboardType
    private let textContentType: UITextContentType?
    /// `.field.bad` — the border turns danger and the message appears. `nil` is a valid field.
    private let error: LocalizedStringResource?
    /// Which of the design's two surfaces the field sits on (ADR-0021). Auth is the second caller the
    /// appearance was waiting for.
    private let appearance: HWAppearance
    /// `type="password"` plus the design's `.reveal` eye. The toggle is the field's own state because it is
    /// about *this* control's rendering and nothing else — a caller that owned it would have to reset it.
    private let isSecure: Bool

    @State private var isRevealed = false

    init(
        _ label: LocalizedStringResource,
        text: Binding<String>,
        placeholder: LocalizedStringResource? = nil,
        systemImage: String? = nil,
        keyboardType: UIKeyboardType = .default,
        textContentType: UITextContentType? = nil,
        error: LocalizedStringResource? = nil,
        appearance: HWAppearance = .surface,
        isSecure: Bool = false
    ) {
        self.label = label
        self._text = text
        self.placeholder = placeholder
        self.systemImage = systemImage
        self.keyboardType = keyboardType
        self.textContentType = textContentType
        self.error = error
        self.appearance = appearance
        self.isSecure = isSecure
    }

    /// `.ctrl{min-height:54px}` — a minimum, so the box grows with the text rather than clipping it.
    static let minimumHeight: CGFloat = 54

    private var isInvalid: Bool { error != nil }

    /// The two surfaces have **different danger values** — `#C0453A` in-app, `#FFC9C0` on auth — which is
    /// ADR-0021's clearest evidence that they are two surfaces rather than one theme in two modes.
    private var danger: Color {
        appearance == .brand ? theme.palette.brand.danger : theme.palette.feedback.danger
    }

    /// `.ctrl:focus-within{border-color:var(--universe)}` on surface, `--border-lit` on brand, and `.bad`
    /// overriding both with danger.
    private var borderColour: Color {
        if isInvalid { return danger }
        return switch appearance {
        case .surface: isFocused ? theme.palette.accent.muted : theme.palette.surface.separator
        case .brand: isFocused ? theme.palette.brand.separatorStrong : theme.palette.brand.separator
        }
    }

    /// `.field-box{background:rgba(sky,.06)}` and its `:focus-within` lift on brand; the card and the
    /// secondary ground on surface.
    private var boxFill: Color {
        switch appearance {
        case .surface: isFocused ? theme.palette.surface.raised : theme.palette.surface.backgroundSecondary
        case .brand: theme.palette.brand.raised
        }
    }

    /// `.field-ico{color:var(--muted)}` → `--sky` when the box has focus.
    private var iconColour: Color {
        if isInvalid { return danger }
        return switch appearance {
        case .surface: theme.palette.accent.muted
        case .brand: isFocused ? theme.palette.brand.inkAccent : theme.palette.brand.inkSecondary
        }
    }

    private var inkColour: Color {
        appearance == .brand ? theme.palette.brand.ink : theme.palette.surface.ink
    }

    /// What the caret takes. The placeholder is drawn in ``placeholderInk`` instead — see there.
    private var caretColour: Color {
        appearance == .brand ? theme.palette.brand.inkAccent : theme.palette.accent.base
    }

    /// What the greyed placeholder takes — **the muted ink, not the accent tint**. A plain `TextField` draws its
    /// placeholder in the `.tint` colour, which on surface is `--planetary`: a dark blue that on the light ground
    /// reads as unfilled text nobody can make out. The muted tertiary ink is the same lighter grey the combo and
    /// date fields already draw their placeholders in, so the whole form's unfilled state matches.
    private var placeholderInk: Color {
        appearance == .brand ? theme.palette.brand.inkSecondary : theme.palette.surface.inkTertiary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label)
                // The appearance goes *into* the style. An outer `.foregroundStyle` here — which is what this
                // line was until #15 — is overridden by the one inside `HWLabelStyle`, so the label took the
                // surface's ink on the galaxy ground and could not be read.
                .hwLabel(appearance)
                // The field below carries this as its own VoiceOver label, so announcing it twice is the
                // noise ADR-0012 warns about.
                .accessibilityHidden(true)

            box
                .animation(reduceMotion ? nil : HWMotion.easeInOut.animation(.standard), value: isFocused)
                .animation(reduceMotion ? nil : HWMotion.easeInOut.animation(.standard), value: isInvalid)

            if let error {
                // **Left in the accessibility tree, and also delivered as the field's hint.** It was hint-only
                // until review, which sounded tidier and is not: a hint is spoken last, after a delay, and can be
                // switched off entirely (VoiceOver ▸ Verbosity ▸ Speak Hints) — with it off, "use at least 8
                // characters" was unreachable by any means. The small duplication buys a message that cannot be
                // configured away, on a screen whose copy was moved out of a toast for exactly that reason.
                Text(error)
                    .font(.hw(.caption))
                    .foregroundStyle(danger)
                    .fixedSize(horizontal: false, vertical: true)
                    // The design shakes the box to draw the eye. Under Reduce Motion the message
                    // cross-fades in instead of sliding — replaced, not removed (ADR-0012).
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
        // **`nil` under Reduce Motion, not a shorter curve.** The `.transition` above governs the message
        // appearing; *this* eases the height change, which pushes every field below it down the screen. Replacing
        // the slide and keeping the reflow would have been half the fix — the message now arrives in place
        // (ADR-0012: replaced, not removed).
        .animation(reduceMotion ? nil : HWMotion.easeOut.animation(.standard), value: isInvalid)
    }

    private var box: some View {
        HStack(spacing: 10) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.hw(.bodyLarge))
                    .foregroundStyle(iconColour)
                    // The glyph restates the label beside it.
                    .accessibilityHidden(true)
            }

            entry
            .textFieldStyle(.plain)
            .font(.hw(.bodyLarge).weight(.regular))
            .foregroundStyle(inkColour)
            // **The tint, not the ink.** A plain `TextField` draws its placeholder *and* its caret in the
            // accent colour, and on the galaxy ground `--planetary` is barely a shade off the background — a
            // placeholder nobody can read and a cursor nobody can find.
            .tint(caretColour)
            .keyboardType(keyboardType)
            .textContentType(textContentType)
            // **Never capitalised and never corrected.** An email is the identity (invariant 4) and a revealed
            // password is a password: iOS defaults to sentence case with autocorrect on, which silently edits
            // both. A capital first letter in an address is the kind of failure a user cannot see.
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($isFocused)
            // Labelled here rather than by grouping the whole stack: an `accessibilityElement` over a
            // `TextField` collapses it into one static element and VoiceOver can no longer edit it.
            .accessibilityLabel(Text(label))
            .accessibilityHint(error.map { Text($0) } ?? Text(verbatim: ""))

            if isSecure {
                reveal
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: Self.minimumHeight)
        .hwBox(
            fill: boxFill,
            radius: appearance == .brand ? .large : .medium,
            border: borderColour,
            borderWidth: 1.5
        )
    }

    /// A secure field when the text is hidden and a plain one when it is not.
    ///
    /// Two `View`s rather than one with a flag, because that is what SwiftUI offers: `SecureField` and
    /// `TextField` are different types, so the swap is a *replacement* — the text survives (it is the binding's)
    /// and the first responder does not. `reveal` puts focus back afterwards, which is the whole of what can be
    /// done about it short of a UIKit representable, and Rule 1 rules that out for a keyboard hop.
    @ViewBuilder
    private var entry: some View {
        if isSecure, !isRevealed {
            SecureField(text: $text) { prompt }
                .id(false)
        } else {
            TextField(text: $text) { prompt }
                .id(true)
        }
    }

    /// The prompt, or nothing at all.
    ///
    /// **`Text(verbatim:)` for the empty case rather than `Text("")`**, because a localised empty string is a
    /// catalogue lookup for a key that is not there.
    @ViewBuilder
    private var prompt: some View {
        if let placeholder {
            // The foreground is set on the prompt itself so it wins over the field's `.tint`, which would
            // otherwise colour the placeholder in the accent (see ``placeholderInk``).
            Text(placeholder)
                .foregroundStyle(placeholderInk)
        } else {
            Text(verbatim: "")
        }
    }

    /// The design's `.reveal` — the eye that shows the password.
    ///
    /// `aria-pressed` in the design, which is `.isSelected` here: VoiceOver then says "Show password,
    /// selected" rather than leaving the state to the glyph, which it cannot see (ADR-0012).
    private var reveal: some View {
        Button {
            isRevealed.toggle()
            // Swapping `SecureField` for `TextField` replaces the responder, so focus is asserted again rather
            // than left to fall on the floor and dismiss the keyboard mid-password.
            isFocused = true
        } label: {
            Image(systemName: isRevealed ? "eye.slash" : "eye")
                .font(.hw(.bodyLarge))
                .foregroundStyle(iconColour)
                .frame(width: HWTouchTarget.minimum, height: HWTouchTarget.minimum)
                .contentShape(.rect)
        }
        .buttonStyle(HWPressStyle.compact)
        .accessibilityLabel(Text("component.field.revealPassword"))
        .hwSelectionTraits(isSelected: isRevealed)
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
