/// Everything every screen draws with.
///
/// The target exists from the first commit so that no screen invents its own spinner, empty state,
/// or colour. What lands here:
///
/// - The asset catalogue of **semantic** colour names over galaxy / planetary / universe / venus /
///   sky / meteor / milky, plus six category slots and five Learn unit accents. Light-only, named
///   semantically so dark mode later is a palette swap rather than a rewrite.
/// - The single `StateView` covering `HWCore`'s `LoadState`, in which `offline` is visually distinct
///   from `failed` (ADR-0016), and the one error-code-to-copy mapping.
/// - The type scale, the two easing curves from the design CSS, and the
///   clamp-plus-alternative-layout pattern the donut, meter, split bar, and week strip will use
///   (ADR-0012).
///
/// Until then the tab placeholders render their states inline.
///
/// The namespace is empty until the first of those lands.
public enum HWDesignSystem {}
