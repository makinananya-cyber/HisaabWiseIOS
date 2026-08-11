import SwiftUI

/// Registration, converted from the design's three `view-reg1/2/3` sections.
///
/// **Three screens, one request** — the [FIX] this ticket exists for. The design walks the user through details,
/// money, and a goal, and the client holds all of it until the last button: nothing is created server-side until
/// then, so there is no half-built account to resume, clean up, or accidentally sign in to. Which also settles
/// where an email collision is discovered — at the end, sending the user back to step 1 — because an
/// availability check partway through would be an endpoint that answers "does this person have an account" to
/// anybody who asks.
///
/// **One screen, not three pushed screens.** The design cross-fades the three `.view`s inside one `.stage` and
/// keeps the wordmark, the headline, and the step bar above them. A `NavigationStack` of three would give each
/// step its own back gesture and its own lifetime — and a swipe-back that discarded a step's typing is exactly
/// the failure the atomic submit is designed around. So the step is state, and `goBack()` is the only way
/// backwards.
///
/// Same surface and the same non-``BaseView`` reasoning as sign-in: `brand` rather than the chrome's `surface`
/// (ADR-0021), and no ``LoadState`` because this screen writes. The **reference lists** it reads are the one
/// exception, and they are not a `LoadState` either: they are three cacheable content resources, and what a
/// screen does when they are missing is offer a retry rather than render an empty form (ADR-0009).
struct RegistrationView: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The app's locale, not the device's — `hwLanguage(_:)` set it at the root, and `HWAnnouncement` resolves
    /// its copy against whatever is passed rather than reading a locale of its own (ADR-0011).
    @Environment(\.locale) private var locale

    /// Made and held here, like sign-in's and for the stronger version of the same reason: this object holds a
    /// password, two security answers, a date of birth, and a salary. Popping the screen is what frees them.
    @State private var viewModel: RegistrationViewModel

    /// Back to sign-in — the design's `#go-signin`. The route belongs to whoever owns the stack.
    let onSignIn: () -> Void

    /// - Parameter viewModel: built by the composition root, which is the only thing that can — the form needs
    ///   the session *and* the content loader, and `LayeringTests` keeps both out of `Views/`. Wrapped in
    ///   `@State`, so the instance that survives is the first one: this initialiser runs on every re-render of
    ///   the enclosing `navigationDestination`, and a form that took the newest object each time would reset
    ///   itself as the user typed.
    init(viewModel: RegistrationViewModel, onSignIn: @escaping () -> Void) {
        _viewModel = State(initialValue: viewModel)
        self.onSignIn = onSignIn
    }

    /// The design's three steps, so the dots and the label are counted rather than spelled.
    static let stepCount = RegistrationStep.allCases.count

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
        // The lists are asked for once per visit to the screen. `.task` rather than `onAppear`, so a screen the
        // user leaves mid-fetch cancels the request instead of resolving into an object nobody is looking at.
        .task { await viewModel.loadReferenceLists() }
        // Moving between steps says where the user now is. A step change is a *screen* change as far as a
        // screen reader is concerned, and nothing else on the page says so out loud — the dots are decoration
        // and the label is not focused (ADR-0012). `.immediate`, because it is feedback about the button the
        // user has just pressed.
        .onChange(of: viewModel.step) { _, step in
            HWAnnouncement.post(Self.stepLabel(step), in: locale, priority: .immediate)
        }
        // **And a refusal says why.** Pressing Register, Next, or Submit with something wrong changes nothing a
        // screen reader would notice: the screen does not move, every per-field message is a static element the
        // user would have to go looking for, and the form-level one sits *below* the button they are standing on.
        // So the first failure is spoken, at the moment it is produced. `.immediate`, because it is feedback about
        // the button just pressed and an answer that arrives after the user has moved on is worse than silence.
        //
        // Here rather than in the three steps: `failures` is the form's, all three write into it, and one owner
        // means a step added later cannot forget.
        .onChange(of: viewModel.failures) { _, failures in
            guard let first = failures.first, let copy = Self.copy(for: first) else { return }
            HWAnnouncement.post(copy, in: locale, priority: .immediate)
        }
    }

    private var bands: some View {
        VStack(spacing: 0) {
            HWMark(size: 34).hwEnters(step: 0, suppressed: reduceMotion)

            Spacer(minLength: 20)

            head.hwEnters(step: 1, suppressed: reduceMotion)

            Spacer(minLength: 22)

            stepBar.hwEnters(step: 2, suppressed: reduceMotion)

            Spacer(minLength: 18)

            if viewModel.hasReferenceLists {
                step
            } else {
                listsMissing
            }

            if viewModel.step == .one {
                Spacer(minLength: 24)
                switchToSignIn.hwEnters(step: 6, suppressed: reduceMotion)
            }
        }
        .frame(maxWidth: .infinity)
        // The step change is a cross-fade in the design (`.view.is-in`), which is what a `.transition` on a
        // replaced subtree gives — and under Reduce Motion the same replacement without the slide (ADR-0012).
        .animation(reduceMotion ? nil : HWMotion.easeOut.animation(.standard), value: viewModel.step)
    }

    /// `.head` — the title and the line under it, both of which change with the step.
    private var head: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(Self.titleFirst(viewModel.step))
                    .foregroundStyle(theme.palette.brand.ink)
                Text(Self.titleSecond(viewModel.step))
                    // `.title em` — the same sky→venus wash Landing and sign-in carry.
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

            Text(Self.subtitle(viewModel.step))
                .font(.hw(.bodyLarge).weight(.regular))
                .foregroundStyle(theme.palette.brand.inkSecondary)
                .opacity(0.9)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var stepBar: some View {
        HWStepBar(
            stepCount: Self.stepCount,
            currentIndex: viewModel.step.rawValue - 1,
            label: Self.stepLabel(viewModel.step),
            backLabel: Self.backLabel(viewModel.step),
            // `nil` on the first step, where the design hides `.stepback` — there is nowhere back to go inside
            // the form, and the way out is the navigation stack's own back.
            onBack: viewModel.step == .one ? nil : { viewModel.goBack() }
        )
    }

    @ViewBuilder
    private var step: some View {
        switch viewModel.step {
        case .one:
            RegistrationDetailsStep(viewModel: viewModel)
        case .two:
            RegistrationMoneyStep(viewModel: viewModel)
        case .three:
            RegistrationGoalStep(viewModel: viewModel)
        }
    }

    /// What the screen shows instead of the form when the reference lists would not load.
    ///
    /// **Not a `LoadState`** (`StateTaxonomyTests`): the taxonomy belongs to a screen's one read, and this screen
    /// writes. It is also not a *field* error, because there is nothing to correct — so it gets the one thing
    /// that helps, which is a way to ask again.
    private var listsMissing: some View {
        VStack(spacing: 14) {
            // **The spinner is the default, and the failure needs a failure.** The screen's `.task` is what asks
            // for the lists and it runs *after* the first body evaluation, so for one frame the state is "three
            // empty lists and nothing attempted" — which was drawing "something went wrong · Try again", with a
            // Retry button a VoiceOver user could land on before anything had been tried.
            if let failure = viewModel.referenceFailure {
                Text(Self.copy(for: failure) ?? ErrorCopy.generic)
                    .font(.hw(.body))
                    .foregroundStyle(theme.palette.brand.inkSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                HWButton("registration.reference.retry", variant: .ghost, appearance: .brand) {
                    Task { await viewModel.loadReferenceLists() }
                }
            } else {
                ProgressView()
                    .tint(theme.palette.brand.inkAccent)
                    .accessibilityLabel(Text("state.loading"))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    /// `.switch` — the hairline, the prompt, and the way back to sign-in. Step 1 only, as the design draws it.
    private var switchToSignIn: some View {
        VStack(spacing: 16) {
            LinearGradient(
                colors: [.clear, theme.palette.brand.separator, .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 1)
            .accessibilityHidden(true)

            Text("registration.signIn.prompt")
                .font(.hw(.body))
                .foregroundStyle(theme.palette.brand.inkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HWButton("registration.signIn.action", variant: .ghost, appearance: .brand, action: onSignIn)
        }
    }

    // MARK: - Copy

    /// The step's own headline, subtitle, label, and back label — the design's `COPY` table, as four functions
    /// over the step rather than one dictionary, so a fourth step would fail to compile rather than render blank.
    static func titleFirst(_ step: RegistrationStep) -> LocalizedStringResource {
        switch step {
        case .one: "registration.one.title.first"
        case .two: "registration.two.title.first"
        case .three: "registration.three.title.first"
        }
    }

    static func titleSecond(_ step: RegistrationStep) -> LocalizedStringResource {
        switch step {
        case .one: "registration.one.title.second"
        case .two: "registration.two.title.second"
        case .three: "registration.three.title.second"
        }
    }

    static func subtitle(_ step: RegistrationStep) -> LocalizedStringResource {
        switch step {
        case .one: "registration.one.subtitle"
        case .two: "registration.two.subtitle"
        case .three: "registration.three.subtitle"
        }
    }

    /// `.steplab` — "Step 2 of 3", as three whole sentences rather than two numbers interpolated into one.
    ///
    /// There are exactly three, they never grow, and a language that counts differently — or writes the total
    /// first — gets to say so. Assembling it from `\(current) of \(total)` would save two catalogue entries and
    /// cost the translation its word order (ADR-0011).
    static func stepLabel(_ step: RegistrationStep) -> LocalizedStringResource {
        switch step {
        case .one: "registration.one.stepLabel"
        case .two: "registration.two.stepLabel"
        case .three: "registration.three.stepLabel"
        }
    }

    /// The design's own `aria-label`s on `.stepback`: "Back to your details", "Back to your money details".
    /// Step 1 has no back affordance, so its value is never drawn — and is still a real sentence rather than an
    /// empty string, because a label that exists only to satisfy a type is a label somebody will render.
    static func backLabel(_ step: RegistrationStep) -> LocalizedStringResource {
        switch step {
        case .one, .two: "registration.back.toDetails"
        case .three: "registration.back.toMoney"
        }
    }

    /// The sentence for a failure that belongs to the form rather than to a field.
    ///
    /// **The only place a `RegistrationFailure` becomes words**, shared by the three steps, so "a refusal never
    /// says more than the user can act on" is one table to read (ADR-0016).
    static func copy(for failure: RegistrationFailure?) -> LocalizedStringResource? {
        switch failure {
        case nil: nil
        case .nameMissing: "registration.error.nameMissing"
        case .emailInvalid: "registration.error.emailInvalid"
        case .emailTaken: "registration.error.emailTaken"
        case .phoneInvalid: "registration.error.phoneInvalid"
        case .dateOfBirthMissing: "registration.error.dateOfBirthMissing"
        // **The age is in the sentence, not interpolated into it.** Thirteen is a fixed rule, not a runtime
        // value, and a language that phrases an age differently gets a whole sentence to work with rather than
        // a number dropped into an English frame. `RegistrationCopyTests` asserts the copy still says the
        // number `minimumAge` holds, which is the drift interpolation would have prevented.
        case .tooYoung: "registration.error.tooYoung"
        case .passwordTooShort: "registration.error.passwordTooShort"
        case .passwordsDoNotMatch: "registration.error.passwordsDoNotMatch"
        case .termsNotAccepted: "registration.error.termsNotAccepted"
        case .salaryMissing: "registration.error.salaryMissing"
        case .firstQuestionMissing: "registration.error.firstQuestionMissing"
        case .firstAnswerMissing: "registration.error.firstAnswerMissing"
        case .secondQuestionMissing: "registration.error.secondQuestionMissing"
        case .secondQuestionRepeated: "registration.error.secondQuestionRepeated"
        case .secondAnswerMissing: "registration.error.secondAnswerMissing"
        case .goalMissing: "registration.error.goalMissing"
        case .unreachable: "state.offline"
        case .refused(let code): ErrorCopy.message(for: code)
        }
    }
}

#if DEBUG
#Preview("Registration — step 1") {
    RegistrationView(viewModel: .preview, onSignIn: {})
        .hwTheme()
}

#Preview("Registration — step 2, filled") {
    RegistrationView(viewModel: .previewOnStepTwo, onSignIn: {})
        .hwTheme()
}

#Preview("Registration — step 3, the goal") {
    RegistrationView(viewModel: .previewOnStepThree, onSignIn: {})
        .hwTheme()
}

/// The lists refused, which is the state the retry exists for.
#Preview("Registration — the reference lists would not load") {
    RegistrationView(viewModel: .previewWithoutReferenceLists, onSignIn: {})
        .hwTheme()
}

#Preview("RTL") {
    RegistrationView(viewModel: .preview, onSignIn: {})
        .hwTheme()
        .hwLanguage(LanguageManager(selected: .arabic))
}

#Preview("AX5") {
    RegistrationView(viewModel: .previewOnStepThree, onSignIn: {})
        .hwTheme()
        .dynamicTypeSize(.accessibility5)
}
#endif
