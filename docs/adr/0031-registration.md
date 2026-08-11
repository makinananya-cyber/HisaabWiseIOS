# ADR-0031 — Registration: three steps in the UI, one request at the end

**Status:** accepted
**Extends:** [ADR-0009](0009-content-cache.md) (the content store, built here for its first caller),
[ADR-0021](0021-two-surfaces-and-token-collapse.md) (`brand` gains its second form),
[ADR-0023](0023-session-plumbing.md) (registration answers with a login's token pair),
[ADR-0030](0030-sign-in.md) (the failure-as-a-value shape, reused)
**Applies:** Product Spec §3.3, §4.3 **[FIX]** (question identity), invariants 1, 2, 4, 5, 6, 8
**Corrects:** three live defects in the test harness and one in `HomeView`'s VoiceOver label — see "What the
running app and review found"
**Records a gap:** the currency exponent — see the last section

## Decision

### One atomic `POST /v1/auth/register`

The design walks three screens. The client holds all three in memory and sends them together, so **nothing
exists server-side until the last button**. There is no half-built account to resume, to clean up, or to
accidentally sign in to, and no state machine describing which steps have been persisted.

Two consequences follow, and both are the point rather than a cost:

- **There is no email-availability endpoint, anywhere.** Such a route answers "does this person have an
  account" to anybody who asks. So the collision can only be discovered at the end — a `409 EMAIL_TAKEN`
  sends the user back to step 1 with the email field marked and everything else they typed intact. Asserted
  on the wire *and* by a source scan, because the way that route gets added is somebody making the form feel
  faster next year.
- **Validation at submit runs every step's rules, not the current one's.** A field left invalid two screens
  ago would otherwise reach the server, and the user would be told about it by a refusal rather than by the
  form. When it fails, the step moves to the earliest one that has something wrong with it.

### One screen, not three pushed screens

The step is `@State` on one view, matching the design's own `.stage` with three cross-fading `.view`s under a
shared wordmark, headline, and step bar. A `NavigationStack` of three would give each step its own back
gesture and its own lifetime — and a swipe-back that discards a step's typing is exactly the failure the
atomic submit is built around. `goBack()` is the only way backwards inside the form.

### Skip is not "no goal"

**Submit** and **Skip for now** are the same request. They differ in one field: `goalWasSkipped`. Skip sends
the 20% suggestion, so a skipped 20% and a typed 20% are the same figure and different facts, and only that
flag can tell them apart — which matters the first time the app wants to say "you chose this" rather than "we
suggested this". The design's own `finish(suggested(), true)` says the same thing with a `source` string; a
boolean is the same information with one fewer value to spell wrongly.

### The reference lists are server content, and the form cannot be drawn without them

251 countries, 160 currencies, 14 questions — fetched through the ADR-0009 content store, revalidated by
ETag, **never compiled into the binary**. A dial code changing is not a reason to ship an app update.

Three decisions inside that:

- **The bytes are stored, not the decoded values.** A store holding models would be storing this client's idea
  of the payload, and the next revalidation would be asking the server about a document that never existed.
- **An ETag is only ever sent alongside the bytes it describes.** `Caches` is evictable and nothing promises a
  resource's two files are removed as a pair, so an ETag can outlive its data; sending an orphaned one earns a
  truthful `304` for bytes the client no longer has.
- **A read may be served offline; a write may not.** This is not an exception to ADR-0019 — it is the other
  side of it. A user opening registration in a lift sees the currency list they saw yesterday, and still
  cannot submit.
- **All three or none.** The currency and the two questions are pickers over server content with no keyboard
  fallback, so one failure fails the screen and offers a retry. Not a `LoadState`: the taxonomy belongs to a
  screen's one *read*, and this screen writes (`StateTaxonomyTests`).

### The rules that differ from the design

| Rule | Design | Here | Why |
|---|---|---|---|
| Password floor | 6 at sign-in | **8** everywhere | Invariant 4 |
| Minimum age | 13, picker-capped | 13, picker-capped **and refused client-side** | A form that collects a twelve-year-old's name, email, and phone number before the server refuses them has already collected them |
| Question identity | the English text | the opaque id `sq01`…`sq14` | §4.3 **[FIX]** — a question stored by its wording cannot be reworded, translated, or compared across languages, and the answer is hashed against the question it belongs to |
| Terms consent | two links inside the checkbox label | the checkbox, and **two links beside it** | A VoiceOver user cannot reach a link buried in a control's label, and a localised string carrying markdown links puts a URL's position inside the translation |
| Terms URLs | hardcoded | **build configuration** (`HW_TERMS_URL`, `HW_PRIVACY_URL`) | Rule 7 — the domain arrives with the Cloudflare credentials, and staging must be able to link to staging's Terms |
| Failure copy | a toast | under the control that failed | A toast is not somewhere a screen-reader user finds an error |
| `.orb` behind the statement card | a 9-second ambient loop | not drawn | An ambient loop needs a Reduce Motion replacement *and* a reason; decoration behind a card read once has neither (the call `HWBrandGround` already made about the drifting starfield) |

### Nine components, seven of them brand-only

`HWStepBar`, `HWStrengthMeter`, `HWCombo`, `HWMoneyField`, `HWPhoneField`, `HWDateField`, and
`HWPickerSheet` are new; `HWSheetChrome`, `HWSheetRow`, `HWCodeChip`, `HWIconButton`, and the two text-role
modifiers gained an `HWAppearance`. Seven of the new ones resolve `brand` only, and say so: the design draws
their `surface` twins on Add Expense (#18), and inventing that arm now would be re-picking rather than
converting — the reasoning `HWButton` already applies to the destructive variant it has not drawn.

**The date field is the system's `DatePicker`, deliberately.** It is the one place a date is rendered without
our code touching it: ADR-0011 keeps every formatter out of the app, and a compact picker draws the chosen date
in the environment's own locale and calendar. Building a field that showed `12/03/1994` would mean choosing an
order, and the order is the locale's. It binds `Date?`, not `Date` — a picker defaulted to "eighteen years ago"
would let somebody submit a birthday they never entered, and the "please choose your date of birth" rule could
then never fire.

### One calendar for every date rule, in the device's zone

`isoDay`, `dateOfBirthRange`, and `age(on:now:)` share one Gregorian calendar, and its zone is the **device's**
— because that is the zone the value was produced in. A `DatePicker` yields the instant a chosen wall-clock day
began locally; reading its components in UTC moves the day for every user whose local time is inside the offset.

This was UTC first, on the argument that a span should not cross an offset change. It is the wrong half to
optimise: a *span* measured in a real zone does cross one — the Gulf adopted +04:00 in 1920, so "120 years ago"
comes back 119 years and 364 days — but that only shifts the oldest date a picker offers by a day, while getting
the *day* wrong shifts a birthday. The zone follows the input. It is arithmetic either way, not display: what the
user reads is drawn by the system picker in the environment's locale.

## What the running app and review found

Fourteen defects that every test passed through. Each is now asserted, and three were confirmed by deliberate
mutation.

### From looking at it running

**The label style painted its own colour, so every caller's override was dead code.** `HWLabelStyle` applied
`.foregroundStyle(surface.inkSecondary)` *inside* the modifier; an outer `.foregroundStyle` at the call site
loses to an inner one. Four field components on the galaxy ground each wrote that override and each got the
light surface's ink anyway — a field whose label could not be read at all. It also means the fix made during
#14's review never took effect on sign-in. Both roles now take an `HWAppearance`.

**`Text` markdown-autolinked the placeholder.** `you@example.com` is an email address, so SwiftUI drew it as a
system-blue link inside the box. The real error was upstream: the design's floating label *replaces* the
placeholder (`input::placeholder{color:transparent}`), and here the label always sits above the box — so a
placeholder repeating it printed the field's name twice. `HWTextField` now draws none when none is given, and
the two example-address entries are gone from the catalogue.

**The re-entrancy guard made `await loadReferenceLists()` return without the lists.** Two callers exist — the
screen's `.task` and the retry button — and the second one returned early, then carried on and validated
against a `nil` currency. The visible symptom was a filled form refusing its own salary. It is now
single-flight over a stored `Task`, the same shape `APIClient` uses for a refresh: a second caller *joins*.
The guard that only skips work is the one that silently lies about what it did.

**A key with an interpolated argument never resolved, and the scan required the shape that cannot.**
`Text("home.income.accessibilityLabel \(figure)")` looks up `home.income.accessibilityLabel %@` — not the bare
key — so Home's income figure had been announcing its own key to VoiceOver, in a green suite, since #12.
`LocalisationTests` now derives the key **with** its specifiers, and the convention that makes that derivable
is stated: **every argument this app's copy takes is a `String`**, so a number is converted where it is
computed rather than where it is drawn. A `\(count)` would resolve to `%lld`, which is unknowable from the
source — so the convention is a convention, and the scan says so rather than implying it enforces it.

### From review

**Money.** A comma may be a decimal separator, and reading it as grouping is a 100× error. `.decimalPad` offers
the *device region's* separator and no other, so on a German or Brazilian phone there is no `.` key at all: a
salary of `8000,50` was arriving as `80_005_000` minor units, and every "% of pay" in the app is computed against
that figure (invariant 2). The **last** separator now decides, by what follows it — one or two digits separates a
fraction, three or more groups. Eastern Arabic-Indic digits were also refused as "not a figure"; every digit is
read through `wholeNumberValue`, which knows every script.

**Dates.** A `DatePicker` yields the instant a local wall-clock day began, so reading its components in **UTC**
moved the day for anybody whose local time is inside the offset — in `Asia/Dubai`, every user registering before
04:00 sent a birthday one day early. The calendar's zone now follows the input. The cost is that a 120-year span
crosses a historical offset change (the Gulf adopted +04:00 in 1920), so the oldest date the picker offers is
119 years and 364 days; exactness matters for a birthday and not for a bound.

**The goal went stale.** The step-3 pre-fill was guarded on "the box is empty", which is only ever true on the
first arrival. Correcting a salary on step 2 and continuing left `1600` in the box beside a statement card
reading `4000` — and **submitted it with `goalWasSkipped: false`**, recording as the user's own choice a figure
the app had computed from a salary that no longer existed. `goalIsSuggestion` now re-derives it, and a figure the
user typed is left alone.

**Failures on the wrong control.** `.firstAnswerMissing` was attached to the *question's* field, so an unanswered
question reddened the picker and left the empty box unmarked. Worse, typing an answer cleared "choose a question"
— a clean-looking form with nothing chosen, which the next submit refuses again. The answers have their own
fields. And editing the *password* left a stale "those do not match" under a confirm box that now matched: that
sentence is about both boxes, so correcting either clears it.

**One bad payload deleted the other two.** The loader recovered from an undecodable resource by calling
`clear()`, which on disk is one `removeItem(at: directory)`. The three loads run concurrently, so any one of them
could take the other two lists and their ETags with it — and with them the offline fallback the store exists for.
`ContentStore` grew `remove(_:)`.

**"Not asked yet" was drawn as "the ask failed".** The screen's `.task` runs after the first body evaluation, so
for one frame the state is three empty lists and no failure — which rendered "something went wrong · Try again",
with a Retry button a VoiceOver user could land on before anything had been attempted. The spinner is now the
default and the failure state needs a failure.

**E.164 had a trunk prefix in it.** A UAE resident writes their number `0501234567`; concatenated onto `+971`
that is a thirteen-digit string inside the accepted range and not a dialable number. The national significant
number is stripped, and the digit count is checked against what will be sent.

**The date field announced a date nobody chose.** `.opacity(0)` does not remove a view from the accessibility
tree, and the proxy binding reads the range's upper bound — so an untouched field told VoiceOver "Date of birth,
1 January 2013", to exactly the users who cannot see the placeholder saying otherwise. It now carries the
placeholder as its value in that state.

**A refusal was silent.** Pressing Register, Next, or Submit with something wrong changes nothing a screen reader
notices: the screen does not move, and the form-level message sits *below* the button. The first failure is now
announced, at `.immediate` priority, from one place that all three steps write into.

**Field errors were hint-only.** A hint is spoken last, after a delay, and can be switched off entirely — so
"use at least 8 characters" was unreachable by any means for a user who had done that, on a screen whose copy was
moved out of a toast for exactly that reason. The message stays in the accessibility tree *and* is delivered as
the hint. `HWCombo`'s affordance hint is no longer replaced by the error either: the user who has just been told
the field is wrong is the one who most needs to know it opens a list.

**Reduce Motion was half-applied.** Every field branched its `.transition` and left the container `.animation`
unconditional — and the container animation is what eases the *height* change, so an error appearing still slid
every field below it down the screen. `nil` under Reduce Motion, so the message arrives in place.

**An emptied picker was silent.** Filtering replaces the rows where they are, so a VoiceOver user searching a
251-row list heard nothing when it emptied.

**And two of the scans asserted nothing.** `formatSpecifiers` returned an empty array for every string in the app,
because `@` is not a `Character.isLetter` — so "every multi-argument format string numbers its arguments" was
vacuous, including about the three two-argument entries this change added. And the new key derivation counted
interpolations and appended a run of `" %@"`, which is right only when every argument comes last: `key %@ of %@`
would have been reported as both missing *and* orphaned. Both helpers now have their own suite, because a scan
that reads source is code, and both of these stopped working quietly.

## Alternatives rejected

**Three pushed screens.** Simpler navigation, and it would have given each step a swipe-back that discards it.

**An email-availability check on step 1.** Faster feedback, and an account-enumeration oracle.

**Interpolating the minimum age into its message.** It keeps the number in one place; it also puts an English
sentence frame around it. The copy names thirteen and a test asserts it still matches `minimumAge` — which is
the job the interpolation would have done, without the frame.

**Two numbers interpolated into "Step %lld of %lld".** Two catalogue entries saved, and the translation's word
order lost. There are exactly three steps and they will not grow, so there are three sentences.

## Consequences

- Registration is reachable from sign-in and lands on Home through `isSignedIn` alone — no screen navigates.
- An unverified account can use the app and sees a strip above the tabs. It carries no action: verification
  happens in the email, and ADR-0008's foreground revalidation is what makes the strip disappear. A "resend"
  control belongs to Account (#17).
- The three lists cost three conditional `GET`s per visit to the form, in parallel, answering `304` after the
  first.
- `AppConfig` now parses four values, and `BuildConfigurationTests` derives its assertions from one table of
  them — so a fifth is covered by every check rather than by whoever adds it remembering.

## The gap this leaves

**The currency exponent.** `Currency` carries a code, a name, and a symbol, because that is what the design's
list carries. Minor units are therefore read as two decimal digits — right for 157 of the 160 currencies and
wrong for KWD, BHD, and OMR, which have three. Nobody's *salary* is stored wrongly by this today (the figure
goes as minor units and the server owns the conversion), but a Kuwaiti dinar typed as `1.234` would arrive as
`123` minor units instead of `1234`. The reference list needs an `exponent` field; recorded in `CONTEXT.md`.
