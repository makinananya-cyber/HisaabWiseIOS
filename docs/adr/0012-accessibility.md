# ADR-0012 — Scale all text, clamp only the visualisations, replace motion rather than remove it

**Status:** accepted
**Amends:** Product Spec §3.1 and §3.5 ("skip under reduced motion" → *replace* under reduced
motion)

## Context

Product Spec §9 makes accessibility a **feature parity requirement**, not polish, and the risk
table calls out treating it as polish as a named risk. But the designs are fixed-layout HTML: at
AX5 (~310% text) the donut's centre readout, the savings meter's pin and percentage pill, the
four-segment split bar, and the 7-day week strip all break.

Separately, §3.1 and §3.5 say to "skip" strapline rotation and confetti under reduced motion.
Skipping silently removes feedback that a motion-sensitive **sighted** user still needs — and
removes it for VoiceOver users too, who never had the animation.

## Decision

**Dynamic Type is unclamped on all text** — and especially on tips, articles, and lesson steps,
which are the education product. Clamping the reading content is the real accessibility failure;
clamping a chart label is a cosmetic one.

**Clamp only the data visualisations** — donut, savings meter, split bar, week strip — with
`.dynamicTypeSize(...DynamicTypeSize.xxxLarge)`, each paired with an **accessibility-size
alternative layout**: donut → ring hidden, category list with values; split bar → vertical list;
week strip → wrapping.

**Reduce Motion replaces, never removes.** Confetti → a static celebratory badge carrying the XP
figure. Combo → cross-fade only, no spring or scale. Straplines → one strapline, stable for the
session. **No in-app motion toggle** — the OS setting is the contract; a second switch is a second
source of truth.

**`AccessibilityNotification.Announcement`** for combo and completion, since neither the animated
nor the static form reaches VoiceOver on its own.

**VoiceOver labels are composed client-side** from String Catalog format strings plus ADR-0003's
display strings (`"\(category), \(displayAmount), \(share) percent of spending"`). The designs'
ARIA text is a **wording checklist**, not shipped content — accessibility phrasing follows
per-language VoiceOver convention, which the server has no business encoding. Charts get
`accessibilityRepresentation`.

**Haptics, sparing and semantic**, via `.sensoryFeedback` only: `.success` on a correct answer, on
expense logged, and on lesson complete; `.error` on incorrect; `.impact` on heart lost. Nothing on
scroll or donut isolate.

**The Accessibility Inspector audit is a per-screen gate**, not a Phase 5 sweep.

## Consequences

- Clamping only the visualisations keeps the parity requirement honest on the screens where it
  matters most — the long-form educational content.
- Confetti built with `Canvas` + `TimelineView` keeps Rule 1's pure-SwiftUI mandate with no
  third-party library and no UIKit representable.
- `.sensoryFeedback` is iOS 17+ (ADR-0001 covers it) and needs no UIKit wrapper. It also respects
  the system haptic setting automatically.
- Haptics are the one channel that still feels responsive when ADR-0004 has deliberately left the
  numbers stale offline.
- ADR-0016's `SectorMark` choice supplies per-mark accessibility descriptors that a hand-rolled
  donut would not.
