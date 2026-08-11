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

    var body: some View {
        switch Self.world(isSignedIn: session.isSignedIn) {
        case .shell:
            AppShell()
        case .landing:
            NavigationStack(path: $preAuth) {
                LandingView(viewModel: landing) { preAuth.append(.signIn) }
                    .navigationDestination(for: PreAuthRoute.self) { route in
                        switch route {
                        case .signIn: SignInPlaceholder()
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

/// Where Landing can go. One case today, and a `NavigationStack` path rather than a boolean so that
/// registration and password reset (#15, #16) are cases rather than a second mechanism.
enum PreAuthRoute: Hashable, Sendable, CaseIterable {
    case signIn
}

/// Sign in, until #14 writes it.
///
/// It exists so that **Get Started actually goes somewhere** — a call to action that did nothing would be the
/// third dead button in this repo, and the criterion is that it navigates to sign-in. On `brand`, because Auth
/// is a brand screen (ADR-0021), and reusing the placeholder sentence the unwritten tabs use so there is one
/// string to delete rather than two.
private struct SignInPlaceholder: View {
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
    RootView()
        .environment(SessionCoordinator.preview)
        .environment(TabViewModels(home: .previewINRSalary))
        .hwTheme()
}

/// Signed in, which in a preview means a coordinator that has actually been through `signIn` — there is no way
/// to set `isSignedIn` from outside, deliberately (ADR-0007).
#Preview("Signed in — the shell") {
    RootView()
        .environment(SessionCoordinator.previewSignedIn)
        .environment(TabViewModels(home: .previewINRSalary))
        .hwTheme()
}

#Preview("RTL") {
    RootView()
        .environment(SessionCoordinator.preview)
        .environment(TabViewModels(home: .previewINRSalary))
        .hwTheme()
        .hwLanguage(LanguageManager(selected: .arabic))
}

#Preview("AX5") {
    RootView()
        .environment(SessionCoordinator.preview)
        .environment(TabViewModels(home: .previewINRSalary))
        .hwTheme()
        .dynamicTypeSize(.accessibility5)
}
#endif
