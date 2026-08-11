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
/// | `.btn` · `-primary` `-soft` `-ghost` `-quiet` · `.addline` · `[disabled]` · `.loading` | ``HWButton``, ``HWButtonVariant``, ``HWButtonState`` |
/// | `.iconbtn` · `.editbtn` | ``HWIconButton`` · ``HWEditButton`` |
/// | `:active` scale on every control | ``HWPressStyle`` |
/// | the rounded box + hairline border + elevation under all of them | `hwBox(fill:radius:border:borderWidth:elevation:)` |
/// | `.field-box` + `.field-ico` · `.ctrl` · `.field.bad` + `.msg` | ``HWTextField`` |
/// | `.fld-lab` · `.eyebrow` / `.card-cap` | `hwLabel()` · `hwEyebrow()` |
/// | `.card` + `.card-top` + `.card-cap` + `.card-sub` | ``HWCard`` |
/// | `.mchip` · `.opt-chip` / `.srow-iso` | ``HWChip`` · ``HWCodeChip`` |
/// | `.row` · `.key-row` · `.cat` | ``HWRow`` · ``HWKeyRow`` · ``HWCategoryRow`` |
/// | `.grab` + `.sheet-head` + `.sheet-title` + `.sheet-x` | ``HWSheetChrome`` |
/// | `.sheet-list` / `.optlist` / `.opts` · `.srow` / `.opt` | ``HWSheetList`` · ``HWSheetRow`` |
/// | `.topbar` · `.backbar` | ``HWTopBar`` · ``HWBackBar`` |
/// | `.toast` | ``HWToast`` · `hwToast(_:isPresented:)` |
/// | `.summary` + `.sum-split` + `.chip` · `.budget` | ``HWSpendSummary`` · ``HWBudgetBar`` |
/// | `.hero` · `.entry` · `.empty` | ``HWCategoryHero`` · ``HWEntryRow`` · ``HWEmptyNote`` |
/// | `.line` · `.editing .line` · `.fixed-val` | ``HWBillLine`` · ``HWBillLineEditor`` · ``HWFixedAmount`` |
/// | `.money-sym` + `.money-code` · `.amount` | ``HWMoneyField``, ``HWMoneyProminence`` |
///
/// **Components are presentational and know nothing.** They take values and closures. They do not
/// import the networking layer, do not hold a view model, and do not fetch — `LayeringTests` asserts
/// all three, because a component that can fetch is a screen wearing a component's name.
///
/// They draw with `DesignSystem`'s semantic colours and type scale, never with literals, so the
/// dark-mode palette swap stays a palette swap. `ComponentVocabularyTests` asserts that too: no asset
/// symbol reaches a component directly, no system font does, and no elevation is hand-rolled.
///
/// **Two things from that CSS are deliberately absent**, and each says why:
///
/// - The destructive button — the design's `.btn-danger` and Account's `.logout` — which arrives with
///   Account (#23), where there is a caller to shape it. The same reasoning `ScreenChrome` gives for not
///   being appearance-agnostic yet: two callers shape a control better than one guess.
/// - `.tabbar`. It is the five-tab shell's, and in SwiftUI it is a `TabView` rather than a control:
///   converting the CSS would mean re-implementing a system container, which Rule 1 rules out.
///
/// Two more used to be on that list and no longer are. `.mark` is drawn by ``HWMark`` now that the design's
/// base64 logo has been extracted to the asset catalogue (ADR-0026). And the **`brand` appearance is no longer
/// pending**: ``HWMoneyField`` and ``HWCombo`` were brand-only while registration was their one caller, and
/// Expenses (#18) is the second one that settled both — the combo's caption even moves, because the design puts
/// it inside the box on one surface and above it on the other.
///
/// The namespace itself is empty: the components are top-level types, so a call site reads
/// `HWButton(…)` rather than `Components.HWButton(…)`.
enum Components {}
