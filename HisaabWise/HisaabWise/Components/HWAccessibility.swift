import SwiftUI

/// The minimum size of anything a finger has to hit.
///
/// The design draws several controls smaller than this — `.iconbtn` at 40, `.mchip` at roughly 34 — and
/// they are all raised to 44 here. ADR-0012 makes the Accessibility Inspector a **per-screen gate**, so a
/// control that fails it fails the screen; four points of fidelity is the cheaper thing to give up.
///
/// It is named for the rule rather than for the control that first needed it, so that a component asking
/// for it is not asking "how big is the icon button".
enum HWTouchTarget {
    static let minimum: CGFloat = 44
}

extension View {
    /// The trait pair every selectable component carries.
    ///
    /// The design marks the current choice with colour alone — `.mchip.on`, `.srow.sel`, `.opt.sel`,
    /// `.key-row.on` — and colour reaches VoiceOver not at all. Adding `.isSelected` beside `.isButton` is
    /// what makes the selection audible, and it is one call so that four components cannot disagree about
    /// whether they bothered (ADR-0012).
    func hwSelectionTraits(isSelected: Bool) -> some View {
        accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
