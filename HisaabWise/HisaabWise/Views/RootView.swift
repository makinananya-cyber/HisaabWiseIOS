import SwiftUI

/// Which of the app's two worlds is on screen: the five tabs, or Landing.
///
/// One branch, on one object. `SessionCoordinator.isSignedIn` is the whole condition, which is what makes "log
/// out returns to Landing" a consequence rather than a piece of navigation code — the sign-out clears the
/// session and this follows, so no screen has to know it is being dismissed.
///
/// **What is not here.** The privacy overlay and the `scenePhase` observer both live at the composition root
/// instead (see ``HisaabWiseApp``): `scenePhase` belongs to the scene, it already had one reader there for
/// ADR-0008's foreground sequence, and keeping this view free of it is what lets a test render the branch
/// deterministically. The earlier note on `HisaabWiseApp` said the shell would take both over; it takes over
/// neither, and the reason is worth more than the tidiness would have been.
struct RootView: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(SessionCoordinator.self) private var session

    /// Where a signed-out user is, before they are signed in. `@State`, because it is where the user is rather
    /// than something the app knows about them — and it is **emptied whenever the session changes**, which is
    /// not automatic: this view's identity outlives the branch, so the path would otherwise survive a sign-out.
    @State private var preAuth: [PreAuthRoute] = []

    /// Made here rather than in ``LandingView``'s `body` so the strapline it is showing survives a re-render
    /// (issue #5's reasoning, one screen smaller).
    @State private var landing = LandingViewModel(straplineCount: LandingView.straplines.count)

    /// How a registration form is built (#15).
    ///
    /// A closure rather than the form itself, because the form is **per visit**: it holds a password, two
    /// security answers, a date of birth, and a salary, and popping the screen is what frees them. And a closure
    /// rather than the objects it needs, because those are an `APIClient` and a `ContentLoader` — which
    /// `LayeringTests` keeps out of `Views/`, and rightly: a screen that could reach either is a screen that
    /// could fetch.
    let makeRegistrationViewModel: () -> RegistrationViewModel

    var body: some View {
        switch Self.world(isSignedIn: session.isSignedIn) {
        case .shell:
            AppShell()
        case .landing:
            NavigationStack(path: $preAuth) {
                LandingView(viewModel: landing) { preAuth.append(.signIn) }
                    .navigationDestination(for: PreAuthRoute.self) { route in
                        switch route {
                        case .signIn:
                            SignInView(
                                session: session,
                                onForgotPassword: { preAuth.append(.forgotPassword) },
                                onRegister: { preAuth.append(.register) },
                                onRestoreAccount: { preAuth.append(.restoreAccount) }
                            )
                        case .register:
                            RegistrationView(viewModel: makeRegistrationViewModel()) {
                                // "Sign in instead" — back to the screen already underneath rather than a second
                                // copy of it pushed on top, which is what appending `.signIn` would do.
                                preAuth.removeAll { $0 == .register }
                            }
                        // The two screens sign-in leads to that are still one ticket away each. A placeholder
                        // rather than a dead link, for the reason Get Started got a destination in #13.
                        case .forgotPassword, .restoreAccount:
                            UnwrittenBrandScreen()
                        }
                    }
            }
            // **Emptied whenever the session changes.** `@State` belongs to `RootView`, whose identity survives
            // the branch, so without this a sign-out would come back to Landing with sign-in still pushed on
            // top of it — and "the only exit is log out" would land the user somewhere they did not choose.
            .onChange(of: session.isSignedIn) { _, _ in preAuth.removeAll() }
        }
    }

    /// Which world the session puts on screen.
    ///
    /// Pulled out as a value for the reason `StatePresentation` and `PrivacyOverlay.covers(_:)` are: it is the
    /// one decision this view makes, and **it cannot be asserted through a render.** `ImageRenderer` draws
    /// neither a `TabView` nor a `NavigationStack` — both come back as the unsupported-view glyph, byte for
    /// byte identical — so a pixel comparison of the two branches compares two pictures of the same yellow
    /// square. Asserting the function says the thing the test is actually about.
    static func world(isSignedIn: Bool) -> RootWorld {
        isSignedIn ? .shell : .landing
    }
}

/// The two worlds the app has, as a value.
enum RootWorld: Sendable, Equatable, CaseIterable {
    /// The five tabs, behind sign-in.
    case shell
    /// Landing, and what a signed-out user can reach from it.
    case landing
}

/// Where a signed-out user can go, as a path rather than a set of booleans so that each new pre-auth screen is
/// a case rather than a second mechanism.
enum PreAuthRoute: Hashable, Sendable, CaseIterable {
    case signIn
    /// #15 — registration's three steps.
    case register
    /// #16 — request a password reset.
    case forgotPassword
    /// #24 — the way back from a pending deletion (ADR-0015).
    case restoreAccount
}

/// A pre-auth screen that has not been written yet — registration, password reset, restore.
///
/// It exists so that every control on sign-in **goes somewhere**: a link that did nothing would be the kind of
/// dead affordance this repo has now removed twice. On `brand`, because these are brand screens (ADR-0021), and
/// reusing the sentence the unwritten tabs use so there is one string to delete rather than four.
private struct UnwrittenBrandScreen: View {
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        Text("shell.unwritten.note")
            .font(.hw(.body))
            .foregroundStyle(theme.palette.brand.inkSecondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.palette.brand.background.ignoresSafeArea())
    }
}

#if DEBUG
#Preview("Signed out — Landing") {
    RootView(makeRegistrationViewModel: { .preview })
        .environment(SessionCoordinator.preview)
        .environment(TabViewModels(home: .previewINRSalary, expenses: .previewINR))
        .hwTheme()
}

/// Signed in, which in a preview means a coordinator that has actually been through `signIn` — there is no way
/// to set `isSignedIn` from outside, deliberately (ADR-0007).
#Preview("Signed in — the shell") {
    RootView(makeRegistrationViewModel: { .preview })
        .environment(SessionCoordinator.previewSignedIn)
        .environment(TabViewModels(home: .previewINRSalary, expenses: .previewINR))
        .hwTheme()
}

#Preview("RTL") {
    RootView(makeRegistrationViewModel: { .preview })
        .environment(SessionCoordinator.preview)
        .environment(TabViewModels(home: .previewINRSalary, expenses: .previewINR))
        .hwTheme()
        .hwLanguage(LanguageManager(selected: .arabic))
}

#Preview("AX5") {
    RootView(makeRegistrationViewModel: { .preview })
        .environment(SessionCoordinator.preview)
        .environment(TabViewModels(home: .previewINRSalary, expenses: .previewINR))
        .hwTheme()
        .dynamicTypeSize(.accessibility5)
}
#endif
