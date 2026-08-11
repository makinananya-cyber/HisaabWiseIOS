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
    @Environment(SessionCoordinator.self) private var session

    var body: some View {
        if session.isSignedIn {
            AppShell()
        } else {
            LandingView()
        }
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
