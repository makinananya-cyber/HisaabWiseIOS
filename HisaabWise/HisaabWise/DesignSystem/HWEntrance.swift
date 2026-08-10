import SwiftUI

/// How something arrives on screen — and, because the two are one decision, what it arrives as when the
/// user has asked for less movement.
///
/// **ADR-0012's rule is that Reduce Motion *replaces*, never removes.** Product Spec §3.1 and §3.5 said to
/// "skip" the strapline rotation and the confetti; skipping silently takes away feedback a motion-sensitive
/// **sighted** user still needs, and takes it away from VoiceOver users too, who never had the animation.
///
/// The reason this is a value rather than a ternary at each call site is that a ternary has a third option.
/// `reduceMotion ? nil : .move(edge: .bottom)` compiles, reads as considerate, and is the defect. Here the
/// reduced form of every entrance is a **cross-fade**, ``reduced`` cannot return nothing, and
/// `ReducedMotionTests` asserts it over the whole vocabulary rather than over whichever caller a reviewer
/// happened to open.
///
/// Timing is deliberately *not* reduced. A toast that took 420ms to arrive still takes 420ms, so the event
/// reads as the same event at the same pace — only the travel is gone.
///
/// The other half of the rule lives in ``HWPressStyle``, which replaces the design's `:active` scale with a
/// dip in opacity. It is a `ButtonStyle` rather than an arrival, so it is not one of these.
struct HWEntrance: Sendable, Hashable {
    /// What the movement actually is. Named for the gesture rather than for the control that first wanted
    /// it, so a second caller is not asking "how does a toast arrive".
    enum Kind: Sendable, Hashable, CaseIterable {
        /// Travels up from the **bottom** edge as it fades. The design's toast and its sheets, both of
        /// which come from the bottom; the edge is part of the case rather than a parameter, so an
        /// arrival from somewhere else is a new entrance with its own name and not this one silently
        /// reused.
        case rise
        /// Grows into place, overshooting slightly. The design's confetti badge and the Learn combo.
        case pop
        /// Cross-fades. What the other two become, and a legitimate choice in its own right.
        case fade
    }

    let kind: Kind
    let duration: HWDuration

    /// `.toast` — `translateY(16px) scale(.97)` → none, eased with `--ease-out` over the design's longest
    /// common transition.
    static let rise = HWEntrance(kind: .rise, duration: .emphasised)

    /// The one that overshoots, which is the whole reason `--ease-back` is in the design system.
    static let pop = HWEntrance(kind: .pop, duration: .emphasised)

    static let fade = HWEntrance(kind: .fade, duration: .standard)

    /// The vocabulary. Kept beside `Kind.allCases` so a fourth entrance cannot be added without appearing
    /// in the assertions that iterate it.
    static let all: [HWEntrance] = [.rise, .pop, .fade]

    /// What this becomes under Reduce Motion: a cross-fade of the same length. **Never `nil`, and never
    /// `.identity`** — a change with no transition at all appears between one frame and the next, which is
    /// the removal ADR-0012 forbids.
    var reduced: HWEntrance {
        HWEntrance(kind: .fade, duration: duration)
    }

    /// The form to use. The call site's one decision, made from the environment value it read.
    func resolved(reduceMotion: Bool) -> HWEntrance {
        reduceMotion ? reduced : self
    }

    /// The easing. `pop` is the only one that overshoots, which is what makes it the only one whose
    /// reduction is visible as more than a shorter path.
    var curve: HWCurve {
        switch kind {
        case .rise, .fade: HWMotion.easeOut
        case .pop: HWMotion.easeBack
        }
    }

    var animation: Animation {
        curve.animation(duration)
    }

    var transition: AnyTransition {
        switch kind {
        case .rise: .move(edge: .bottom).combined(with: .opacity)
        case .pop: .scale(scale: 0.94).combined(with: .opacity)
        case .fade: .opacity
        }
    }
}
