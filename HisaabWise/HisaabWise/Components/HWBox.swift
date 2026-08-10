import SwiftUI

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
    func hwBox(
        fill: some ShapeStyle,
        radius: HWRadius,
        border: Color? = nil,
        borderWidth: CGFloat = 1,
        elevation: HWShadow? = nil
    ) -> some View {
        background(fill, in: .rect(cornerRadius: radius.points))
            .overlay {
                if let border {
                    RoundedRectangle(cornerRadius: radius.points)
                        .strokeBorder(border, lineWidth: borderWidth)
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
