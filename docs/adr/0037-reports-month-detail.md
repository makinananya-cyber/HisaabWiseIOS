# ADR-0037 — One closed month: four segments, a pinned snapshot, and a scroller left behind

**Status:** accepted
**Issue:** #22 — Reports: per-month detail, split bar, pinned FX immutability
**Builds on:** [ADR-0036](0036-reports-archive.md) (the archive, and the row with nowhere to go),
[ADR-0020](0020-screen-scoped-endpoints.md) (screen-scoped endpoints),
[ADR-0032](0032-home.md) (the donut and the meter), [ADR-0033](0033-expenses.md) (the summary card),
[ADR-0012](0012-accessibility.md) (replace, never shrink),
[ADR-0003](0003-money-presentation.md) (the server converts and formats)

## Context

The month detail is the second level of Reports: one closed month in full — its totals, its own donut, the savings
meter, the wants allowance, a bar showing where the whole month's income went, an accordion of **every** entry that
was logged, and a "For the record" facts grid.

It is also the screen **invariant 7** exists for. An archived month is immutable and carries the FX rate set pinned
at close; changing display currency later converts the figures through *those* rates and must never change the
story. A met goal stays met.

The prototype computed the whole page in the browser from one `ARCHIVE` literal. `budget(m)` re-implemented the
adaptive 50/30/20 engine; `goalPct(m)` divided a **stored** `saved` by the goal so `verdict(m)` could threshold the
quotient; `drawSplit()` reduced four amounts to widths; `drawFacts()` composed six labelled figures; `dayLabel(m,
day)` built a date with `new Date(...)`; and `drawAcc()` counted entries and pluralised the count. Each of those is
a figure, a total, a date label, a verdict, or an ordering — so each of them is the server's (ADR-0020).

## Decision

### One `GET /v1/screens/reports/:monthKey`, and the figures on it are a snapshot's own strings

The payload carries the page: `totals` with the engine's `isAdapted` flag, `spending` with one slice per category
that has something in it, `savings` with the meter's position and the sentence-choosing optionals, `wants` with the
allowance and the over verdict, `split` with **four** segments, `groups` with seven categories and their entries,
and `facts` with six kinds. `ReportsMonthViewModel` owns exactly two pieces of presentation state — which slice is
isolated, and which panel is open — and neither is a figure.

**Re-reading the address is what a currency change is.** There is no client-side conversion to invoke and none
available: the client holds no rate, `Money` has no arithmetic, and every figure arrives formatted. So the
invariant-7 regression test is a *sequence on one path* — February in rupees, then February in dirhams — asserting
that every monetary display string differs and that the verdict, the percentage, the meter position, and every
geometry fraction are identical. The corpus carries both payloads, generated from one table of authored rupee
figures so that they cannot drift apart by hand.

### It carries `saved` and `goal`, where the archive carries neither

ADR-0036's whole client-side defence against defect D11 was **absence**: the archive draws a badge, so a `saved` on
it would be a figure with nothing to do but be thresholded. This screen draws the savings *meter*, which is the
shape Home's is — so both figures are on the wire for the reason Home's are, and the protection is the same one Home
has: no percentage arrives as a number, the verdict arrives as a verdict, and there is no arithmetic to threshold
with. Stating that difference is the point; a reader comparing the two payloads should not have to guess whether one
of them slipped.

### The split bar's fourth segment is the Product Spec overruling the design

The design draws `needs / wants / savings / left unspent`. Under §4.2's residual definition of `saved` — income
minus needs minus wants, clamped — the fourth is **identically zero**: all spending is one or the other, so there is
no remainder. §4.2 **[FIX]** replaces it with the **surplus above goal**, and the four become `needs / wants /
min(saved, goal) / max(0, saved − goal)`, which add up to income exactly whether the goal was reached or missed.

`Portion` therefore **refuses to guess**, where `Fact.Kind` degrades. A fifth part drawn as one the client happened
to recognise is a bar whose segments no longer sum to the income printed beside them, about a month that cannot be
corrected — so it is a coordinated release, exactly as `ReportsScreen.Verdict` and `ExpensesScreen.Kind` are. A
seventh *fact* is the opposite case: the grid is a set of tiles and the label is the app's, so an unknown kind has no
words to draw itself with. Dropping one tile is additive; failing the month over an extra figure nobody asked for
would take a whole immutable record away. The corpus also asserts the **absence of the name** `leftUnspent` on the
wire, because a `Portion` that merely failed to decode a fifth part would make a server that had added one invisible.

### The surplus is the one colour that is not transcribed

`.split i` takes `--s1`, `--s5`, `--r5`, and a flat `#C6D5EA` grey for "left unspent". The first three convert
directly — the category slots the donut gives Rent and Entertainment, and the top of the savings ombré. The fourth
described a different quantity, so it gets `--r4`: the neighbouring stop of the ombré `saved` comes from, which
reads as "the same thing, more of it" rather than as a fourth unrelated colour.

### The bar is replaced by the key that is already under it

ADR-0012 requires the bar to be *replaced* above the accessibility threshold, and `HWScaling`'s own note has named
the four-segment split bar as one of the four visualisations since #7. The list it is replaced by is the design's
`.split-key`, which is drawn at **every** size — so the alternative is `EmptyView()` and the key stays where it is.
That is the call `HWDonut` already makes and the trade ADR-0032 recorded: passing the key as the alternative *as
well* draws it twice at accessibility sizes, and passing it *only* there leaves the parts unnamed at ordinary ones.

`HWSplitBarTests` asserts it in pixels rather than by reading the source: the same component drawn with every part
at zero width is byte-identical above the threshold and different below it, which is only true if the bar is gone
rather than smaller.

### Two treatments of one budget bar, and two components

The design draws the wants allowance twice, differently: Expenses puts it inside the galaxy summary as a caption and
a 7pt track (`.budget`, `HWBudgetBar`), and a month report gives it a card of its own on the light ground with the
figure at heading size over a 9pt track and a sentence underneath (`.bud-*`). Two stylesheet treatments, two
components — `HWAllowanceBar` is the second. A single component with an appearance argument would be one control
with two layouts, which is the rule at the top of `Components.swift` broken from the other direction.

### The accordion owns its panel, and an archived entry has no delete

`HWAccordionRow` takes the entries rather than a `ViewBuilder` slot: the hairline-separated rows and the empty note
*are* the panel's layout, and a screen handed the slot would be a screen writing it. **One panel open at a time** is
the caller's rule, held as a `String?` so two-open is not representable.

`HWEntryRow` — Expenses' `.entry` — is not reused, and the reason is not styling. That row draws a quiet cross and
takes a `nil` closure to mean "not now"; an archived month is immutable, so there is no delete to be temporarily
unavailable. A disabled control there would offer something that is not merely busy but impossible. The design
agrees: it writes `.ent` here and `.entry` there.

### The affordance arrived, and the row became a label

ADR-0036 left `HWMonthRow` with an optional action, saying #22 would pass a closure. It does not, and the reason is
where the `NavigationStack` lives: the shell wraps each tab in one and hands out no path binding, so a push is a
value-based `NavigationLink` — which supplies its own button, and a `Button` nested in a link is two controls for one
row. So the row follows `HWCategoryRowLabel`: **`HWMonthRowLabel`** is the contents plus a `showsChevron` flag, and
the archive draws it inside a link that carries the month key. The chevron, the button trait, and the hint copy all
arrive together, which is what #21 withheld while there was nowhere to go.

### The month scroller is not converted

The design's `.scroller` is a row of month chips above the report, so a reader can move between months without going
back. It is **deliberately not built**, and this is the one place this ticket narrows the design:

- It is a second way to reach a month the archive one screen back already lists, and the archive is one back button
  away.
- Converting it would mean this payload carrying the **whole archive's month list** beside the month it is about —
  either that, or the client fetching the archive again and joining the two, which is the composition ADR-0020
  exists to prevent.
- The stack's own back button is the design's `.backbar`, and the platform's swipe-back is the gesture.

If it comes back, it comes back as a payload change: a `months[{monthKey, label, isCurrent}]` array on this
response, and a `HWChip` row above the summary card. Nothing about the screen resists it.

### The facts grid: the app's labels, the server's figures, the server's notes

Six tiles, each a label, a value, and a qualifying line. The **kind** crosses the wire and the **label** is the
catalogue's, which is the split `ExpenseCategoryView.label(for:)` draws: the payload says which fact it is and the
words stay where the localisation scans look for them. The `value` is a string rather than a `Money` because one of
the six is a category *name* ("Biggest cost: Rent"), and the `note` is a **server sentence** because it joins a
figure to words — which is also why a currency change re-reads it: a sentence with a figure inside it is
re-composed, not converted.

### The empty month keeps the screen

A closed month with nothing logged is `.loaded`, not `.empty`. It still has a salary, a goal, a verdict, and a meter
reading 500% — the reader saved everything they earned by logging nothing. What the empty *treatment* covers is
narrower and lives inside two cards: the grey ring where there are no slices, and a note inside each empty panel.
The same narrowing `HomeView` records for its first-run donut, and the archive's own empty state — no month has
closed at all — remains the one genuine `LoadState.empty` in the app.

The ring is drawn from the **absence of categories** rather than from a flag. Home needs `isFirstRun` to tell a new
account from an empty month; a month that has *closed* with no categories has one reading.

## Consequences

- **`GET /v1/screens/reports/:monthKey` is now declared and covered.** ADR-0036 deliberately left it undeclared —
  a path with no caller and no payload is a guessed contract — and the corpus's coverage scan is what made that
  enforceable. Three payloads arrive with it, and two of them are one month.
- **The corpus gains a cross-payload assertion**, in the shape the Home/Expenses pair already has: the archive's
  February row and February's own report agree about what the month cost, its verdict, and its percentage, and the
  archive's stripe shares match the detail's slice shares to the row's own rounding.
- **Three new geometry `Double`s in `Models`**, and all three **borrow** names already exempt in
  `MoneyFormattingAbsenceTests` — `Category.share`, `Savings.position`, `Wants.fill`, `Segment.share`. The scan's
  allow-list did not grow, which is the test that exemption has to pass.
- **`ReportsMonthScreen` reuses `ExpensesScreen.Icon` and `Flow` by typealias.** Eleven glyph names for the same
  eleven things, one table, and `LocalisationTests` keeps subtracting them from its key scan without a second
  mapping to name. A `Reports`-only copy would be a second table that could disagree about which drawing Utilities
  gets.
- **The savings meter's VoiceOver *label* is still `home.savings.meter.accessibilityLabel`**, a key named after
  another screen, because the component owns it. This screen is its second caller, so the copy has earned a move to
  `HWComponentCopy` — worth doing on its own, with both callers in hand, rather than inside this ticket.
- **`ReportsMonthPage` takes the view model as well as the screen**, unlike `ReportsArchivePage`, which takes
  neither. Two of its cards are interactive, and the state they read is the view model's.
- **The three preview fixtures are the three states with their own layouts**: February, February in dirhams, and a
  month with nothing in it. The dirham one exists for the invariant, and it is previewable for the same reason it is
  testable.

### What looking at the pixels and reading the diff found

Four of the decisions above are corrections rather than first drafts, and each is worth naming because none of them
fails to compile:

- **The donut's share line is under the ring, not in it.** The design puts "82% of income" inside a 90px hole at
  9px, where it fits. The app's smallest step is `micro`, and at that size the sentence ran out of the hole and over
  the ring's stroke — tertiary grey ink on whichever category colour happened to be behind it. Shrinking further is
  what ADR-0012 forbids, so it moved. Found by rendering the page and looking at it; `HomeView` keeps its own inside
  the hole and is right to, because "9% of pay" and "54%" both fit.
- **A split with a part *missing* now fails the screen.** `Portion` refusing a fifth *name* was only half the rule:
  three segments decoded perfectly well and drew a bar that did not add up to the income printed beside it. The
  sequence is checked in `Split.init(from:)`.
- **Only the allowance *track* stands aside at accessibility sizes, not the row it sits in.** Replacing the whole row
  took the percentage — "63%", which appears nowhere else — off the screen at exactly the sizes where it is wanted
  most. `HWBudgetBar` has the same shape and the same bug; it is not this ticket's to fix, but it is the same
  finding.
- **`wantsFoot(_:)` returns `nil` where the payload has no figure for the sentence to name**, rather than
  substituting a nearby one. Both sentences are *about* an amount, so a substituted figure prints a number the words
  do not describe (invariant 10).

And one that is a *test* rather than code: **two `Text`s built from one resource and one set of arguments are not
`==`** — the storage is compared, not the sentence. So `meterDescription(_:)` and `wantsDescription(_:)` return
`LocalizedStringResource` where `HomeView`'s and `ExpensesView`'s return `Text`, and the assertions read
`String(localized:)`. `ExpensesViewTests` has the older shape — `#expect(wantsDescription(under) != wantsDescription(over))`
— which passes on any two descriptions, including two identical ones. Flagged separately.

## What this leaves

- **The month scroller**, above, if it is wanted.
- **`HWComponentCopy.savingsMeter`** — the label move described above.
- **Nothing about a month is refreshable**, as nothing about the archive is: there is no pull-to-refresh anywhere in
  the app, the chrome's `.task` is the only load, and the retry is `StateView`'s. A closed month never changes, so
  this is the last screen that would want one — except for the currency change, which re-reads through the same
  `.task` when the screen is re-entered. **Account (#23) is where a live currency switch will need to invalidate
  what is on screen**, and this payload is ready for it: the repaint is a re-read.
