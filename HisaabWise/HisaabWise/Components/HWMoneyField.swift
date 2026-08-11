import SwiftUI

/// The design's money field — `.money-sym`, the box, `.money-code`.
///
/// A salary or a goal, typed. The symbol leads and the ISO code trails, both taken from the currency the user
/// chose one field earlier, so the number they are typing is unambiguous while they type it.
///
/// **The symbol and the code are decoration, not formatting.** ADR-0003 gives every *displayed* figure to the
/// server, which formats and converts it; nothing here formats anything. What this draws is the currency's own
/// two labels around a plain number the user is entering — and the number goes to the server as minor units with
/// a currency beside it (invariant 1), never as this string.
///
/// **Brand only, for now** — the same reasoning as ``HWCombo``: Add Expense's amount field is this shape on the
/// light surface and arrives with #18.
struct HWMoneyField: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isFocused: Bool

    private let label: LocalizedStringResource
    @Binding private var text: String
    /// `.money-sym` — `₹`, `AED`, `د.إ`. From the chosen currency, so it is a `String` rather than copy.
    private let symbol: String
    /// `.money-code` — the ISO code, `INR`.
    private let code: String
    private let error: LocalizedStringResource?

    init(
        _ label: LocalizedStringResource,
        text: Binding<String>,
        symbol: String,
        code: String,
        error: LocalizedStringResource? = nil
    ) {
        self.label = label
        self._text = text
        self.symbol = symbol
        self.code = code
        self.error = error
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
        HStack(spacing: 8) {
            Text(verbatim: symbol)
                .font(.hw(.subheading))
                .foregroundStyle(isInvalid ? theme.palette.brand.danger : theme.palette.brand.inkAccent)
                .frame(minWidth: 30)
                // Read as part of the field's own label below, so the currency is announced once rather than
                // twice — and a bare "₹" read on its own is not something a screen reader can say usefully.
                .accessibilityHidden(true)

            TextField(text: $text) { Text(label) }
                .textFieldStyle(.plain)
                .font(.hw(.bodyLarge).weight(.regular))
                .foregroundStyle(theme.palette.brand.ink)
                .tint(theme.palette.brand.inkAccent)
                // `inputmode="decimal"` — a keypad with a separator, because a salary can have fils.
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
                .hwLabel(.brand)
                .opacity(0.75)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: HWTextField.minimumHeight)
        .hwBox(
            fill: theme.palette.brand.raised,
            radius: .large,
            border: borderColour,
            borderWidth: 1.5
        )
    }

    private var borderColour: Color {
        if isInvalid { return theme.palette.brand.danger }
        return isFocused ? theme.palette.brand.separatorStrong : theme.palette.brand.separator
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

#Preview("AX3 — the symbol, the number and the code all grow") {
    @Previewable @State var salary = "8000"

    HWMoneyField("Monthly salary", text: $salary, symbol: "د.إ", code: "AED")
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
