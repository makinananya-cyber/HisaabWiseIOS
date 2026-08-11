import SwiftUI

/// How large the design draws a money field.
///
/// Two sizes, both in the design, and neither is a preference: registration's `.money-sym`/`.money-code` pair
/// sits in a column of ordinary fields and matches them, while Expenses' `.amount` is the **primary input on
/// its screen** — a 28px figure against a 22px symbol, in a box that lifts on focus. Collapsing them into one
/// size would make one screen's main control look like a row in a form, or every form's salary box shout.
enum HWMoneyProminence: Sendable, Equatable, CaseIterable {
    /// `.money-*` — one field among several.
    case standard
    /// `.amount` — the thing the screen is for.
    case prominent
}

/// The design's money field — `.money-sym`, the box, `.money-code`.
///
/// A salary, a goal, or an expense, typed. The symbol leads and the ISO code trails, both taken from the
/// currency the user is authoring in, so the number they are typing is unambiguous while they type it.
///
/// **The symbol and the code are decoration, not formatting.** ADR-0003 gives every *displayed* figure to the
/// server, which formats and converts it; nothing here formats anything. What this draws is the currency's own
/// two labels around a plain number the user is entering — and the number goes to the server as minor units with
/// a currency beside it (invariant 1), never as this string.
///
/// **Both appearances, and both sizes.** The brand form is registration's salary and goal (#15); the surface
/// form is Expenses' amount field (#18), which is where the second caller the appearance was waiting for
/// arrived.
struct HWMoneyField: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isFocused: Bool

    private let label: LocalizedStringResource
    @Binding private var text: String
    /// `.money-sym` / `.amount .cur` — `₹`, `AED`, `د.إ`. From the currency being authored in, so it is a
    /// `String` rather than copy.
    private let symbol: String
    /// `.money-code` / `.amount .code` — the ISO code, `INR`.
    private let code: String
    private let error: LocalizedStringResource?
    private let appearance: HWAppearance
    private let prominence: HWMoneyProminence
    /// Whether the label above the box is drawn at all.
    ///
    /// `false` for Expenses, where the card's own `.card-cap` — "Add an expense" — already says what the field
    /// is for and the design draws no `.fld-lab` above the amount. The label is still the field's VoiceOver
    /// label, which is the half that must not be dropped: a screen reader has no card caption to read from.
    private let showsLabel: Bool

    init(
        _ label: LocalizedStringResource,
        text: Binding<String>,
        symbol: String,
        code: String,
        error: LocalizedStringResource? = nil,
        appearance: HWAppearance = .surface,
        prominence: HWMoneyProminence = .standard,
        showsLabel: Bool = true
    ) {
        self.label = label
        self._text = text
        self.symbol = symbol
        self.code = code
        self.error = error
        self.appearance = appearance
        self.prominence = prominence
        self.showsLabel = showsLabel
    }

    private var isInvalid: Bool { error != nil }
    private var isBrand: Bool { appearance == .brand }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if showsLabel {
                Text(label)
                    .hwLabel(appearance)
                    .accessibilityHidden(true)
            }

            box
                .animation(reduceMotion ? nil : HWMotion.easeInOut.animation(.standard), value: isFocused)
                .animation(reduceMotion ? nil : HWMotion.easeInOut.animation(.standard), value: isInvalid)

            if let error {
                // Left in the accessibility tree **and** delivered as the field's hint, for the reason
                // `HWTextField` records: a hint is spoken last, after a delay, and can be switched off
                // entirely, so a message that existed only as one would be unreachable for some readers.
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
        HStack(spacing: prominence == .prominent ? 10 : 8) {
            Text(verbatim: symbol)
                .font(.hw(symbolStyle))
                .foregroundStyle(isInvalid ? danger : accentInk)
                .frame(minWidth: 30)
                // Read as part of the field's own value below, so the currency is announced once rather than
                // twice — and a bare "₹" read on its own is not something a screen reader can say usefully.
                .accessibilityHidden(true)

            TextField(text: $text) { Text(label) }
                .textFieldStyle(.plain)
                .font(.hw(entryStyle).weight(prominence == .prominent ? .heavy : .regular))
                .foregroundStyle(primaryInk)
                .tint(accentInk)
                // `inputmode="decimal"` — a keypad with a separator, because an amount can have fils.
                .keyboardType(.decimalPad)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($isFocused)
                .accessibilityLabel(Text(label))
                // The currency the number is in, announced as the field's value rather than left to a glyph
                // and a code a screen reader would read as two loose fragments. Through the catalogue with
                // **numbered** arguments, because a language that wants the code first has to be able to ask
                // (ADR-0011) — an interpolated Swift string could not.
                .accessibilityValue(
                    text.isEmpty
                        ? Text("component.money.accessibilityEmpty \(code)")
                        : Text("component.money.accessibilityValue \(text) \(code)")
                )
                .accessibilityHint(error.map { Text($0) } ?? Text(verbatim: ""))

            Text(verbatim: code)
                .hwLabel(appearance)
                .opacity(0.75)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, prominence == .prominent ? 6 : 0)
        .frame(minHeight: HWTextField.minimumHeight)
        // `.amount{border-radius:18px}` and the brand box's own 18 — one radius, so the two sizes read as one
        // control at two scales rather than as two controls.
        .hwBox(fill: boxFill, radius: .large, border: borderColour, borderWidth: 1.5)
    }

    /// `.amount:focus-within{background:var(--card)}` — the surface box starts on the secondary ground and
    /// lifts to the card colour under focus, which is what `HWTextField` does on the same screen. On brand it
    /// is the raised galaxy fill either way, as the design has it.
    private var boxFill: Color {
        guard !isBrand else { return theme.palette.brand.raised }
        return isFocused ? theme.palette.surface.raised : theme.palette.surface.backgroundSecondary
    }

    private var borderColour: Color {
        if isInvalid { return danger }
        return switch appearance {
        case .brand: isFocused ? theme.palette.brand.separatorStrong : theme.palette.brand.separator
        // `border:1.5px solid transparent` until focus, which is `--universe`. Transparent rather than a
        // hairline: the design's surface amount box is defined by its fill, and a permanent border would make
        // it a different control from the one beside it.
        case .surface: isFocused ? theme.palette.accent.muted : Color.clear
        }
    }

    /// The two surfaces have **different danger values** — `#C0453A` in-app, `#FFC9C0` on auth — which is
    /// ADR-0021's clearest evidence that they are two surfaces rather than one theme in two modes.
    private var danger: Color {
        isBrand ? theme.palette.brand.danger : theme.palette.feedback.danger
    }

    private var primaryInk: Color {
        isBrand ? theme.palette.brand.ink : theme.palette.surface.ink
    }

    /// What the symbol, the caret, and the placeholder take.
    private var accentInk: Color {
        isBrand ? theme.palette.brand.inkAccent : theme.palette.accent.base
    }

    /// `.amount .cur{font-size:22px}` against `.money-sym`'s 19.
    private var symbolStyle: HWTextStyle {
        prominence == .prominent ? .heading : .subheading
    }

    /// `.amount input{font-size:28px;font-weight:800}` against `.money-*`'s ordinary field size.
    private var entryStyle: HWTextStyle {
        prominence == .prominent ? .subheading : .bodyLarge
    }
}

#if DEBUG
#Preview("Money field — typed, empty, invalid") {
    @Previewable @State var salary = "8000"
    @Previewable @State var blank = ""
    @Previewable @State var goal = "1600"

    VStack(spacing: 16) {
        HWMoneyField("Monthly salary", text: $salary, symbol: "AED", code: "AED")
        HWMoneyField("Monthly savings goal", text: $goal, symbol: "₹", code: "INR")
        HWMoneyField(
            "Monthly salary",
            text: $blank,
            symbol: "₹",
            code: "INR",
            error: "Enter your salary as a number."
        )
    }
    .padding(22)
    .background(HWPreviewGround(appearance: .brand))
    .hwTheme()
}

#Preview("The prominent surface form — Expenses' amount field") {
    @Previewable @State var amount = "250"
    @Previewable @State var blank = ""

    VStack(spacing: 20) {
        HWMoneyField(
            "Amount",
            text: $amount,
            symbol: "₹",
            code: "INR",
            appearance: .surface,
            prominence: .prominent,
            showsLabel: false
        )
        HWMoneyField(
            "Amount",
            text: $blank,
            symbol: "₹",
            code: "INR",
            error: "Enter an amount greater than zero.",
            appearance: .surface,
            prominence: .prominent,
            showsLabel: false
        )
    }
    .padding(22)
    .background(HWPreviewGround())
    .hwTheme()
}

#Preview("AX3 — the symbol, the number and the code all grow") {
    @Previewable @State var salary = "8000"
    @Previewable @State var amount = "250"

    VStack(spacing: 20) {
        HWMoneyField("Monthly salary", text: $salary, symbol: "د.إ", code: "AED")
        HWMoneyField(
            "Amount",
            text: $amount,
            symbol: "د.إ",
            code: "AED",
            appearance: .surface,
            prominence: .prominent
        )
    }
    .padding(22)
    .dynamicTypeSize(.accessibility3)
    .background(HWPreviewGround(appearance: .brand))
    .hwTheme()
}

#Preview("RTL — the symbol leads on the right") {
    @Previewable @State var salary = "8000"

    HWMoneyField("الراتب الشهري", text: $salary, symbol: "د.إ", code: "AED")
        .padding(22)
        .environment(\.layoutDirection, .rightToLeft)
        .background(HWPreviewGround(appearance: .brand))
        .hwTheme()
}
#endif
