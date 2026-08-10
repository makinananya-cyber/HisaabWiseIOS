import SwiftUI

/// The design's two text roles that are not sizes.
///
/// `HWTextStyle` owns *how big* text is; these own the two recurring combinations of size, weight,
/// tracking, case, and colour that the design names as classes rather than as sizes:
///
/// | Design | Modifier | Rule |
/// |---|---|---|
/// | `.fld-lab` / `.info-lab` | ``SwiftUI/View/hwLabel()`` | 11.5px · 700 · `.4px` · `--ink-2` |
/// | `.eyebrow` / `.card-cap` | ``SwiftUI/View/hwEyebrow()`` | 11px · 700 · `1.3px` · uppercase · `--universe` |
///
/// They are modifiers rather than views so that a caller keeps its own `Text` — which is what lets a
/// screen pass a catalogue key and a card pass a server string through the same style.
struct HWLabelStyle: ViewModifier {
    @Environment(ThemeManager.self) private var theme

    func body(content: Content) -> some View {
        content
            .font(.hw(.caption).weight(.bold))
            .tracking(0.4)
            .foregroundStyle(theme.palette.surface.inkSecondary)
    }
}

/// `.eyebrow` — the tracked, upper-cased line above a title or at the top of a card.
///
/// The upper-casing is a `textCase` rather than upper-cased copy, so the String Catalogue keeps the
/// sentence as written and Arabic — which has no case — is unaffected (ADR-0011).
struct HWEyebrowStyle: ViewModifier {
    @Environment(ThemeManager.self) private var theme

    func body(content: Content) -> some View {
        content
            .font(.hw(.micro).weight(.bold))
            .tracking(1.3)
            .textCase(.uppercase)
            .foregroundStyle(theme.palette.accent.muted)
    }
}

extension View {
    /// The design's `.fld-lab` — the small bold line that names a field or a value.
    func hwLabel() -> some View { modifier(HWLabelStyle()) }

    /// The design's `.eyebrow` — the tracked upper-case line above a title or at the top of a card.
    func hwEyebrow() -> some View { modifier(HWEyebrowStyle()) }
}

#if DEBUG
#Preview("Label and eyebrow") {
    VStack(alignment: .leading, spacing: 18) {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: "Your account").hwEyebrow()
            Text(verbatim: "Settings").font(.hw(.title))
        }
        Text(verbatim: "Monthly income").hwLabel()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding()
    .hwTheme()
}

#Preview("AX3 — both roles scale") {
    VStack(alignment: .leading, spacing: 18) {
        Text(verbatim: "Your account").hwEyebrow()
        Text(verbatim: "Monthly income").hwLabel()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding()
    .dynamicTypeSize(.accessibility3)
    .hwTheme()
}

#Preview("RTL") {
    VStack(alignment: .leading, spacing: 18) {
        Text(verbatim: "حسابك").hwEyebrow()
        Text(verbatim: "الدخل الشهري").hwLabel()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding()
    .environment(\.layoutDirection, .rightToLeft)
    .hwTheme()
}
#endif
