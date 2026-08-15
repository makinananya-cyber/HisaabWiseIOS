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

            securityQuestions.hwEnters(step: 5, suppressed: reduceMotion)

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

    /// Which of the two slots a row is. `Identifiable` because that identity is the point — see below.
    private enum Slot: Int, CaseIterable, Identifiable {
        case first, second
        var id: Int { rawValue }
    }

    /// Both slots, built by **one loop with an identity per row** rather than four hand-written properties.
    ///
    /// This shape matches the password screen, whose two answers have always been a `ForEach` with an id per
    /// row, and it is what makes the two distinct catalogue labels below possible — two boxes both reading
    /// "Your answer" are two boxes a screen reader cannot tell apart.
    ///
    /// **It is not, on the evidence, the fix for the reported focus defect.** A test session found the second
    /// answer box refusing the caret — taps landed in the first answer and every keystroke went there — and this
    /// restructure did *not* change that. What the same session then established is that the boundary is
    /// positional rather than structural: on this form a text field around 790pt down the screen or lower will
    /// not take focus from a synthetic tap, while one at 680pt or above will, and *buttons* at 840pt work fine.
    /// Both of these answer boxes focus normally on ``ForgotPasswordView``, which is the same component in the
    /// same loop, higher up the screen.
    ///
    /// Ruled out: the shared label key, `HWTextField`'s inner `.id()`, `ForEach` identity, the submit button's
    /// blurred backdrop, the `GeometryReader`/`minHeight` wrapper, and the software keyboard. The remaining
    /// candidates are the test harness's tap injection and something about hit-testing near the bottom of this
    /// particular scroll view; distinguishing them needs a real device or a UI test, not another guess.
    private var securityQuestions: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Slot.allCases) { slot in
                VStack(alignment: .leading, spacing: 16) {
                    questionCombo(for: slot)
                    answerField(for: slot)
                }
            }
        }
    }

    private func questionCombo(for slot: Slot) -> some View {
        let field: RegistrationField = slot == .first ? .firstQuestion : .secondQuestion
        return HWCombo(
            slot == .first
                ? "registration.two.question.one.label"
                : "registration.two.question.two.label",
            value: (slot == .first ? viewModel.firstQuestion : viewModel.secondQuestion)
                .map { Text(verbatim: $0.text) },
            placeholder: "registration.two.question.placeholder",
            systemImage: "questionmark.circle",
            error: RegistrationView.copy(for: viewModel.failure(for: field)),
            appearance: .brand
        ) {
            picker = slot == .first ? .firstQuestion : .secondQuestion
        }
    }

    /// **Two distinct labels, not one key twice.** Both boxes read "Your answer", but a screen reader landing
    /// on the second one with the same label as the first cannot say which question it belongs to.
    private func answerField(for slot: Slot) -> some View {
        let field: RegistrationField = slot == .first ? .firstAnswer : .secondAnswer
        return HWTextField(
            slot == .first
                ? "registration.two.answer.one.label"
                : "registration.two.answer.two.label",
            text: Binding(
                get: { slot == .first ? viewModel.firstAnswer : viewModel.secondAnswer },
                // Each clears its **own** failure. Clearing the question's here — which is what the first
                // answer did until review — wiped "choose a question" the moment the user typed, leaving a
                // clean-looking form with no question chosen that the next submit refuses again.
                set: { typed in
                    if slot == .first {
                        viewModel.firstAnswer = typed
                    } else {
                        viewModel.secondAnswer = typed
                    }
                    viewModel.clearFailure(for: field)
                }
            ),
            systemImage: "list.bullet",
            error: RegistrationView.copy(for: viewModel.failure(for: field)),
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
                // **Decoration, and decoration must not take touches.** A `.blur` renders well outside its own
                // bounds, and this glow sits directly under the last field on the form — which is the field that
                // could not be focused. It is a background: it has nothing to do when tapped.
                .allowsHitTesting(false)
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
