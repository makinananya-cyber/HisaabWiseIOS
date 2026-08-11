import SwiftUI

/// Step 1 of registration — the design's `view-reg1`, "about you".
///
/// Name, email, phone, date of birth, a password and its confirmation, and the Terms consent. Six fields and one
/// checkbox, and **nothing here talks to the server**: the button validates and advances, because the account is
/// created once at the end of step 3 (the [FIX] `RegistrationView` explains).
///
/// **Two rules the design does not have.** The password floor is **8** characters, not 6 (invariant 4). And
/// **13 is enforced on the client as well as on the server**: a form that collects a twelve-year-old's name,
/// email, and phone number before refusing them has already collected them, so the picker cannot offer a date
/// that young and the validation says why if one arrives anyway.
struct RegistrationDetailsStep: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Opens the hosted Terms and Privacy pages. `openURL` rather than a `Link`, so the two affordances are the
    /// same `HWLink` control the rest of the auth flow uses (#26) rather than a second link style.
    @Environment(\.openURL) private var openURL

    /// Handed down from ``RegistrationView`` rather than made here: it is the *form*, and all three steps write
    /// into the same one. That is the whole mechanism behind one atomic submit.
    let viewModel: RegistrationViewModel

    /// The design's `#dial-btn` sheet. Local to this step, because the country picker cannot be open while any
    /// other step is on screen.
    @State private var isChoosingCountry = false

    var body: some View {
        VStack(spacing: 16) {
            name.hwEnters(step: 3, suppressed: reduceMotion)
            email.hwEnters(step: 3, suppressed: reduceMotion)
            phone.hwEnters(step: 4, suppressed: reduceMotion)
            dateOfBirth.hwEnters(step: 4, suppressed: reduceMotion)
            password.hwEnters(step: 5, suppressed: reduceMotion)
            confirmPassword.hwEnters(step: 5, suppressed: reduceMotion)
            terms.hwEnters(step: 5, suppressed: reduceMotion)
            submit.hwEnters(step: 5, suppressed: reduceMotion)
        }
        .animation(reduceMotion ? nil : HWMotion.easeOut.animation(.standard), value: viewModel.failures)
        .sheet(isPresented: $isChoosingCountry) {
            HWPickerSheet(
                title: "registration.country.title",
                searchPrompt: "registration.country.search",
                options: viewModel.countries.map(Self.option),
                selection: viewModel.country?.code,
                appearance: .brand,
                onSelect: { code in
                    viewModel.chooseCountry(code: code)
                    isChoosingCountry = false
                },
                onClose: { isChoosingCountry = false }
            )
            // The panel is the design's galaxy sheet, so it takes the brand ground rather than the system's.
            .presentationBackground(theme.palette.brand.backgroundDeep)
        }
    }

    // MARK: - The fields

    private var name: some View {
        HWTextField(
            "registration.name.label",
            text: Binding(
                get: { viewModel.name },
                set: { viewModel.name = $0; viewModel.clearFailure(for: .name) }
            ),
            systemImage: "person",
            textContentType: .name,
            error: RegistrationView.copy(for: viewModel.failure(for: .name)),
            appearance: .brand
        )
    }

    private var email: some View {
        HWTextField(
            "registration.email.label",
            text: Binding(
                get: { viewModel.email },
                set: { viewModel.email = $0; viewModel.clearFailure(for: .email) }
            ),
            systemImage: "envelope",
            keyboardType: .emailAddress,
            textContentType: .emailAddress,
            error: RegistrationView.copy(for: viewModel.failure(for: .email)),
            appearance: .brand
        )
    }

    /// The design's phone field, and **it is optional at launch** — Product Spec §3.3 collects a number but does
    /// not require one. A number that *is* given still has to be 6–15 digits.
    private var phone: some View {
        HWPhoneField(
            "registration.phone.label",
            digits: Binding(
                get: { viewModel.phoneDigits },
                set: { viewModel.phoneDigits = $0; viewModel.clearFailure(for: .phone) }
            ),
            countryCode: viewModel.country?.code ?? "",
            dialCode: viewModel.country?.dialCode ?? "",
            dialLabel: "registration.phone.dial.accessibilityLabel",
            error: RegistrationView.copy(for: viewModel.failure(for: .phone))
        ) {
            isChoosingCountry = true
        }
    }

    private var dateOfBirth: some View {
        HWDateField(
            "registration.dateOfBirth.label",
            date: Binding(
                get: { viewModel.dateOfBirth },
                set: { viewModel.dateOfBirth = $0; viewModel.clearFailure(for: .dateOfBirth) }
            ),
            in: RegistrationViewModel.dateOfBirthRange(),
            placeholder: "registration.dateOfBirth.placeholder",
            error: RegistrationView.copy(for: viewModel.failure(for: .dateOfBirth))
        )
    }

    /// The password box and the design's `.meter` under it.
    ///
    /// The meter appears the moment there is something to measure and disappears when the box is emptied, which
    /// is `.meter.show` — it is feedback about what has been typed, so an empty box has nothing to say.
    private var password: some View {
        VStack(alignment: .leading, spacing: 9) {
            HWTextField(
                "registration.password.label",
                text: Binding(
                    get: { viewModel.password },
                    // **And the confirmation's failure.** "Those do not match" is a statement about *both* boxes,
                    // so correcting either one has to clear it — editing the password left a stale mismatch under
                    // the confirm box, red-bordered, until the next submit.
                    set: {
                        viewModel.password = $0
                        viewModel.clearFailure(for: .password)
                        viewModel.clearFailure(for: .confirmPassword)
                    }
                ),
                systemImage: "lock",
                textContentType: .newPassword,
                error: RegistrationView.copy(for: viewModel.failure(for: .password)),
                appearance: .brand,
                isSecure: true
            )

            if viewModel.passwordStrength != .none {
                HWStrengthMeter(
                    filled: viewModel.passwordStrength.rawValue,
                    outOf: PasswordStrength.strong.rawValue,
                    label: Self.strengthLabel(viewModel.passwordStrength)
                )
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : HWMotion.easeOut.animation(.standard), value: viewModel.passwordStrength)
    }

    private var confirmPassword: some View {
        HWTextField(
            "registration.confirmPassword.label",
            text: Binding(
                get: { viewModel.confirmPassword },
                set: { viewModel.confirmPassword = $0; viewModel.clearFailure(for: .confirmPassword) }
            ),
            systemImage: "checkmark.shield",
            textContentType: .newPassword,
            error: RegistrationView.copy(for: viewModel.failure(for: .confirmPassword)),
            appearance: .brand,
            isSecure: true
        )
    }

    /// The Terms consent — a blocker, and the design flags the control itself rather than a message below it.
    ///
    /// The message is drawn as well: `flagCheck` in the design turns the checkbox red and puts the sentence in a
    /// toast, and a toast is not somewhere a VoiceOver user finds an error. So the sentence sits under the
    /// control, where every other failure on this form is.
    private var terms: some View {
        VStack(alignment: .leading, spacing: 7) {
            HWCheckbox(
                "registration.terms",
                isOn: Binding(
                    get: { viewModel.acceptedTerms },
                    set: { viewModel.acceptedTerms = $0; viewModel.clearFailure(for: .terms) }
                ),
                appearance: .brand
            )

            // **The two pages, as their own controls rather than links inside the sentence.** The design puts
            // them in the label's text; splitting them out is deliberate, on two grounds. A VoiceOver user
            // reaches a link that is its own element and cannot reach one buried in a checkbox's label. And a
            // localised string carrying markdown links would put a URL's position inside the translation, where
            // a translator can break it and nothing would notice (ADR-0011, ADR-0012).
            HStack(spacing: 18) {
                HWLink("registration.terms.terms", appearance: .brand) { openURL(viewModel.legal.terms) }
                HWLink("registration.terms.privacy", appearance: .brand) { openURL(viewModel.legal.privacy) }
                Spacer(minLength: 0)
            }
            .padding(.leading, 2)

            if let failure = viewModel.failure(for: .terms) {
                Text(RegistrationView.copy(for: failure) ?? ErrorCopy.generic)
                    .font(.hw(.caption))
                    .foregroundStyle(theme.palette.brand.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var submit: some View {
        HWButton("registration.one.action", appearance: .brand, systemImage: "arrow.forward") {
            viewModel.advance()
        }
        .background {
            // `.cta-glow` — a blurred sky pill behind the control, outside its own bounds, as on Landing.
            Capsule()
                .fill(theme.palette.brand.inkAccent)
                .blur(radius: 24)
                .opacity(0.5)
                .padding(.horizontal, 18)
                .padding(.top, 6)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Copy and mapping

    /// One country as a picker row — the design's config: the ISO code as the chip, the name, the dial code as
    /// meta, and all three searchable.
    static func option(for country: Country) -> HWPickerOption {
        HWPickerOption(
            id: country.code,
            name: country.name,
            leading: .code(country.code),
            meta: country.dialCode,
            // `(o.n + ' ' + o.c + ' ' + o.d)` — searching "971", "AE", or "Emirates" all find the same row.
            searchText: "\(country.name) \(country.code) \(country.dialCode)"
        )
    }

    /// The design's four `LEVELS` labels. `none` has no word, because an empty box has nothing to rate.
    static func strengthLabel(_ strength: PasswordStrength) -> LocalizedStringResource? {
        switch strength {
        case .none: nil
        case .weak: "registration.password.strength.weak"
        case .fair: "registration.password.strength.fair"
        case .good: "registration.password.strength.good"
        case .strong: "registration.password.strength.strong"
        }
    }
}

#if DEBUG
#Preview("Step 1 — empty") {
    RegistrationStepPreview { RegistrationDetailsStep(viewModel: .preview) }
}

#Preview("Step 1 — filled, with a strong password") {
    RegistrationStepPreview { RegistrationDetailsStep(viewModel: .previewFilledStepOne) }
}

#Preview("Step 1 — every field refused") {
    RegistrationStepPreview { RegistrationDetailsStep(viewModel: .previewFailedStepOne) }
}

#Preview("AX3 — the fields and the meter grow") {
    RegistrationStepPreview { RegistrationDetailsStep(viewModel: .previewFilledStepOne) }
        .dynamicTypeSize(.accessibility3)
}

#Preview("RTL") {
    RegistrationStepPreview { RegistrationDetailsStep(viewModel: .previewFilledStepOne) }
        .environment(\.layoutDirection, .rightToLeft)
}
#endif
