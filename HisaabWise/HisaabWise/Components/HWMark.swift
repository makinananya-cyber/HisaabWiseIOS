import SwiftUI

/// The design's `.mark` — the HisaabWise logo on a milky tile.
///
/// `CONTEXT.md` recorded this as the one component the design specifies and the app could not draw: "the asset
/// catalogue carries colour sets only, so there is no image to draw". The design carries the logo as a base64
/// PNG in five places and it is now in the catalogue as `hwMark`, so the component exists — the privacy overlay
/// (ADR-0014) needed it, since "logo on solid galaxy" is what the overlay *is*.
///
/// **The tile is the light ground**, and it is load-bearing rather than decorative: the logo is drawn in galaxy
/// navy and greens, so on a galaxy ground it needs something light behind it. `surface.background` is the
/// design's `--milky` exactly — the role reads oddly on a brand screen and is right anyway, because what the
/// design paints there *is* the light ground as a tile. On the surface screens the design uses `--card`
/// (`surface.raised`) instead, a difference worth one argument when ``HWTopBar`` adopts this (#23's Account and
/// #17's Home are the two callers that would shape it) rather than a guess made now with one.
///
/// The sizes are the design's own where it lays the mark out — 34 in a `.topbar`, 38 beside a title, 46 on
/// Landing — and ``PrivacyOverlay`` passes a larger one, because a mark alone on a screen is not in a layout.
struct HWMark: View {
    @Environment(ThemeManager.self) private var theme

    private let size: CGFloat

    /// - Parameter size: the logo's own edge, before the tile's padding. Defaults to the design's most common.
    init(size: CGFloat = 38) {
        self.size = size
    }

    var body: some View {
        Image(.hwMark)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            // The design rounds the image inside the tile as well as the tile itself — `.mark img` carries
            // its own `border-radius`, two or three points tighter. Proportional rather than a token,
            // because it is a fraction of an image and not a corner of a control.
            .clipShape(.rect(cornerRadius: size * 0.24, style: .continuous))
            .padding(size * 0.07)
            .hwBox(fill: theme.palette.surface.background, radius: .medium, elevation: .medium)
            // One element, and it says the name rather than "image": the logo is the app's name written down,
            // so that is what it reads as (ADR-0012).
            .accessibilityElement()
            .accessibilityLabel(Text("shell.mark.accessibilityLabel"))
    }
}

#if DEBUG
#Preview("The mark, at the design's three sizes") {
    ZStack {
        HWPreviewGround()
        HStack(spacing: 20) {
            HWMark(size: 34)
            HWMark()
            HWMark(size: 46)
        }
    }
    .hwTheme()
}

#Preview("On the galaxy ground it was drawn for") {
    ZStack {
        HWPreviewGround(appearance: .brand)
        HWMark(size: 46)
    }
    .hwTheme()
}

#Preview("RTL — a logo does not mirror") {
    HWMark(size: 46)
        .environment(\.layoutDirection, .rightToLeft)
        .hwTheme()
}

#Preview("AX5 — and it does not scale either") {
    HWMark(size: 46)
        .dynamicTypeSize(.accessibility5)
        .hwTheme()
}
#endif
