/// Everything every screen draws with.
///
/// | Token | Type | Source |
/// |---|---|---|
/// | Colours | ``HWPalette`` over `Assets.xcassets` | the design's `:root` blocks |
/// | Type scale | ``HWTextStyle`` | the design's `font-size` clusters |
/// | Motion | ``HWMotion`` · ``HWDuration`` | `--ease-out` · `--ease-io` · `--ease-back` |
/// | Radii and elevation | ``HWRadius`` · ``HWShadow`` | `border-radius` · `--shadow-s/m/l` |
/// | The four empty-handed states | ``StateView`` · ``StateCopy`` · ``ErrorCopy`` | ADR-0016 |
/// | Scaling policy and the clamp pattern | ``HWScaling`` · `hwVisualisation(replacedBy:)` | ADR-0012 |
/// | How a view arrives, and what it arrives as under Reduce Motion | ``HWEntrance`` | ADR-0012 |
/// | Saying something VoiceOver would not hear | ``HWAnnouncement`` | ADR-0012 |
///
/// Reached through ``ThemeManager`` in the environment, so the later dark palette is a swap rather than
/// a rewrite (ADR-0001, ADR-0021).
///
/// The accessibility three are here rather than in `Components/` because each is a **policy** rather than
/// a control: a component may not clamp, may not choose what Reduce Motion means, and may not decide which
/// locale an announcement is spoken in. `ComponentVocabularyTests` and `AccessibilityTests` hold that line
/// from both sides.
///
/// The namespace itself is empty — the tokens are top-level types so a call site reads
/// `.font(.hw(.caption))` rather than `DesignSystem.font(...)`.
enum DesignSystem {}
