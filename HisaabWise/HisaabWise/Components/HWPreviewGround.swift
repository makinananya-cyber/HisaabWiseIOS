#if DEBUG
import SwiftUI

/// The ground a component preview sits on.
///
/// Cards, rows, and sheet rows are card-coloured, and a card-coloured control on the canvas's default
/// white background is a control you cannot see. This paints the `surface` ground the five in-app screens
/// use, so a preview shows the same contrast the screen will (ADR-0021).
///
/// Preview-only, and behind `#if DEBUG` so it never ships.
struct HWPreviewGround: View {
    @Environment(ThemeManager.self) private var theme

    /// Which of the two grounds the design ships (ADR-0021). Defaults to `surface`, the five in-app screens,
    /// which is what nearly every component preview wants.
    enum Appearance: Sendable {
        case surface
        case brand
    }

    var appearance: Appearance = .surface

    var body: some View {
        switch appearance {
        case .surface: theme.palette.surface.background.ignoresSafeArea()
        case .brand: theme.palette.brand.background.ignoresSafeArea()
        }
    }
}
#endif
