/// Everything every screen draws with.
///
/// | Token | Type | Source |
/// |---|---|---|
/// | Colours | ``HWPalette`` over `Assets.xcassets` | the design's `:root` blocks |
/// | Type scale | ``HWTextStyle`` | the design's `font-size` clusters |
/// | Motion | ``HWMotion`` · ``HWDuration`` | `--ease-out` · `--ease-io` · `--ease-back` |
/// | Radii and elevation | ``HWRadius`` · ``HWShadow`` | `border-radius` · `--shadow-s/m/l` |
///
/// Reached through ``ThemeManager`` in the environment, so the later dark palette is a swap rather than
/// a rewrite (ADR-0001, ADR-0021).
///
/// **Still to arrive here:** the single `StateView` over `LoadState`, with the one error-code-to-copy
/// mapping (issue #11), and the clamp-plus-alternative-layout pattern the donut, meter, split bar, and
/// week strip will use (ADR-0012, issue #8).
///
/// The namespace itself is empty — the tokens are top-level types so a call site reads
/// `.font(.hw(.caption))` rather than `DesignSystem.font(...)`.
enum DesignSystem {}
