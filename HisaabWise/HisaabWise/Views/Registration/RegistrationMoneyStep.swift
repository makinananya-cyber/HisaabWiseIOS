import SwiftUI

/// Step 2 of registration — the design's `view-reg2`, "money & security".
///
/// Two sections under two `.section-cap`s. **Your money**: the display currency and the monthly salary. **Security
/// questions**: two of the fourteen, each with an answer.
///
/// **The salary has one owner and it is the server** (invariant 2, defect D1). What this screen does is *collect*
/// it — the last moment in the app where a salary figure is typed rather than read from a response — and it goes
/// as `{amount, currency}` in minor units (invariant 1), never as the string in the box.
///
/// **The two questions must differ, and the picker makes that unbreakable** rather than checking afterwards: each
/// slot's list omits whatever the other slot holds. `validate()` still refuses a repeat, because the slots can be
/// filled in either order and the second one filled is not always the second one shown.
///
/// **The answers are sent once and never stored** (invariant 5). They go in the one atomic submit, the server
/// hashes the normalised key words, and nothing here keeps or echoes them.
struct RegistrationMoneyStep: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let viewModel: RegistrationViewModel

    /// Which of the three pickers is open, or `nil`. One value rather than three booleans: two sheets open at
    /// once is a state that cannot happen, so it should not be representable.
    @State private var picker: Picker?

    /// The three sheets this step opens.
    enum Picker: Identifiable, Sendable, Equatable {
        case currency
        case firstQuestion
        case secondQuestion

        var id: Self { self }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionCap("registration.two.money.section")
                .hwEnters(step: 3, suppressed: reduceMotion)

            currencyField.hwEnters(step: 3, suppressed: reduceMotion)

            hint("registration.two.currency.hint")
                .hwEnters(step: 3, suppressed: reduceMotion)

            salaryField.hwEnters(step: 4, suppressed: reduceMotion)

            sectionCap("registration.two.security.section")
                .hwEnters(step: 4, suppressed: reduceMotion)

            hint("registration.two.security.hint")
                .hwEnters(step: 4, suppressed: reduceMotion)

            firstQuestion.hwEnters(step: 5, suppressed: reduceMotion)
            firstAnswer.hwEnters(step: 5, suppressed: reduceMotion)
            secondQuestion.hwEnters(step: 5, suppressed: reduceMotion)
            secondAnswer.hwEnters(step: 5, suppressed: reduceMotion)

            submit.hwEnters(step: 5, suppressed: reduceMotion)
        }
        .animation(reduceMotion ? nil : HWMotion.easeOut.animation(.standard), value: viewModel.failures)
        .sheet(item: $picker) { picker in
            sheet(for: picker)
                .presentationBackground(theme.palette.brand.backgroundDeep)
        }
    }

    // MARK: - Your money

    private var currencyField: some View {
        HWCombo(
            "registration.two.currency.label",
            // `.combo-val` — "Indian Rupee · INR". The name and the code are **server content** and the middle
            // dot is **copy**, so the two arrive through a catalogue entry with numbered arguments rather than
            // being joined here: a language that wants the code first has to be able to ask (ADR-0011).
            value: viewModel.currency.map { Text("registration.two.currency.value \($0.name) \($0.code)") },
            placeholder: "registration.two.currency.placeholder",
            systemImage: "globe",
            badge: viewModel.currency?.symbol,
            // Spelled at the call site now that the combo draws both surfaces, and both layouts (#18). On
            // `brand` the caption stays inside the box, which is the rendering this screen already had.
            appearance: .brand
        ) {
            picker = .currency
        }
    }

    private var salaryField: some View {
        HWMoneyField(
            "registration.two.salary.label",
            text: Binding(
                get: { viewModel.salaryText },
                set: { viewModel.salaryText = $0; viewModel.clearFailure(for: .salary) }
            ),
            symbol: viewModel.currency?.symbol ?? "",
            code: viewModel.currency?.code ?? "",
            error: RegistrationView.copy(for: viewModel.failure(for: .salary)),
            // Spelled at the call site now that the field draws both surfaces (#18). It was brand-only, so this
            // is the same rendering said out loud rather than inferred.
            appearance: .brand
        )
    }

    // MARK: - Security questions

    private var firstQuestion: some View {
        HWCombo(
            "registration.two.question.one.label",
            value: viewModel.firstQuestion.map { Text(verbatim: $0.text) },
            placeholder: "registration.two.question.placeholder",
            systemImage: "questionmark.circle",
            error: RegistrationView.copy(for: viewModel.failure(for: .firstQuestion)),
            appearance: .brand
        ) {
            picker = .firstQuestion
        }
    }

    private var firstAnswer: some View {
        HWTextField(
            "registration.two.answer.label",
            text: Binding(
                get: { viewModel.firstAnswer },
                // Its **own** field. Clearing `.firstQuestion` here — which is what this did until review — wiped
                // "choose a question" the moment the user typed an answer, leaving a clean-looking form with no
                // question chosen that the next submit refuses again.
                set: { viewModel.firstAnswer = $0; viewModel.clearFailure(for: .firstAnswer) }
            ),
            systemImage: "list.bullet",
            error: RegistrationView.copy(for: viewModel.failure(for: .firstAnswer)),
            appearance: .brand
        )
    }

    private var secondQuestion: some View {
        HWCombo(
            "registration.two.question.two.label",
            value: viewModel.secondQuestion.map { Text(verbatim: $0.text) },
            placeholder: "registration.two.question.placeholder",
            systemImage: "questionmark.circle",
            error: RegistrationView.copy(for: viewModel.failure(for: .secondQuestion)),
            appearance: .brand
        ) {
            picker = .secondQuestion
        }
    }

    private var secondAnswer: some View {
        HWTextField(
            "registration.two.answer.label",
            text: Binding(
                get: { viewModel.secondAnswer },
                set: { viewModel.secondAnswer = $0; viewModel.clearFailure(for: .secondAnswer) }
            ),
            systemImage: "list.bullet",
            error: RegistrationView.copy(for: viewModel.failure(for: .secondAnswer)),
            appearance: .brand
        )
    }

    private var submit: some View {
        HWButton("registration.two.action", appearance: .brand, systemImage: "arrow.forward") {
            viewModel.advance()
        }
        .background {
            Capsule()
                .fill(theme.palette.brand.inkAccent)
                .blur(radius: 24)
                .opacity(0.5)
                .padding(.horizontal, 18)
                .padding(.top, 6)
                .accessibilityHidden(true)
        }
    }

    // MARK: - The sheets

    @ViewBuilder
    private func sheet(for picker: Picker) -> some View {
        switch picker {
        case .currency:
            HWPickerSheet(
                title: "registration.two.currency.title",
                searchPrompt: "registration.two.currency.search",
                options: viewModel.currencies.map(Self.option),
                selection: viewModel.currency?.code,
                appearance: .brand,
                onSelect: { code in
                    viewModel.chooseCurrency(code: code)
                    self.picker = nil
                },
                onClose: { self.picker = nil }
            )
        case .firstQuestion:
            HWPickerSheet(
                title: "registration.two.question.one.title",
                searchPrompt: "registration.two.question.search",
                // Everything except the other slot's question, so "a second, *different* question" is a rule the
                // list keeps rather than a message the user reads after breaking it.
                options: viewModel.questions(excluding: viewModel.secondQuestion).map(Self.option),
                selection: viewModel.firstQuestion?.id,
                appearance: .brand,
                onSelect: { id in
                    viewModel.chooseFirstQuestion(id: id)
                    self.picker = nil
                },
                onClose: { self.picker = nil }
            )
        case .secondQuestion:
            HWPickerSheet(
                title: "registration.two.question.two.title",
                searchPrompt: "registration.two.question.search",
                options: viewModel.questions(excluding: viewModel.firstQuestion).map(Self.option),
                selection: viewModel.secondQuestion?.id,
                appearance: .brand,
                onSelect: { id in
                    viewModel.chooseSecondQuestion(id: id)
                    self.picker = nil
                },
                onClose: { self.picker = nil }
            )
        }
    }

    // MARK: - Chrome

    /// `.section-cap` — the uppercase rule above a group of fields.
    private func sectionCap(_ key: LocalizedStringResource) -> some View {
        Text(key)
            .hwEyebrow(.brand)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }

    /// `.hint` — the explanatory line under a field.
    private func hint(_ key: LocalizedStringResource) -> some View {
        Text(key)
            .font(.hw(.caption))
            .foregroundStyle(theme.palette.brand.inkSecondary)
            .opacity(0.7)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Mapping

    /// One currency as a picker row: the symbol as the chip, the name, the ISO code as meta — the design's own
    /// `#cur-btn` config, searchable by all three.
    static func option(for currency: Currency) -> HWPickerOption {
        HWPickerOption(
            id: currency.code,
            name: currency.name,
            leading: .code(currency.symbol),
            meta: currency.code,
            searchText: "\(currency.name) \(currency.code) \(currency.symbol)"
        )
    }

    /// One question as a picker row. No chip and no meta — a question is a sentence, and the design's
    /// `wrap: true` gives it the whole row.
    static func option(for question: SecurityQuestion) -> HWPickerOption {
        HWPickerOption(id: question.id, name: question.text)
    }
}

#if DEBUG
#Preview("Step 2 — the defaults") {
    RegistrationStepPreview { RegistrationMoneyStep(viewModel: .previewOnStepTwo) }
}

#Preview("Step 2 — filled") {
    RegistrationStepPreview { RegistrationMoneyStep(viewModel: .previewFilledStepTwo) }
}

#Preview("Step 2 — refused") {
    RegistrationStepPreview { RegistrationMoneyStep(viewModel: .previewFailedStepTwo) }
}

#Preview("AX3 — the questions wrap inside taller combos") {
    RegistrationStepPreview { RegistrationMoneyStep(viewModel: .previewFilledStepTwo) }
        .dynamicTypeSize(.accessibility3)
}

#Preview("RTL") {
    RegistrationStepPreview { RegistrationMoneyStep(viewModel: .previewFilledStepTwo) }
        .environment(\.layoutDirection, .rightToLeft)
}
#endif
