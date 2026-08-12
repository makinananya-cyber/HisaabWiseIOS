# ADR-0035 — The lesson player: the submission *is* the screen, and grading is the one thing the client works out

**Status:** accepted
**Applies:** [ADR-0020](0020-screen-scoped-endpoints.md) (its fourth read, and **the first that is a `POST`**),
[ADR-0019](0019-no-offline-writes-curriculum-pdf.md) (a write that fails offline, with nothing queued),
[ADR-0012](0012-accessibility.md) (the sixth clamp consumer, the two announcements it was written for, and the
first haptics in the app),
[ADR-0011](0011-localisation.md) (a typed figure under `ar`, and eleven rotating headlines),
[ADR-0016](0016-presentation-details.md) (`{c}` in 124 steps rather than in one tip)
**Amends:** [ADR-0034](0034-learn-unit-map.md) — `GET /v1/screens/learn` gains a `currencyToken`, and the closure the
shell passed Learn for a screen that did not exist is gone; [ADR-0012](0012-accessibility.md) in one line — its
`.impact` on a lost heart is **folded into** the wrong answer's `.error`, because the two are the same moment and two
feedbacks for one event is a stutter
**Records what looking at renders found, what review found, and what this leaves** — see the last three sections

## Decision

### Grading is client-side, and the exception is **bounded** rather than argued

Invariant 10 and the ticket both say it plainly: the client grades so that a tap is answered without a round trip.
What makes that safe is not the size of the exception but its shape, and there are three limits on it:

- **It grades; it does not score.** `LessonRun` decides *right or wrong* and nothing else. It counts hearts,
  consecutive correct answers, and results — none of which is a figure the reader reads.
- **Every result is submitted.** `POST /v1/learn/lessons/:id/complete` carries one `{stepIndex, isCorrect}` per
  question, so the server recomputes the XP and can **refuse** an impossible submission: a result naming a step that
  is not a question, a question answered twice, more wrong answers than there are hearts, a lesson whose predecessor
  is unfinished. That refusal is a `422`, and it is a definite failure.
- **Every total comes back.** The XP earned, the accuracy, and the streak are read from ``LessonCompletion`` and are
  drawn by nothing else. The client is holding the results it submitted and could divide them; ADR-0020 says it may
  not, and this is the screen where that matters most, because its whole job is to tell the reader what they earned.

The tolerance is where the exception is most easily wrong, so it is the one thing tested from both sides: `< 0.5` is
**strict**, `3600.49` is right and `3600.5` is wrong, and the comparison is integer hundredths because `Models` may
hold no `Double` (ADR-0003) *and* because a floating-point tolerance has a boundary that moves with the magnitude of
the value it is applied to. `TypedAmount` does the parse, which is the app's one owner of "what did the user type" —
a decimal comma is a decimal point, and any digit script reads (ADR-0011). It gained a `scaled(from:exponent:)` that
permits **zero**, because every money form in the app refuses a zero amount and a lesson answer of `0` is a real
answer that happens to be wrong.

### The submission is a **read** — which is why the player adds no fifth error mapping

`LessonCompletionViewModel` is a `BaseViewModel` whose `fetch()` is a `POST`. That is not a stretch of the base
contract; it is what ADR-0020 already says — a write answers with the payload the screen renders, and the
celebration's payload *is* the response to submitting the lesson. Three of the ticket's requirements fall out of it
rather than being written:

| Requirement | What provides it |
|---|---|
| offline shows `LoadState.offline` with a retry, nothing queued | `BaseViewModel.load()` and `StateView`'s CTA (ADR-0019) |
| a `422` is a definite failure | the same mapping, carrying the code through `ErrorCopy` |
| the retry is the reader's, never behind their back | the CTA is a button; there is no queue and no drain |

So `StateTaxonomyTests` still names **four** owners of the `APIError` mapping and not five. The other write — the
interim `POST /v1/learn/progress` — reports *nothing* on failure: the reader has left the lesson, and replacing a
perfectly good map with an error state over a best-effort save would be the shape `loadPicklists()` avoids.

**One `Idempotency-Key` per intent, minted at `init` and reused across retries.** Finishing a lesson happens once, so
a submission that reached the server and lost its response has to be recognised rather than counted twice — the
caller-supplied form `APIClient.post` was written for and `ExpensesViewModel` established. The object *is* the
intent: a second run of the same lesson is a new player, a new completion, and a new key.

### The player is a **run**, so it holds its own copy — the opposite of the guide sheet

Learn's guide sheet holds a unit **id** and re-reads it from the current payload, so that a reload writes through
(ADR-0020, ADR-0034). The player takes its material once, at `init`, and keeps it. The two are not inconsistent: a
sheet is a *view of server state*, and a run is what the reader is doing right now. Re-reading it from each reload
would restart the lesson under them.

Which is also why the cover is presented off the **object** rather than off an id, and why closing it is the only
thing that ends the run.

### Two writes, and the second one closes with the panel

Closing a part-finished run reports where the reader got to — the step and the results so far. Two decisions in it:

- **`LearnViewModel` launches the request, not the player.** The report is a value; the panel is released at once and
  a `Task` owned by the tab's view model carries the write. A player awaiting its own request before dismissing would
  be a closing animation that waited for the network.
- **A finished run reports nothing**, because the completion has already said everything the progress route would. An
  interim report filed after it would be an older truth landing on a newer one.

The body carries `results` rather than a count of lit arcs, because `LessonProgress.filledSegments` is a figure the
*screen* draws and ADR-0020 gives it to the server. A ring whose fill came from the client on Tuesday and the server
on Wednesday is a ring with two owners.

### `{c}` needs a token, so the Learn payload gains one

The curriculum is cacheable and identical for everybody, and the content rules require `{c}` verbatim in all 124
steps. The *symbol* is this reader's. So `GET /v1/screens/learn` carries a `currencyToken` — which is exactly how
Home's tip already works, because a cacheable tip pool cannot carry one user's currency either — and the replacement
moved into a `CurrencyToken` type with one owner (ADR-0016). The amounts beside the token are **illustrative and
never converted**: a worked example keeps the numbers it was written around and only the symbol follows the account.

The one place a figure is *not* given a symbol is the "right answer" line after a wrong numeric answer. The design
writes `asMoney(s.correct)`; the client owns no formatter (ADR-0003), and a symbol pushed onto the front of a string
lands on the wrong side of an Arabic figure — the same finding ADR-0033 records for an incoming expense. The input
box draws its symbol as a **view beside the field** for that reason, where the layout mirrors it for free.

### Reduce Motion, and the two announcements ADR-0012 was written for

| The design | Under Reduce Motion |
|---|---|
| the combo pill springs in, holds, floats away | a cross-fade, plus an **announcement** — `.immediate`, because it is about the answer just given |
| 34 pieces of confetti fall | nothing falls; the badge, the XP tile, and an **announcement** are what the celebration is |
| the badge scales in from 0.3 and rotates | it has already arrived |
| the step slides in from the right | it cross-fades (`HWEntrance.rise.resolved(reduceMotion:)`) |
| the heart pulses when one is spent, `.wd.today` bumps | dropped rather than gated — an attention loop's only replacement is the thing itself, and the sentence beside the hearts already says how many are left |

The confetti is **deterministic**: its positions, sizes, and durations come from the piece's index, for the reason
`HWBrandGround`'s star field is transcribed rather than randomised — a celebration that is a different picture on
every render is a picture nobody can review.

**The app's first haptics** (ADR-0012): `.success` on a right answer and on a landed completion, `.error` on a wrong
one. The ADR also names `.impact` for a lost heart, which is the *same moment* as a wrong answer — two feedbacks for
one event is a stutter, so the error carries both.

### The week strip is **replaced** at accessibility sizes; the three tiles become a column

The fourth of ADR-0012's four named visualisations, and the last to arrive. Seven 26pt circles with two-letter
captions have nowhere to grow, so above the threshold the same seven days are **rows** built from the server's own
per-day sentence — which is also the strip's `accessibilityRepresentation` below it.

The three completion tiles are a *layout* choice rather than a clamp, which is the distinction `HWSpendSummary`
records: a row of three at accessibility sizes leaves each about 100pt, and `+1,500` breaks across three lines.

### Every count and label the reader hears is a value, not an assembled sentence

`Step 4 of 8`, `2 of 3 hearts left`, `Combo — 3 right in a row`, and each day's `Sunday, lesson finished` are
catalogue entries with **numbered** arguments or server strings. The numbers are converted where they are *computed*
(`LessonRun.stepNumberText`, `Curriculum.Step.Numeric.answerText`), which is the convention the localisation scan
depends on: it derives `key %@` from the source and cannot know that `\(anInt)` resolves to `%lld`.

The design's eleven feedback headlines are kept — seven `PRAISE` and four `ENCOURAGE` — because the variety is its
own retention behaviour rather than decoration, and because none of the four ways of saying "no" says *wrong*. The
rotation is derived from the run rather than random, so the same answer always produces the same words and a test can
state which.

## Consequences

**The rules the ticket names are asserted, each in the layer that owns it.** The tolerance boundary, hearts
exhaustion, and the combo interval are `LessonRunTests` — a value with no transport in it. The submission's shape,
the four states it lands in, and "a replay earns no XP" are `LessonPlayerViewModelTests`. The mappings and the copy
are `LessonPlayerViewTests`.

**Defect D13 is two payloads.** `lesson-completed.json` is a first completion — three of four right, so 50 XP and
75% — and `lesson-revisited.json` earns **zero** with an XP total byte-identical to `learn-in-progress.json`'s. That
is what makes "a replay earns nothing" a numeric assertion rather than a reading of a headline. The accuracy is
deliberately not 100%, because a screen computing its own accuracy looks right against a perfect run.

**A run that ends on an empty heart is not `isFinished`.** Two states that look alike are kept apart on purpose:
finished means every step is behind the reader and *submits*; out of hearts means the run is over and nothing is
filed. `advance()` refuses to move, so there is no step after it to draw.

**`LessonRun.Answer` has one case per question kind**, so "a typed figure on a multi-select question" is not a state
anything can be in — the same reason `Curriculum.Step` has one discriminator instead of two.

**The player is not a `BaseView`**, because it makes no request. It is the second such screen after Landing, and the
reasoning is the same: there is no `LoadState` to draw. What has one is the celebration.

**`HWRunButton` is not a fifth `HWButtonVariant`.** `HWButtonAppearance` resolves a fill from a variant, an
appearance, and the palette; this control's fill is the *unit's* accent while a question is open and the *verdict's*
colour once it has been graded, neither of which that type can see. Folding them in would also make `.primary` with a
verdict representable.

**Nine new components, and the vocabulary rule held**: no screen in this ticket styles a control. `HWRunHeader` ·
`HWComboBadge` · `HWKicker` · `HWRunButton` · `HWAnswerOption` · `HWAnswerField` · `HWFeedbackNote` ·
`HWTeachingEntry` · `HWWorkedExample` · `HWTeachingTip` · `HWDoneBadge` · `HWCompletionStat` · `HWCompletionStats` ·
`HWWeekStrip` · `HWConfetti`.

## What looking at renders found

**The multi-select boxes were circles.** The design says which kind of question this is with the *shape* of the box —
a square for "pick every right answer", a circle for "choose one" — and `HWRadius.small` is 11pt, collapsed from the
design's 10–12px cluster around **large** controls. On a 24pt box that draws a circle, so the two kinds of question
looked identical side by side. `.hairline` is the step that reads as a square at this size. Nothing about this was
visible in the code; it took rendering the two pages and putting them next to each other.

**A `TextField` cannot be photographed.** `ImageRenderer` yields the unsupported-view glyph for one — the same
yellow field with a red bar `CONTEXT.md` records for `TabView` and `NavigationStack`. So the numeric step's render
proves the page lays out around the box and says nothing about the box, which is worth knowing before the snapshot
suite (#9) treats a green render as a picture.

**`loadedContent` cannot be called from outside a hierarchy.** A view's `@Environment` is populated when *its* body
is evaluated, so invoking the method directly traps on the missing `ThemeManager`. A loaded `BaseView` render has to
go through the chrome, which is what the note in `CONTEXT.md` already says about the spinner.

**The tip's caption is stacked, not inline.** The design writes `<b>Remember it:</b> ` followed by the sentence, in
one paragraph. Doing that here would mean joining app copy onto server content, which is exactly the sentence
assembly ADR-0011 forbids (`LocalisationTests` scans for `+ Text(`). So the caption sits on its own line — a
deliberate departure, visible in the render, and cheaper than an untranslatable sentence.

## The compiler finding

**A partially-applied `@MainActor` method crashed IRGen.** `set: viewModel.type` and `onChoose: viewModel.choose`
both compile as far as the type checker and then abort in `SyncCallEmission::setArgs` with
`report_at_maximum_capacity` — no diagnostic, no line number, just a frontend crash on the whole file. Wrapping each
in a closure (`{ viewModel.type($0) }`) fixes it. Recorded because the two forms read as equivalent, because `LearnView`
passes `onOpenGuide: viewModel.openGuide(unitID:)` in the crashing form and builds, and because the failure looks
like a broken toolchain rather than a line of code.

## The eight things review found

**A preview helper spun for ever.** `previewNumeric` walked the run with `while player.run.index < 6 {
player.primaryAction() }`, and `u1l1`'s numeric step sits behind two single-choice ones: an unanswered question is not
`isReadyToCheck`, so the press moved nothing and the loop never ended. "The player — a typed answer" hung Xcode rather
than drawing anything, and nothing noticed because **no test used a preview**. The walk now answers each question on
the way and stops if a press changes nothing, and `LessonPlayerViewTests` asserts that all five previews land where
they claim — under a time limit, so a regression fails rather than hangs.

**A parameter read by nothing.** `LessonCompletionView` took a `tint`, threaded from the player, and never used it.
Chasing it back through the design is the interesting part: `#done` *is* given `u-<accent>`, and nothing inside reads
it — the badge is the sun gradient, the button is mint, the tiles are fixed. So the parameter is gone rather than
wired, which is the `.stat--crown` answer applied to a class that *is* set.

**A haptic that could never fire.** `.sensoryFeedback(.success, trigger: completion.xpEarned.value)` reads correctly
and never plays: the content is built only once the submission has landed, so the figure's first value is its only
one and nothing ever transitions. It triggers on a `@State` flag the announcement task sets instead.

**The dialog covered the sentence explaining it.** The third heart goes *inside* `check()`, so an alert bound straight
to `run.isOutOfHearts` appeared over the footer explaining the answer that ended the run. The design waits 700ms
(`setTimeout(outOfHearts, reduced ? 0 : 700)`) and not at all under Reduce Motion; so does this.

**Seven accessibility labels were discarded.** `hwVisualisation` defaults to `describesItself: false`, which installs
the alternative as the chart's representation — so the week strip's per-day sentences, built onto each circle, were
read by nothing. It passes `true`, which is what ADR-0025 says the flag is for and the mirror image of the mistake it
records the donut making.

**One table written eight times.** "Mint means right, coral means wrong" was re-derived in an option's box, its fill,
its border, the typed box's fill and border, the feedback note, the button, and the footer. It is
`HWPalette.Units.verdict(isCorrect:)` now, beside `accent(_:)` — each site still picks its own value from the triad,
which is the part that legitimately differs.

**Two pass-throughs that left the view reaching past them.** `LessonPlayerViewModel` forwarded `step` and
`isOutOfHearts` to the run while the screen read `run.verdict`, `run.index`, `run.stepCount`, `run.heartsRemaining`,
`run.isReadyToCheck`, and `run.results` directly. The forwarding is gone: one owner of "what is the run doing" beats
a shorter call site.

**A report thrown away.** `closePlayer()` guarded on `run.index > 0`, so a reader who answered a question without the
index moving had their results dropped. It guards on there being anything to report.

## What this leaves

**The XP rule lives in the ADR, the fixtures, and the contract — not in the client.** 10 a correct answer plus a 20
completion bonus, first completion only, is the server's arithmetic (invariant 10). The client cannot assert it and
must not: a test that checked the sum would be a second implementation of it. What the client asserts is that it
sends what the server needs and draws what comes back.

**Nothing scrolls the map to the lesson that has just unlocked.** ADR-0034 left the `ScrollViewReader` open pending
"somewhere to continue to"; there is one now, and the decision is still worth making with the completion's own
Continue in hand rather than inside this ticket.

**The out-of-hearts dialog is a system `alert`.** The design draws an illustrated modal with a heart-and-cross icon;
an alert is announced, cannot be dismissed by accident, and reads as two choices — the reasoning `LogoutControl`
records. What is lost is the illustration.

**A run reports only on an explicit close.** `POST /v1/learn/progress` fires when the reader dismisses the player;
backgrounding, termination, and a sign-out send nothing, so a lesson abandoned by switching apps loses its position.
Wiring that up means a `scenePhase` reader, and `scenePhase` has exactly one in this app — the composition root, which
passes it as an argument precisely so that no view can grow a second (ADR-0026). It is a change to the root's
foreground sequence rather than to this screen, and it is worth making with ADR-0008's other consumers in view.

**A run does not survive the app being killed.** `POST /v1/learn/progress` saves the reader's *position*, and nothing
restores it into a new run: opening a lesson starts at step 0. The ring behind the map fills, which is what the
design's own partial progress does, and "resume mid-lesson" would need the server's stored position to come back on
`GET /v1/screens/learn` — a payload change to make with the route, not around it.

**White text on the `sun` band is still about 2.5:1**, and the celebration adds a caller: the done badge is the sun
gradient with a white tick on it. A glyph needs 3:1 rather than 4.5:1 and the tick is 52pt-ish, so it clears the bar
the small text on that band does not — the shortfall ADR-0034 measured is unchanged and still wants a fourth
`HWPalette.UnitAccent` slot.
