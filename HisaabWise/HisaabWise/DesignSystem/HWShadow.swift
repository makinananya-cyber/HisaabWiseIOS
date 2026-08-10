import SwiftUI

/// One elevation level, from the design's `--shadow-s` / `-m` / `-l`.
///
/// Two conversions happen on the way in, and both change the number:
///
/// - **CSS blur is roughly twice SwiftUI's shadow radius.**
/// - **CSS spread has no SwiftUI equivalent**, and every one of these shadows uses a *negative* spread
///   to pull the shadow in. Dropping it outright would make each shadow materially larger and darker
///   than drawn, so it is folded into the radius instead: `radius = (blur + spread) / 2`.
///
/// So `--shadow-m: 0 12px 28px -12px` gives `(28 - 12) / 2 = 8`, not 14.
/// `Equatable` so that a component's resolved appearance can be compared as a value — which is what
/// makes "no two button variants draw identically" a test rather than a screenshot (issue #26).
struct HWShadow: Sendable, Equatable {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

extension HWShadow {
    /// `--shadow-s: 0 2px 8px -2px rgba(8,31,92,.10)`
    static let small = HWShadow(color: .hwInk.opacity(0.10), radius: 3, x: 0, y: 2)
    /// `--shadow-m: 0 12px 28px -12px rgba(8,31,92,.24)`
    static let medium = HWShadow(color: .hwInk.opacity(0.24), radius: 8, x: 0, y: 12)
    /// `--shadow-l: 0 26px 60px -24px rgba(8,31,92,.42)`
    static let large = HWShadow(color: .hwInk.opacity(0.42), radius: 18, x: 0, y: 26)
}

extension View {
    func hwShadow(_ shadow: HWShadow) -> some View {
        self.shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
    }
}
