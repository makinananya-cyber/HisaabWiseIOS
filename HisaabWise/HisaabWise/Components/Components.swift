/// The shared UI vocabulary: one implementation of each control, used everywhere.
///
/// The rule that makes this worth having: **a screen never styles a control itself.** If Expenses
/// needs a button that Home does not have, the variant is added here, not inlined there — otherwise
/// there are two buttons that look alike until one of them changes.
///
/// The inventory comes from the design's own CSS (`HisaabwiseDesigns/HisaabWise 6.html`), which
/// already has a component vocabulary worth honouring rather than reinventing. What it converts to:
///
/// | Design | Here |
/// |---|---|
/// | `.btn` · `-primary` `-soft` `-ghost` `-quiet` · `[disabled]` · `.loading` | ``HWButton``, ``HWButtonVariant``, ``HWButtonState`` |
/// | `.iconbtn` · `.editbtn` | ``HWIconButton`` · ``HWEditButton`` |
/// | `:active` scale on every control | ``HWPressStyle`` |
/// | the rounded box + hairline border + elevation under all of them | `hwBox(fill:radius:border:borderWidth:elevation:)` |
/// | `.field-box` + `.field-ico` · `.ctrl` · `.field.bad` + `.msg` | ``HWTextField`` |
/// | `.fld-lab` · `.eyebrow` / `.card-cap` | `hwLabel()` · `hwEyebrow()` |
/// | `.card` + `.card-top` + `.card-cap` + `.card-sub` | ``HWCard`` |
/// | `.mchip` · `.opt-chip` / `.srow-iso` | ``HWChip`` · ``HWCodeChip`` |
/// | `.row` · `.key-row` | ``HWRow`` · ``HWKeyRow`` |
/// | `.grab` + `.sheet-head` + `.sheet-title` + `.sheet-x` | ``HWSheetChrome`` |
/// | `.sheet-list` / `.optlist` / `.opts` · `.srow` / `.opt` | ``HWSheetList`` · ``HWSheetRow`` |
/// | `.topbar` · `.backbar` | ``HWTopBar`` · ``HWBackBar`` |
/// | `.toast` | ``HWToast`` · `hwToast(_:isPresented:)` |
///
/// **Components are presentational and know nothing.** They take values and closures. They do not
/// import the networking layer, do not hold a view model, and do not fetch — `LayeringTests` asserts
/// all three, because a component that can fetch is a screen wearing a component's name.
///
/// They draw with `DesignSystem`'s semantic colours and type scale, never with literals, so the
/// dark-mode palette swap stays a palette swap. `ComponentVocabularyTests` asserts that too: no asset
/// symbol reaches a component directly, no system font does, and no elevation is hand-rolled.
///
/// **Four things from that CSS are deliberately absent**, and each says why:
///
/// - The `brand` appearance. Every component here resolves the `surface` tokens, which is the five
///   in-app screens. Landing and Auth are `brand` (ADR-0021) and arrive with #13–#16 — the reason
///   `ScreenChrome` gives for not being appearance-agnostic yet: two callers shape it better than one guess.
/// - The destructive button — the design's `.btn-danger` and Account's `.logout` — which arrives with
///   Account (#17), for the same reason.
/// - `.tabbar`. It is the five-tab shell's, and in SwiftUI it is a `TabView` rather than a control:
///   converting the CSS would mean re-implementing a system container, which Rule 1 rules out.
/// - `.mark`, the wordmark tile in `.topbar`. The asset catalogue carries colour sets only, so there is
///   no image to draw; ``HWTopBar`` gains the slot when one ships.
///
/// The namespace itself is empty: the components are top-level types, so a call site reads
/// `HWButton(…)` rather than `Components.HWButton(…)`.
enum Components {}
