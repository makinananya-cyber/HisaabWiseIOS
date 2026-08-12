# ADR-0034 — Learn: two endpoints joined by id, and a path that is replaced rather than shrunk

**Status:** accepted
**Applies:** [ADR-0020](0020-screen-scoped-endpoints.md) (its third read, and **the first that is not one request**),
[ADR-0009](0009-content-cache.md) (the curriculum, and the store's largest resource),
[ADR-0019](0019-no-offline-writes-curriculum-pdf.md) (why the store exists now, and what still fails offline),
[ADR-0012](0012-accessibility.md) (a fifth clamp consumer, and the first whose replacement is a *layout* rather
than a chart's figures),
[ADR-0003](0003-money-presentation.md) (applied to two figures that are not money)
**Amends:** [ADR-0009](0009-content-cache.md) — nothing it decided; its `/v1/curriculum` resource now exists and is
keyed like the rest
**Records six things looking at it running found, six review found, and what this leaves** — see the last three
sections

## Decision

### Learn reads **two** endpoints, and that is invariant 8 choosing where the seam goes

ADR-0020 says one read endpoint per screen. Learn has two, and the reason is not that the rule bends: the two halves
of this screen have **opposite cache rules**, and neither can be folded into the other without breaking one.

| | `GET /v1/curriculum` | `GET /v1/screens/learn` |
|---|---|---|
| What | 5 units · 15 lessons · 124 steps · answer keys | streak · XP · cursor · unlock states · ring counts |
| Who for | everybody, byte for byte | one reader |
| Caching | ETag, stored on disk (invariant 8) | bypasses every cache (invariant 8) |
| Size | ~100 KB | ~3 KB |

Folding the curriculum into the screen payload would make editorial content per-user and throw the ETag away —
100 KB on every visit to a tab. Folding progress into the curriculum would make a cacheable response describe one
reader, which is the breach invariant 8 is actually about. So the client asks for both, **concurrently**, and joins
them **by lesson id**.

**The join is a lookup, not a calculation.** It introduces no figure that was not in one of the two responses: every
lock, every count, every label, and the ordering arrived computed. That is the test the exception has to pass, and it
is why the join happens in one place — `LearnMap`, built in the view model — rather than as fifteen lookups inside a
`body`.

### The payload's field names are the list of things the design worked out in the browser

| The design | The payload |
|---|---|
| `isOpen(id)` walking `FLAT` for "is the previous one done" | `LessonProgress.state` |
| `firstOpen()` scanning for the cursor | `nextLesson` |
| `unitOpen = u.lessons.some(isOpen ‖ isDone)` | `UnitProgress.isUnlocked` |
| `qCount(l) = steps.filter(t === 'q').length` | `LessonProgress.segments` |
| `done ? segs : (progress[id] ‖ 0)` | `LessonProgress.filledSegments` |
| `state.streak` diffed against `new Date()` via `lastActive` | `streak`, and **no date at all** |

The last row is invariant 6, and the fix is the stronger form of it: the payload carries no date, no timestamp, and
no day key, so the client **could not** re-derive a streak if it wanted to. The design kept
`lastActive: dayKey(-1)` and compared it against the device clock, which means moving the clock moved the streak.
`LearnViewModelTests` asserts the absence — of `Date`, `Calendar`, and a day key — across all five Learn files,
because "the number is copied through" is the only other thing a test could say and it says nothing.

**The two ring counts are `Int`s and no new `Double` joins the geometry exemptions.** A segmented ring's geometry
*is* two counts — how many arcs, how many lit — so `MoneyFormattingAbsenceTests`' list of three named fractions
stays three. The client could have counted the curriculum's own question steps instead, which is exactly why it does
not: a count is a calculation, and a ring whose segments came from one response while its fill came from another is
a ring with two owners. `FixtureCorpusTests` asserts the corpus's two halves agree; `LearnViewModelTests` sends a
payload where they **do not** and asserts the screen draws the payload's figure, which is the only way to tell a
client that reads from a client that counts.

### `Stat` is `Money`'s shape applied to a figure that is not money

The streak and the XP each arrive three ways — `value`, `display`, `accessibilityLabel` — and each has a caller the
other two cannot serve:

- **`display`** because the client has no formatter (ADR-0003). `1500` has to reach the pill as `1,500`, and the
  client that spelled it would be the client deciding what a thousands separator looks like in Arabic.
- **`accessibilityLabel`** because "4-day streak" is a count *and* a plural, and Arabic has six plural forms
  (ADR-0011). The design leans on a `title` attribute here, which touch never surfaces at all.
- **`value`** because it is drawn by nothing, and that is its job: it makes "Home and Learn agree about the streak"
  a numeric assertion. Two formatted strings can be wrong in the same way; two integers cannot be equal by accident.

The **unit number** deliberately does *not* arrive formatted, and the difference is real rather than an
inconsistency: 1…5 has no separator and no plural, so `String(_:)` is the whole of its formatting. It is spelled in
`Curriculum.Unit.numberText` — in the model, where a number is converted *where it is computed*, because the
localisation scan derives `key %@` from the source and cannot know that `\(anInt)` resolves to `%lld`.

### `LessonState` refuses to guess; `Accent` and `Icon` degrade

The ADR-0033 rule, applied again and to the mirror-image case. `Accent` and `Icon` degrade to the design's own
fallbacks (`--acc: planetary`, `ICON[l.icon] || ICON.book`) because they are presentation: a unit in the wrong tint
is a blemish.

`LessonState` decides whether the reader can open a lesson, and **both fallbacks are wrong in a way the reader
cannot get out of** — guessing `locked` strands them in front of a lesson they have earned with no way to ask again;
guessing `available` offers one the server will refuse. So an unrecognised state fails the decode and the screen
renders `LoadState.failed`, which is honest and has a retry on it. A fourth state is a coordinated release.

`Step`'s kind refuses for a related reason that belongs to #20: it decides what the player *does*, grading is
client-side, and grading the wrong thing tells a learner they are wrong when they are right.

### The client renders the lock; the server enforces it

A locked node draws a padlock and, when pressed, **says why** — the design's own
`say('Finish the lesson before it to unlock this one.')`. Two things follow.

**It is not a disabled control.** The design's `<button>` *is* `disabled`, and its refusal comes from a click handler
on the container that fires anyway; a SwiftUI `.disabled(true)` button fires nothing, so a reader would tap a padlock
and be told nothing. Enabled-with-a-refusal delivers the same experience by a less strange route, and the VoiceOver
hint says so before the press.

**A client that got the lock wrong costs nothing.** The rule lives server-side, so the worst a stale lock does is
refuse a lesson the next reload offers. That asymmetry is what makes rendering the lock client-side acceptable at
all.

### The path is **replaced** at accessibility sizes, not shrunk

The fifth consumer of ADR-0012's clamp pattern, and the first whose replacement is a *layout* rather than the same
figures as rows. A 78pt ring with a wrapping label under it, swung 56pt off the centre line, has nowhere to grow —
the labels of two adjacent nodes collide before AX3. Above the threshold the path is gone and the same lessons are a
plain column of `HWLessonRow`s, which is text and scales to AX5; below it, the same rows are the path's
`accessibilityRepresentation`, so a VoiceOver user reads the list at every size.

**The rows are the guide sheet's rows.** One component, two callers: both want a number, a title, a line of detail,
and a status glyph, and a second component would be the same row drawn twice.

### The connectors are **measured**, and that is the RTL fix

The dotted curves between nodes are drawn from each node's frame, read out of a named coordinate space after layout
— which is what the design does with `getBoundingClientRect()`, and for the same reason: where a node ends up
depends on how its label wrapped.

Measuring also makes the whole path mirror for free. A hand-computed `x` would have needed the layout direction read
and negated, which is the class of bug `HWSavingsMeter` records for its pin: an `offset(x:)` is screen-rightward
whatever the direction. Measured frames come back already mirrored. The swing itself is an **alignment** inside the
full width rather than an offset, for the same reason.

The curve is a cubic leaving one node straight down and entering the next straight down, so it sweeps around the
ring and its label instead of cutting through them — which is what the design's rotate-and-bow arithmetic achieves
by a longer route, and it needs no direction of its own.

### Three animations are dropped rather than gated, and one grey is not the design's

**Dropped:** the `START` flag's 1.6-second bob, the current node's `breathe`, and the per-node `pop` entrance.
ADR-0012's rule is *replace, never remove*, and the replacement for a continuous attention loop is the thing
itself — a bordered flag in the unit's accent is already the loudest element on the screen. Gating them on
`accessibilityReduceMotion` instead would leave two components in the "animates without offering a replacement"
shape that `ComponentVocabularyTests` exists to catch.

**Not the design's grey:** a locked unit header is `linear-gradient(#A9B2C7,#8B95AE)` with white text, which is
about **2.9:1** — under the 4.5:1 the rest of this palette is asserted against (`ColorAssetTests`), and neither grey
is a token. It becomes the `locked` role with the surface's own ink on it, which passes comfortably and keeps the two
states as far apart as the design intends.

`.stat--crown` is in the stylesheet and nothing renders it, so it is not converted.

### `/v1/curriculum` is cacheable and is not under `/v1/content`

Invariant 8 names three cacheable families — `/v1/content/*`, `/v1/curriculum*`, and `/v1/fx/rates` — so this is the
second of them rather than an exception to the first. It sits on its own root because the curriculum is the
*product*: the PDF (#25) and any per-unit or per-locale variant hang off the same path, and burying them under
`content` would make `/v1/content/curriculum/pdf` the address of the app's headline feature.

`ContentLoaderTests` used to assert one `/v1/content` prefix; it now checks the invariant's own list, and asserts the
converse too — that no per-user route sits inside a cacheable family.

**The reason for storing it has changed and the storage has not.** ADR-0009 kept the curriculum on disk so the
lessons would work without a connection; ADR-0019 gave that job to the server-generated PDF. What is left is latency
and data use, which is a smaller claim and still a good one — and the ticket asks for it to be recorded rather than
inherited.

### Answer keys ship, on the responsiveness argument alone

Invariant 10, and the ticket is explicit: do not strip them. Grading is client-side so a tap feels immediate, and
the server recomputes XP from the submitted per-question results and rejects impossible ones. The old
justification — offline lessons — went away with ADR-0019, and the decision survives it: the cheating incentive in
a free app with no leaderboard is nil, and a round trip per question is a worse lesson.

## Consequences

**The counts are the acceptance test, asserted exactly.** 5 units · 15 lessons · 124 steps — 58 teach and 66
question, of which 50 single-choice, 14 numeric, 2 multi-select. The prototype's own "115 steps" comment is stale.
`CurriculumTests` asserts each number rather than a range, because a range passes a lesson that lost a step, plus
the things a count alone would not catch: no empty step, every answer key present and in range, no HTML surviving
the markdown conversion, `{c}` verbatim with no hardcoded symbol anywhere, and every lesson carrying its own glyph
rather than the `book` fallback.

**The design's two step discriminators became one.** `t: "teach" | "q"` plus a `kind` on the questions is a pair
whose invalid combinations are representable; one four-case enum is not, and the player gets one `switch`.

**`Curriculum.Step.Numeric.answer` is an `Int`, by content rule.** All fourteen answers are whole — a net pay, a
number of years, a percentage — and `Models` may hold no `Double` outside the named geometry fractions. A fractional
key is therefore a coordinated content-and-client change, which is the right price for it. The strict `< 0.5`
tolerance the design grades with belongs to the player (#20), where a typed string becomes a number.

**`HWUnitTint` is a selector, not a triad.** Which of the five accents travels as a name and
`HWPalette.Units.accent(_:)` is the one place it becomes colour, so the dark-mode swap stays a swap and no component
or screen carries a second copy of the five-way table.

**A lesson the payload says nothing about is skipped**, not invented and not fatal. A curriculum deployed ahead of
the screen assembly is a transitional window; dropping one node beats rendering a lock the server did not send and
beats failing fourteen good ones. A unit whose every lesson went missing goes too, because a unit header over empty
space is a band of colour saying nothing.

**The corpus grew a cross-payload assertion it could not make before.** `home-first-run.json` pointed **Continue**
at a lesson called "Money, plainly" that no unit carries — #17 had no curriculum to check it against, and the teaser
is a *title* rather than an id, so nothing about it would ever have failed. It now names the curriculum's first
lesson, and `FixtureCorpusTests` asserts that every lesson either payload names exists.

## What looking at it running found

**The extraction lost every explanation.** The first pass mapped the design's `q`, `a`, `correct`, and `prefix` and
silently dropped `why` — the sentence shown after grading, which is the *teaching* half of a question. Nothing about
the map noticed: 124 steps still decoded to 124 objects, and the counts were right. What caught it was the model
requiring the field, which is the argument for a non-optional `explanation` rather than a lenient one — a question
with nothing to say after the answer is not a question, and a `String?` would have shipped 66 blanks past every
count in `CurriculumTests`.

**Two `Text`s built from the same localised key are not `==`.** `LocalizedTextStorage` compares by identity, so an
equality assertion about the unit caption passed or failed for reasons having nothing to do with the caption. It is
now three assertions that each mean something: the number is spelled where it is computed, the catalogue entry
numbers both arguments, and no two units share a caption — the last being what proves neither argument is dropped on
the way in. `ExpensesViewTests` had already found the shape of this and only ever asserts that two of them *differ*.

**The connectors ran through the labels.** The first version left each node's *centre* going straight down, which is
directly through the lesson title underneath it — a dotted line through the middle of "Emergency Fund". The design
avoids this with its rotate-and-bow arithmetic; this avoids it by measuring one more number, the bottom of the whole
node **column**, and leaving from there. The curve arrives at the top of the next node's ring, which is the
asymmetry the collision required: a node's own label is under it, and the next node's is under *that*.

**Three colours the design specifies were illegible, and all three are the same mistake.** An accent's `base` and
`deep` are **fill** colours, and the design uses them as ink:

| Where | The design | Measured | Now |
|---|---|---|---|
| `.unit-n` number tile | `rgba(255,255,255,.22)` behind white | a ghost on the sun band | white tile, `accent.deep` numeral |
| `.unit-guide` button | translucent light + sky-blue ink | same | the `surface` icon button |
| `.unit-cap` eyebrow | `--sky` on the accent gradient | ~1.6:1 | the band's own ink at the eyebrow's step |
| `.gi-n` row chip | `--acc-deep` on `--acc-soft` | 2.6:1 on sun | `surface.ink` on the wash, >13:1 |
| `.gi-s` open glyph | `--acc` on a white card | 1.9:1 on sun | `accent.deep`, 3.4:1 |

The eyebrow is the one that could not be fixed by passing an argument: `hwEyebrow` resolves its own colour and
cannot be overridden from outside — the rule CONTEXT records as *a style that paints inside itself cannot be
overridden from outside*. Its `brand` value is the design's sky blue, drawn for the galaxy ground, and a unit band
is neither of the design's two surfaces. The header draws the caption itself, at the eyebrow's type step.

**A `VStack` compresses rather than overflows, which made a render assertion meaningless.** `TestBench.render` pins
390×300, and the unit map is about 2,700pt tall: handed 300, the page squashed — and two different payloads squashed
into the *same* picture, so "three states draw three pictures" failed for a reason that had nothing to do with the
page. `render` now takes an optional height, and `nil` lets a page taller than a phone have the height it asks for.

## The six things review found

**A comment claimed a parity nothing kept.** The `START` flag is hidden from VoiceOver — it is a second element
saying something about the node beside it — on the stated grounds that "the node below says it is the next lesson in
its own hint". It did not: the node's hint was only "Starts the lesson", the same as every other open lesson's, and
`Node.isNext` reached **no accessibility surface anywhere**. A reader could not tell which of fifteen lessons was
the cursor. There is a third hint now, and one table — `HWComponentCopy.lessonHint(state:isNext:)` — that the node
on the path and the row in the guide sheet both read. *Accessibility is a parity requirement, not polish*, and a
comment asserting the parity is the worst form of getting it wrong.

**A figure the reader sees was derived from an array index, at two call sites.** `number: String(index + 1)` in the
guide sheet and again in the accessibility-size replacement — which is ADR-0020 broken twice, and by a rule
`Curriculum.Unit.number`'s own documentation states in the same file. `Curriculum.Unit.Lesson` carries a `number`
now, the extraction emits it, and `HWLessonTrack.Node` passes it through. The two lists could have disagreed.

**A sheet that re-presented itself.** Presentation was bound to `openGuideUnit != nil` — the *resolved* unit — so a
reload that dropped that unit flipped presentation to `false` with no dismissal writing through: the id stayed set,
and the sheet came back the moment the unit did. It binds to `isShowingGuide` (the id) now, and a vanished unit
closes rather than drawing an empty panel. Presentation follows the thing a dismissal clears.

**An assertion one payload away from vacuous.** `#expect(home.learning.summary.contains(learn.nextLesson?.title ??
""))` is `contains("")` — always true — the day a fixture has no cursor. It requires the cursor now.

**Three referencing errors in doc comments**, each pointing somewhere real and wrong: a claim attributed to
`CurriculumTests` that belongs to `FixtureCorpusTests.theCorpusAgreesAboutRingSegments`; a `` ``streakLabel`` ``
that no longer exists (`Stat.accessibilityLabel`); "absent means no symbol, which is the commoner of the two" about
a field the curriculum sends on all fourteen numeric steps, eleven of them `true`. Plus "88 KB" in five files for a
101 KB document.

**Three couplings and one representable-wrong state.** `78` was written twice in one file, and the connector landing
on the ring is correct only while the two agree — the track reads `HWLessonNode.diameter` now. The same
`AnyShapeStyle` gradient construction appeared in the unit band and the lesson face, differing only in which locked
colour stands in — one `hwAccentGround` function now. And `HWStatChip` took `tone` *and* `systemImage`, so
`.streak` with a star was representable; the glyph moved onto `Tone`, which already owned the flame's colour.

## What this leaves

**Pressing an open lesson goes nowhere yet** — *settled by [ADR-0035](0035-lesson-player.md), which brought the
player and with it a `currencyToken` on this screen's payload; the closure below is gone.* The lesson player is #20.
The seam is a closure the shell supplies —
the shape Home's two CTAs already have — rather than a `navigationDestination` for a view that does not exist, which
would be a fictional route in the client for the reason `UnwrittenTabRoot` makes no request. Everything else on the
screen is real: the guide sheet opens, and a locked node refuses with the design's own sentence.

**The steps are decoded and nothing draws them.** 124 steps, their answer keys, and their markdown are in the model
and in the store because the ticket asks for the curriculum *loading* that the player will need, and because the
counts are this ticket's acceptance test. `HWMarkdown` is what will render them.

**Home still carries `learning.summary` as a composed sentence.** "120 XP · next up, Needs vs. Wants" is one server
string, so the corpus asserts it *contains* Learn's XP display and Learn's next-lesson title rather than equalling
anything. A stronger assertion needs Home's mini-card to take the pieces, which is a change to a screen this ticket
does not own.

**White text on the `sun` band is still about 2.5:1, and no token fixes it.** The five accents cannot share one ink,
and this is the arithmetic rather than an impression — contrast of the band's two ends against white, and against
the surface's own galaxy ink:

| Accent | white on `base` … `deep` | galaxy on `base` … `deep` |
|---|---|---|
| sun | 1.9 … 2.9 | **8.2 … 5.3** |
| mint | 3.1 … 5.3 | **5.0** … 2.2 |
| coral | 3.5 … 4.7 | **5.1** … 2.0 |
| violet | 4.3 … 6.7 | 3.6 … 1.6 |
| sky | **7.3 … 15.5** | 2.1 … 1.1 |

White passes on sky and violet; galaxy passes on sun, mint, and coral; neither passes on all five. What this needs is
a **fourth slot on `HWPalette.UnitAccent`** — an `ink` value chosen per accent, asserted by `ColorAssetTests` the way
the six category slots already are. That is a palette change with five new colour sets in it, which is a change to
make on its own rather than inside a screen ticket. Until then the band keeps the design's white, the two states stay
as far apart as the design intends, and the *small* text on the warm three is the shortfall — measured here so it is
a decision somebody made rather than something nobody looked at.

**The clock test is an absence, not a clock.** The ticket asks that "a device-clock change does not alter the
streak", and the test asserts the absence — no `Date`, `Calendar`, or day key in any of the five Learn files, and no
date, timestamp, or day key in any of the three payloads. The literal form would need `NSTimeZone.default`, the only
process-wide lever, and three suites here compare a request body's `timeZone` against `TimeZone.current.identifier`
*at assertion time*; Swift Testing runs suites in parallel, so mutating it would make those three flaky. A test that
breaks other tests to assert an absence is a worse deal than asserting the absence directly.

**The unit path is not scrolled to the cursor.** `nextLesson.unitID` is in the payload precisely so a screen can do
it without searching the curriculum for a lesson's parent, and nothing does yet: a `ScrollViewReader` that moved the
view on every load is a decision worth making with the player in place, when "continue where you left off" has
somewhere to continue to.
