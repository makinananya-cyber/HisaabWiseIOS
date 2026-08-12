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
/// | `.stat` + `.stat--streak` / `--xp` | ``HWStatChip`` |
/// | `.unit-head` + `.unit-n` + `.unit-guide` | ``HWUnitHeader`` |
/// | `.track` + `.links` · `.node` + `.ring` + `.face` + `.start` | ``HWLessonTrack`` |
/// | `.guide-item` + `.gi-n` + `.gi-s` | ``HWLessonRow`` |
/// | `.p-top` + `.p-bar` + `.p-fill` + `.p-hearts` | ``HWRunHeader`` |
/// | `.combo` · `.kicker` | ``HWComboBadge`` · ``HWKicker`` |
/// | `.btn-go` / `.btn-ok` / `.btn-no` | ``HWRunButton`` |
/// | `.opt` + `.opt-box` · `.numwrap` + `.num-hint` | ``HWAnswerOption`` · ``HWAnswerField``, ``HWAnswerState`` |
/// | `.fb` + `.fb-ico` + `.fb-h` + `.fb-p` + `.fb-ans` | ``HWFeedbackNote`` |
/// | `.t-li` + `.t-dot` · `.eg` · `.tip` | ``HWTeachingEntry`` · ``HWWorkedExample`` · ``HWTeachingTip`` |
/// | `.done-badge` · `.done-stats` + `.dstat` | ``HWDoneBadge`` · ``HWCompletionStats`` · ``HWCompletionStat`` |
/// | `.week` + `.wd` · `.confetti` + `.cf` | ``HWWeekStrip`` · ``HWConfetti`` |
///
/// **Components are presentational and know nothing.** They take values and closures. They do not
/// import the networking layer, do not hold a view model, and do not fetch — `LayeringTests` asserts
/// all three, because a component that can fetch is a screen wearing a component's name.
///
/// They draw with `DesignSystem`'s semantic colours and type scale, never with literals, so the
/// dark-mode palette swap stays a palette swap. `ComponentVocabularyTests` asserts that too: no asset
/// symbol reaches a component directly, no system font does, and no elevation is hand-rolled.
///
/// **What Learn's four entries do *not* convert** is worth naming, because each is a decision rather than an
/// omission (#19, ADR-0034). `.stat--crown` is in the stylesheet and nothing renders it. The `.links` connectors
/// are **measured** rather than computed, as the design measures them, so the whole path mirrors under Arabic for
/// nothing. The `.start` flag's 1.6-second bob and the current node's `breathe` are **dropped rather than gated**
/// on Reduce Motion: an attention loop's replacement is the flag itself, and a component that animates owes
/// ADR-0012 a replacement it cannot have here. And the design's locked unit header — white on `#8B95AE`, about
/// 2.9:1 — becomes the `locked` role with the surface's own ink on it, because the rest of this palette is
/// asserted at 4.5:1 and those two greys are not tokens.
///
/// **Two things from that CSS are deliberately absent**, and each says why:
///
/// - The destructive button — the design's `.btn-danger` and Account's `.logout` — which arrives with
///   Account (#23), where there is a caller to shape it. The same reasoning `ScreenChrome` gives for not
///   being appearance-agnostic yet: two callers shape a control better than one guess.
/// - `.tabbar`. It is the five-tab shell's, and in SwiftUI it is a `TabView` rather than a control:
///   converting the CSS would mean re-implementing a system container, which Rule 1 rules out.
///
/// **What the lesson player's fifteen entries decide** (#20, ADR-0035), because three of them are departures. A
/// multi-select's box is `.hairline` rather than `.small`: that step is 11pt on a 24pt box, which draws a *circle* and
/// made the two kinds of question look identical beside each other — the shape is how the design says "pick more than
/// one", so it has to be unmistakable. `HWRunButton` is **not** a fifth `HWButtonVariant`, because its fill is a unit
/// accent while a question is open and a verdict once it has been graded, and `HWButtonAppearance` can see neither.
/// And a graded `HWAnswerOption` stays a `Button` rather than becoming `.disabled(true)`, which the design does: a
/// disabled control leaves the accessibility tree, so the reader who most needs to hear "this was the right one"
/// would hear nothing.
///
/// The design's `heartHit` pulse and `.wd.today` bump are **dropped rather than gated**, for the reason the `START`
/// flag's bob is: an attention loop's only replacement is the thing itself, and the sentence beside the hearts
/// already says how many are left. `HWConfetti` draws **nothing** under Reduce Motion, and the replacement ADR-0012
/// names — a static badge carrying the XP figure — is `HWDoneBadge` and `HWCompletionStat`, both permanent.
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
