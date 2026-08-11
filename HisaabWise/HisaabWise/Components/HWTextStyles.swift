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
///
/// **Both take an appearance, and both have to** (ADR-0021). The colour is applied *inside* the modifier, so an
/// outer `.foregroundStyle` at the call site does not override it — the inner one wins. Four field components on
/// the galaxy ground each wrote that outer override and each got the surface's ink anyway, which read as a field
/// whose label could not be seen at all. Parameterising is the fix; the outer override never could have been.
struct HWLabelStyle: ViewModifier {
    @Environment(ThemeManager.self) private var theme

    let appearance: HWAppearance

    /// `--ink-2` on the light surface, and the design's `.input-wrap label` colour on the galaxy: `--sky` at the
    /// opacity the design gives it.
    private var ink: Color {
        appearance == .brand
            ? theme.palette.brand.inkAccent.opacity(0.9)
            : theme.palette.surface.inkSecondary
    }

    func body(content: Content) -> some View {
        content
            .font(.hw(.caption).weight(.bold))
            .tracking(0.4)
            .foregroundStyle(ink)
    }
}

/// `.eyebrow` — the tracked, upper-cased line above a title or at the top of a card.
///
/// The upper-casing is a `textCase` rather than upper-cased copy, so the String Catalogue keeps the
/// sentence as written and Arabic — which has no case — is unaffected (ADR-0011).
struct HWEyebrowStyle: ViewModifier {
    @Environment(ThemeManager.self) private var theme

    let appearance: HWAppearance

    /// `--universe` on the light surface. On the galaxy ground the design uses `--muted` for `.steplab` and
    /// `--sky` for `.st-rule`; `universe` is legible on both and is what the two share as a *role* — the tracked
    /// line that labels something rather than says it.
    private var ink: Color {
        appearance == .brand ? theme.palette.brand.inkSecondary : theme.palette.accent.muted
    }

    func body(content: Content) -> some View {
        content
            .font(.hw(.micro).weight(.bold))
            .tracking(1.3)
            .textCase(.uppercase)
            .foregroundStyle(ink)
    }
}

extension View {
    /// The design's `.fld-lab` — the small bold line that names a field or a value.
    func hwLabel(_ appearance: HWAppearance = .surface) -> some View {
        modifier(HWLabelStyle(appearance: appearance))
    }

    /// The design's `.eyebrow` — the tracked upper-case line above a title or at the top of a card.
    func hwEyebrow(_ appearance: HWAppearance = .surface) -> some View {
        modifier(HWEyebrowStyle(appearance: appearance))
    }
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

/// **The reason both roles take an appearance.** On the galaxy ground the surface's ink is very nearly the ground
/// itself, and the colour is applied inside the modifier — so a call site cannot correct it from outside.
#Preview("Both roles on the brand ground") {
    VStack(alignment: .leading, spacing: 18) {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: "Step 2 of 3").hwEyebrow(.brand)
            Text(verbatim: "Now the money bit.").font(.hw(.title))
        }
        Text(verbatim: "Monthly salary").hwLabel(.brand)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding()
    .background(HWPreviewGround(appearance: .brand))
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
