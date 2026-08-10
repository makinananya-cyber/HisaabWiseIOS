import SwiftUI

/// Corner radii, from the design's `border-radius` values.
///
/// The design uses **29 distinct radii between 2 and 46pt**; these are the clusters. Same reasoning as
/// the type scale: an 11 where a sibling uses 12 is noise a design system exists to remove.
enum HWRadius: Sendable, CaseIterable {
    /// 2–4pt. Bars, meter tracks, hairline chips.
    case hairline
    /// 10–13pt. Fields, small chips.
    case small
    /// 14–17pt. Cards, rows.
    case medium
    /// 18pt. The design's most-used card radius.
    case large
    /// 24pt. Sheets.
    case extraLarge
    /// Fully rounded. The design's 30 / 38 / 46pt radii are all pill-shaped controls whose radius is
    /// really "half my height" — 22 uses between them, and a fixed number would only be a pill at one
    /// height. SwiftUI clamps a corner radius to half the smaller dimension, so an absurd value is the
    /// idiom; `Capsule()` is equivalent where the shape is standalone.
    case pill

    var points: CGFloat {
        switch self {
        case .hairline: 3
        case .small: 11
        case .medium: 14
        case .large: 18
        case .extraLarge: 24
        case .pill: 999
        }
    }
}

extension View {
    func hwCornerRadius(_ radius: HWRadius) -> some View {
        clipShape(.rect(cornerRadius: radius.points))
    }
}
