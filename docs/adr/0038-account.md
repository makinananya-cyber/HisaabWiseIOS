# ADR-0038 — Account: one screen, four writes, and the two settings that make every other screen stale

**Status:** accepted
**Issue:** #23 — Account and settings: profile, language, currency, password
**Builds on:** [ADR-0020](0020-screen-scoped-endpoints.md) (screen-scoped endpoints),
[ADR-0003](0003-money-presentation.md) (the server converts and formats),
[ADR-0024](0024-language-plumbing.md) (the language switch and its revert),
[ADR-0031](0031-registration.md) (one atomic submission; the phone and security-answer shapes),
[ADR-0026](0026-shell-plumbing.md) (`LogoutControl`, and the way out),
[ADR-0019](0019-no-offline-writes-curriculum-pdf.md) (no offline writes),
[ADR-0014](0014-privacy-surfaces.md) (what the app keeps a copy of),
[ADR-0033](0033-expenses.md) (the chrome/page split, and the write mapping)

## Context

Account is the last of the five in-app screens and the one that changes the other four. Two of its rows —
Currency and Language — are settings every figure and every sentence in the app is formatted against
server-side, so changing one does not re-render the app: it makes every payload already in hand *wrong*.

The design's `account` document is where the largest number of defects live in the smallest space. Its
`state` object holds a bare `salary` number, the **raw text of both security answers**, and a
`SALARY_BASE` currency it converts in and out of. Its `paintProfile()` derives the avatar's initials with
`split(/\s+/).slice(0, 2).map(w => w[0]).toUpperCase()` and its summary chip with `currency.c + ' · ' +
language.n`. Its `savePersonal()` reads the salary back out of `money(salaryShown())` — a figure that has
been through magnitude-aware rounding. Its `answerMatches()` reduces both sides to key words and compares
them with a Levenshtein distance, in the browser. Its language list has 87 entries. And its
`passwordChanged: '3 months ago'` is a literal reconciled against nothing.

Those are, in order: defect D16, defect D4, defect D12's neighbour, Product Spec §3.7's **[FIX]**, and
invariant 6. Every one of them is a thing this screen has to *not* do.

## Decision

### One `GET /v1/screens/account`, and the strings on it include the ones that look derivable

The payload carries the screen: a `profile` with its own `initials` and its own `summaryLabel`, four `rows`
in the order they are drawn with a subtitle and an optional value each, a `personal` block with the four
lines, the stored `language` and display `currency` at the root, and the **two security questions** the
password flow asks.

Three of those fields look like things a client could work out, and each is on the wire for a reason:

- **`initials`** — "the first letter of each of the first two words, upper-cased" is a rule about writing
  systems. It is wrong for a script with no case, wrong for a mononym, and wrong for a name whose first
  grapheme cluster is more than one scalar. The corpus's display name is deliberately a **mononym**, so the
  case the rule is about is the one the standing payload exercises.
- **`summaryLabel`** — the design concatenates a currency code and a language name with a separator, which
  is a sentence assembled on the client and one no translation can reorder (ADR-0011).
- **`rows[].hint`** — "Changed 3 months ago" is a date label computed against a day boundary in the user's
  stored timezone (invariant 6). It is the same fix `ExpensesScreen.Entry.dateLabel` made one screen
  earlier, and it is why the row subtitles are in the payload at all rather than being app copy.

`language` sits at the **root** rather than inside a `preferences` object, because `PUT /v1/me/language`
answers with this whole payload and `APIClient.setLanguage` reads exactly one field out of it (ADR-0024). A
nested field would be a second shape describing one value.

`Section` is the enum on this screen that **refuses to guess**, for `ExpensesScreen.Kind`'s reason: it
decides which page opens, and a fifth section drawn as `personal` would put a salary field over something
that is not a salary.

### The salary is `minor` on the way out and a typed string on the way back — defect D16

`Money` already carries both halves: `display` is what the reader reads and `minor` is what the figure *is*.
The edit field is filled from `TypedAmount.major(salary.minor, exponent:)` and never from `display`, and the
two directions use their own exponents — the figure's for reading it out, the authoring currency's for
reading it back — which is the 10× trap `ExpensesViewModel.beginEditing` records.

The test for it needs a figure whose display string has been rounded *away* from its minor units, so it
patches the standing payload to `₹65,123.45` displayed as `₹65,120` and asserts both halves: that the write
carries `6512345`, and that parsing the display string would **not** have. Without the second assertion the
test would pass against the defect for every figure that happens to round to itself — which `₹65,000` does.

### `PUT /v1/me` carries three fields, and email is not one of them

The Technical Spec says `PATCH`. This is a `PUT`, for two reasons: the design's Save button commits the whole
`#pi` card at once, so every field the route accepts is in every request and there is no partial update to
express; and a `PATCH` would be a fifth verb on `APIClient` — a fifth set of rules about idempotency keys and
cache bypass — bought for one route with nothing to distinguish "left alone" from "set to this".

**Email has no field in the request**, which is invariant 4 made structural rather than remembered. The
assertion is against the **bytes on the wire** (`Set(body.keys) == ["displayName", "salary", "phone"]`),
because an `Encodable` that stopped encoding a field would still compile and because "the client cannot
change the email" is a claim about what the server receives.

Phone is **absent rather than empty** when it is not given, as registration sends it (ADR-0031) — and where
the design requires a number, this allows none and refuses a *partial* one: phone is optional at
registration, so "not given" is a state an account can really be in.

### The password change is **one** request, and the refusals name the step

The design walks three steps and verifies each in the browser: the current password against nothing at all,
and the answers against `state.security[i].answer`. That is defect D4, and invariant 5 makes both the
server's. Once verification is server-side, a step-by-step flow needs the server to *remember* that this
session got past step one — a session-scoped verification state nothing else in this app has.

And it would be worse to have than to do without: **a route that answers "is this the right current
password?" before being told what to change it to is a password-checking oracle behind a session**, which is
the class of thing the email-availability route was refused for (ADR-0031). So the three steps are the
client's sequencing of one submission — nothing exists server-side until the last button, exactly as
registration decided — and `POST /v1/me/password` carries the current password, both answers keyed by
question id, and the new password together.

Its refusal therefore has to say *which* part was wrong, and two codes do: `INVALID_CREDENTIALS` sends the
reader back to step one and `SECURITY_ANSWERS_INVALID` to step two. Neither is in `ErrorCopy`: they are
*field* errors on a flow, and the screen that owns the flow draws them.

**`SECURITY_ANSWERS_INVALID` does not say which answer missed, and must not.** The design reddens the
specific field because it compared the raw strings locally; §4.3 **[FIX]** compares argon2id hashes of a
normalised form, and telling somebody which of two guesses landed is a hint to whoever is guessing. The
message therefore goes under the **first** box only — repeated under both it would read as two separate
refusals of two separate answers.

**One constraint on the backend, found by writing the test for it: those refusals come on a `422`, never a
`401`.** A `401` is answered by refreshing and retrying once (ADR-0007), and a refresh the server then
refuses ends the session and clears the store — so on a rotating token family, a mistyped current password
would sign the user out. The first version of the test used `401` and watched the session end.

### A currency change is a re-read of the app, through `ScreenRepaint`

`PUT /v1/me/currency` carries the ISO code and nothing else — no figure crosses, and the client converts
nothing (§4.1, ADR-0003). It answers with this screen; the other four are the problem, because their figures
were converted at read in the currency that has just stopped being in force.

So there is a new seam: `ScreenRepaint`, a `@MainActor` protocol in `Models`, conformed to by
**`TabViewModels`** — the one object that holds all five view models. `AccountViewModel` holds it `weak` and
is `connect`ed to it by `AppEnvironment`, exactly as `LanguageManager` is connected to `APIClient` and for
the same reason: the graph has a genuine cycle in it, so one of the two halves is connected rather than
injected, and the half-built state stays confined to an object nobody has called yet. An unconnected view
model changes the preference and repaints nothing rather than failing.

It is **not a second seam** (ADR-0013): the only conformance is the real `TabViewModels`, in the app and in
the tests alike — which is why the repaint test stands up all five screens over one transport and counts
requests rather than asserting that a double was called.

The repaint re-reads the four screens **one after another**. Four `async let`s would overlap the waiting, and
would also put four screens into `.loading` at once behind a tab bar the user is free to tap — the tab they
land on being the one whose request is still in flight. Sequential means they come back in tab-bar order,
which is the order a reader is most likely to visit them in.

A **language** change repaints too, and for the same reason: `Accept-Language` is what decided the wording
and the number formatting of every payload in hand. The switch itself stays `LanguageManager`'s, including
the optimistic revert when the server stores a different language (ADR-0024); what this screen adds is its
own re-read and the other four.

### The one write in the app whose offline failure does not replace the screen

Issue #23 asks for this in so many words: "offline, the row is disabled with an explanation rather than
failing". Everywhere else, a write that fails offline becomes `LoadState.offline` (ADR-0019) — there is
nothing to correct and no queue to hold it. Here that would take away the picker the user is standing in
**and** the only explanation of why nothing changed.

So a *preference* write (and the export) reports an `AccountViewModel.Refusal` beside the control instead: a
**subject** and a reason. Two reasons, because a change that needs a connection is one to try again in a
minute and a change the server refused is not; and a subject because a refusal is about **one control** —
without it, a failed export drew its sentence over the currency picker and a failed currency change drew one
under the export button. Review found both. Neither half is a `LoadState`: the screen is fine, and the
taxonomy has one owner (ADR-0016). `StateTaxonomyTests` names `AccountViewModel` as the fifth owner of a
write mapping, alongside Expenses.

**Two deviations from the criterion's literal wording, recorded rather than smoothed over.**

The app has no connectivity monitor, deliberately — `URLSessionTransport` does not wait for connectivity,
because a request held open until the network returns is the write queue ADR-0019 removed wearing a system
API's name. So "offline" is something this app learns by *asking*: there is nothing to disable a row
*before* an attempt on. Adding a monitor would buy a pre-emptive disable and a second source of truth about
connectivity, which is a worse trade than a control that explains itself once.

And **a refusal does not disable the control either**, which is where the first version of this got the
criterion's word "disabled" wrong: the picker read `.disabled(isWriting || refusal != nil)` and nothing
cleared the refusal, so one attempt with no connection left the control dead for the rest of the session —
the user told a change had not happened and unable to make it. The row is disabled *while a change is in
flight*; the **explanation** is what says nothing changed. A control that cannot be tried again is worse
than the failure it reports.

### The export is bytes, and the app keeps no copy of them

`GET /v1/me/export` is the UAE PDPL access right. It is the one per-user response the client **does not
decode** (`APIClient.bytes(at:)`): what comes back is every collection this system holds about one person,
streamed, and modelling it would mean the client owning a schema for all eleven of them. Re-encoding it to
save would hand the user *this client's* idea of their data instead of the server's — the rule
`ContentLoader` already follows about storing bytes rather than values.

**And nothing is written to disk.** The bytes go into a `Transferable` and the user picks where they go
through a share sheet, so there is no copy of one person's entire financial history sitting in a temporary
directory for something else to find and nothing to remember to delete (ADR-0014). The suggested file name
is **not dated**: the client owns no calendar (invariant 6), and the export timestamps itself inside the
document.

The control is not a fifth row. The design's `.bubble` has four and a fifth would claim to be one of them, so
it sits with the other thing on this screen that is about the account rather than a setting of it — the way
out.

### Adding `perform(reading:)` to `APIClient` rather than a second request path

The export needed a session-authenticated `GET` that does not decode. `perform`'s type parameter became a
`read: (Data) throws -> Response` closure and the four verbs pass a decode; `bytes(at:)` passes `{ $0 }`. The
alternative was a second path through the `401`-refresh-and-retry logic, and that logic is the twenty lines
in this app that must not have two copies.

## What the design asks for and does not get

- **The `.version` footer.** "HisaabWise · version 1.0" is a fact about the *build*: it comes from
  `Info.plist`, `AppConfig` is the one type that reads one, and it is not injected into the view tree.
  Drawing it means either a second reader of `Bundle.main` — which two source scans forbid — or a new
  environment value for one line of small print. It is one property on `AppConfig` and one entry in
  `hwEnvironment` when somebody wants it.
- **87 languages.** The picker shows the two shipped ones (Product Spec §3.7 **[FIX]**, ADR-0011). Each row
  is the language's **endonym**, resolved in its *own* locale rather than the reader's: a picker that named
  Arabic "Arabic" to an English reader and "الإنجليزية" to an Arabic one is a picker in which neither reader
  can find their own language. It is the one string in the app that is deliberately not translated, and it
  comes from `Locale` rather than from a catalogue key — a key would be translated, which is the behaviour
  being avoided.
- **`.btn-danger`.** The filled red gradient on the log-out confirmation. The confirmation is a
  `confirmationDialog` rather than the design's own `.confirm` overlay (ADR-0026), so its destructive button
  is the platform's red and a transcription would have nowhere to be used. `HWButtonVariant.destructive` is
  the *other* danger control — `.logout`, card-coloured with a danger border and danger ink — and it has a
  caller, which is the rule that kept it out of the vocabulary until now.
- **The design's own `.backbar` and its two-level page transitions.** The stack's own back button is the
  affordance and the title goes in the navigation bar, which is the call `ArticleView` and
  `ReportsMonthView` both make.
- **Three flourishes on the profile card** — the orbiting glow behind it, the avatar's entrance pop, the ring
  pulsing around it — plus the summary chip's pinging dot. **Dropped rather than gated** on Reduce Motion, on
  the reasoning the `START` flag's bob carries (ADR-0012): an entrance's only honest replacement is the thing
  already being there, and a dot that pulses to mean nothing is an attention loop with nothing to attend to.
- **The toast on a refused form.** The design toasts "Check the highlighted details." and reddens the rows;
  the message is put under the box it is about instead (`HWFieldNote`), for the reason `HWTextField` keeps its
  own message in the accessibility tree: a toast is announced once, can be switched off, and the user has to
  be able to read which rule they broke *while* they fix it.

## Components this needed

Six new, one split in two, one folded out, and three that grew a second appearance.

- `HWProfileHeader` · `HWSettingsTray` · `HWRowCard` · `HWInfoRow` + `HWInfoValue` + `HWInfoNote` ·
  `HWInlineField` · `HWDialTrigger` — the design's `.profile`, `.bubble`, `.card{padding:6px}`, `.info`,
  `.info input` and `.dial`. `HWRowCard` is a second card rather than an inset parameter on `HWCard` because
  the choice follows from whether the content is full-width rows: insetting them would draw a separator that
  stops short of the card's border.
- `HWInlineField` is **not** `HWTextField`. The design's `.info input` is an underlined field inside a row
  inside a card; drawing `.field-box` there is three borders for one field where the design draws one.
- `HWBanner` — the shell's "verify your email" strip was inlined in `AppShell` until this screen needed the
  same thing beside the locked email. Two callers, so it is a component, and `AppShell` now uses it.
- `HWRow` is split into `HWRowLabel` and `HWRow`, the split `HWMonthRowLabel` and `HWCategoryRowLabel`
  already make: Account's rows are pushed pages and the shell hands out no path, so each row is a value-based
  `NavigationLink` and a `Button` inside a link is two controls for one row.
- `HWButton` is split into `HWButton` and `HWButtonFace`, for the same reason one level down: `ShareLink` is
  a control of its own, and the export link wears the face while the framework supplies the behaviour.
- `HWOptionList` is folded out of `HWPickerSheet`, the fold `HWFigureChips` came out of: Account draws the
  same searchable list of the same rows as a *pushed page* under an `.explain` paragraph, not as a sheet. The
  panel stays the sheet's; the list is shared.
- `HWStepBar`, `HWStrengthMeter` and — through `HWButtonAppearance` — the destructive variant grew a
  `surface` arm. The meter's fourth level is the one **departure**: the design's fourth colour is the palest
  of the four, which reads as strongest on the galaxy ground and as almost nothing on an off-white one, so the
  in-app ramp runs the other way. The design's *decision* — darker is stronger against this ground — is
  converted rather than its four hex values.

## Consequences

- **Six endpoints the backend has to write**: `GET /v1/screens/account`, `PUT /v1/me`, `PUT /v1/me/currency`,
  `POST /v1/me/password`, `GET /v1/me/export`, and `PUT /v1/me/language` now answering with this payload.
  `CONTEXT.md`'s table of changes this repo requires elsewhere carries all six, plus the `422` constraint.
- **`GET /v1/me` and `PUT /v1/me` share one path with two verbs**, and only one fixture may claim a path. The
  identity read holds it; the personal write is stubbed explicitly by whichever test or preview exercises it,
  exactly as the second Reports month is.
- **The placeholder is gone.** `UnwrittenTabRoot` and `UnwrittenScreenViewModel` have no callers in the shell
  now that all five screens exist. They are left in place rather than deleted: they are what a sixth tab or a
  screen taken out for rework stands on, and `AppShellTests` still exercises them.
- **`Delete account` is not here.** Product Spec §3.7 asks for it and App Store 5.1.1(v) requires it; issue
  #23's acceptance criteria do not list it, and ADR-0015 gives it a flow of its own with a restore path and a
  screen behind it (#24). No route for it has been invented here.
- **No "resend verification" route either**, for the same reason: the criteria ask for the banner and not for
  a control, so the banner carries no action — as the shell's does not.
- **Two of the review's findings are regressions with tests now**: that a refused currency change can be made
  again, and that a refusal is about the control that was tried and no other. Both were behaviour, not
  wording.
- **`String(localized:)` resolves against the *resource's* locale**, which is the device's unless it is told
  otherwise — so the one string on this screen not drawn by a `Text` ("Not given", where no phone number was
  given) came back in English under Arabic. `HWAnnouncement.text(_:in:)` had already recorded the correction
  for announcements; the phone line takes the locale from the environment the same way. The export's
  suggested file name is the one site that cannot: a `TransferRepresentation` is `static` and has no
  environment, so it resolves in the device's locale. It is a file name rather than something read on screen,
  and it is recorded here rather than left to be discovered.
