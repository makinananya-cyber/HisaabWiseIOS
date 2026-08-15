import SwiftUI

/// Recovery by security question — three steps on the brand ground.
///
/// **This is the only way back into an account.** There is no OTP and no email verification in this product, so
/// the two questions the reader chose at registration, plus their date of birth, are the whole of it. The
/// screen exists because the control that led here rendered "This screen is not built yet" while three finished
/// routes sat behind it — a reader who forgot their password had no way back in at all.
///
/// Same surface and the same reasons for not being a ``BaseView`` as ``SignInView``: no read on appear, no
/// ``LoadState``, and `brand` rather than the chrome's `surface` (ADR-0021).
///
/// **Both answer boxes are built by one loop over the questions the server sent.** That is not a stylistic
/// choice — hand-writing two structurally identical fields is exactly the shape that made the second box on
/// registration step 2 unfocusable, so the reader could not answer their second question and could not
/// register. Here the same mistake would lock somebody out of their own account. Keep it a `ForEach`.
struct ForgotPasswordView: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Made by the composition root and handed over, then held here: it carries two security answers, a date of
    /// birth and a new password, and popping the screen is what frees them.
    @State private var viewModel: ForgotPasswordViewModel

    /// Where "done" goes — back to sign-in, which is already underneath.
    let onFinished: () -> Void

    init(viewModel: ForgotPasswordViewModel, onFinished: @escaping () -> Void) {
        _viewModel = State(initialValue: viewModel)
        self.onFinished = onFinished
    }

    /// Every key this screen renders, asserted against the catalogue in one place because a key with nothing
    /// behind it shows the reader the key (ADR-0011).
    static let copyKeys = [
        "recovery.title",
        "recovery.email.heading",
        "recovery.email.blurb",
        "recovery.email.label",
        "recovery.email.action",
        "recovery.identity.heading",
        "recovery.identity.blurb",
        "recovery.identity.answer.label",
        "recovery.identity.dob.label",
        "recovery.identity.dob.placeholder",
        "recovery.identity.action",
        "recovery.password.heading",
        "recovery.password.blurb",
        "recovery.password.new.label",
        "recovery.password.confirm.label",
        "recovery.password.action",
        "recovery.done.heading",
        "recovery.done.blurb",
        "recovery.done.action",
        "recovery.support",
        "recovery.error.emailMissing",
        "recovery.error.answerMissing",
        "recovery.error.dateOfBirthMissing",
        "recovery.error.passwordMissing",
        "recovery.error.passwordTooShort",
        "recovery.error.passwordsDiffer",
        "recovery.error.identityRefused",
        "recovery.error.locked",
        "recovery.error.ticketExpired",
    ]

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                bands
                    .padding(.horizontal, 22)
                    .padding(.vertical, 26)
                    .frame(minHeight: proxy.size.height, alignment: .top)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(HWBrandGround())
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var bands: some View {
        VStack(alignment: .leading, spacing: 18) {
            HWMark(size: 30)
                .frame(maxWidth: .infinity)
                .hwEnters(step: 0, suppressed: reduceMotion)

            if viewModel.didReset {
                finished.hwEnters(step: 1, suppressed: reduceMotion)
            } else {
                stepCounter.hwEnters(step: 1, suppressed: reduceMotion)
                stage.hwEnters(step: 2, suppressed: reduceMotion)

                if let formFailure = viewModel.formFailure {
                    HWInfoNote(Self.copy(for: formFailure) ?? "recovery.error.identityRefused")
                }
                if viewModel.suggestsSupport {
                    HWInfoNote("recovery.support")
                }
            }

            Spacer(minLength: 0)
        }
    }

    /// "Step 2 of 3" — the same orientation the password wizard gives, because a reader three boxes into a
    /// recovery should be able to see how much is left.
    private var stepCounter: some View {
        // Strings, not Ints, so the catalogue key is `%@ %@` — the convention every other interpolated
        // key in this app follows. An `Int` makes the key `%lld %lld`, which is a different key with
        // nothing behind it, and a key with nothing behind it is what the reader sees (ADR-0011).
        Text("recovery.step \(String(viewModel.stage.rawValue + 1)) \(String(RecoveryStage.allCases.count))")
            .hwEyebrow(.brand)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    @ViewBuilder
    private var stage: some View {
        switch viewModel.stage {
        case .email: emailStep
        case .identity: identityStep
        case .newPassword: newPasswordStep
        }
    }

    // MARK: - Step one — who are you

    private var emailStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading("recovery.email.heading", "recovery.email.blurb")

            HWTextField(
                "recovery.email.label",
                text: Binding(
                    get: { viewModel.email },
                    set: { viewModel.email = $0; viewModel.clearFailure(for: .email) }
                ),
                systemImage: "envelope",
                keyboardType: .emailAddress,
                textContentType: .emailAddress,
                error: Self.copy(for: viewModel.failure(for: .email)),
                appearance: .brand
            )

            action("recovery.email.action") { await viewModel.lookUpQuestions() }
        }
    }

    // MARK: - Step two — prove it

    private var identityStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading("recovery.identity.heading", "recovery.identity.blurb")

            // **A loop with an identity per row.** See the type's note: two hand-written sibling fields is the
            // shape that made an answer box unfocusable on registration.
            ForEach(Array(viewModel.questions.enumerated()), id: \.element.id) { index, question in
                VStack(alignment: .leading, spacing: 7) {
                    // The question is **server content** in the reader's language, so it is drawn verbatim and
                    // the field's label is the catalogue's "Your answer".
                    Text(verbatim: question.text)
                        .hwLabel(.brand)
                        .fixedSize(horizontal: false, vertical: true)

                    HWTextField(
                        "recovery.identity.answer.label",
                        text: Binding(
                            get: { viewModel.answers.indices.contains(index) ? viewModel.answers[index] : "" },
                            set: { typed in
                                guard viewModel.answers.indices.contains(index) else { return }
                                viewModel.answers[index] = typed
                                viewModel.clearFailure(for: .answers)
                            }
                        ),
                        systemImage: "checkmark.shield",
                        // The message goes under the first box only: the server does not say which answer
                        // missed, so repeating it under both would read as two separate refusals.
                        error: index == 0 ? Self.copy(for: viewModel.failure(for: .answers)) : nil,
                        appearance: .brand
                    )
                }
            }

            HWDateField(
                "recovery.identity.dob.label",
                date: Binding(
                    get: { viewModel.dateOfBirth },
                    set: { viewModel.dateOfBirth = $0; viewModel.clearFailure(for: .dateOfBirth) }
                ),
                // **The same span registration offers**, from the one place that computes it. A recovery form
                // whose window disagreed with the sign-up form's would refuse a date the account was made with.
                in: RegistrationViewModel.dateOfBirthRange(),
                placeholder: "recovery.identity.dob.placeholder",
                error: Self.copy(for: viewModel.failure(for: .dateOfBirth))
            )

            action("recovery.identity.action") { await viewModel.verifyIdentity() }
        }
    }

    // MARK: - Step three — a new password

    private var newPasswordStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading("recovery.password.heading", "recovery.password.blurb")

            HWTextField(
                "recovery.password.new.label",
                text: Binding(
                    get: { viewModel.newPassword },
                    set: { viewModel.newPassword = $0; viewModel.clearFailure(for: .newPassword) }
                ),
                systemImage: "lock",
                textContentType: .newPassword,
                error: Self.copy(for: viewModel.failure(for: .newPassword)),
                appearance: .brand,
                isSecure: true
            )

            HWTextField(
                "recovery.password.confirm.label",
                text: Binding(
                    get: { viewModel.confirmPassword },
                    set: { viewModel.confirmPassword = $0; viewModel.clearFailure(for: .confirmPassword) }
                ),
                systemImage: "checkmark.shield",
                textContentType: .newPassword,
                error: Self.copy(for: viewModel.failure(for: .confirmPassword)),
                appearance: .brand,
                isSecure: true
            )

            action("recovery.password.action") { await viewModel.resetPassword() }
        }
    }

    // MARK: - Done

    /// **It does not sign the reader in.** A recovery revokes every family, including whoever else was in the
    /// account, so signing this device straight back in would be the one exception to a rule that should not
    /// have one. They go to the form and use the password they just chose.
    private var finished: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading("recovery.done.heading", "recovery.done.blurb")

            HWButton("recovery.done.action", appearance: .brand, systemImage: "arrow.forward") {
                onFinished()
            }
        }
    }

    // MARK: - Chrome

    private func heading(
        _ title: LocalizedStringResource,
        _ blurb: LocalizedStringResource
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.hw(.heading))
                .foregroundStyle(theme.palette.brand.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Text(blurb)
                .font(.hw(.body))
                .foregroundStyle(theme.palette.brand.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func action(
        _ key: LocalizedStringResource,
        perform: @escaping () async -> Void
    ) -> some View {
        HWButton(
            key,
            appearance: .brand,
            systemImage: "arrow.forward",
            // A busy control is not an unavailable one: the label becomes a spinner and the button keeps its
            // shape, so a slow request does not look like a dead one.
            state: viewModel.isWorking ? .inFlight : .ready
        ) {
            Task { await perform() }
        }
    }

    /// A failure as copy. **One place**, so a code becomes a sentence exactly once (ADR-0016).
    static func copy(for failure: RecoveryFailure?) -> LocalizedStringResource? {
        switch failure {
        case nil: nil
        case .emailMissing: "recovery.error.emailMissing"
        case .answerMissing: "recovery.error.answerMissing"
        case .dateOfBirthMissing: "recovery.error.dateOfBirthMissing"
        case .passwordMissing: "recovery.error.passwordMissing"
        case .passwordTooShort: "recovery.error.passwordTooShort"
        case .passwordsDiffer: "recovery.error.passwordsDiffer"
        case .identityRefused: "recovery.error.identityRefused"
        case .locked: "recovery.error.locked"
        case .ticketExpired: "recovery.error.ticketExpired"
        // Offline is never rendered as a fault (ADR-0016), and it shares the taxonomy's own copy.
        case .unreachable: "state.offline"
        case .refused: "state.failed.generic"
        }
    }
}

#if DEBUG
#Preview("Recovery — step one, the address") {
    ForgotPasswordView(viewModel: .preview) {}
        .hwTheme()
}

#Preview("Recovery — step two, the three factors") {
    @Previewable @State var model: ForgotPasswordViewModel?

    Group {
        if let model {
            ForgotPasswordView(viewModel: model) {}
        } else {
            // The questions arrive over a `FixtureTransport`, exactly as they do in the app (ADR-0013), so the
            // canvas shows the real loaded state rather than a fabricated one.
            Color.clear.task { model = await .previewOnIdentityStep() }
        }
    }
    .hwTheme()
}

#Preview("RTL — Arabic mirrors the whole form") {
    ForgotPasswordView(viewModel: .preview) {}
        .hwTheme()
        .hwLanguage(LanguageManager(selected: .arabic))
}

#Preview("AX5 — the boxes grow and the form still reads in order") {
    ForgotPasswordView(viewModel: .preview) {}
        .hwTheme()
        .dynamicTypeSize(.accessibility5)
}
#endif
