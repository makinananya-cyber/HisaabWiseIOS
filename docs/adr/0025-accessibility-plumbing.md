# ADR-0025 — Accessibility plumbing: one clamp, one arrival, one announcement, and defaults a screen inherits

**Status:** accepted
**Extends:** [ADR-0012](0012-accessibility.md) (which decided *that* text scales unclamped, that the four
visualisations are replaced rather than shrunk, and that Reduce Motion replaces rather than removes — not
where any of that lives or how a screen gets it)
**Needs a GUI step:** the Accessibility Inspector audit in its automatable form needs a UI-test target,
which cannot be created from the CLI (recorded in `CONTEXT.md` and below)

## Context

ADR-0012 is a policy document. It says what must be true and leaves four questions open, and each of them
is the question that decides whether the policy survives eleven more screens.

**Where the clamp lives, and how a screen asks for it.** The clamp is one modifier. Written at each of the
four visualisations it is four chances to clamp and forget the alternative layout — which produces a chart
that is capped and unreadable, the exact outcome the ADR rejects, while looking like the ADR was followed.

**What "replace rather than remove" is, as code.** `reduceMotion ? nil : .move(edge: .bottom)` compiles,
reads as considerate, and is the defect. Every ternary at a call site has a third option in it, and the
third option is the one the ADR forbids.

**Which language an announcement is spoken in.** An announcement is the only copy in the app that no `Text`
draws, so it is the only copy that does not get the environment locale for free. `String(localized:)`
resolves against the *resource's* locale, and every string here is a literal created in a type initialiser
long before a screen exists — `StateCopy`'s defaults, `ErrorCopy`'s table, every component's control copy.
So the locale it captured is the **device's**, not the one the user chose in the app. With English-only copy
until Phase 5 the failure is invisible.

**How a screen passes a per-screen gate.** ADR-0012 makes the Accessibility Inspector audit a gate on every
screen rather than a Phase 5 sweep. A gate that each screen has to remember is a gate that eleven screens
will pass at different standards.

## Decision

**One clamp, with the alternative as its argument.** `hwVisualisation(replacedBy:)` in `DesignSystem/` is
the only place in the app that clamps Dynamic Type, and it cannot be called without supplying the layout
that replaces the chart. Below `HWScaling.visualisationCeiling` the chart is drawn and clamped; at and above
it the chart is **gone**, not smaller. The ceiling is `xxxLarge` and the threshold is
`DynamicTypeSize.isAccessibilitySize`, which means the two meet exactly — pinned by a test, because a gap
between them is precisely a chart that is capped with nothing having replaced it.

**The alternative is also the `accessibilityRepresentation`.** One argument, two jobs: it is what a sighted
user at AX3 sees and what VoiceOver reads at every size. ADR-0012 asks for both a replacement layout and a
chart representation; making them the same value removes the case where a screen supplies one and not the
other.

**An arrival is a value, not a ternary.** `HWEntrance` — `rise`, `pop`, `fade` — carries the transition, the
curve, and the duration, and `reduced` returns a **cross-fade of the same length**. It cannot return
nothing. Timing is deliberately not reduced: a toast that took 420ms still takes 420ms, so the event reads
as the same event at the same pace and only the travel is gone. `HWPressStyle`'s scale-becomes-opacity is
the same rule on a `ButtonStyle` and stays where it is.

**`HWAnnouncement` takes the locale explicitly**, resolving the copy against the app's chosen language
rather than the device's, and carries a priority: `.immediate` interrupts, for feedback about what the user
just did (a toast, a Learn combo), `.standard` queues. It is the only caller of
`AccessibilityNotification` in the app.

**The chrome carries the defaults.** `ScreenChrome` makes every screen one accessibility container, and
`StateView` announces a state change — which belongs there rather than in the chrome because the taxonomy is
what knows a placeholder has been replaced by a *different* placeholder. Nothing is announced for `loaded`:
there is content to explore, and a sentence saying the screen has loaded is the app talking about itself.

**No in-app motion toggle**, and it is asserted rather than agreed: every mention of
`accessibilityReduceMotion` in the app must be an `@Environment` read, and no motion preference can be kept —
`Persistence/` and `Models/` may hold neither a `reduceMotion` property, a defaults key of that name, nor an
`@AppStorage` binding.

**The scans are the continuous half**, in the spirit `LocalisationTests` established: the clamp has one
owner, nothing shrinks text to fit, nothing reorders VoiceOver focus, no screen or component can name
`Money.minor` and so cannot re-spell a figure, every screen carries an accessibility-size preview, and the
chrome still carries its defaults.

## Consequences

- A screen written in #13–#25 gets container semantics, the state announcement, and unclamped text by
  conforming to `BaseView`. What it still has to write is its own words — labels, the heading trait, and the
  alternative layout for any visualisation it draws.
- **The clamp cannot bite while the threshold sits immediately above the ceiling**, and that is the point of
  keeping both. The ceiling states the largest size a chart may be *drawn* at independently of where the
  threshold happens to be, so moving the threshold later cannot silently un-cap the chart. A test asserts
  the join rather than either number alone.
- `accessibilitySortPriority` is banned app-wide. Not eternal: a screen that genuinely needs one changes the
  scan and argues for it, which is the difference between a decision and a habit.
- **The Accessibility Inspector audit is not automated, and its automatable form needs a new target.**
  `XCUIApplication.performAccessibilityAudit()` *is* the Inspector's audit, and it runs only from a UI-test
  bundle; this project has an app target and a unit-test target. Creating the target is a GUI step, and the
  screen worth auditing is the five-tab shell, which is #5. So the audit stays a manual pass for now and the
  automatable subset — clamps, shrink-to-fit, focus reordering, re-spelled money, per-screen previews — is
  what these scans cover. Recorded as a commitment, not deferred silently.
- Announcements are posted unconditionally rather than behind a VoiceOver check. `post()` is a no-op with no
  assistive technology running, and a check at each call site is a second thing to get wrong.
- **Two costs accepted.** `HWEntrance.pop` has no caller until Learn (#20) — it is here because a vocabulary
  with one entry teaches a call site nothing about the rule, and because the confetti replacement is the
  case ADR-0012 argues hardest about. And `Money.minor` being unnameable in `Views/` and `Components/` is
  broader than accessibility; it is enforced here because a VoiceOver label is where somebody would first
  want to build a formatter, and "AED 4,200 read out as digits" is a plausible reason to try.
