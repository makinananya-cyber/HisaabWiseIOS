import SwiftUI

/// Every colour the app draws with, named for what it does rather than what it looks like.
///
/// There is deliberately no `Color.galaxy`, `Color.universe`, or any other raw palette name: the seven
/// palette values reach a use site only through a role. That is what makes the later dark palette a
/// swap of this one value rather than a search-and-replace through every screen (ADR-0001, ADR-0012).
///
/// Values live in `Assets.xcassets`, one colour set per role, transcribed from the design's `:root`
/// blocks and asserted against them by `ColorAssetTests`.
///
/// **Every group is a `var` with a default**, which is what makes a second palette constructible
/// without a new type — `HWPalette(surface: .init(background: .someDarkGround))` and the rest falls
/// back. `ThemeTests` builds one to prove it.
struct HWPalette: Sendable {
    /// The five in-app screens: light, off-white ground, galaxy ink.
    var surface = Surface()
    /// Landing and auth: galaxy ground, milky ink. **Not a dark mode** — a different surface that
    /// ships alongside, see ADR-0021.
    var brand = Brand()
    var accent = Accent()
    var feedback = Feedback()
    /// The six donut slots.
    var categories = Categories()
    /// The five Learn unit accents.
    var units = Units()
    /// The savings meter's red-to-green ramp.
    var meter = Meter()
    /// The three goal verdicts, as a wash and the ink that reads on it.
    var verdicts = Verdicts()

    static let standard = HWPalette()
}

/// Which of §4.2's three goal verdicts a control is drawn in, as a **name** rather than as two colours.
///
/// It sits here beside ``HWUnitTint`` for the reason that one does: both a component and a screen name a
/// verdict — the archive's badge, the trend chart's bars, the savings meter's percentage pill — and a caller
/// that passed the resolved pair would be a caller that had already reached into ``HWPalette/Verdicts``.
///
/// **Three names, and the design gives them one table.** `.m-badge.hit/.near/.miss` on the archive and
/// `.mf-r` with its `.warn` and `.low` variants on the meter are the *same three* soft/ink pairs, written twice
/// in the CSS. Written twice here they would be the second copy of a colour table, which is the shape defect
/// D11 took with a threshold table — so the meter's three verdicts resolve through this one.
enum HWVerdictTint: Sendable, Hashable, CaseIterable {
    /// `saved ≥ 100%` of goal — `.m-badge.hit`, and the meter pill's unmodified state.
    case hit
    /// `saved ≥ 70%` — `.m-badge.near` / `.mf-r.warn`.
    case near
    /// Otherwise — `.m-badge.miss` / `.mf-r.low`.
    case miss
}

/// Which of the five Learn unit accents a view is drawn in, as a **name** rather than as three colours.
///
/// The design sets `--acc`, `--acc-soft`, and `--acc-deep` per unit from this palette, and a view that took the
/// resolved triad would be a view whose caller had already reached into ``HWPalette/Units``. A name travels
/// instead, and ``HWPalette/Units/accent(_:)`` is the one place it becomes colour — which is what keeps the later
/// dark-mode swap a swap (ADR-0001).
///
/// Distinct from ``HWPalette/UnitAccent``, which is the *resolved* triad. This is the selector; that is the
/// answer. It sits here rather than in `Components/` because both a component and a screen name a slot, and
/// `HWAppearance` is the same shape of decision in the same layer.
enum HWUnitTint: Sendable, Hashable, CaseIterable {
    case sun
    case mint
    case coral
    case sky
    case violet
}

extension HWPalette {
    struct Surface: Sendable {
        var background = Color.hwBackground
        var backgroundSecondary = Color.hwBackgroundSecondary
        /// Cards, which sit on the background.
        var raised = Color.hwSurface
        /// Text and iconography. The design's `--ink`, used on both the ground and the card — which is
        /// why it is not called `onBackground` or `onSurface`: it is on both.
        var ink = Color.hwInk
        var inkSecondary = Color.hwInkSecondary
        var inkTertiary = Color.hwInkTertiary
        var separator = Color.hwSeparator
        var separatorStrong = Color.hwSeparatorStrong
    }

    struct Brand: Sendable {
        var background = Color.hwBrandBackground
        var backgroundDeep = Color.hwBrandBackgroundDeep
        /// The lift the landing gradient uses for depth.
        var backgroundLift = Color.hwBrandBackgroundLift
        var ink = Color.hwBrandInk
        var inkSecondary = Color.hwBrandInkSecondary
        var inkAccent = Color.hwBrandInkAccent
        var raised = Color.hwBrandSurface
        var separator = Color.hwBrandSeparator
        var separatorStrong = Color.hwBrandSeparatorStrong
        /// A distinct value from ``Feedback/danger`` — the clearest evidence these are two surfaces
        /// shipping together rather than one theme in two appearances (ADR-0021).
        var danger = Color.hwBrandDanger
    }

    struct Accent: Sendable {
        var base = Color.hwAccent
        var soft = Color.hwAccentSoft
        var deep = Color.hwAccentDeep
        /// The design's `--universe`, used at ~35 sites for secondary text, borders, and one gradient.
        var muted = Color.hwAccentMuted
        var tint = Color.hwTint
        var tintSecondary = Color.hwTintSecondary
    }

    struct Feedback: Sendable {
        var danger = Color.hwDanger
        var dangerSoft = Color.hwDangerSoft
        /// The donut's unfilled ring, and the first-run empty state.
        var emptyTrack = Color.hwEmptyTrack
        var locked = Color.hwLocked
        var lockedSoft = Color.hwLockedSoft
    }

    /// The six category slots, in the design's order.
    ///
    /// The design records the constraint beside them: every slot clears **3:1 against the white card**,
    /// and the order **alternates cool / warm** so neighbouring donut wedges stay apart for
    /// colour-blind users. `ColorAssetTests` enforces the contrast; the alternation is preserved by
    /// keeping this order, so change hues rather than positions.
    struct Categories: Sendable {
        var rent = Color.hwCategoryRent
        var groceries = Color.hwCategoryGroceries
        var transport = Color.hwCategoryTransport
        var utilities = Color.hwCategoryUtilities
        var entertainment = Color.hwCategoryEntertainment
        var other = Color.hwCategoryOther

        /// In slot order, which is the order a donut assigns them.
        var all: [Color] { [rent, groceries, transport, utilities, entertainment, other] }
    }

    /// One Learn unit's accent: a base, a soft wash behind it, and a deep for text on the wash.
    struct UnitAccent: Sendable {
        var base: Color
        var soft: Color
        var deep: Color
    }

    struct Units: Sendable {
        var sun = UnitAccent(base: .hwUnitSun, soft: .hwUnitSunSoft, deep: .hwUnitSunDeep)
        var mint = UnitAccent(base: .hwUnitMint, soft: .hwUnitMintSoft, deep: .hwUnitMintDeep)
        var coral = UnitAccent(base: .hwUnitCoral, soft: .hwUnitCoralSoft, deep: .hwUnitCoralDeep)
        /// The design spells this one through the palette — `--acc: planetary`, `--acc-soft: sky`,
        /// `--acc-deep: galaxy` — rather than as its own triad, so it reuses the accent colour sets
        /// instead of carrying three byte-identical copies of them.
        var sky = UnitAccent(base: .hwAccent, soft: .hwAccentSoft, deep: .hwAccentDeep)
        var violet = UnitAccent(base: .hwUnitViolet, soft: .hwUnitVioletSoft, deep: .hwUnitVioletDeep)

        /// In the order the workspace `CLAUDE.md` lists them: sun · mint · coral · sky · violet.
        var all: [UnitAccent] { [sun, mint, coral, sky, violet] }

        /// The triad for one slot.
        ///
        /// Here rather than at the call site so that "which of the five" travels as a ``HWUnitTint`` and the
        /// resolution happens once — a component or a screen switching over five slots itself would be a
        /// second copy of this table, and the second copy is the one that forgets a slot (ADR-0001).
        func accent(_ tint: HWUnitTint) -> UnitAccent {
            switch tint {
            case .sun: sun
            case .mint: mint
            case .coral: coral
            case .sky: sky
            case .violet: violet
            }
        }

        /// The triad a **graded answer** is drawn in — mint for right, coral for wrong (#20).
        ///
        /// The design's `.right` and `.wrong` are the mint and coral sets, and the lesson player asks which one in
        /// eight places: an option's box, its fill and its border, the typed box's fill and border, the feedback
        /// note's ink, the primary button, and the footer's wash. Each of those wants a *different value* from the
        /// triad, which is legitimate — but re-deriving *which triad* eight times is one table written eight times,
        /// and the eighth is the one that gets it backwards. So the pair lives here, beside ``accent(_:)``, for the
        /// reason that one does.
        func verdict(isCorrect: Bool) -> UnitAccent {
            isCorrect ? mint : coral
        }
    }

    /// The savings meter's gradient track, red through green (ADR-0016).
    struct Meter: Sendable {
        var nothing = Color.hwMeterNothing
        var low = Color.hwMeterLow
        var half = Color.hwMeterHalf
        var high = Color.hwMeterHigh
        var reached = Color.hwMeterReached

        /// Ordered for a `LinearGradient`.
        var stops: [Color] { [nothing, low, half, high, reached] }

        /// The stop a **verdict** is drawn in, which is the trend chart's bar colour (#21).
        ///
        /// The design's own `ramp()`: `p >= 100 ? --r5 : p >= 70 ? --r3 : --r1`. It lives beside the gradient
        /// rather than in ``Verdicts`` because it *is* the gradient — three of its five stops, picked out — and
        /// a bar that took its colour from the badge's pastel wash would be a bar nobody could see on the
        /// galaxy card. Two treatments of one verdict, each with one owner.
        func stop(for tint: HWVerdictTint) -> Color {
            switch tint {
            case .hit: reached
            case .near: half
            case .miss: nothing
            }
        }
    }

    /// One verdict's badge: the wash behind it and the ink that reads on the wash.
    ///
    /// A pair rather than a single tint, because the design's badges are *filled* — and the fill is a pastel
    /// that nothing on this palette's ink roles reads on at 4.5:1. The design supplies both, so both are
    /// transcribed; `ColorAssetTests` asserts the contrast rather than trusting the transcription.
    struct VerdictTone: Sendable {
        var soft: Color
        var ink: Color
    }

    /// The three verdict badges, transcribed from `.m-badge.hit/.near/.miss`.
    struct Verdicts: Sendable {
        var hit = VerdictTone(soft: .hwVerdictHitSoft, ink: .hwVerdictHitInk)
        var near = VerdictTone(soft: .hwVerdictNearSoft, ink: .hwVerdictNearInk)
        var miss = VerdictTone(soft: .hwVerdictMissSoft, ink: .hwVerdictMissInk)

        /// The pair for one verdict.
        ///
        /// Here rather than at the call site, for the reason ``Units/accent(_:)`` is: the badge, the trend
        /// chart, and the savings meter each ask, and three copies of this `switch` is one table written three
        /// times — the third being the one that gets a colour backwards (ADR-0001).
        func tone(_ tint: HWVerdictTint) -> VerdictTone {
            switch tint {
            case .hit: hit
            case .near: near
            case .miss: miss
            }
        }
    }
}
