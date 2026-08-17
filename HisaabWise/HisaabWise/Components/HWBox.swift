import SwiftUI

/// The one broken outline the design draws, as a dash-and-gap pair.
///
/// `border-style:dashed` at 1.5px. A browser derives the pattern from the stroke width; SwiftUI wants it stated, so
/// 5 on and 4 off is the closest reading of what the design renders at that width — decided **here**, beside the
/// function that strokes it, because there are two callers: `.addline` (``HWButtonVariant/dashed``) and the empty
/// note (``HWEmptyNote``). It was a literal in each until review, one of them claiming to be the only one.
enum HWBorderDash {
    static let standard: [CGFloat] = [5, 4]
}

extension View {
    /// The rounded box the design draws nearly every control inside.
    ///
    /// `.btn`, `.iconbtn`, `.editbtn`, `.card`, `.mchip`, `.opt-chip`, `.ctrl`, `.toast`, `.row` — every
    /// one of them is a fill, an optional hairline border on the *same* radius, and an optional elevation.
    /// Written once here because the failure mode of writing it eight times is a border drawn on a radius
    /// that no longer matches its fill, which is invisible until it is not.
    ///
    /// Takes colours rather than reading the palette: the caller has already resolved a role, and a box
    /// that picked its own colour would be a second opinion about what the control is.
    /// - Parameter borderDash: the dash pattern, for the one control the design draws with a broken outline —
    ///   `.addline`'s `border:1.5px dashed`. `nil` is a solid stroke, which is every other control. It is a
    ///   parameter here rather than a second modifier because a dash is a property of *this* border: applying
    ///   it separately would mean drawing the stroke twice and hoping the two radii agreed, which is the
    ///   failure this function exists to prevent.
    /// - Parameter shine: a decorative layer drawn **on the fill and under the content**, clipped to the same
    ///   radius. `EmptyView` for every control but one — the design's `.btn-primary::before`, the light streak
    ///   that travels across the primary button. It is a slot here rather than an `.overlay` at the call site
    ///   for a reason the Simulator shows immediately: an overlay draws *over* the label, so the streak passes
    ///   across the words and washes them out, while the design's `::before` sits behind `.lbl`. Behind the
    ///   content is a place only this function can reach, because it owns the background.
    func hwBox<Shine: View>(
        fill: some ShapeStyle,
        radius: HWRadius,
        border: Color? = nil,
        borderWidth: CGFloat = 1,
        borderDash: [CGFloat]? = nil,
        elevation: HWShadow? = nil,
        @ViewBuilder shine: () -> Shine = { EmptyView() }
    ) -> some View {
        background {
            ZStack {
                Rectangle().fill(fill)
                shine()
            }
            // Clipped here rather than by the caller: the streak is a band wider and taller than the control,
            // and the radius it has to respect is this function's.
            .clipShape(.rect(cornerRadius: radius.points))
        }
        .overlay {
            if let border {
                RoundedRectangle(cornerRadius: radius.points)
                    .strokeBorder(
                        border,
                        style: StrokeStyle(lineWidth: borderWidth, dash: borderDash ?? [])
                    )
            }
        }
        .hwElevation(elevation)
    }

    /// Applies an elevation, or none where the design draws the control flat on the page.
    ///
    /// The optional is the point: `.btn-ghost` and `.btn-quiet` have no `box-shadow` at all, and
    /// `.btn[disabled]` drops the one it had. Expressing that as `nil` keeps the absence in the token
    /// rather than in an `if` at each call site.
    @ViewBuilder
    func hwElevation(_ shadow: HWShadow?) -> some View {
        if let shadow {
            hwShadow(shadow)
        } else {
            self
        }
    }
}
