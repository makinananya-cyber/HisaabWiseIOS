# ADR-0033 — Expenses: seven categories in three kinds, and the first screen that writes

**Status:** accepted
**Applies:** [ADR-0020](0020-screen-scoped-endpoints.md) (its second read, and its **first writes**),
[ADR-0019](0019-no-offline-writes-curriculum-pdf.md) (online-only, and what a failed write renders as),
[ADR-0009](0009-content-cache.md) (the two pick lists),
[ADR-0022](0022-production-transport.md) (the caller-supplied `Idempotency-Key`, whose reason for existing this is),
[ADR-0012](0012-accessibility.md) (a fourth clamp consumer, and one row that becomes a column)
**Amends:** [ADR-0032](0032-home.md) — nothing it decided, but its `Double` exemption list grows by one
**Records three things looking at it running found, and five review found** — see the last two sections

## Decision

### `GET /v1/screens/expenses` is the single read, and it carries four things the design computed

Home was ADR-0020's first caller and only had to stop *joining* four responses. Expenses is the first screen where
the design's own JavaScript did the arithmetic, so the payload's shape is a list of calculations that have moved:

| The design | The payload |
|---|---|
| `catTotal(id)` reduced over the live month | `Category.total`, per category |
| `totalFixed()` · `totalVar()` · `totalIn()` | `summary.fixed` · `variable` · `income` |
| `budget()` — the 50/30/20 engine, re-implemented in the browser | `wants.allowance` |
| `b.used > b.wants` | `wants.isOver` |
| `whenLabel(ts)` against `new Date()` | `Entry.dateLabel` |
| `n === 1 ? '1 entry' : n + ' entries'` | `Category.entryCountLabel` |

Two of those are more than tidying. `budget()` is **invariant 3 violated in the source material** — the adaptive
engine existing twice, which is how defect D11 happened — and `whenLabel` is **invariant 6 violated**: moving the
device clock re-labelled history. The payload carries no timestamp at all, which is the stronger form of the fix:
the client could not derive a date label if it wanted to.

**The per-category total is read, not computed, and that is testable only against a payload that disagrees with
itself.** A client that sums its entries and a client that reads the total look identical against a consistent
month, so `ExpensesViewModelTests` sends a `transport` total of `₹9,999` over entries of `₹120` and `₹320` and
asserts the screen says `₹9,999`.

### Three kinds, and `kind` is the one enum here that refuses to guess

`Icon` and `Flow` degrade to a default because they are presentation: a category drawn with the wrong glyph is a
blemish. `kind` decides **which write the detail page offers**, and guessing it offers the wrong shape of write — a
`log` form over Rent would let a user append a second rent for the month rather than correct the one there is. So
an unrecognised kind fails the decode and the screen renders `LoadState.failed`.

`Field` goes the other way and is lenient, for the mirror-image reason: an unknown field shape reads as **no
field**, which is the Groceries case — an amount, labelled with the category's own name. Nothing about that files
the wrong thing, so a fifth shape added server-side degrades to a usable form rather than blanking the screen.

### The four field shapes are a closed vocabulary, and their words are not on the wire

The design carries a label, a placeholder, a type, and two flags per category. Only the *shape* is structural —
whether it is typed or picked, which list it picks from, whether it may be left empty — so that is what crosses,
as four cases: `place` · `source` · `transportMode` · `otherType`. The labels stay app copy in the presentation
layer where the localisation scans look for them.

**Money in is signed by the server.** `Category.total.display` for Additional Income is `+₹900`, because the
design's own `(c.income ? '+' : '')` puts the sign on the wrong side of an Arabic string. A sign is formatting, and
ADR-0003 gives formatting to the server; `flow` still crosses, because the *tint* and the inverted glyph tile are
presentation.

### Four writes, each answering with the updated screen payload

| Route | Why that shape |
|---|---|
| `POST /v1/expenses` | one entry, with a **caller-supplied** `Idempotency-Key` |
| `DELETE /v1/expenses/:id` | one entry, gone |
| `PUT /v1/expenses/fixed/{categoryId}` | replaces one amount, so no key (ADR-0022) |
| `PUT /v1/expenses/lines/{categoryId}` | replaces **the whole set of bills** |

The last one is the interesting one. Utilities' edit mode lets the user rename a bill, correct two amounts, delete
a third, and add a fourth, and then commits all of it with **Update bills**. Expressing that as a `POST`, two
`PUT`s, and a `DELETE` would be four requests for one user intent, four chances to fail halfway, and four screen
payloads of which only the last is the truth. So the set is replaced: a line with an `id` existed, a line without
one is new, and anything not sent is gone — which is exactly what the design's `harvest()` does.

**One departure from `harvest()`:** a row with a blank name is dropped rather than saved as `"Untitled bill"`. That
string is client copy going into stored data an Arabic reader will see. A bill with no name is not a bill.

### An `Idempotency-Key` per *intent*, which is what the header was written for

`APIClient.post` has always keyed every `POST` and always noted that "it is the caller-supplied form that will
matter when a 'try again' button sits in front of a write (#18)". This is that caller. The key is minted when the
user first presses **Add** and **reused across attempts**, so a write that reached the server and lost its response
is not filed twice. A *second* entry mints a new key; so does accepting a re-filing offer, because the first attempt
was refused and there is nothing to deduplicate against.

### A write's error is this view model's own mapping — the fourth owner

`StateTaxonomyTests` names four now, and each is a different *kind* of mapping rather than a repetition:

- **A read** becomes a `LoadState`, in `BaseViewModel.load()`. One owner, twelve screens.
- **A form** becomes field errors, in `SignInViewModel` and `RegistrationViewModel`. "Offline" under a password box
  is not an offline screen.
- **A write** becomes a third thing: offline becomes `LoadState.offline` because there is nothing to correct and no
  queue to hold it (ADR-0019), and `MONTH_CLOSED` becomes an **offer** rather than a sentence.

`StateTaxonomyTests` had already predicted this one — "`ViewModels` may legitimately branch on one — Expenses will,
to offer re-filing on `MONTH_CLOSED`" — so the entry is a prediction met rather than an exception carved out.

### Offline: the screen goes, and the draft stays

The criterion is that a write attempted offline "renders `LoadState.offline` with a retry and is not queued", and
that is taken literally: `state` becomes `.offline`, `StateView` draws it, and its retry is the screen's own load.

**Two consequences, both deliberate.** The pushed detail page **pops**, because the destination is registered inside
`loadedContent` and there is no loaded content for a moment. And the user's typing **survives**, because `EntryDraft`
lives in the view model rather than in the payload — so reloading and reopening the category finds the amount still
in the box, and pressing Add again re-sends the same key. That is the whole of what can be offered without a queue,
and it is why the draft snapshots the field shape it needs rather than looking it up in `state` at send time.

### `MONTH_CLOSED` reloads before it offers

A write can cross a rollover boundary in flight (§4.5). Archives are immutable with no exceptions — amending one
reopens defect D6 — so the client offers to file the entry into the live month instead.

**The offer names the live month, and it learns that name by reloading.** The label the screen was holding names the
month that has just *closed*, so offering "add it to August instead" while the live month is September would be the
app lying about the date, which is precisely what §4.5 says not to do. One request is what that costs, and the
re-file is then a plain re-send: the server derives `monthKey` from the entry date in the user's stored timezone at
write time, never trusts a client-supplied one, and the live month only moves forward. The entry comes back carrying
the server's own `dateLabel`, which is the "showing the true date" half of the rule.

### The two pick lists are content, and the option that opens free text is flagged

`GET /v1/content/picklists` — 22 transport modes and 20 "Other" types, cacheable because they are the same 42
options for everybody (ADR-0009, invariant 8). The design carries them as two JavaScript constants, which is what
"content is server-served and versioned, never compiled into the app" exists to prevent: a new transport mode would
otherwise be an App Store release. Fetched on the **first sheet** rather than with the screen, for the reason Home
fetches its tip pool on the first press.

**[FIX] — the free-text option is a flag, not a name match.** The design tests `/something else/i` against the
selected option's English text. The moment the list is translated, the one option whose behaviour differs becomes an
ordinary option for every Arabic reader. `Picklists.Option.opensFreeText` is the server's, and the **id** is what
crosses the wire, so the entry an Arabic user files reads in Arabic and the same entry reads in English for an
English one.

**Nothing extracts the design's `?demo` auto-fill block**, as the content rules require, and nothing here fills a
field for the user.

### `TypedAmount`, extracted rather than copied

Reading a figure the user typed was private to `RegistrationViewModel`. Expenses is the second caller, and the rule
is one whose failure mode is a **100× error**: `.decimalPad` offers the *device region's* separator and no other, so
on a German or Brazilian phone a comma is the only way to express fils, and treating it as grouping files an expense
a hundred times too large. Two copies of that is two chances to get it wrong in one of them.

It also now takes an **exponent**, which registration could not: the screen payload carries one and the currency
reference list still does not (`CONTEXT.md`). A dinar typed `1.234` is 1234 minor units, not 123.

## Consequences

- Expenses is one read. The pick lists are a second, and only on demand — cacheable content is separate by
  ADR-0020's own rule rather than as an exception to it.
- **The two screens tell one story about one month**, structurally: `expenses-inr.json`'s total spent is
  byte-identical to `home-inr.json`'s, and the corpus asserts it per category. A difference is one of the two
  assemblies having summed something, which is the class of mistake defect D1 was.
- `TabViewModels.expenses` changed type and nothing else in that file moved, which is what its own note predicted
  of #18, #19, #21, and #23.
- The vocabulary grew by a dashed `HWButtonVariant`, two `HWIconButtonVariant`s, eight Expenses components, and a
  `surface` appearance on the two field controls that were brand-only — which is the second caller `HWMoneyField`
  and `HWCombo` were waiting for. The combo's caption **moves** between the two, because the design puts it inside
  the box on one surface and above it on the other.

## What looking at it running found

Rendered to PNGs and read, because the design is a visual reference and a test cannot see weight or crowding.

**Every logged entry carried a raised, bordered, accent-blue cross.** `HWIconButton` had one form — `.iconbtn`,
which is a control that stands on its own — and the design's `.entry-del` is a transparent 28pt glyph in `--ink-3`.
Drawn as the raised form it read as the most important thing in a row about a ₹120 metro fare, when it is the least.
`HWIconButtonVariant` now names the three weights the design actually draws: `raised` · `quiet` · `destructive`, the
last being `.line-del`'s danger tint, because removing a *named* bill is a consequence worth showing.

**The three summary chips were unreadable at accessibility sizes.** A row of three leaves each about 100pt, and
`₹3,529` came back as "₹3, / 52 / 9" with `VARI / ABL / E` beside it — a **figure broken across three lines**, which
is past wrapping and into wrong. The row becomes a column above the threshold, which is the same fix `HomeView.duo`
makes for its two-up grid and the same reasoning.

**`ImageRenderer` does not lay out the content of a `ScrollView`**, and the test asserting the detail page "renders"
was passing on a blank ground. That is worth knowing beyond this screen — it is a second entry alongside
`CONTEXT.md`'s note that a `TabView` and a `NavigationStack` come back as the unsupported-view glyph. The page is
now two views split at the navigation chrome: `ExpenseCategoryPage` is the content, so a render draws something and
a test can say so, and `ExpenseCategoryView` is the scroll, the title, the toolbar, and the sheet. Chrome outside,
content inside, which is the arrangement `BaseView` and `ScreenChrome` already have.

## The five things review found

Each was a real defect and each is now fixed and tested.

**`MONTH_CLOSED` was offered for writes with nothing to re-file, and accepting always re-sent the create.** Every
write funnelled the refusal into the offer, but `refile()` called `addEntry()` — so a deletion refused across a
rollover boundary offered "add it to September" and then **filed a new expense**, and on a `lines` or `fixed` page
the same offer was a silent no-op. `WriteKind` now says what a write is: **only a create is offered**, because only a
create has a body to re-file. A deletion in a closed month is a deletion of something an archive holds, and archives
are immutable with no exceptions; a replacement can simply be tried again against the month that is now live. The
others read as `.failed(.monthClosed)`, whose copy — "That month has closed. Reload to see the current one." — was
already in `ErrorCopy` and is exactly the right thing to say.

**Every write emptied the entry form on success.** So deleting last week's row wiped a half-typed new one, which the
design's own `bindDelete` never does. The same `WriteKind` decides it: the form's own write clears the form.

**Edit mode survived leaving and coming back.** The guard that stops a re-render wiping the user's typing sat
*outside* `open(_:)` and skipped the whole reset when the id had not changed — so Utilities → Edit → back → Utilities
still said **Done** over rows the user had abandoned. The guard moved inside, where the two lifetimes can be told
apart: edit mode is per *visit*, and the entry draft is per *category* and outlives one on purpose.

**A stored figure was read with the wrong exponent.** `beginEditing` filled its fields with
`authoring?.exponent ?? …`, and `entry.exponent` describes the figure being *typed* while a `Money`'s own describes
the figure being *shown*. They are the same currency in every payload the server will send, which is precisely why
picking the wrong one would have gone unnoticed until the day they were not — the 10× error `TypedAmount` exists to
prevent. Each direction now uses the exponent that belongs to it.

**And one thing that was wrong before this ticket and is now this ticket's.** `TypedAmount` treated *any* run longer
than the exponent as grouping, so `8000.505` read as **eight million** — a thousand-fold error, worse than the 100×
one the separator rule is proud of preventing. Grouping is now a claim the string has to support: one to three digits
before the first separator and exactly three after every one. `1.234` is still 1234 at exponent 2 and `250.505` is
still two hundred fifty thousand (both are validly grouped); `8000.505` is **refused**, because neither reading is
safe and a refusal is something the user can see and correct.

A sixth was cosmetic and is fixed too: the dash pattern was a literal in two files, one of which claimed to be "the
one place it is decided". It is `HWBorderDash.standard` now, beside the function that strokes it. And a seventh is a
hole closed rather than a defect found: `Endpoint.expense(id:)` *drops* what a path segment may not contain, so a
mangled id would leave a `DELETE` addressed to a different, perfectly valid resource — `../me` becoming
`/v1/expenses/me`. The mangling is now detected and the request is not sent. (`ContentResource.forArticle(id:)` drops
for the same reason and can afford to: the worst it produces is a cache-key collision, not a request somewhere else.)

## What this leaves

**The rows are cramped at accessibility sizes and are not restacked.** A category row, an entry row, a bill, and the
hero all put a glyph tile, a text column, and a trailing figure in one line, and at AX3 the text column narrows to a
few characters per line. Nothing truncates and nothing overlaps — which is what ADR-0012 and `LocalisationTests`
require — but it is cramped. `HWKeyRow` already recorded where this belongs: "the accessibility-size alternative
layout is issue #8's". Four more rows for that ticket, rather than four bespoke layouts here.

**A `MONTH_CLOSED` create pops the detail page too**, for the same reason offline does — `offerRefiling` reloads, and
`load()` writes `.loading` before it writes anything else. The alert is presented from the list level, which survives,
so the user decides on the screen that has actually changed. Recorded rather than fought: after re-filing they are on
the list with the entry filed and the toast confirming it, which is a defensible place to be when the month has just
rolled over underneath them.

**The wants bar in the standing fixture reads 6%**, because the corpus keeps `expenses-inr.json` in step with
`home-inr.json` — whose salary is ₹65,000 against the design's dirham-magnitude spending. Consistency between the
two screens is worth more than a livelier default preview, and `expenses-over-budget.json` is what the interesting
state is previewed from.
