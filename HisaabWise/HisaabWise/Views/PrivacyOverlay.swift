import SwiftUI

/// What the app-switcher gets to see instead of the user's salary.
///
/// ADR-0014 — the logo on solid `galaxy`, applied whenever the scene stops being active, **unconditionally
/// and with no setting**. Open decision O3's default is "keep screens free of secrets in the app-switcher
/// snapshot", and on this app that is not a no-op: Home *is* salary and spending.
///
/// **It is not an app lock.** Returning to the app requires no authentication — there is simply nothing to
/// read in the snapshot. That distinction is the reason this is nine lines rather than a subsystem, and it is
/// what makes O3's eventual app lock a gate in front of an existing overlay.
///
/// Two things it deliberately does not do, both asserted by `RootViewTests`:
///
/// - **It does not animate.** iOS takes the snapshot at `.inactive`, so a cross-fade would put a
///   half-transparent overlay — and therefore half a screen of figures — into the picture the system keeps.
///   The one place ADR-0012's replace-not-remove does not apply, because there is no motion to replace.
/// - **It asks for nothing.** No field, no biometry, no tap target.
struct PrivacyOverlay: View {
    @Environment(ThemeManager.self) private var theme

    /// Whether the overlay is up, as a function of the phase — so the rule is a value a test can check rather
    /// than a condition buried in a modifier.
    ///
    /// Anything but `.active`. `.inactive` is the phase that matters, because it is when the snapshot is
    /// taken; `.background` is covered for the same reason and for free, and "not active" is the honest
    /// spelling of the condition. iOS also passes through `.inactive` for permission prompts and share
    /// sheets, so the overlay flashes there too — accepted in ADR-0014, since `.background` is too late to
    /// help.
    static func covers(_ phase: ScenePhase) -> Bool {
        phase != .active
    }

    var body: some View {
        ZStack {
            theme.palette.brand.background
            // The design's `.mark`, which is the whole of what the switcher gets to see.
            HWMark(size: 64)
        }
        // Fills whatever it is given before it ignores the safe area. As an `.overlay` it is proposed the
        // size of the content it covers, and a `ZStack` that sized itself to the logo would leave the
        // figures around the logo showing.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }
}

extension View {
    /// Covers the content with ``PrivacyOverlay`` for every scene phase but `.active`.
    ///
    /// **The phase is passed in rather than read here**, and that is the point of the signature: `scenePhase`
    /// has one reader in this app — the composition root, which already had one for ADR-0008's foreground
    /// sequence — and passing it makes both halves of this rule testable. A modifier that read the environment
    /// itself could only be checked by whatever phase a renderer happened to be in.
    func hwPrivacyOverlay(covering phase: ScenePhase) -> some View {
        overlay {
            if PrivacyOverlay.covers(phase) {
                PrivacyOverlay()
            }
        }
    }
}

#if DEBUG
#Preview("The switcher's view of the app") {
    PrivacyOverlay().hwTheme()
}

/// What it is for, side by side: a figure, and the same view with the overlay up.
#Preview("Inactive — the figure is gone, not blurred") {
    Text(verbatim: "₹65,000")
        .font(.hw(.display))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .hwPrivacyOverlay(covering: .inactive)
        .hwTheme()
}

#Preview("RTL") {
    PrivacyOverlay()
        .hwTheme()
        .environment(\.layoutDirection, .rightToLeft)
}

#Preview("AX5 — a logo does not scale, and there is nothing else in it") {
    PrivacyOverlay()
        .hwTheme()
        .dynamicTypeSize(.accessibility5)
}
#endif
