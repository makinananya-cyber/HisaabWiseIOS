import SwiftUI

/// The design's `.link` — a word that acts, with no box around it.
///
/// "Forgot password?" is the first one (#14). It is deliberately **not** `HWButton(variant: .quiet)`: that is a
/// full-width bordered control, and the design's `.link` is inline text at 13px. Two different shapes doing two
/// different jobs, so two entries rather than one stretched over both.
///
/// The design's hover underline does not ship — there is no hover on a phone — but the **44pt target does**:
/// 13pt text is a third of a finger, and `HWTouchTarget.minimum` is the rule that makes the Accessibility
/// Inspector's per-screen gate passable (ADR-0012).
struct HWLink: View {
    @Environment(ThemeManager.self) private var theme

    private let title: LocalizedStringResource
    private let appearance: HWAppearance
    private let action: () -> Void

    init(
        _ title: LocalizedStringResource,
        appearance: HWAppearance = .surface,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.appearance = appearance
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.hw(.body).weight(.semibold))
                .foregroundStyle(ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: HWTouchTarget.minimum)
                .contentShape(.rect)
        }
        .buttonStyle(HWPressStyle.compact)
        // The title is the label; a link needs nothing else said about it. The button trait comes from `Button`.
        .accessibilityLabel(Text(title))
    }

    /// `.link{color:var(--sky)}` on brand; the accent in-app.
    private var ink: Color {
        appearance == .brand ? theme.palette.brand.inkAccent : theme.palette.accent.base
    }
}

#if DEBUG
#Preview("On brand, where the design draws it") {
    ZStack {
        HWPreviewGround(appearance: .brand)
        HWLink("Forgot password?", appearance: .brand) {}
    }
    .hwTheme()
}

#Preview("On the in-app surface") {
    ZStack {
        HWPreviewGround()
        HWLink("Forgot password?") {}
    }
    .hwTheme()
}

#Preview("AX3 — it grows rather than truncating") {
    HWLink("Forgot password?", appearance: .brand) {}
        .padding()
        .dynamicTypeSize(.accessibility3)
        .background(HWPreviewGround(appearance: .brand))
        .hwTheme()
}

#Preview("RTL") {
    HWLink("Forgot password?", appearance: .brand) {}
        .padding()
        .environment(\.layoutDirection, .rightToLeft)
        .background(HWPreviewGround(appearance: .brand))
        .hwTheme()
}
#endif
