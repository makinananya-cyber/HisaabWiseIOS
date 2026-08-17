import SwiftUI

/// The type scale.
///
/// The design uses **more than thirty distinct font sizes**, many separated by half a pixel — which is
/// what a prototype looks like, not a scale. These eight steps collapse them by cluster, and the
/// collapse is the point: two screens differing by 0.5pt is noise a design system exists to remove.
///
/// **Each step is anchored to a `Font.TextStyle` rather than a fixed point size.** That is what makes
/// text scale to AX5 unclamped (ADR-0012); a fixed `.system(size:)` would pin it. The cost is that a
/// step lands on Apple's metric rather than the design's exact pixel, and the deltas are recorded
/// against each case below.
///
/// **The four reading steps sit deliberately above the design's pixels.** The design was authored in CSS
/// px at a 390px viewport, and transcribing those literally put body text at 13pt and captions at 12 —
/// which measured faithfully and read as fine print on a phone held at arm's length. The bottom half of
/// the scale is therefore anchored one Dynamic Type step higher than the transcription: `bodyLarge` 17,
/// `body` 15, `caption` 13, `micro` 12. The top four are unchanged, because they were never the problem —
/// a 28pt screen title is a 28pt screen title. The scale stays strictly ordered and every step keeps its
/// own `Font.TextStyle`, both of which `ThemeTests` asserts, so the relationships the design draws with
/// survive the shift.
///
/// A call site that needs a different weight uses `Font`'s own `.weight(_:)` — sizes stay owned here.
enum HWTextStyle: Sendable, CaseIterable {
    /// Design 30–38px. The one big number on a screen.
    case display
    /// Design 26–30px. Screen titles.
    case title
    /// Design 20–24px. Card headings and figures.
    case heading
    /// Design 17–19px. Section headings. Anchored 1–3pt above the design.
    case subheading
    /// Design 15–16.5px. Emphasised body. Anchored at 17pt — see the note on the type above.
    case bodyLarge
    /// Design 13–14.5px. Body and list rows. Anchored at 15pt.
    case body
    /// Design 11–12.5px. Labels and captions — the design's most-used range. Anchored at 13pt.
    case caption
    /// Design 9–10.5px. Eyebrows and the smallest labels.
    ///
    /// Anchored at 12pt, **above** the design. The design's own 9px is smaller than Apple's smallest
    /// text style, and the smallest text in the app is where a faithful transcription costs the most.
    case micro

    /// The Dynamic Type style this step scales with.
    var textStyle: Font.TextStyle {
        switch self {
        case .display: .largeTitle
        case .title: .title
        case .heading: .title2
        case .subheading: .title3
        case .bodyLarge: .body
        case .body: .subheadline
        case .caption: .footnote
        case .micro: .caption
        }
    }

    /// The design leans heavily on weight — 800 dominates, then 700 and 600 — so each step carries the
    /// weight its cluster actually uses.
    var weight: Font.Weight {
        switch self {
        case .display, .title, .heading: .heavy
        case .subheading: .bold
        case .bodyLarge, .caption, .micro: .semibold
        case .body: .regular
        }
    }

    var font: Font {
        .system(textStyle, weight: weight)
    }

}

extension Font {
    /// `Text("…").font(.hw(.caption))`
    static func hw(_ style: HWTextStyle) -> Font { style.font }
}
