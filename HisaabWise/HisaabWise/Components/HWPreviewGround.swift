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

    var body: some View {
        theme.palette.surface.background.ignoresSafeArea()
    }
}
#endif
