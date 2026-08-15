import SwiftUI

/// The only way out of the app, and the question it asks first.
///
/// Issue #5 — "log out presents a confirmation dialog, then clears the session and returns to Landing". All
/// three halves are here: the control, the dialog, and the one call to `signOut()` in the presentation layers,
/// which `AppShellTests` asserts is the only one. A second caller would be a second exit, and it would not be
/// one anybody chose.
///
/// **The dialog is an `alert`, not the design's `.confirm` overlay and no longer a `confirmationDialog`.**
/// The design draws its own modal — scrim, dialog, icon, two buttons — and a system presentation is what a
/// destructive confirmation should be on iOS: the platform's own red, read correctly to VoiceOver, and not
/// dismissable by accident. The design's *copy* is converted verbatim, which is the part carrying the
/// decision: "Your data stays safe. You'll need your password to sign back in."
///
/// It was a `confirmationDialog` until this control was tested on a device, and that is the reason for the
/// change: a `confirmationDialog` renders as a **popover** in some presentations, and SwiftUI drops
/// `.cancel`-role buttons from a popover on the grounds that tapping outside dismisses it. The observed
/// result was a confirmation offering "Log out" and nothing else — no visible way to say no to the one
/// irreversible action in the app. An `alert` draws both buttons in every size class, so the way out of the
/// dialog is always on screen. Keep it an alert.
///
/// **The button is `HWButtonVariant.destructive`** since #23, which is the caller that shape was waiting for: the
/// design's `.logout` is a card-coloured control with a danger-tinted border and danger text, and it was `.soft`
/// while the vocabulary had no destructive entry. The dialog's confirm is destructive too, and there the colour is
/// the platform's.
///
/// It reads the session from the environment rather than taking a closure: what "log out" means is not a
/// decision a screen gets to make differently.
struct LogoutControl: View {
    @Environment(SessionCoordinator.self) private var session

    @State private var isConfirming = false

    /// Every key this control renders. Asserted against the String Catalogue in one place, because a key with
    /// nothing behind it shows the user the key (ADR-0011).
    static let copyKeys = [
        "shell.logout.action",
        "shell.logout.confirm.title",
        "shell.logout.confirm.message",
        "shell.logout.confirm.cancel",
    ]

    var body: some View {
        HWButton(
            "shell.logout.action",
            variant: .destructive,
            // `.forward`, not `.right`: the glyph mirrors with the layout and a named direction would not
            // (ADR-0011).
            systemImage: "rectangle.portrait.and.arrow.forward"
        ) {
            isConfirming = true
        }
        .alert(
            Text("shell.logout.confirm.title"),
            isPresented: $isConfirming
        ) {
            // The design spells the trigger "Log Out" and the confirm "Log out". One key, one spelling: two
            // strings that differ only in a capital letter are two strings to translate and one to get wrong.
            Button(role: .destructive) {
                Task { await session.signOut() }
            } label: {
                Text("shell.logout.action")
            }

            Button(role: .cancel) {} label: {
                Text("shell.logout.confirm.cancel")
            }
        } message: {
            Text("shell.logout.confirm.message")
        }
    }
}

#if DEBUG
#Preview("The way out") {
    VStack {
        Spacer()
        LogoutControl().padding(20)
    }
    .background(HWPreviewGround())
    .environment(SessionCoordinator.preview)
    .hwTheme()
}

#Preview("RTL — the glyph mirrors") {
    LogoutControl()
        .padding(20)
        .background(HWPreviewGround())
        .environment(SessionCoordinator.preview)
        .hwTheme()
        .hwLanguage(LanguageManager(selected: .arabic))
}

#Preview("AX5 — the control grows rather than clipping") {
    LogoutControl()
        .padding(20)
        .background(HWPreviewGround())
        .environment(SessionCoordinator.preview)
        .hwTheme()
        .dynamicTypeSize(.accessibility5)
}
#endif
