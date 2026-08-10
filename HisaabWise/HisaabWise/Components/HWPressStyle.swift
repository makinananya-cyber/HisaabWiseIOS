import SwiftUI

/// The press feedback every tappable component shares.
///
/// The design gives almost every control the same gesture — `transform:scale(.94…​.985)` on `:active`,
/// eased with `--ease-out` — so it is written once here rather than picked separately by a button, a
/// chip, a row, and a sheet row. The scales cluster in two places, which is why there is a default and
/// one ``compact`` override rather than a value per control.
///
/// **Reduce Motion replaces the scale rather than dropping it** (ADR-0012): the control dips in opacity
/// instead, so a motion-sensitive user still gets confirmation that the tap landed. Removing the
/// feedback outright is the failure this style exists to prevent — in one place, for every control.
struct HWPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The design's `:active` scale for full-width controls.
    let pressedScale: CGFloat

    /// Written out rather than left to the memberwise initialiser, which the `@Environment` property
    /// above would make `private`.
    init(pressedScale: CGFloat = 0.97) {
        self.pressedScale = pressedScale
    }

    /// The scale the design gives its small controls — the icon button, the chip, a sheet row.
    static let compact = HWPressStyle(pressedScale: 0.94)

    /// What the scale becomes under Reduce Motion. Not a fade-out: the control stays legible while it
    /// acknowledges the tap.
    static let pressedOpacity: Double = 0.72

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed

        return configuration.label
            .scaleEffect(reduceMotion || !pressed ? 1 : pressedScale)
            .opacity(reduceMotion && pressed ? Self.pressedOpacity : 1)
            .animation(HWMotion.easeOut.animation(.quick), value: pressed)
    }
}
