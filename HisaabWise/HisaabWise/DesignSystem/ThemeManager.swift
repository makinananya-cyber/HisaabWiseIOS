import Observation
import SwiftUI

/// The one place a screen asks for a colour, a font, or a curve.
///
/// It is `@Observable` and injected through `@Environment` rather than being a pile of static
/// constants, and that indirection buys exactly one thing: ADR-0001 ships light-only but is
/// *architected* for a dark palette, and with the manager in place that later palette is a
/// ``palette`` swap instead of a search through every screen. Today there is one palette, and saying
/// so is more honest than pretending the abstraction is already earning its keep.
///
/// It holds no `Color` literals — every value comes from the asset catalogue, and a source scan in
/// `LayeringTests` keeps it that way.
@MainActor
@Observable
final class ThemeManager {
    private(set) var palette: HWPalette
    let motion: HWMotion

    init(palette: HWPalette = .standard, motion: HWMotion = .standard) {
        self.palette = palette
        self.motion = motion
    }

    func font(_ style: HWTextStyle) -> Font {
        style.font
    }

    /// The palette swap ADR-0001 promises, as a method.
    ///
    /// It has no caller yet, and it is here anyway: `@Observable` on a type whose properties can never
    /// change is decoration. This is the mutation the macro exists to broadcast, and the reason a
    /// second palette needs no new type.
    func apply(_ palette: HWPalette) {
        self.palette = palette
    }
}

extension View {
    /// Injects the theme. The composition root calls this; previews and tests call it to get the
    /// standard one without ceremony.
    func hwTheme(_ theme: ThemeManager = ThemeManager()) -> some View {
        environment(theme)
    }
}
