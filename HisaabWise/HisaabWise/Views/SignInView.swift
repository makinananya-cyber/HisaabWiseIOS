import SwiftUI

/// Sign in, converted from the design's `auth` document.
///
/// The brand ground, the wordmark, a headline, two fields, the "Keep me signed in" choice beside "Forgot
/// password?", the submit button, and a way to register. Same surface as Landing and the same reasons for not
/// being a ``BaseView``: no read, no ``LoadState``, and `brand` rather than the chrome's `surface` (ADR-0021).
///
/// **Three [FIX]es land here**, all Product Spec §3.2. The identifier is the **email**, because the design asks
/// for a username at sign-in and registration never collects one. The password rule is **8+**, where the
/// design's sign-in accepted 6 (invariant 4). And the failure copy is **identical whatever the reason**, so the
/// response cannot be used to find out which addresses are registered.
///
/// **It does not navigate on success.** `SessionCoordinator.signIn` flips `isSignedIn`, and `RootView` swaps
/// Landing for the shell (ADR-0026) — which is what "successful sign-in lands on Home" means here: one object
/// changes and the root follows it.
struct SignInView: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// **Made and held by this screen, not by the composition root**, which is the opposite of a tab's view
    /// model (issue #5) and is deliberate: a tab keeps its state across a switch away and back, while a pushed
    /// form should lose it when the form goes. Here that is a security property as much as a lifetime one — the
    /// password lives in this object, and popping the screen is what frees it.
    @State private var viewModel: SignInViewModel

    /// Where the two links go. Held as closures for the reason Landing's is: the routes belong to whoever owns
    /// the stack, and #15 and #16 are the screens behind them.
    let onForgotPassword: () -> Void
    let onRegister: () -> Void
    let onRestoreAccount: () -> Void

    /// - Parameter session: who signs in. Taken rather than read from `@Environment` so the screen can be built
    ///   over a coordinator on a fixture transport, which is the seam every test and preview here uses
    ///   (ADR-0013).
    init(
        session: SessionCoordinator,
        onForgotPassword: @escaping () -> Void,
        onRegister: @escaping () -> Void,
        onRestoreAccount: @escaping () -> Void
    ) {
        _viewModel = State(initialValue: SignInViewModel(session: session))
        self.onForgotPassword = onForgotPassword
        self.onRegister = onRegister
        self.onRestoreAccount = onRestoreAccount
    }

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

    private var bands: some View {
        VStack(spacing: 0) {
            HWMark(size: 34).hwEnters(step: 0, suppressed: reduceMotion)

            Spacer(minLength: 20)

            head.hwEnters(step: 1, suppressed: reduceMotion)

            Spacer(minLength: 22)

            form

            Spacer(minLength: 24)

            switchToRegister.hwEnters(step: 5, suppressed: reduceMotion)
        }
        .frame(maxWidth: .infinity)
    }

    /// `.head` — the title and the line under it.
    private var head: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text("signin.title.first")
                    .foregroundStyle(theme.palette.brand.ink)
                Text("signin.title.second")
                    // `.title em` — the same sky→venus wash Landing's headline carries.
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                theme.palette.brand.inkAccent,
                                theme.palette.brand.inkSecondary,
                                theme.palette.brand.inkAccent,
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
            .font(.hw(.title))
            .tracking(-0.5)

            Text("signin.subtitle")
                .font(.hw(.bodyLarge).weight(.regular))
                .foregroundStyle(theme.palette.brand.inkSecondary)
                .opacity(0.9)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - The form

    private var form: some View {
        VStack(spacing: 16) {
            HWTextField(
                "signin.email.label",
                // Editing a box clears the failure under it, so a corrected field stops being red while the
                // user is still typing rather than at the next submit.
                text: Binding(
                    get: { viewModel.email },
                    set: { viewModel.email = $0; viewModel.clearFailure(for: .email) }
                ),
                placeholder: "signin.email.placeholder",
                systemImage: "envelope",
                keyboardType: .emailAddress,
                textContentType: .emailAddress,
                error: Self.copy(for: viewModel.failure(for: .email)),
                appearance: .brand
            )
            .hwEnters(step: 2, suppressed: reduceMotion)

            HWTextField(
                "signin.password.label",
                text: Binding(
                    get: { viewModel.password },
                    set: { viewModel.password = $0; viewModel.clearFailure(for: .password) }
                ),
                systemImage: "lock",
                textContentType: .password,
                error: Self.copy(for: viewModel.failure(for: .password)),
                appearance: .brand,
                isSecure: true
            )
            .hwEnters(step: 3, suppressed: reduceMotion)

            choices.hwEnters(step: 3, suppressed: reduceMotion)

            submit.hwEnters(step: 4, suppressed: reduceMotion)

            if let failure = viewModel.formFailure {
                formFailure(failure)
            }

            if viewModel.suggestsSupport {
                // Three refusals in, and the screen offers a way out rather than repeating itself. The count is
                // the client's *hint*; the backoff is the server's (#14).
                Text("signin.error.support")
                    .font(.hw(.caption))
                    .foregroundStyle(theme.palette.brand.inkSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
        .animation(HWMotion.easeOut.animation(.standard), value: viewModel.failures)
        .animation(HWMotion.easeOut.animation(.standard), value: viewModel.suggestsSupport)
    }

    /// `.row` — the checkbox and the reset link, on one line.
    private var choices: some View {
        HStack(alignment: .firstTextBaseline) {
            HWCheckbox(
                "signin.keepSignedIn",
                isOn: Binding(get: { viewModel.keepMeSignedIn }, set: { viewModel.keepMeSignedIn = $0 }),
                appearance: .brand
            )

            Spacer(minLength: 12)

            HWLink("signin.forgot", appearance: .brand, action: onForgotPassword)
        }
    }

    private var submit: some View {
        HWButton(
            "signin.action",
            appearance: .brand,
            systemImage: "arrow.forward",
            state: viewModel.isSigningIn ? .inFlight : .ready
        ) {
            Task { await viewModel.signIn() }
        }
        .background {
            // `.cta-glow`, as on Landing: a blurred sky pill behind the control, outside its own bounds.
            Capsule()
                .fill(theme.palette.brand.inkAccent)
                .blur(radius: 24)
                .opacity(0.5)
                .padding(.horizontal, 18)
                .padding(.top, 6)
                .accessibilityHidden(true)
        }
    }

    /// The failures that belong to the form rather than to a box: offline, refused, pending deletion.
    @ViewBuilder
    private func formFailure(_ failure: SignInFailure) -> some View {
        VStack(spacing: 10) {
            Text(Self.copy(for: failure) ?? ErrorCopy.generic)
                .font(.hw(.body))
                .foregroundStyle(theme.palette.brand.danger)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            // **Pending deletion is a flow, not a sentence** (ADR-0015): the way out is offered rather than
            // described, and the restore screen is #24's.
            if failure == .pendingDeletion {
                HWLink("signin.pendingDeletion.action", appearance: .brand, action: onRestoreAccount)
            }
        }
        .frame(maxWidth: .infinity)
        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
    }

    /// `.switch` — the hairline, the prompt, and the way to register.
    private var switchToRegister: some View {
        VStack(spacing: 16) {
            // `.hairline` — a one-pixel gradient rule, decoration only.
            LinearGradient(
                colors: [.clear, theme.palette.brand.separator, .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 1)
            .accessibilityHidden(true)

            Text("signin.register.prompt")
                .font(.hw(.body))
                .foregroundStyle(theme.palette.brand.inkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HWButton("signin.register.action", variant: .ghost, appearance: .brand, action: onRegister)
        }
    }

    // MARK: - Copy

    /// The sentence for one failure. **The only place a `SignInFailure` becomes words**, so that "the copy never
    /// says whether the account exists" is one line to read rather than four to compare.
    static func copy(for failure: SignInFailure?) -> LocalizedStringResource? {
        switch failure {
        case nil: nil
        case .emailMissing: "signin.error.emailMissing"
        case .passwordMissing: "signin.error.passwordMissing"
        case .passwordTooShort: "signin.error.passwordTooShort"
        // One sentence for every refusal, whatever the server's reason. A "no account with that email" would
        // turn the form into an address checker (#14).
        case .credentialsRefused: "signin.error.refused"
        case .pendingDeletion: "signin.pendingDeletion.title"
        case .unreachable: "state.offline"
        // Not the server's prose: the code chooses the copy, through the one table that does that (ADR-0016).
        case .refused(let code): ErrorCopy.message(for: code)
        }
    }
}

#if DEBUG
#Preview("Sign in") {
    SignInView(
        session: .preview,
        onForgotPassword: {},
        onRegister: {},
        onRestoreAccount: {}
    )
    .hwTheme()
}

/// The refused state, reached the way a user reaches it: three real attempts through a coordinator whose
/// fixture answers `401`.
#Preview("Refused, three times over") {
    SignInView(session: .previewRefusing, onForgotPassword: {}, onRegister: {}, onRestoreAccount: {})
        .hwTheme()
}

#Preview("RTL") {
    SignInView(
        session: .preview,
        onForgotPassword: {},
        onRegister: {},
        onRestoreAccount: {}
    )
    .hwTheme()
    .hwLanguage(LanguageManager(selected: .arabic))
}

#Preview("AX5") {
    SignInView(
        session: .preview,
        onForgotPassword: {},
        onRegister: {},
        onRestoreAccount: {}
    )
    .hwTheme()
    .dynamicTypeSize(.accessibility5)
}
#endif
