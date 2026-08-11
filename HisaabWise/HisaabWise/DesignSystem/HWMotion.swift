import SwiftUI

/// One easing curve, as its four Bézier control points.
///
/// Stored as numbers rather than as a built `Animation` for two reasons: `Animation` cannot be read
/// back, so the design's values would be unassertable; and a curve is reusable across durations while
/// an `Animation` is not.
struct HWCurve: Sendable, Hashable {
    let p1x: Double
    let p1y: Double
    let p2x: Double
    let p2y: Double

    init(_ p1x: Double, _ p1y: Double, _ p2x: Double, _ p2y: Double) {
        self.p1x = p1x
        self.p1y = p1y
        self.p2x = p2x
        self.p2y = p2y
    }

    /// The four control points in CSS `cubic-bezier()` order, so a reader can compare them to the
    /// design's stylesheet without translating.
    var controlPoints: [Double] { [p1x, p1y, p2x, p2y] }

    /// Whether the curve passes its end value and settles back. True only of `easeBack`, where the
    /// overshoot *is* the effect — a y control point above 1 is what produces it.
    var overshoots: Bool { p1y > 1 || p2y > 1 }

    func animation(_ duration: HWDuration) -> Animation {
        .timingCurve(p1x, p1y, p2x, p2y, duration: duration.seconds)
    }

    /// An **ambient loop**, whose period is a number of seconds rather than an ``HWDuration`` step.
    ///
    /// The four durations are a *transition* scale — the design's 200/250/420/500ms clusters, collapsed so
    /// that a screen cannot pick 320 over 300 and call it a decision (ADR-0021). An ambient loop is a
    /// different measurement: the landing hero breathes over 6 seconds and the strapline's dot pulses over
    /// 2.2, and neither is a response to anything the user did. Rounding those into the transition scale
    /// would make them twitch.
    ///
    /// It is a separate method rather than a fifth duration so that the exception is visible at the call
    /// site: a transition passing seconds is going around the scale, and this signature says it is not one.
    func loop(seconds: Double) -> Animation {
        .timingCurve(p1x, p1y, p2x, p2y, duration: seconds)
    }
}

/// The design's easing curves, verbatim from its CSS custom properties.
struct HWMotion: Sendable, Hashable {
    /// `--ease-out`. The workhorse: most of the design's transitions use it.
    let easeOut: HWCurve
    /// `--ease-io`. Symmetric, for movements that come back.
    let easeInOut: HWCurve
    /// `--ease-back`. Overshoots and settles, for things that pop into place.
    ///
    /// The design carries two spellings of this one — `.34,1.4,.5,1` in five documents and
    /// `.34,1.5,.5,1` in `learn`. The majority value is used; the discrepancy is noted in ADR-0021
    /// rather than silently averaged.
    let easeBack: HWCurve

    static let standard = HWMotion(
        easeOut: HWCurve(0.16, 1, 0.3, 1),
        easeInOut: HWCurve(0.45, 0, 0.55, 1),
        easeBack: HWCurve(0.34, 1.4, 0.5, 1)
    )
}

extension HWMotion {
    static var easeOut: HWCurve { standard.easeOut }
    static var easeInOut: HWCurve { standard.easeInOut }
    static var easeBack: HWCurve { standard.easeBack }
}

/// How long a movement takes.
///
/// The design uses twenty-odd distinct durations; these are the four clusters they fall into, chosen
/// by frequency rather than by preference. Collapsing them is deliberate: a screen picking 320ms over
/// 300ms is noise, and noise is what makes a design system stop being one.
enum HWDuration: Sendable, CaseIterable {
    /// 180–220ms in the design. Feedback on a tap.
    case quick
    /// 250–320ms. The default.
    case standard
    /// 400–450ms. Something arriving that deserves to be noticed.
    case emphasised
    /// 500–600ms. A whole screen or sheet.
    case slow

    var seconds: Double {
        switch self {
        case .quick: 0.2
        case .standard: 0.25
        case .emphasised: 0.42
        case .slow: 0.5
        }
    }
}
