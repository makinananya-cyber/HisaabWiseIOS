import SwiftUI

/// The design's `.mark` — the HisaabWise logo on a milky tile.
///
/// `CONTEXT.md` recorded this as the one component the design specifies and the app could not draw: "the asset
/// catalogue carries colour sets only, so there is no image to draw". The design carries the logo as a base64
/// PNG in five places and it is now in the catalogue as `hwMark`, so the component exists — the privacy overlay
/// (ADR-0014) needed it, since "logo on solid galaxy" is what the overlay *is*.
///
/// **The tile is a light ground on both surfaces**, and it is load-bearing rather than decorative: the logo is
/// drawn in galaxy navy and greens, so it needs something light behind it wherever it lands.
///
/// **Which light, though, is the design's own difference, and ``HWTopBar`` is the caller that settled it.** The
/// note here used to say the argument was worth having once a second caller existed; it now does. On the galaxy
/// ground the design paints `--milky` with no border and the medium lift — a tile of the light ground, floating
/// on the dark one. In a `.topbar` on the light screens it paints
/// `background:var(--card);border:1px solid var(--line-2);box-shadow:var(--shadow-s)`: the *card* colour, a
/// hairline, and the small lift, because a milky tile on a milky ground is invisible and what marks it out there
/// is the border rather than the fill. So the appearance is a parameter, resolved once here, rather than two
/// callers each guessing which white they wanted (ADR-0001, ADR-0021).
///
/// The sizes are the design's own where it lays the mark out — 34 in a `.topbar`, 38 beside a title, 46 on
/// Landing — and ``PrivacyOverlay`` passes a larger one, because a mark alone on a screen is not in a layout.
struct HWMark: View {
    @Environment(ThemeManager.self) private var theme

    private let size: CGFloat
    /// Which of the design's two grounds the tile is sitting on (ADR-0021).
    private let appearance: HWAppearance

    /// - Parameter size: the logo's own edge, before the tile's padding. Defaults to the design's most common.
    /// - Parameter appearance: defaults to `brand`, which is where the mark was first drawn — the privacy
    ///   overlay and Landing. The four tab roots pass `surface` through ``HWTopBar``.
    init(size: CGFloat = 38, appearance: HWAppearance = .brand) {
        self.size = size
        self.appearance = appearance
    }

    private var isBrand: Bool { appearance == .brand }

    /// `--milky` on the dark ground, `--card` on the light one. See the note above.
    private var tile: Color {
        isBrand ? theme.palette.surface.background : theme.palette.surface.raised
    }

    /// `border:1px solid var(--line-2)` in a `.topbar`, and no border at all on the galaxy ground.
    private var border: Color? {
        isBrand ? nil : theme.palette.surface.separatorStrong
    }

    /// `--shadow-m` floating on the dark ground, `--shadow-s` sitting in a light header.
    private var elevation: HWShadow {
        isBrand ? .medium : .small
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
            .hwBox(fill: tile, radius: .medium, border: border, elevation: elevation)
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
            HWMark(size: 34, appearance: .surface)
            HWMark(appearance: .surface)
            HWMark(size: 46, appearance: .surface)
        }
    }
    .hwTheme()
}

/// The two tiles side by side on the ground each was drawn for — the milky tile floats, the card tile is held
/// by its hairline.
#Preview("Both grounds, each with its own tile") {
    VStack(spacing: 0) {
        ZStack {
            HWPreviewGround(appearance: .brand)
            HWMark(size: 46)
        }
        ZStack {
            HWPreviewGround()
            HWMark(size: 46, appearance: .surface)
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
