import SwiftUI
import UIKit
import Testing

@testable import HisaabWise

/// The token API every screen draws through.
///
/// These assert the *values*, not that a screen used them — a scan does that. What they protect is the
/// provenance: each number here came out of the design's CSS, and a nudge to any of them should be a
/// deliberate act with a failing test attached.
@Suite("Theme tokens")
@MainActor
struct ThemeTests {
    // MARK: - Motion

    /// The design's three curves, verbatim. Two are named in issue #6; there is a third — see the
    /// suite below.
    @Test("the easing curves carry the design's control points")
    func curvesMatchTheDesign() {
        #expect(HWMotion.easeOut.controlPoints == [0.16, 1, 0.3, 1])      // --ease-out
        #expect(HWMotion.easeInOut.controlPoints == [0.45, 0, 0.55, 1])   // --ease-io
        #expect(HWMotion.easeBack.controlPoints == [0.34, 1.4, 0.5, 1])   // --ease-back
    }

    @Test("ease-back overshoots and the other two do not")
    func onlyEaseBackOvershoots() {
        // The overshoot is the whole point of `--ease-back`; a y control point above 1 is what produces
        // it. If someone "tidies" it to 1.0 the curve silently becomes an ordinary ease.
        #expect(HWMotion.easeBack.overshoots)
        #expect(!HWMotion.easeOut.overshoots)
        #expect(!HWMotion.easeInOut.overshoots)
    }

    @Test("durations cover the design's four clusters")
    func durationsMatchTheDesign() {
        // The design uses 20-odd distinct durations; these are the clusters they fall into, taken by
        // frequency: 180-220, 250-320, 400-450, 500-600 ms.
        #expect(HWDuration.quick.seconds == 0.2)
        #expect(HWDuration.standard.seconds == 0.25)
        #expect(HWDuration.emphasised.seconds == 0.42)
        #expect(HWDuration.slow.seconds == 0.5)
    }

    @Test("a curve and a duration compose into an animation")
    func curvesProduceAnimations() {
        #expect(HWMotion.easeOut.animation(.standard) == HWMotion.easeOut.animation(.standard))
        #expect(HWMotion.easeOut.animation(.quick) != HWMotion.easeOut.animation(.slow))
        #expect(HWMotion.easeOut.animation(.quick) != HWMotion.easeInOut.animation(.quick))
    }

    // MARK: - Type scale

    @Test("the type scale has one step per cluster the design uses")
    func typeScaleIsComplete() {
        // Eight steps collapse the design's 30-plus half-pixel sizes. `allCases` exists so this cannot
        // drift without the test noticing.
        #expect(HWTextStyle.allCases.count == 8)
        #expect(HWTextStyle.allCases.first == .display)
        #expect(HWTextStyle.allCases.last == .micro)
    }

    @Test("each step anchors to a distinct Dynamic Type style")
    func stepsAnchorToDistinctStyles() {
        // Anchoring on a `Font.TextStyle` is what makes a step scale to AX5 unclamped (ADR-0012); a
        // fixed `.system(size:)` would pin it. Distinct styles matter too: two steps sharing one would
        // be indistinguishable at every Dynamic Type setting, which makes one of them a lie.
        let styles = HWTextStyle.allCases.map(\.textStyle)

        #expect(Set(styles).count == styles.count, "two steps share a Dynamic Type style")
    }

    @Test("the scale runs monotonically from display down to micro")
    func scaleIsOrdered() {
        // Ordering by the underlying text style's default size, largest first. A step inserted out of
        // order is a scale nobody can reason about.
        let sizes = HWTextStyle.allCases.map(\.referenceSize)
        #expect(sizes == sizes.sorted(by: >), "steps are out of order: \(sizes)")
        #expect(Set(sizes).count == sizes.count, "two steps share a size")
    }

    @Test("every step actually grows with Dynamic Type, all the way to AX5")
    func everyStepScalesUnclamped() {
        // The other tests assert the *anchoring*; this asserts the consequence, which is what ADR-0012
        // actually requires. Measured through the matching `UIFont.TextStyle`, because a SwiftUI `Font`
        // will not tell you its resolved size.
        for style in HWTextStyle.allCases {
            let atDefault = style.pointSize(at: .large)
            let atAX5 = style.pointSize(at: .accessibilityExtraExtraExtraLarge)

            #expect(atAX5 > atDefault, "\(style) does not scale: \(atDefault) → \(atAX5)")
            // `referenceSize` is documented as the size at the default setting; a drift here means the
            // cluster comment on each case lies about what a screen will look like.
            #expect(abs(atDefault - style.referenceSize) < 0.01, "\(style) reference size")
        }
    }

    @Test("no step drops below the 11pt floor")
    func microStepRespectsTheFloor() {
        // The design's smallest labels are 9-10.5px. Nothing in the scale goes below 11pt: shrinking
        // further to match the prototype would make the smallest text worse, not more faithful.
        #expect(HWTextStyle.allCases.allSatisfy { $0.referenceSize >= 11 })
    }

    // MARK: - Palette

    @Test("the palette exposes the in-app surfaces and the brand surfaces separately")
    func paletteCarriesBothSurfaces() {
        let palette = HWPalette.standard

        // Landing and auth are galaxy-backed while the five in-app screens are light. That is two
        // surfaces, not a light and a dark mode (ADR-0021).
        #expect(palette.surface.background != palette.brand.background)
        #expect(palette.surface.ink != palette.brand.ink)
        // `--danger` genuinely differs between them, which is the evidence this is two surfaces rather
        // than one theme in two appearances (ADR-0021).
        #expect(palette.feedback.danger != palette.brand.danger)
    }

    @Test("the palette exposes six categories and five unit accents")
    func paletteCarriesTheSlots() {
        let palette = HWPalette.standard

        #expect(palette.categories.all.count == 6)
        #expect(palette.units.all.count == 5)
        #expect(palette.meter.stops.count == 5)
    }

    // MARK: - ThemeManager

    @Test("the theme manager exposes the palette, the type scale, and the curves")
    func themeManagerExposesTheTokens() {
        let theme = ThemeManager()

        #expect(theme.palette.categories.all.count == 6)
        #expect(theme.font(.body) == HWTextStyle.body.font)
        #expect(theme.motion.easeOut.controlPoints == [0.16, 1, 0.3, 1])
    }

    @Test("a second palette needs no new type")
    func paletteIsSwappable() {
        // ADR-0001 ships light-only, "architected for, not shipped". That claim is only true if a
        // different palette is *constructible* — so build one. Every group is a `var` with a default,
        // which is what makes this compile without touching HWPalette.
        var swapped = HWPalette.standard
        swapped.surface.background = .hwBrandBackground
        swapped.surface.ink = .hwBrandInk

        let theme = ThemeManager(palette: swapped)
        #expect(theme.palette.surface.background != HWPalette.standard.surface.background)
        // Untouched groups fall back, so a partial palette is a partial edit rather than a rewrite.
        #expect(theme.palette.categories.all == HWPalette.standard.categories.all)

        theme.apply(.standard)
        #expect(theme.palette.surface.background == HWPalette.standard.surface.background)
    }

    // MARK: - Radii and elevation

    @Test("the radius scale includes a pill, because the design's largest radii are pills")
    func radiusScaleCoversPills() {
        // The design has 29 distinct radii from 2 to 46pt; 30 / 38 / 46 account for 22 uses and are all
        // pill-shaped controls, where the radius is really "half my height" (ADR-0021).
        #expect(HWRadius.allCases.contains(.pill))
        #expect(HWRadius.pill.points > HWRadius.extraLarge.points)

        let laddered = HWRadius.allCases.filter { $0 != .pill }.map(\.points)
        #expect(laddered == laddered.sorted(), "the radius ladder is out of order: \(laddered)")
    }

    @Test("elevation folds the design's negative spread into the radius")
    func shadowsCompensateForSpread() {
        // `--shadow-m: 0 12px 28px -12px` → (28 - 12) / 2 = 8. Dropping the spread would give 14 and
        // every card would sit under a shadow materially larger than the one drawn.
        #expect(HWShadow.small.radius == 3)
        #expect(HWShadow.medium.radius == 8)
        #expect(HWShadow.large.radius == 18)
        #expect(HWShadow.small.y == 2)
        #expect(HWShadow.medium.y == 12)
        #expect(HWShadow.large.y == 26)
    }
}
