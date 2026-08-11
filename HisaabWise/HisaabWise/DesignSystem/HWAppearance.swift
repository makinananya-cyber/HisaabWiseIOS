import Foundation

/// Which of the design's two surfaces a control is being drawn on.
///
/// ADR-0021 — the design ships **two surfaces at once**, not a light and a dark theme: `landing` and `auth`
/// are galaxy-backed, the five in-app screens are light, and `--danger` has a different value on each. So a
/// control's colours depend on where it sits, and that is a parameter rather than a mode: both appearances
/// are on screen in the same build, one before sign-in and one after.
///
/// It arrives with Landing (#13), which is the first screen on `brand`. `CONTEXT.md` parked it until there
/// was a caller, and the reason it is safe to add now is that the design's own CSS settles it: the landing
/// `.cta` and auth's `.btn-primary` carry the *same* fill and the *same* ink, two points of height apart. So
/// this is not a guess at what a brand button looks like — it is the second half of a control the vocabulary
/// already has.
///
/// **Why not read it from the environment.** A control that inferred its appearance would be a control whose
/// colours change when it moves, and the one thing a screen must not be able to do is get this wrong
/// silently: `surface` is the default because the five in-app screens are the majority, and a pre-auth screen
/// says so at the call site where a reviewer can see it.
enum HWAppearance: Sendable, Equatable, CaseIterable {
    /// The five in-app screens: milky ground, galaxy ink.
    case surface
    /// Landing and Auth: galaxy ground, milky ink.
    case brand
}
