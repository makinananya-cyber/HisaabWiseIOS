import SwiftUI

/// Where a signed-out user is, and what a log out returns to.
///
/// **This is a placeholder, and the real screen is issue #13** — the galaxy ground, the rotating straplines,
/// the wordmark, and the two calls to action. What is here is the part the shell needs in order to be
/// finishable: somewhere for ``RootView`` to go when nobody is signed in, on the right surface, so that the
/// session branch is real rather than commented out.
///
/// It is on `brand` and is **not** a ``BaseView`` conformance, which is ADR-0021: Landing and Auth sit on the
/// galaxy ground with a `danger` of their own, both appearances ship together, and the chrome paints
/// `surface`. Making that chrome appearance-agnostic is work for #13–#16, with two real callers to shape it.
///
/// **It offers no way in.** Sign-in is #14, and a button that could not sign anybody in would be worse than an
/// honest absence — so until that lands the app launches here and stays here, and the shell is reachable in
/// previews and tests. That is a known, temporary state of the repo rather than a defect in the shell.
struct LandingView: View {
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(spacing: 18) {
            // The design's Landing `.mark`, at the largest of its three sizes.
            HWMark(size: 46)

            Text("shell.unwritten.note")
                .font(.hw(.body))
                .foregroundStyle(theme.palette.brand.inkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.palette.brand.background.ignoresSafeArea())
        .accessibilityElement(children: .contain)
    }
}

#if DEBUG
#Preview("Landing — the placeholder #13 replaces") {
    LandingView().hwTheme()
}

#Preview("RTL") {
    LandingView()
        .hwTheme()
        .hwLanguage(LanguageManager(selected: .arabic))
}

#Preview("AX5") {
    LandingView()
        .hwTheme()
        .dynamicTypeSize(.accessibility5)
}
#endif
