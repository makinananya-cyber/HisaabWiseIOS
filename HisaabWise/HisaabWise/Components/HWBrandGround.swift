import SwiftUI

/// `.aurora` plus the ground under it — the galaxy radial gradient, two soft colour blobs, and the star field.
///
/// **A component because it has two callers**, which is the bar `CONTEXT.md` sets: the design's `landing` and
/// `auth` documents carry byte-identical `.aurora` blocks, so Landing (#13) drew it and sign-in (#14) is what
/// made it vocabulary. Registration and password reset (#15, #16) are the third and fourth.
///
/// Presentational and argument-free: it is a background, so there is nothing for a caller to configure and
/// nothing for it to know.
struct HWBrandGround: View {
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        aurora
    }

    /// `.aurora` — the ground, two soft colour blobs, and the star field, in that order.
    ///
    /// **`.grain` is the one layer that does not ship.** It is a 3%-opacity fractal-noise SVG tiled over the
    /// screen; SwiftUI has no `feTurbulence`, and the honest alternatives are a noise image asset or a
    /// hand-rolled `Canvas` of random dots. At 3% it is texture nobody can name, so it is dropped rather than
    /// approximated (ADR-0029).
    private var aurora: some View {
        ZStack {
            ground

            // `.blob--planetary` — 430pt, off the top-left corner, planetary fading to nothing at 68%.
            blob(
                colour: theme.palette.accent.base,
                opacity: 0.85,
                size: 430,
                alignment: .topLeading,
                offset: CGSize(width: -125, height: -155)
            )

            // `.blob--universe` — 450pt, off the bottom-right, the muted accent at just over half strength.
            blob(
                colour: theme.palette.accent.muted,
                opacity: 0.55,
                size: 450,
                alignment: .bottomTrailing,
                offset: CGSize(width: 155, height: 185)
            )

            stars
        }
        .ignoresSafeArea()
        // The whole band is decoration: the design marks it `aria-hidden` and so does this.
        .accessibilityHidden(true)
    }

    /// One `.blob` — a radial fade with the design's `blur(6px)` on top of it.
    private func blob(
        colour: Color,
        opacity: Double,
        size: CGFloat,
        alignment: Alignment,
        offset: CGSize
    ) -> some View {
        RadialGradient(
            stops: [
                .init(color: colour.opacity(opacity), location: 0),
                .init(color: colour.opacity(0), location: 0.68),
            ],
            center: .center,
            startRadius: 0,
            endRadius: size / 2
        )
        .frame(width: size, height: size)
        .blur(radius: 6)
        .offset(offset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }

    /// `.stars` — the design's eight `radial-gradient` dots, at its own fractions and its own three colours.
    ///
    /// Transcribed rather than randomised: a `Canvas` of random points would be a different star field on every
    /// launch, and these eight were placed. The `twinkle` loop they animate with is dropped — an opacity
    /// oscillation on a half-transparent 1.4pt dot is not something anybody sees.
    private var stars: some View {
        GeometryReader { proxy in
            ForEach(Self.starField.indices, id: \.self) { index in
                let star = Self.starField[index]
                Circle()
                    .fill(star.colour(theme.palette))
                    .frame(width: star.diameter, height: star.diameter)
                    .position(x: proxy.size.width * star.x, y: proxy.size.height * star.y)
            }
        }
        .opacity(0.5)
    }

    /// The design's `radial-gradient(125% 85% at 50% -10%, galaxy-lift, galaxy 52%, galaxy-deep)`.
    private var ground: some View {
        RadialGradient(
            stops: [
                .init(color: theme.palette.brand.backgroundLift, location: 0),
                .init(color: theme.palette.brand.background, location: 0.52),
                .init(color: theme.palette.brand.backgroundDeep, location: 1),
            ],
            // `at 50% -10%` — above the top edge, so the lift reads as a glow behind the wordmark.
            center: UnitPoint(x: 0.5, y: -0.1),
            startRadius: 0,
            endRadius: 620
        )
        .ignoresSafeArea()
    }

    /// One star: where it sits as a fraction of the screen, how big it is, and which of the three inks it is.
    ///
    /// A tiny type rather than a tuple so the palette role stays a role — a `Color` here would be a colour
    /// resolved before there is a theme to resolve it against.
    private struct Star: Sendable {
        /// Which of the brand's three inks the star is. A role rather than a `Color`, because a colour here
        /// would be resolved before there is a theme to resolve it against — and a `KeyPath` rather than a
        /// closure, so the whole thing stays `Sendable`.
        enum Ink: Sendable {
            case milky
            case sky
            case venus
        }

        let x: Double
        let y: Double
        let diameter: CGFloat
        let ink: Ink

        func colour(_ palette: HWPalette) -> Color {
            switch ink {
            case .milky: palette.brand.ink
            case .sky: palette.brand.inkAccent
            case .venus: palette.brand.inkSecondary
            }
        }
    }

    /// The eight stars, at the design's own fractions, sizes, and colours — milky, sky, venus, repeating.
    private static let starField: [Star] = [
        Star(x: 0.20, y: 0.12, diameter: 1.4, ink: .milky),
        Star(x: 0.68, y: 0.24, diameter: 1.2, ink: .sky),
        Star(x: 0.42, y: 0.38, diameter: 1.0, ink: .venus),
        Star(x: 0.84, y: 0.55, diameter: 1.6, ink: .milky),
        Star(x: 0.12, y: 0.62, diameter: 1.1, ink: .sky),
        Star(x: 0.56, y: 0.78, diameter: 1.3, ink: .venus),
        Star(x: 0.30, y: 0.88, diameter: 1.0, ink: .milky),
        Star(x: 0.90, y: 0.90, diameter: 1.2, ink: .sky),
    ]
}

#if DEBUG
#Preview("The brand ground") {
    HWBrandGround().hwTheme()
}

#Preview("With something on it, so the blobs read") {
    ZStack {
        HWBrandGround()
        HWMark(size: 46)
    }
    .hwTheme()
}

#Preview("RTL — a ground does not mirror, and is checked not to look as though it does") {
    HWBrandGround()
        .environment(\.layoutDirection, .rightToLeft)
        .hwTheme()
}

#Preview("AX5 — nothing here scales, deliberately") {
    HWBrandGround()
        .dynamicTypeSize(.accessibility5)
        .hwTheme()
}
#endif
