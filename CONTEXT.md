# CONTEXT — HisaabWiseIOS

Glossary for the iOS app. These terms have precise meanings; use them exactly, in code,
tests, and issues. Where a term has a tempting synonym, the synonym is named and rejected.

Backend vocabulary (`Money`, `saved`, `verdict`, `monthKey`, `dayKey`, `live month`,
`closed month`, `token family`, `securityEpoch`, …) is defined in
`../HisaabWiseBackend/CONTEXT.md` and is **not** redefined here. This file covers only what
is client-side.

Decisions that established these terms live in `docs/adr/`.

## Structure

**app target** — `HisaabWise`, the single target holding all of the app's Swift, grouped by
MVVM layer: `Models` · `ViewModels` · `Views` · `Components` · `Networking` · `Fixtures` ·
`DesignSystem` · `Persistence` · `Resources`. `Fixtures` code is `#if DEBUG` only.
See [ADR-0018](docs/adr/0018-app-target-and-mvvm.md), which supersedes ADR-0002's package
topology and its six `HW*` library targets. Where a spec or issue still says `HWCore`,
`HWNetworking`, or `HWDesignSystem`, read the corresponding folder.

**composition root** — `HisaabWiseApp.swift`. The only place that decides which `Transport` the
app runs on and what base URL it points at, and the only place in the app target that names
`Bundle.main` — the live-Worker suite names it too, deliberately, to read the plist the real build
produced. Nothing below it knows what an environment is. There is **one transport in every configuration** —
`URLSessionTransport`, including in Debug, which points at `wrangler dev` — so fixtures are what
tests and previews run on rather than what the app runs on ([ADR-0022](docs/adr/0022-production-transport.md)).

**build configuration** — the three ADR-0010 configurations, `Debug` · `Staging` · `Release`, each
an `.xcconfig` in `HisaabWise/Configuration/` setting `HW_API_BASE_URL` and naming the `Info.plist`
it uses. **`AppConfig`** parses the plist key into a `URL` and is the only type that knows a
configuration exists; it refuses cleartext for any host but `localhost`, which is also the only host
the Debug plist's ATS exception names. `BuildConfigurationTests` reads all five files from disk,
because nothing here is checked by a compiler.

**app environment** — `AppEnvironment`, the object graph the composition root assembles: the
`APIClient`, the `ThemeManager`, and the `LanguageManager`. It is *not* the composition
root — it owns the wiring on the far side of the root's one decision. It **builds** the client from
the root's base URL and transport rather than being handed one, so the client's `Accept-Language` and
the language on screen are necessarily the same choice, and it **connects** the language back to that
client, which is the graph's one cycle (ADR-0024). It is also where the real, *persisting* stores are
chosen — `KeychainTokenStore` and `UserDefaultsLanguageStore` — so that constructing either object
elsewhere leaves no footprint on the machine. **No singletons and no globals**: nothing in
the app reaches for a `.shared`, and a source scan in `LayeringTests` keeps it that way. View models
are *made* here, not held here.

**view model** — an `@Observable` `@MainActor` class owning one screen's presentation state. It
conforms to **`BaseViewModel`**: it declares `fetch()`, optionally `isEmpty(_:)`, and gets `load()`
— the one `APIError` → ``LoadState`` mapping in the app — from the protocol extension. It never
*derives* a figure: every figure is computed server-side (invariant 3) and `Money` exposes no
arithmetic to derive one with. Formerly called a *store* (ADR-0002); that term is retired.

**base contract** — the pair of protocols an in-app screen is written against: `BaseViewModel` in
`ViewModels/` (one request, one state, no mapping of its own) and `BaseView` in `Views/` (a
defaulted `body` supplying the chrome, the `StateView`, and the `.task` that starts the load). A
screen declares three things — the view model, its `StateCopy`, and `loadedContent` — and inherits
the rest. **A conforming view model cannot declare `private(set) var state`**: the protocol needs a
settable `state`, so confining mutation to `load()` is a convention here rather than a compiler
guarantee. That trade-off is accepted, not worked around.

**screen chrome** — `ScreenChrome`, the view that carries what every screen has in common: the
ground, the `StateView`, and the `.task`. It exists because a protocol extension cannot declare
`@Environment`, so a defaulted `body` has no way to read the theme. **It paints `surface`**, which
is the five in-app screens; Landing and Auth are `brand` (ADR-0021) and are not `BaseView`
conformances. Making the chrome appearance-agnostic is work for whichever of #13–#16 needs it, with
two real callers to shape it.

**the shell** — `AppShell`, the `TabView` with a `NavigationStack` per tab: Home · Expenses · Learn · Reports ·
Account, all reachable from all, with log out as the only way out. The design's `.tabbar` CSS is **not**
converted — re-implementing a system container would mean re-implementing the safe-area inset, the material, the
selection semantics, and VoiceOver's "tab 2 of 5" (Rule 1). Its decisions are: labels always visible, selection
marked with `--galaxy` through `surface.ink`, and its five stroke icons as the SF Symbols that draw the same
things. The unselected `--ink-3` is the system's grey, because reaching it means `UITabBar.appearance()`.
See [ADR-0026](docs/adr/0026-shell-plumbing.md).

**Landing** — `LandingView`, the first screen converted from the design (#13). **Not a `BaseView` and its view
model has no `fetch()`**: it makes no request, so there is no `LoadState` to draw, and it sits on `brand`, which
`ScreenChrome` does not paint. `LandingViewModel` holds the strapline *index* and no clock — the view's `.task`
advances it, which is what lets Reduce Motion suppress the rotation by never starting it. The four straplines are
the view's, because copy belongs where the localisation scans look for it.

**The hero illustration is an SVG asset** (`hwHeroBook`), extracted verbatim from the design rather than
hand-converted or re-picked; it ships in its settled state, and the six animations the design drives with CSS do
not. **The screen scrolls when the type outgrows it** — the design's fixed viewport is a web assumption, and at
AX5 the first build drew the headline through the strapline. **The wordmark is one `Text` carrying an
`AttributedString`**, because two `Text`s in an `HStack` reorder under RTL and a brand name is one word whichever
way the layout runs. **The strapline's sentence is an accessibility *value*, not a label**, so the rotation never
re-announces. And the first strapline is a **[FIX]**: the design named a currency the app does not display, and a
test scans all four so it cannot come back.
See [ADR-0029](docs/adr/0029-landing-conversion.md).

**sign in** — `SignInView` plus `SignInViewModel`, the second brand screen (#14). **Email is the identifier and
the password rule is 8+** (Product Spec §3.2 [FIX] ×2 — the design asked for a username it never collects, and
accepted six characters). **Every refusal reads the same**: the mapping is inverted so that everything from the
login route is `credentialsRefused` *unless it is a known fault* (5xx · 429 · 400), because listing the refusal
statuses instead left a `404 NO_SUCH_ACCOUNT` carrying its own copy and turning the form into an address
checker. Three refusals suggest support and never gate a request — the backoff is the server's. The screen holds
its own view model, unlike a tab's: a pushed form should lose its state when it goes, and here that state is a
password.

**`SignInFailure`** — what is wrong with the form, as a value that knows **which field it belongs beside**, so
"field-level errors" is a property of the type. `unreachable` rather than `offline`: the word `offline` belongs to
`LoadState` and the taxonomy scan is a text scan (the copy is still `state.offline`). It is the app's **second**
owner of the `APIError` → presentation mapping, and `StateTaxonomyTests` names both — a read becomes a
`LoadState`, a form becomes field errors. A third means changing that list.
See [ADR-0030](docs/adr/0030-sign-in.md).

**atomic registration** — three steps in the UI, **one `POST /v1/auth/register` at the end**. The client holds
steps 1–2 in memory, so nothing exists server-side until the last button and there is no half-built account to
resume or clean up. Two consequences are the point rather than the cost: there is **no email-availability
endpoint anywhere** (it would answer "does this person have an account" to anybody who asks), so a collision is
discovered at submit and sends the user back to step 1 with the field marked; and submit validates **every**
step's rules, because a field left invalid two screens ago would otherwise reach the server. The step is `@State`
on one screen rather than three pushed ones — a swipe-back that discarded a step's typing is the failure the
atomic call is built around.

**`goalWasSkipped`** — the one field that distinguishes **Skip for now** from a typed 20%. Both buttons send the
same request and the same figure; skip means "you choose for me", not "leave it empty". Without the flag the two
are indistinguishable, and the app could never say "you chose this" rather than "we suggested this".

**`RegistrationFailure`** — the third owner of an error-to-presentation mapping and the second *form*, alongside
`SignInFailure`. Same shape and the same reasons; the interesting case is `emailTaken`, which is the only
per-field failure registration can receive from the server and the only way the client ever learns an address is
registered.
See [ADR-0031](docs/adr/0031-registration.md).

**appearance** — `HWAppearance`, which of the design's two surfaces a control is drawn on, as a *parameter*
rather than a mode: both ship at once, one before sign-in and one after (ADR-0021). It arrives on `HWButton` with
Landing, and the design settles it rather than a guess — the landing `.cta` and auth's `.btn-primary` carry the
same fill and the same ink. Brand buttons are **pills**; in-app ones use the card radius. The one pair that is
not a transcription is brand `soft`, which resolves to brand `ghost` because the design has no `.btn-soft` there.

**ambient loop** — a repeating decorative animation whose period is measured in seconds, through
`HWCurve.loop(seconds:)`. Deliberately outside the four-duration scale: those are *transition* clusters, and
rounding a 6-second breath into 500ms would make it twitch. Landing's hero float and its pill dot are the two.

**`RootView`** — the one branch on `SessionCoordinator.isSignedIn`: the shell, or Landing. That is what makes
"log out returns to Landing" a consequence rather than navigation code — the sign-out clears the session and the
root follows, so no screen has to know it is being dismissed. It reads **no** `scenePhase`, deliberately.

**`TabViewModels`** — one view model per tab, **made** by `AppEnvironment.makeTabViewModels()`, held by the
composition root, and injected once. Five named properties, so every tab has one by construction. Held rather
than made in a `body`: a view model built during a render resets its screen on every re-render, and the reset
looks like a slow network. Conforms to `Observable` by hand rather than through the macro — every property is a
`let`, and what changes is the state inside each model. **Its lifetime is the session's, not the app's**: the
root replaces the whole set when `isSignedIn` goes false, because a view model holds the last response it got
and a signed-out `HomeViewModel` is still holding a salary. Invariant 8's reasoning about caches applies to
objects too — per-user data that outlives the user is a leak, not a warm start.

**unwritten tab root** — `UnwrittenTabRoot` plus `UnwrittenScreenViewModel`, the stand-in for the screens that are
other tickets. **One of them now**: Account (#23) — Expenses retired its placeholder with #18, Learn with #19, and
Reports with #21, which is what "retired the moment each screen lands" means in practice. A full `BaseView` conformance, so it renders through `StateView`,
and it **makes no request**: calling the ADR-0020 screen endpoint would put a fictional contract in the client
and render "Something went wrong" on four of five tabs. A screen that is not built is not a screen that is
broken. Its `footer` slot carries `LogoutControl` on Account. **Retired the moment each screen lands.**

**Expenses** — `ExpensesView` plus `ExpenseCategoryView` and `ExpensesViewModel`, the core loop and **the first
screen in the app that writes** (#18). Two levels over one read: the monthly summary with its wants bar and the seven
category rows, and behind each row a detail page drawing whichever of the three structural kinds that category is.

**Seven categories in three kinds**, and the kinds decide which write the page offers: `log` (Groceries · Transport ·
Entertainment · Other · Additional Income) appends individually deletable entries, `lines` (Utilities) holds a set of
named monthly bills edited and saved *together*, `fixed` (Rent) holds one editable amount. `kind` is therefore the
one enum in the payload that **refuses to guess** — `Icon` and `Flow` degrade to a default because they are
presentation, and a `log` form over Rent would file the wrong shape of thing.

**Additional Income is money in**, said structurally rather than by the client recognising an id: it is out of the
spend total, into the budget's income, and its display string arrives **already signed** (`+₹900`) because a
client-side `+` lands on the wrong side of an Arabic figure.

**`ExpenseCategoryPage` is the content and `ExpenseCategoryView` is the chrome** — the scroll, the title, the
toolbar, the sheet. The split was found by looking: `ImageRenderer` does not lay out the content of a `ScrollView`,
so a render of the whole page came back as an empty ground and the test asserting it rendered was passing on it.
See [ADR-0033](docs/adr/0033-expenses.md).

**Learn** — `LearnView` plus `LearnViewModel`, the unit map (#19): five units, fifteen lessons, a segmented progress
ring on each, sequential unlocking, and the per-unit guide sheet. An open node now opens the **lesson player** (#20)
as a full-screen cover over the map, and the closure the shell used to supply is gone with the screen it stood in
for — see **lesson player** below.

**It is the one screen that reads two endpoints**, and that is invariant 8 deciding where the seam goes rather than an
exception to ADR-0020. `GET /v1/curriculum` is ~100 KB of editorial content, the same bytes for everybody, stored on
disk with an ETag; `GET /v1/screens/learn` is ~3 KB of per-user state that bypasses every cache. Folding either into
the other breaks one of those rules. The client asks for both concurrently and joins them **by lesson id** —
`LearnMap`, built once in the view model rather than as fifteen lookups in a `body`.

**The join is a lookup, not a calculation**, and that is the test the exception has to pass: it introduces no figure
that was not in one of the two responses. Every lock, every ring count, every label, and the ordering arrived
computed. `isOpen(id)`, `firstOpen()`, `unitOpen`, and `qCount(l)` are all in the payload now.

**A segmented ring's geometry is two `Int`s**, so `MoneyFormattingAbsenceTests`' three named `Double` exemptions stay
three. The client *could* count the curriculum's own question steps and does not: a count is a calculation, and a ring
whose segments came from one response while its fill came from another is a ring with two owners. The corpus asserts
the two halves agree; `LearnViewModelTests` sends a payload where they do not and asserts the screen draws the
payload's figure — the only way to tell a client that reads from a client that counts.

**`LearnScreen.Stat`** — `Money`'s three-field shape applied to a figure that is not money. `display` because the
client has no thousands separator (ADR-0003); `accessibilityLabel` because "4-day streak" is a count *and* a plural
(ADR-0011); `value` because it is drawn by nothing, which is its job — it makes "Home and Learn agree about the
streak" a numeric assertion rather than a comparison of two strings that could be wrong in the same way. The **unit
number** deliberately does not arrive formatted: 1…5 has no separator and no plural, so `String(_:)` is the whole of
its formatting, spelled in `Curriculum.Unit.numberText` where the number is *computed*.

**`LearnScreen.LessonState` refuses to guess** where `Curriculum.Accent` and `Curriculum.Unit.Icon` degrade. The two
presentation enums fall back to the design's own defaults; a lesson's state decides whether the reader can open it,
and **both fallbacks are wrong in a way the reader cannot get out of** — `locked` strands them in front of a lesson
they earned, `available` offers one the server refuses. A fourth state is a coordinated release, exactly as
`ExpensesScreen.Kind` is.

**The client renders the lock and the server enforces it**, so a stale lock costs one reload. A locked node is
therefore **not a disabled control**: the design's `<button>` is `disabled` and its refusal comes from a container
handler that fires anyway, and a SwiftUI `.disabled(true)` button fires nothing — so a reader would tap a padlock and
be told nothing. It stays enabled and refuses with the design's own sentence.

**The `START` flag is hidden from VoiceOver and the node says it instead** — one `HWComponentCopy.lessonHint(state:isNext:)`
table, read by the node on the path and by the row in the guide sheet. It is one table because for one build it was
none: the flag was hidden on the stated grounds that the node's hint said it, and `isNext` reached no accessibility
surface at all, so a reader could not tell which of fifteen lessons was the cursor.

**The path is replaced rather than shrunk** — the fifth clamp consumer and the first whose replacement is a *layout*
rather than a chart's figures. A 78pt ring with a wrapping label under it, swung 56pt off the centre line, has
nowhere to grow; above the threshold the same lessons are a column of `HWLessonRow`s, which is also the guide sheet's
row and also the path's `accessibilityRepresentation` below the threshold. **The connectors are measured**, as the
design measures them, and that is the RTL fix for nothing: a measured frame comes back already mirrored where a
hand-computed `x` would need the direction read and negated. See [ADR-0034](docs/adr/0034-learn-unit-map.md).

**lesson player** — `LessonPlayerView` plus `LessonStepPage`, `LessonPlayerViewModel`, and `LessonRun` (#20): the
124 steps, three hearts, the combo, and the way out. A **full-screen cover over the map**, which is what the design's
slide-up `.player` section is — so the closure the shell passed Learn while this was unwritten has gone with it. The
player is **not a `BaseView`**, because it makes no request; the second such screen after Landing.

**`LessonRun`** — one run through one lesson, as a value: the step, the hearts, the consecutive-correct count, the
per-question results, and **the grading**. It owns no clock and no total. Two states that look alike are kept apart:
`isFinished` means every step is behind the reader and *submits*, while `isOutOfHearts` means the run is over and
nothing is filed — `advance()` refuses to move, so there is no step after it to draw.

**client-side grading is bounded, not merely allowed** — the app's one exception to server-side calculation
(invariant 10, ADR-0020), and three limits are what make it safe: it decides *right or wrong* and never a score;
every result is submitted as `{stepIndex, isCorrect}` so the server recomputes the XP and can refuse an impossible
submission; and every total the reader reads comes back in the response. The numeric tolerance is a **strict** `< 0.5`
compared in integer hundredths — `3600.49` is right and `3600.5` is wrong — because `Models` may hold no `Double` and
because a floating-point tolerance has a boundary that moves with the value's magnitude.

**the submission *is* the screen** — `LessonCompletionViewModel` is a `BaseViewModel` whose `fetch()` is
`POST /v1/learn/lessons/:id/complete`. That is ADR-0020's write rule rather than a stretch of the base contract, and
three requirements fall out of it: offline becomes `LoadState.offline` with the chrome's own retry and **nothing
queued** (ADR-0019), a `422` becomes a definite failure carrying its code, and the retry is a button the reader
presses. So the taxonomy still has **four** owners of the `APIError` mapping and not five. One `Idempotency-Key` per
intent, minted at `init` and reused across retries: finishing a lesson happens once.

**the player keeps its own copy of the lesson** — the mirror image of the guide sheet, which holds a unit *id* and
re-reads it so a reload writes through. A sheet is a view of server state; a run is what the reader is doing, and
re-reading it from each reload would restart the lesson under them. The cover is presented off the **object** for the
same reason.

**the interim progress report** — `POST /v1/learn/progress`, sent by `LearnViewModel` when a part-finished player
closes. The request is launched from the *tab's* view model over a value, so the panel closes at once rather than
waiting for the network; a **finished** run reports nothing, because the completion has already said more; and a
failure reports nothing at all, because the reader has left and there is no queue. It carries the results rather than
a count of lit arcs — `filledSegments` is a figure the screen draws, so it is the server's.

**`LessonCompletion`** — the celebration, fully computed, with the updated Learn screen **inside it**. `xpEarned` is
signed server-side (`+50`), the accuracy is a percentage the server computed, `streakLine` is a server sentence
because it is a count with a plural in it, and the seven-day `week` carries a label, two flags, and a reading per day
— decided against the reader's stored timezone, because a client that knew which day was today could move the streak
by moving the clock. **Defect D13 is two payloads**: a replay earns `0` and leaves the XP total byte-identical to
`learn-in-progress.json`'s.

**`CurrencyToken`** — what `{c}` becomes, as a type with one owner. Editorial content is cacheable and carries the
token verbatim; the per-user payload carries the symbol (`LearnScreen.currencyToken`, `HomeScreen.Tip.currencyToken`),
which is the same join Learn already is. Amounts beside it are **illustrative and never converted**.
See [ADR-0035](docs/adr/0035-lesson-player.md), [ADR-0016](docs/adr/0016-presentation-details.md).

**Reports** — `ReportsView` plus `ReportsArchivePage` and `ReportsViewModel`, the retrospective (#21): which months
are closed, what each cost, whether the goal was met, and the trend through all of them against a dashed goal line.
**The shortest view model in the app, and that is structural**: an archive is a record, so there is nothing to
choose about it and nothing to type into it — no isolated slice, no substituted tip, no draft, no run.

**It is the screen defect D11 lives on**, and the client's half of the fix is *absence*. §4.2 keeps one threshold
table — 100/70, server-side — where the prototype carried two disagreeing ones for the same pill on the same number
(Reports 100/70, Home 80/45), and neither is converted. No `saved`, no `goal`, and no percentage as a *number*
reaches this screen in any month or any bar; a percentage arrives as a sentence and a verdict arrives as a verdict.
`ReportsViewModelTests` asserts that against the **wire** rather than the decoded type, because a `Decodable`
ignores keys it does not name — a server that started sending `saved` per month would be invisible to a test that
only read `ReportsScreen`.

**`ReportsScreen.Verdict` refuses to guess where `HomeScreen.Verdict` degrades**, and the difference is what the
value describes. Home's pill is about a month still running, so an unknown verdict reading as "on track" is a hedge
about something that has not happened. This is about a month that has **closed and is immutable** (invariant 7): a
fourth verdict drawn as `near` would tell a reader that a month they smashed or missed outright nearly hit its goal,
and would keep saying so for ever. Two vocabularies — `low`/`onTrack`/`met` and `hit`/`near`/`miss` — for one rule
is a translation, not a second rule.

**Two orderings, both the server's.** The trend runs oldest to newest because time reads that way; the archive runs
newest first because the month a reader wants is the one that just closed. The corpus asserts that every bar and its
month row carry the same verdict and the same percentage — the same number thresholded twice inside one assembly
would be D11 moved from the client into the server. And **there is no per-month `saved` in the payload**, which is
why the corpus checks no arithmetic here: with nothing to sum, the per-year totals and the mean have exactly one
owner.

**The trend's two heights are one scale.** The design scales the plot to `max(125, tallest × 1.08)` so a good month
can overshoot; a bar's height and the goal line's arrive as fractions of the plot and the y-domain is fixed at
`0...1`, because a client computing either could draw a bar at 101% *below* a line at 100% — the chart contradicting
the badge beside it. The chart is keyed on `monthKey` and not on the label: two Februaries in two years share a
label and would collapse into one bar.

**The month rows open the month, and the affordance arrived with it.** `HWMonthRowLabel` draws the row's contents and
takes a `showsChevron` flag; #21 shipped it with the flag off, because a chevron pointing at an unwritten screen is a
broken promise in a smaller font, and the hint copy that describes the tap arrived with the tap rather than sitting in
the catalogue as a sentence nothing shows. It is a **label** rather than a row with an action, for the reason
`HWCategoryRowLabel` is one: the shell hands out no path binding, so the push is a value-based `NavigationLink`, and a
`Button` inside a link is two controls for one row. Reports pushes its own detail rather than being handed a route by
the shell — unlike Home's two destinations, which are *tabs*, a month is a page inside this tab.
See [ADR-0036](docs/adr/0036-reports-archive.md), [ADR-0037](docs/adr/0037-reports-month-detail.md).

**Reports, level two** — `ReportsMonthView` plus `ReportsMonthPage` and `ReportsMonthViewModel`: one closed month in
full (#22). Seven cards over one read of `GET /v1/screens/reports/:monthKey` — the totals with the sentence that
explains them, that month's donut, the savings meter, the wants allowance, the four-segment split bar, an accordion of
every entry logged, and the facts grid.

**This is the screen invariant 7 is about.** An archived month is immutable and carries the FX rate set pinned at
close, so a currency change **is a re-read**: the figures come back converted through those rates and the verdict does
not move. There is no client-side conversion to invoke and none available — the client holds no rate, `Money` has no
arithmetic, and every figure arrives formatted. The corpus carries the same February twice, in rupees and in dirhams,
and both `FixtureCorpusTests` and `ReportsMonthViewModelTests` assert the property: every monetary string differs, and
the verdict, the percentages, the meter position, and every geometry fraction are identical.

**It carries `saved` and `goal` where the archive carries neither**, and the difference is what each screen draws: a
badge has nothing to do with a figure but threshold it (defect D11), while a meter needs both — which is the shape
Home's payload already has. The protection is unchanged: no percentage arrives as a number and the verdict arrives as
a verdict.

**The split bar is where the Product Spec overrules the design.** §4.2 **[FIX]** keeps four segments — `needs /
wants / min(saved, goal) / surplus` — because the prototype's "left unspent" is identically zero under a residual
`saved`. They sum to the income printed beside them, whether the goal was reached or missed, and the corpus asserts
it in minor units. `Portion` **refuses to guess** for `ReportsScreen.Verdict`'s reason and one more: a fifth part
would be a bar that no longer adds up, about a month that cannot be corrected. A seventh **fact** is the opposite
case and is *dropped* — the grid's labels are the app's, so an unknown kind has no words to draw itself with, and
losing one tile is additive.

**The design's month scroller is deliberately not converted**, which is the one place this screen narrows the design:
it is a second way to reach a month the archive one back already lists, and converting it would mean this payload
carrying the whole archive's month list beside the month it is about. If it returns it returns as a payload change.
See [ADR-0037](docs/adr/0037-reports-month-detail.md).

**`EntryDraft`** — the entry being typed, and it **outlives the screen deliberately**. A write that fails offline
replaces `state` with `LoadState.offline` (ADR-0019), so a draft living in the payload would go with it; this one
snapshots the field shape it needs, which is why a retry works with no payload in hand. Its **`Idempotency-Key` is
one per user *intent***, minted on the first attempt and reused across retries — the caller-supplied form
`APIClient.post` was written for and named #18 as the caller of. A second entry mints a new key; so does a re-file,
because the first attempt was *refused* and there is nothing to deduplicate against.

**`RefileOffer`** — what a `MONTH_CLOSED` write becomes: an offer, not a sentence. It names the **live** month, which
the client learns by *reloading* after the refusal — the label it was holding names the month that has just closed,
and offering to file into that one is the app lying about the date (§4.5). The re-file is then a plain re-send: the
server derives `monthKey` at write time and the live month only moves forward.

**A write's error mapping is `ExpensesViewModel`'s own**, the fourth owner `StateTaxonomyTests` names and a different
*kind* from the other three: a read becomes a `LoadState`, a form becomes field errors, and a write becomes either an
offline screen or a re-filing offer. That suite had already predicted this entry.

**`WriteKind`** — whether a write is *the entry form's own create* or one of the other three, which decides two
things: only a create is offered for re-filing on `MONTH_CLOSED` (only a create has a body to re-file — a deletion in
a closed month is a deletion of something an archive holds), and only a create empties the form on success. Both were
wrong when the funnel took a bare category id, and review caught both.

**`TypedAmount`** — reading a figure the user typed into minor units, and writing one back into a field they will
edit. Not client money arithmetic (ADR-0003): it converts nothing and rounds no rate. It was private to
`RegistrationViewModel` and moved out because Expenses is a second caller and the rule's failure mode is a **100×
error** — `.decimalPad` offers the *device region's* separator, so a comma may be the decimal point, and the **last**
separator decides by what follows it. It takes an **exponent**, which registration has none to pass: the screen
payload carries one and the currency reference list still does not.

**`LogoutControl`** — the only exit, and the only caller of `SessionCoordinator.signOut()` in the presentation
layers (asserted). A system `confirmationDialog` rather than the design's own modal: the platform's red, an
alert to VoiceOver, and no accidental dismissal. The design's copy verbatim, including "Stay signed in".

**`scenePhase` has one reader** — the composition root, with two consumers: ADR-0008's foreground sequence and
ADR-0014's privacy overlay, which takes the phase as an argument (`hwPrivacyOverlay(covering:)`). Passing it is
what makes both halves testable; a view that read it would be a view whose branch no test could set.

**`ImageRenderer` cannot draw a `TabView` — or a `NavigationStack`** — both yield the unsupported-view glyph, a
yellow field with a red bar, byte for byte identical. So no assertion about the shell or the root is a pixel
assertion; the renders prove the `body` evaluates with the environment it was given, and the *decisions* are
values instead: `RootView.world(isSignedIn:)` is the branch. Worth knowing before the snapshot suite (#9),
alongside the note that a `BaseView` render lands on `.loading`: all three want a hosted render.

**component** — one entry in the shared control vocabulary in `Components/`: a button variant,
a field, a label style, a card, a chip, a sheet, a row. **Presentational** — it takes values and
closures, holds no view model, and cannot fetch. A screen never styles a control itself; a new
variant is added here rather than inlined there. The inventory follows the design's own CSS
(`.btn` and its four variants, `.iconbtn`, `.editbtn`, `.field-box`, `.fld-lab`, `.eyebrow`, `.card`,
the chip and sheet families, `.row` / `.key-row`, the bars, `.toast`), and the table in
`Components.swift` maps each class to the type that converts it.

Four things about the vocabulary are deliberate and are decisions, not omissions:

- **Every component resolves the `surface` appearance**, which is the five in-app screens. The design
  spells `.btn-ghost` and `.btn-quiet` on `brand` only; their `surface` values come from the design's own
  tinted and bordered controls. The `brand` appearance arrives with Landing and Auth (#13–#16), on the
  same reasoning `ScreenChrome` gives for not being appearance-agnostic yet — two callers shape it better
  than one guess.
- **There is no destructive button yet.** `.btn-danger` and Account's `.logout` are a real fifth shape and
  arrive with Account (#23).
- **`.tabbar` is not a component; `.mark` now is.** The tab bar is the five-tab shell's `TabView` —
  converting the CSS would mean re-implementing a system container, which Rule 1 rules out. The wordmark
  **no longer waits on an image**: the design carries the logo as a base64 PNG in five places, it is extracted
  to `hwMark` in the asset catalogue, and `HWMark` draws it on the milky tile the design specifies (ADR-0026).
  The privacy overlay is the caller that needed it. `HWTopBar` can adopt it when #17 wants it — the design's
  tile is `--card` there and `--milky` on brand, which is one argument better had with two callers.
- **Display text is a `Text`, control copy is a `LocalizedStringResource`.** A button title or a field
  label is always app copy; a card subtitle, a chip label, or a row's name may be a server string
  (ADR-0003, ADR-0020), so the caller decides which. `HWComponentCopy` holds the only copy a component
  owns itself.

**the box** — `hwBox(fill:radius:border:borderWidth:elevation:)`, the rounded fill plus optional hairline
border plus optional elevation that the design draws nearly every control inside. It takes colours rather
than reading the palette, because its caller has already resolved a role. `HWTouchTarget.minimum` sits
beside it: the design draws `.iconbtn` at 40 and `.mchip` at ~34, and both are raised to **44** because
ADR-0012 makes the Accessibility Inspector a per-screen gate — four points of fidelity is the cheaper
thing to give up.

**the clamp pattern** — `hwVisualisation(replacedBy:)` and `HWScaling` in `DesignSystem/`, the **only** place
in the app that clamps Dynamic Type. Below `HWScaling.visualisationCeiling` (`xxxLarge`) the visualisation is
drawn and capped; at and above it — every `isAccessibilitySize` — the chart is **gone** and the alternative
layout is what the screen shows. Not shrunk: a donut at 310% type is a circle with three overlapping labels
in it. The alternative is *also* installed as the chart's `accessibilityRepresentation`, so one argument
serves the AX3 reader and the VoiceOver user both. The consumers are the donut, the savings meter, the wants budget bar,
the split bar, the week strip, and the savings-goal trend (#17, #18, #20, #21, #22) — the wants bar being the one
whose replacement is `EmptyView()`, because the figures it draws are already text above it, and the week strip being
the one whose replacement is the server's own per-day sentence as rows. The **trend chart** is the second
`describesItself: true` consumer after the donut, and for the same reason: its `BarMark`s publish a descriptor each,
so a representation installed over them would be read by nothing at any size.

**One visualisation is neither clamped nor replaced**, and it is a decision rather than an omission:
`HWProportionBar`, the 7pt stripe under each archive row. The pattern exists for fixed-layout *figures* that break
when the type grows, and this holds no text at all — no label, no axis, no legend, and no `aria-label` in the design
either. There is nothing in it to grow and nothing to overlap, so its replacement would be itself.

**Reading the size to choose a *layout* is
not clamping**: `HWFigureChips`' three chips become a column above the threshold, because a row of three broke
`₹3,529` across three lines. Everything else — tips, articles, lesson steps, every label —
**scales unclamped to AX5**, and `AccessibilityTests` asserts the range form of `dynamicTypeSize` appears in
one file. See [ADR-0012](docs/adr/0012-accessibility.md), [ADR-0025](docs/adr/0025-accessibility-plumbing.md).

**entrance** — `HWEntrance`, how a view arrives: `rise` · `pop` · `fade`, each carrying its transition,
curve, and duration. Its `reduced` form is a **cross-fade of the same length** — never `nil`, never
`.identity`, and never a different pace. This is ADR-0012's *replace, never remove* as a value rather than as
a ternary at each call site, because a ternary has a third option in it and the third option is the defect.
The worked example is the toast. **There is no in-app motion toggle**: the OS setting is the contract, every
mention of `accessibilityReduceMotion` in the app is an `@Environment` read, and nothing may store a motion
preference.

**announcement** — `HWAnnouncement.post(_:in:priority:)`, the one caller of `AccessibilityNotification` in
the app. It exists because an announcement is the only copy no `Text` draws, so it is the only copy that does
not get the environment locale for free — `String(localized:)` honours the *resource's* locale, which for a
literal created in a type initialiser is the **device's** (ADR-0011, ADR-0024). The locale is therefore
passed in, from `@Environment(\.locale)`. `.immediate` interrupts, for feedback about what the user just did;
`.standard` queues. Four callers, and the last two are the ones ADR-0012 wrote it for: the toast, `StateView`, the
lesson player's combo, and the completion screen — where the confetti reaches VoiceOver as nothing at all (#20).

**accessibility defaults** — what a screen inherits by conforming to `BaseView` rather than by remembering:
`ScreenChrome` makes the screen one accessibility container, `StateView` announces a placeholder replaced by
a *different* placeholder (nothing is announced for `loaded`), text is unclamped, and focus order is document
order — `accessibilitySortPriority` is banned app-wide. What a screen still writes itself is its own words:
labels, the heading trait, and the alternative layout for any visualisation it draws. **The Accessibility
Inspector audit is still a manual pass**; its automatable form, `XCUIApplication.performAccessibilityAudit()`,
needs a UI-test target this project does not have (ADR-0025).

**press treatment** — `HWPressStyle`, the one `ButtonStyle` behind every tappable component. It exists so
that the design's `:active` scale is picked once and, more importantly, so **Reduce Motion is handled
once**: the scale is *replaced* by a dip in opacity rather than dropped (ADR-0012). `accessibilityReduceMotion`
is a read-only environment value, so nothing can inject it — the replacement is asserted as a value and
the scans in `ComponentVocabularyTests` assert that every animating component reads it.

**screen endpoint** — one read endpoint per screen — `GET /v1/screens/home`, `/expenses`,
`/learn`, `/reports`, `/reports/:monthKey`, `/account` — returning exactly what that screen
renders, fully formatted. Writes keep their own resource addresses but **return the updated screen
payload**, so the client re-renders from server truth instead of patching its own copy. Cacheable
content (article bodies, curriculum, reference lists) stays on its own ETag'd endpoints.
See [ADR-0020](docs/adr/0020-screen-scoped-endpoints.md).

**server-side calculation** — every figure, percentage, count, date label, verdict, total, and
ordering comes from a response. The client renders; it never derives. **One deliberate
exception:** Learn grading is client-side for responsiveness (invariant 10), submitted per
question and recomputed server-side, and the client's answer is never authoritative. Local input
validation is not a calculation in this sense. The exception's three limits — it grades rather than
scores, every result is submitted, and every total comes back — are in **client-side grading is
bounded** below.

**localisation scans** — the source scans in `HisaabWiseTests/Architecture/LocalisationTests.swift`, which
carry ADR-0011 forward past the ticket that decided it. Every layer plus the app root: no `left`/`right`
edge, no direction-encoding SF Symbol, no Eastern Arabic-Indic digit, no `Locale.current`, no concatenated
sentence, no truncation or shrink-to-fit modifier, and positional arguments in every multi-argument format
string. Narrower by nature: an RTL preview on every screen in `Views/`, and the double-length scheme still
switched on. Plus the two that read the String Catalogue: **every key a view renders has English copy** — a
key with nothing behind it renders the key — and **no catalogue entry is orphaned**. Keys are found by
reading the source, not by being listed in a test, so a screen added next month is covered without anybody
remembering.

**accessibility scans** — the source scans in `HisaabWiseTests/Architecture/AccessibilityTests.swift`, which
make ADR-0012's per-screen gate something checked on every screen rather than agreed once: the clamp has one
owner, nothing shrinks text to fit, nothing reorders VoiceOver focus, Reduce Motion is only ever read from the
environment and never stored, no view or component can name `Money.minor` and so cannot re-spell a figure,
every screen in `Views/` carries an accessibility-size preview, and the chrome still carries its defaults.
Same standing as the layering and localisation scans — weaker than a compiler, and the only enforcement there
is.

**layering scans** — the source scans in `HisaabWiseTests/Architecture` that assert no view
touches `Networking`, no model touches `Networking` or SwiftUI, no view model imports SwiftUI, and
no component fetches or holds a view model. `ComponentVocabularyTests` adds the rules specific to a
component: it takes colour from `theme.palette` rather than from an asset symbol, sizes from
`HWTextStyle` rather than from `Font.system`, elevation from `HWShadow` rather than a hand-rolled
`.shadow`, clamps nothing, and carries both a VoiceOver surface and previews — including the RTL and AX
variants. Pinning no edge left or right is no longer among them: it was never specific to a component and
now lives, app-wide, in the localisation scans. In one target the compiler enforces no layer boundary, so these are the enforcement —
weaker than the package graph they replaced, and the only thing that keeps the layering from
being a convention.

## Talking to the server

**the seam** — `Transport`. `URLSessionTransport` in production, `FixtureTransport` in tests and
previews, and **deliberately no other injection point** in the app: a second seam means tests start
exercising doubles of our own design instead of the app (ADR-0013). `LanguageSource` and `LanguageSink` are
not second ones — they are dependency directions, and the only conformances are the real `LanguageManager`
and the real `APIClient`, in the app and in the tests alike.

**production transport** — `URLSessionTransport`, which does one thing and holds two decisions: its
session keeps **no `URLCache` at all**, because the per-request bypass stops a per-user response being
*read* from the cache and not being *written* to it (invariant 8), and it does not wait for
connectivity, because a request held open until the network returns is the write queue ADR-0019
removed wearing a system API's name. It also translates `URLError.cancelled` into `CancellationError`,
so a user navigating away is never reported as offline.
See [ADR-0022](docs/adr/0022-production-transport.md).

**write verbs** — `POST` · `PUT` · `DELETE` on `APIClient`, each returning the **updated screen
payload** (ADR-0020) rather than nothing. Every `POST` carries an **`Idempotency-Key`**, generated per
call unless the caller supplies one; a property of the verb rather than of a path list, so expense
create cannot be the one call that forgets. **The caller-supplied form has its caller now** (#18): the Add button
mints one key per user intent and reuses it across retries, so a write that reached the server and lost its response
is not filed twice. `PUT` and `DELETE` carry none — both are idempotent by
definition. The cache bypass and `Accept-Language` hold for writes exactly as for reads.

**`Accept-Language`** — set on **every** request from the app's `LanguageManager` through
`LanguageSource`. Load-bearing, not cosmetic: the server converts *and formats* money honouring it
(ADR-0003), and the client has no formatter with which to correct a figure that came back in the
wrong language.

**shipped language** — one of the two `AppLanguage` cases, `en` and `ar`, named as a set by
`AppLanguage.shipped`. The design lists 87 languages and the picker shows the shipped ones only
(Product Spec §3.7 **[FIX]**, ADR-0011); the other 85 are reference content the backend serves, and
nothing in the app enumerates them.

**`LanguageManager`** — the one owner of the language choice: `@Observable`, `@MainActor`, composed in
`AppEnvironment`, holding four views of one decision — `acceptLanguage` (the header), `locale` (how a
screen formats, `latn` numbering pinned in both languages), `layoutDirection` (which way it reads), and
`shipped` (what a picker may offer). **Nothing in the app reads `Locale.current`**: once a user chooses,
the app and the device disagree on purpose, and a source scan in `LocalisationTests` keeps every screen on
this object. Injected once at the root by `hwLanguage(_:)` — not per screen, because Landing and Auth are
not `BaseView` conformances (ADR-0021) and mirror too.
See [ADR-0024](docs/adr/0024-language-plumbing.md).

**the language switch** — `select(_:)`, and it is **optimistic with a revert**: `selected` changes first
so the UI updates with no relaunch and the request *carries* the new language, then `PUT /v1/me/language`,
then the store. Any failure — offline, 5xx, or a server that answers with a different language — **undoes
the change** and rethrows. The alternative is a client and a server that disagree with nothing to notice
it: Arabic screens and English email. Needs a session, because the route does; the picker is on Account,
behind sign-in. **Re-selecting the language already on screen is a no-op only when the store confirms it** —
the store is written after the server agrees, so a device-derived language has never been sent, and the
picker has to be able to send it.

**`LanguageStore`** — the protocol in `Models` behind which the *chosen* language is kept.
`UserDefaultsLanguageStore` in the app, `InMemoryLanguageStore` in tests and previews so neither writes a
preference to the machine it runs on. **Synchronous and `@MainActor`, unlike `TokenStore`**: the manager is
constructed before the first frame, and an `async` read could only be adopted after it — a launch showing
English to an Arabic reader and then swapping under them. An explicit choice outranks the device's
language; a stored tag this build no longer ships reads as no choice at all.

**`LanguageSink`** — the write half of `LanguageSource`, conformed to by `APIClient`. Both are protocols in
`Models` pointing the dependency downwards, and neither is a second seam (ADR-0013). The graph's one
genuine cycle — the client reads the language, the language is recorded through the client — is closed by
`AppEnvironment` with one `connect(to:)` call, and an unconnected manager **throws** rather than switching
the language locally in silence.

**pseudolanguage harness** — the continuous half of ADR-0011, rather than a Phase 5 exercise: the shared
`HisaabWise (Double-Length)` scheme carrying `-NSDoubleLocalizedStrings YES`, a right-to-left preview on
every screen, and the app-wide scans in `LocalisationTests` — no edge pinned left or right, no
direction-encoding image, no Eastern Arabic-Indic digit, no sentence concatenated, no text truncated, every
key a view renders backed by English copy, and the catalogue English-only until the Phase 5 translation
pass.

**a `BaseView` render lands on `.loading`** — worth knowing before writing the snapshot suite (#9). The
chrome supplies `.task { load() }`, `load()` writes `.loading` first, and `ImageRenderer` yields to the main
actor before it captures — so the pixels are the spinner however loaded the view model was a moment
earlier. Assertions about a *loaded* screen's layout therefore go through `StateView`, which has no task; a
whole-screen render is a smoke test.

## Money on the client

**display string** — the pre-formatted, localised, currency-symbol-spaced string the server
returns alongside each `Money`. **The only thing the client renders for a monetary value.**
See [ADR-0003](docs/adr/0003-money-presentation.md).

**client money arithmetic** — forbidden, without exception. The client never converts, never
rounds, never applies symbol spacing, and never sums monetary values. The one carve-out
ADR-0003 allowed was for the pending badge, whose only caller went away with offline writes
([ADR-0019](docs/adr/0019-no-offline-writes-curriculum-pdf.md)).

**Reading a figure the user typed is not that**, and `TypedAmount` is where it lives: it parses one number on its way
*to* the server, before any currency exists to convert it into. Everything that comes *back* is `Money.display`.

## Working without a connection

**no offline writes** — every write needs a connection. There is no queue, no SwiftData, no
pending state, no drain. A write attempted offline fails to `LoadState.offline` and the user
retries. See [ADR-0019](docs/adr/0019-no-offline-writes-curriculum-pdf.md), which supersedes
ADR-0004, ADR-0005, and ADR-0006 in full. **Retired terms:** *pending*, *stale*,
*PendingWrite*, *drain*, *poison message*, *arrival-day attribution*. If you find one in an
older document, it no longer describes this app.

**curriculum PDF** — the curriculum as a **server-generated**, locale-aware PDF that the user
downloads and keeps. This is what "take the learning content away with you" means here; it is
not a client-rendered document, so the layout has one owner and every figure inside it stays
formatted server-side (ADR-0003).

**`MONTH_CLOSED`** — still live. A request in flight across a rollover boundary, or a client
left open past midnight on the 1st, still hits it, and the client still offers re-filing into
the live month (Product Spec §4.5). What went away is the queue-replay machinery around it.

## Session

**TokenStore** — the protocol in `Models` behind which the refresh token lives.
`KeychainTokenStore` when "Keep me signed in" is checked, `InMemoryTokenStore` when it is
not. O3's app lock would be a third conformance, not a refactor. **The access token is not in
it** and has no store to put it in: it is held in memory by the client actor and never
persisted, which two source scans now assert.
Its read is allowed to `throw` for one reason — a Keychain protected by `AfterFirstUnlock`
cannot be read before the first unlock after a reboot, and mistaking that for *empty* would
sign a user out for having restarted their phone.
See [ADR-0007](docs/adr/0007-session-and-refresh.md), [ADR-0023](docs/adr/0023-session-plumbing.md).

**single-flight refresh** — at most one refresh in progress per process. Every caller that
sees a 401 awaits the same `Task`. Not an optimisation: concurrent refreshes present a
revoked token and trigger backend family revocation, logging the user out. Two guards, for
the two ways callers arrive: **overlapping** (a refresh is in flight, so join it) and
**staggered** (it already landed, so the token is replaced and retrying is the whole answer).
Neither is reachable on demand from a test; the assertion is the property true of both —
exactly one refresh at the transport.

**authorization** — `APIClient.Authorization`, a property of the *request*: `.session`
presents the access token and answers a 401 by refreshing and retrying **once**, `.anonymous`
presents nothing. Two cases rather than a `/v1/auth/` prefix rule, which would be wrong on its
first exception — `POST /v1/auth/logout` is an auth route that needs the session. `.session`
is the default, because the mistake a default has to make impossible is forgetting to
authenticate a per-user route.

**presented** — what a request carries: the access token **exactly as issued**, signature and
unread claims included. The `sec` claim rides along there, so a re-encoding of the claims the
client happens to read would drop it. A 401 refreshes even when the clock says the token is
fresh, which is what makes a `securityEpoch` bump a prompt sign-out rather than fifteen
minutes of failures.

**hard logout** — the session ending because the **server** refused it: a definitive 401 on
refresh, or a 401 with nothing left to refresh with. The store is cleared and
`APIClient.sessionEnded` yields. A local sign-out does **not** yield — the caller already
knows. A transport failure, a 5xx, and an unreadable store all **keep** the session; the first
and last are `offline`.

**`SessionCoordinator`** — who is signed in, at the app root beside `AppEnvironment` and
`AppConfig` rather than in a layer: it owns no screen, so it is not a view model.
`restore()` · `signIn(email:password:keepMeSignedIn:)` · `signOut()` · `onForeground()`.
**It maps no `APIError`** — that has one owner and this is not it, so what it takes from a
failed request is `client.hasSession`, not an error code. `onForeground()` is a directly
awaitable method, not a `scenePhase` observer, so ADR-0008's ordering — refresh-if-near-expiry
**then** `GET /v1/me` — is something a test asserts. **The composition root observes `scenePhase` and calls
it, and keeps doing so**: issue #5 was expected to take that over and deliberately did not, because a
`RootView` that read the phase would be a `RootView` whose session branch no test could set (ADR-0026). It is
injected into the environment now, where `RootView` branches on it and `LogoutControl` ends it.
See [ADR-0023](docs/adr/0023-session-plumbing.md), [ADR-0026](docs/adr/0026-shell-plumbing.md).

## Content

**content store** — the explicit on-disk JSON store for curriculum, picklists, categories, and
the reference lists, with a persisted ETag per resource. Distinct from `URLCache`, which carries
only tips and articles. It exists for latency and data use; it is **not** what makes the app
usable without a connection — the curriculum PDF is
([ADR-0019](docs/adr/0019-no-offline-writes-curriculum-pdf.md)).
See [ADR-0009](docs/adr/0009-content-cache.md).

**The curriculum is its largest resource, and it is not under `/v1/content`.** Invariant 8 names *three* cacheable
families — `/v1/content/*`, `/v1/curriculum*`, and `/v1/fx/rates` — so `GET /v1/curriculum` is the second of them
rather than an exception to the first; it sits on its own root because the curriculum is the product, and the PDF
(#25) hangs off the same path. `ContentLoaderTests` checks the invariant's own list now, and the converse too: no
per-user route may sit inside a cacheable family.

**What a cold launch with no network gets is the curriculum and not the screen**, which is ADR-0019 rather than a
shortfall in the store. Content is the same for everybody and was already downloaded; progress is per-user and there
is no offline read of it. So Learn is `LoadState.offline` on a second launch with the aeroplane on — and the ~100 KB
does not have to come down again when it comes back.

**screen payload** — what one `GET /v1/screens/*` returns: everything that screen draws, fully computed
(ADR-0020). **Five exist**: Home, Expenses, Learn, Reports, and one closed month — Learn being the one that is
*half* of a screen, because the other half is cacheable content on its own ETag (see **Learn** above), and the month
being the only one addressed by an **identity** rather than by a name (`/v1/screens/reports/:monthKey`). Reports'
field names are a list of things the design's browser worked out about *history*: `Year.totalSaved` for a
filter-and-reduce per header, `Summary.averageSpend` for a mean of six totals, `Bar.fill` and `Trend.goalPosition`
for one shared scale, and `percentageLabel` plus `verdict` for a division followed by a threshold (defect D11). The
month's are the same list one level down, plus the four `Split.Segment`s §4.2 **[FIX]** settles and the
`Totals.isAdapted` flag that chooses between two sentences about the budget rule — and its figures are a **pinned
snapshot's** own strings, so a currency change is a re-read rather than a conversion (invariant 7). Expenses is where the design's own JavaScript did the arithmetic, so
its field names are a list of calculations that *moved* — `Category.total` for `catTotal(id)`, `wants.allowance` for a
50/30/20 engine re-implemented in the browser (invariant 3 violated in the source material), `Entry.dateLabel` for a
`whenLabel()` that read the device clock (invariant 6), and `entryCountLabel` for a pluralised count. Its payload
carries **no timestamp at all**, which is the stronger form of the date fix: the client could not derive a label if
it wanted to. Home is the first one, and its field names are the list of things the client may not work out —
`shareOfPayLabel`, `percentageLabel`, `dateLabel`, `verdict`. **The budget engine has not moved**: invariant 3
still keeps 50/30/20, `saved`, and the verdict in one place, and `GET /v1/budget` is still its own endpoint; the
screen payload is assembled from it server-side, which the corpus asserts by making `home-inr.json`'s `saved`
byte-identical to `budget-inr.json`'s. Two `Double`s in the payload are **geometry** — a slice's fraction and the
meter pin's position — and are named as the exemptions to the `Double` ban rather than quietly allowed.
See [ADR-0032](docs/adr/0032-home.md).

**an accent's `base` and `deep` are fill colours, not ink** — the finding Learn's five unit bands produced, and the
one thing about them still unresolved. The design uses them as ink in five places and each measured under the 4.5:1
(or 3:1 for a glyph) the rest of this palette is asserted at; four were fixed by taking the ink from a role that
works on all five washes, and the fifth cannot be. White text on the band passes on `sky` and `violet`; galaxy passes
on `sun`, `mint`, and `coral`; **no single token passes on all five**. What that needs is a fourth slot on
`HWPalette.UnitAccent` — a per-accent `ink`, asserted by `ColorAssetTests` the way the six category slots are — which
is a palette change to make on its own. The numbers are in [ADR-0034](docs/adr/0034-learn-unit-map.md).

**Swift Charts does not carry the app's environment objects into axis content** — an `AxisValueLabel` that reads
`ThemeManager` traps inside a chart that was itself rendered inside one, which `ReportsViewTests` found by
photographing the page. `HWTrendChart` reads the manager in its `body` and re-injects it around the label, which
keeps `hwEyebrow(_:)` the one owner of that style. Worth knowing before the next chart: the same trap waits in any
`.chart*Axis` content using a design-system modifier. **And an unused `@Environment` of a non-optional observable
object is not free** — `ReportsArchivePage` declared one it never read and trapped for it.

**a mark the framework knows, drawn by the framework; a shape the design invented, drawn by hand** — why the
donut is Swift Charts and the savings meter is not, from one ADR. The trend chart is the third case and it lands on
the framework's side without argument: a bar chart with a threshold line is two marks Swift Charts has. `SectorMark` publishes a per-mark accessibility
descriptor per slice; a gradient track with a sliding pin and a floating pill is not a mark, and expressing it as
one fights the framework for a shape it does not have. Both are **replaced** above the accessibility threshold by
the same figures as rows, and the replacement doubles as the chart's `accessibilityRepresentation`.
See [ADR-0032](docs/adr/0032-home.md), [ADR-0016](docs/adr/0016-presentation-details.md).

**`HWMarkdown`** — server content's emphasis. The design writes `<b>`/`<i>` inline in tips and article bodies;
the extraction converts it to markdown and this renders it through `AttributedString`. Markdown is free for *app
copy* (a `LocalizedStringKey` is parsed as markdown) and not for server content, which goes through
`Text(verbatim:)` — so the parse is explicit. Stripping the emphasis was the alternative and it loses the point of
the sentence.
See [ADR-0032](docs/adr/0032-home.md).

**`ContentLoader`** — the content store joined up: read the stored bytes, revalidate with `If-None-Match`,
download only what changed. Two rules it is easy to get wrong and one that reads as an exception. **The bytes are
stored, not the decoded values** — a store holding models stores this client's idea of the payload, and the next
revalidation asks the server about a document that never existed. **An ETag is only ever sent alongside the bytes
it describes** — `Caches` is evictable and nothing promises a resource's two files are removed as a pair, so an
orphaned ETag earns a truthful `304` for bytes the client no longer has. And **a read may be served offline
while a write may not**, which is the other side of ADR-0019 rather than an exception to it: content is the same
for everybody and was already downloaded.
See [ADR-0031](docs/adr/0031-registration.md), [ADR-0009](docs/adr/0009-content-cache.md).

**`{c}`** — the currency token left verbatim in tip text. Substituted client-side from
server-supplied currency metadata. Amounts printed next to it are **illustrative and never
converted**.
See [ADR-0016](docs/adr/0016-presentation-details.md).

## Presentation

**surface vs brand** — the two appearances the design ships **at the same time**: `surface` is the
light, off-white ground of the five in-app screens; `brand` is the galaxy ground of Landing and
Auth. Not a light and a dark mode — `--danger` has a different value on each, and both ship. The
asset catalogue therefore has exactly one appearance per colour set.
See [ADR-0021](docs/adr/0021-two-surfaces-and-token-collapse.md).

**token** — one entry in the design system: a semantic colour, a ``HWTextStyle`` step, an
``HWCurve``, an ``HWDuration``, an ``HWRadius``, an ``HWShadow``. Every one is transcribed from the
design's CSS custom properties and, for colours, asserted against them. The design's thirty-plus
font sizes and dozen radii are **collapsed** into steps on the way in; a screen picking 320ms over
300ms is noise, and removing that noise is what a design system is for.


**LoadState** — the enum every screen's data goes through: `loaded`, plus the four states in which
there is nothing to draw — loading, empty, offline, failed. `offline` is never rendered as `failed`.
It is written in exactly one place, `BaseViewModel.load()`, and switched on in exactly one place,
`StateView` — both asserted by `StateTaxonomyTests`.

**StateView** — the one view in `DesignSystem/` covering the four empty-handed states, and the
passthrough for `loaded`. It takes a **`StateCopy`** from the screen: only `empty` has no shared
default, because an empty expense list and an empty reports archive are different sentences while
twenty rewordings of "you're offline" are not. `offline` and `failed` are **visually distinct** — a
different symbol and a different tint, not merely different words.

**`StatePresentation`** — the symbol, tint, sentence, and CTA for one empty-handed state, as a
value rather than as view code. It exists so that "offline is not styled as failed" is something a
test asserts rather than something a reviewer eyeballs.

**ErrorCopy** — the **one** table turning a server `ErrorCode` into localised copy. An unrecognised
code yields generic copy; the server's `message` is never displayed, and is never decoded either
(ADR-0016). A code with a flow of its own rather than a sentence — `ACCOUNT_PENDING_DELETION` gets
the restore screen — is deliberately absent.

**privacy overlay** — `PrivacyOverlay`, the `HWMark`-on-`galaxy` view covering **every scene phase but
`.active`** so the app-switcher snapshot carries no financial figures. Applied at the composition root over both
worlds, Landing included — a rule with an exception in it is a rule somebody has to remember. Not app lock:
returning requires no authentication, and a scan asserts the file reaches for no field, no biometry, and no tap
target. **It does not animate**, and that is the one place ADR-0012's replace-not-remove does not apply: iOS
takes the snapshot at `.inactive`, so a cross-fade would put half a screen of figures in the picture the system
keeps.
See [ADR-0014](docs/adr/0014-privacy-surfaces.md), [ADR-0026](docs/adr/0026-shell-plumbing.md).

**fixture corpus** — the JSON files in `Fixtures/Resources`, read by both the decoding tests and the
SwiftUI previews, so a fixture that drifts from the API breaks a test rather than rotting a preview. **Canned
HTTP payloads, never pre-built domain objects**: a preview goes through the same decoding the app does.

Each fixture declares the paths it answers (`Fixture.endpoints`), and `FixtureCorpusTests` reads every `/v1`
literal out of `Endpoint.swift` and requires each to be claimed — **coverage is derived from the source, not
from a list**, so the first commit that adds one of ADR-0020's screen endpoints is told to bring a payload.
The converse holds too: a fixture may not answer a path nothing calls, which is what keeps a guessed contract
out of the corpus. `FixtureTransport.serving([.budgetINR, .meVerified])` is how a test or a preview asks for
payloads by name.

**The Expenses payloads are load-bearing in the same way.** `expenses-inr.json` is the *same month* as
`home-inr.json`, down to the display string, and the corpus asserts they agree per category — Home's donut and
Expenses' summary read one budget engine (invariant 3), so a difference is one of the two assemblies having summed
something. One payload also claims **four paths**, which is ADR-0020's write rule as a fixture: the read and all
three writes answer with the same screen.

**The Reports payloads carry the two things one payload could not.** `reports-inr.json` keeps the design's own six
closed months and its *percentages* — one of each verdict, two met in six, as §3.6 counts them — re-denominated in
rupees, with the goal left at ₹13,000 across a salary rise, which is §4.2's rule that a raise does not move the
target. `reports-two-years.json` spans a year boundary, because one year group proves that a header renders and
nothing at all about the grouping. And `reports-empty.json` is what makes `SnapshotCase.empty` a real screen's empty
state: this is the first `LoadState.empty` the app can reach — Expenses' first run keeps all seven categories and is
`.loaded`, Home's keeps four of its five cards.

**And the three month payloads carry a pair, which is the point of them.** `reports-month-inr.json` is the archive's
own February in full — the corpus asserts that the row, the trend bar, and the detail agree about the spend, the
verdict, and the percentage, which is the Home/Expenses anchor one level down. `reports-month-aed.json` is the *same*
month through the rates pinned at close, so every monetary string differs and nothing that carries the story does:
that pair is invariant 7 as two files, and both were generated from one table of authored rupee figures so they
cannot drift apart by hand. `reports-month-quiet.json` is a closed month with nothing logged — no slices, seven empty
panels, and a split bar that is mostly surplus — and it is a month **no archive in the corpus lists**, because none of
the three archives has an empty month in it.

**Two entries are load-bearing beyond their shape.** `budget-aed.json` carries `AED 8,000` — defect D1's own
figure — while the rupee one stays the default preview, so a screen that has gone back to hardcoding looks
right against exactly one fixture and wrong against the standing one. `budget-drifted.json` has a **blank**
display string, which is the drift `Money`'s own guard refuses (a missing key would fail through `Decodable`
and prove nothing), and it is followed to a screen: `HomeViewModel` over it lands on `failed`.

**One exception to "the corpus is the only source":** the access token. A canned JWT cannot carry a moving
expiry, so `session-tokens.json` is dated 2100 for the shape, and the session suites mint tokens against a
live clock.
See [ADR-0013](docs/adr/0013-testing-and-previews.md),
[ADR-0027](docs/adr/0027-corpus-coverage-and-the-pinned-harness.md).

**the pipeline** — `.github/workflows/ios.yml`, one job: `xcodebuild test` on the `release` and `main`
branches only (Rule 2 — `feature/mvp` stays pipeline-free, asserted). **Three pins**: the runner image
(`macos-26`), the Xcode version (26.6, selected explicitly because the image ships seven and its default moves
when rebuilt), and the destination — which `CIWorkflowTests` asserts equals `SnapshotPin`'s device and runtime.

**A pass has to mean the snapshot cases ran.** `.github/scripts/test-summary.py` reads the `.xcresult`, writes
totals, failing test names, and skipped suites to the step summary, and **fails the job if the snapshot suite
was skipped or absent** — `SnapshotPin` skips it off its pinned pair, and a skip is silent. Two suites may
skip and are listed as context: the live-Worker one (needs `wrangler dev`) and the Keychain one (needs a
writable Keychain).

**Build settings are asserted twice.** `BuildConfigurationTests` reads what `project.pbxproj` *says*;
`.github/scripts/assert-build-settings.py` checks what the build *resolves* — iOS 18.0, Swift 6, iPhone-only,
portrait-only. An `.xcconfig` or an override sits between the two, and a disagreement is the bug.

**No signing material** anywhere: tests run unsigned on a simulator with `CODE_SIGNING_ALLOWED=NO`, and scans
cover both the workflow's words and the repository's file extensions (Rule 3). **The workflow is tested rather
than run** — its first execution is on a real PR into `release`, so its decisions are read out of the YAML.
See [ADR-0028](docs/adr/0028-ci-pins-and-the-skip-gate.md).

**the pinned snapshot harness** — `SnapshotCase` (exactly four: populated · empty · RTL · AX3) and
`SnapshotPin` (iPhone 17 on iOS 26.5, major and minor only). The suite **skips** rather than fails on any
other host, because baselines are a function of device and runtime and a flaky gate gets deleted rather than
fixed; CI (#10) pins the destination so it runs there.

**`swift-snapshot-testing` is not in the project yet, and cannot be added from the CLI.** Every
package-reference class makes this Xcode refuse to open `project.pbxproj`
(`-[XCRemoteSwiftPackageReference _setOwner:]: unrecognized selector`), at every `objectVersion`. It is a GUI
step: File ▸ Add Package Dependencies… → `swift-snapshot-testing` → Up to Next Major 1.19.4 → the
**`HisaabWiseTests` target only** (linked into the app it would reach `PrivacyInfo.xcprivacy` and App Review).
Until then the harness renders each case as a smoke check, and a test asserts the app target links no package
products at all. Three of the four cases also need a **hosted** capture to be photographed loaded, since
`ImageRenderer` captures the spinner (see the `BaseView` note above).

---

**every argument copy takes is a `String`** — so a localisation key's lookup form is derivable from the source
that writes it. `Text("key \(value)")` looks up `key %@`, not `key`, and a catalogue holding only the bare key
resolves nothing and renders the key itself — which is what Home's income figure was announcing to VoiceOver, in
a green suite, from #12 until #15. `LocalisationTests` derives the key **with** its specifiers, by
reconstructing the literal rather than counting arguments — so `key %@ of %@` derives correctly too. A `\(count)`
would resolve to `%lld`, which the scan **cannot** know from the text: the `String` rule is therefore a
convention the scan relies on and does not enforce, and a number is converted where it is *computed* rather than
where it is drawn.
See [ADR-0031](docs/adr/0031-registration.md).

**a style that paints inside itself cannot be overridden from outside** — `HWLabelStyle` and `HWEyebrowStyle`
apply `.foregroundStyle` in `body(content:)`, and an outer `.foregroundStyle` at the call site loses to an inner
one. Four field components on the galaxy ground each wrote that override and each drew the light surface's ink
anyway. Both roles take an `HWAppearance` instead. The general rule: a design-system modifier that resolves a
colour has to be *parameterised*, because a caller cannot correct it.
See [ADR-0031](docs/adr/0031-registration.md).

## Changes these decisions require outside this repo

Recorded here because they are commitments, not suggestions. None has been made yet.

| Source | Change |
|---|---|
| [ADR-0003](docs/adr/0003-money-presentation.md) | Technical Spec §5 — state the currency of `GET /v1/budget`'s figures; every monetary field gains a server-formatted display string honouring `Accept-Language` |
| [ADR-0003](docs/adr/0003-money-presentation.md) | Technical Spec §1 — drop FX from the iOS content cache; `GET /v1/expenses` returns per-category totals |
| [ADR-0011](docs/adr/0011-localisation.md) | The server's `Accept-Language`-driven money formatting must use **Latin digits** (`latn`) under `ar`. The client sends the bare tag `ar` and has no formatter to correct a figure that comes back in Arabic-Indic digits (ADR-0003, [ADR-0022](docs/adr/0022-production-transport.md)) |
| [ADR-0020](docs/adr/0020-screen-scoped-endpoints.md) | **Six new endpoints** — `GET /v1/screens/{home,expenses,learn,reports,account}` and `/v1/screens/reports/:monthKey`, each returning exactly what the screen renders, fully formatted. Every derived value included: "% of pay", the meter percentage, "Today / Yesterday / N days ago", per-category totals, Learn accuracy and progress fractions, the goal verdict, per-year totals |
| [ADR-0020](docs/adr/0020-screen-scoped-endpoints.md) | Writes — `POST /v1/expenses`, `DELETE /v1/expenses/:id`, `POST /v1/learn/lessons/:id/complete`, `PUT /v1/me/*` — **return the updated screen payload**, so the client never patches its own copy |
| [ADR-0019](docs/adr/0019-no-offline-writes-curriculum-pdf.md) | **New endpoint** — the curriculum as a **server-generated PDF**, honouring `Accept-Language`, cacheable (not per-user) with an ETag. The iOS download ticket is blocked on it and is built against a fixture PDF until it lands |
| ~~[ADR-0005](docs/adr/0005-write-queue.md)~~ | ~~`DELETE /v1/expenses/:id` must be explicitly idempotent~~ — **downgraded to optional** by [ADR-0019](docs/adr/0019-no-offline-writes-curriculum-pdf.md): with no retries, an already-deleted id can never be re-sent. Still good hygiene |
| [ADR-0010](docs/adr/0010-configuration-and-auth-links.md) | `POST /v1/auth/reset-password` must be callable from a web form, not only from the app |
| [ADR-0015](docs/adr/0015-deletion-and-demo-account.md) | Technical Spec §5 — sign-in during the grace period returns `ACCOUNT_PENDING_DELETION` with the erase date; add `POST /v1/auth/restore` |
| [ADR-0030](docs/adr/0030-sign-in.md) | **The client cannot yet read that erase date.** It decodes `{error:{code}}` and nothing else (ADR-0016), so showing it needs one decoded field — and a general `details` bag is how "the client never reads the server's prose" erodes. Sign-in handles the code distinctly and offers the restore path; the date lands with #24, which owns the grace period |
| [ADR-0019](docs/adr/0019-no-offline-writes-curriculum-pdf.md) | Product Spec §6 — answer keys no longer ship "to enable offline lessons"; they ship because grading is client-side for responsiveness and the server recomputes (invariant 10) |
| [ADR-0016](docs/adr/0016-presentation-details.md) | Product Spec §6 — amounts inside tips are illustrative and are never converted |
| [ADR-0001](docs/adr/0001-platform-baseline.md) | Product Spec §5.2 — record iPhone-only, portrait-only |
| [ADR-0011](docs/adr/0011-localisation.md) | `DEVELOPMENT_PLAN.md` §5 — string externalisation moves from Phase 5 to Phase 1 (translation stays in Phase 5) |
| [ADR-0007](docs/adr/0007-session-and-refresh.md) | Technical Spec §9 — add a concurrency case: several in-flight requests across an access-token expiry must not log the user out |
| [ADR-0023](docs/adr/0023-session-plumbing.md) | **The auth wire contract**, written by the client because the backend has no `/v1/auth/*` routes yet: `POST /v1/auth/login {email, password, timeZone}` and `POST /v1/auth/refresh {refreshToken, timeZone}` both answer `{accessToken, refreshToken}` — a refresh returns a **new refresh token**, not only an access token; `POST /v1/auth/logout {refreshToken}` is **authenticated** |
| [ADR-0023](docs/adr/0023-session-plumbing.md) | `timeZone` (IANA) on **login and refresh**. Invariant 6 captures the user's stored timezone "at login and refresh", and those two requests are the only places it can happen — without the field it never happens after registration |
| [ADR-0023](docs/adr/0023-session-plumbing.md) | The access token is a **JWT carrying `exp` and `sec`**. The client reads `exp` from the payload rather than from a sibling `expiresIn`, so there is no second copy of the token's lifetime to fall out of step |
| [ADR-0023](docs/adr/0023-session-plumbing.md) | **New endpoint** — `GET /v1/me` returning `{email, displayName, emailVerified}`. Identity only: figures reach a screen through that screen's endpoint (ADR-0020), and a second copy here is one a stale revalidation could disagree with |
| [ADR-0024](docs/adr/0024-language-plumbing.md) | **New endpoint** — `PUT /v1/me/language {language}`, **authenticated**, answering with the updated language (inside the Account screen payload under ADR-0020; the client decodes only the one field). Its reason for existing is **email**: `Accept-Language` tells the server what to format *this* response in and nothing about a reminder composed six hours later, so the preference has to be stored. The client treats a stored language other than the one it asked for as a failed switch |
| [ADR-0024](docs/adr/0024-language-plumbing.md) | The stored preference is what every server-composed message honours — password reset, streak reminder, the curriculum PDF (ADR-0019) — not the header of whichever request happened to be last |
| [ADR-0024](docs/adr/0024-language-plumbing.md) | **`language` on login and refresh**, for the reason ADR-0023 put `timeZone` there: those two requests are the only places the device's language can reach the server without a user action. Without it, an Arabic phone whose account was registered in English gets an Arabic app and English email until somebody opens the picker |
| [ADR-0031](docs/adr/0031-registration.md) | **The registration wire contract**, written by the client because the backend has no `/v1/auth/*` routes yet: `POST /v1/auth/register` takes `{name, email, dateOfBirth, phone?, password, displayCurrency, salary, savingsGoal, goalWasSkipped, securityAnswers, acceptedTerms, timeZone, language}` and answers with the **same token pair a login does** — a new account is signed in. `salary` and `savingsGoal` are `{minor, currency}`; `phone` is `{country, dialCode, national, e164}` and is **absent** rather than empty when not given |
| [ADR-0031](docs/adr/0031-registration.md) | **A distinct error code for the email collision** — `EMAIL_TAKEN`. It is the one per-field failure registration can receive, and the only way the client learns an address is registered. There must be **no** email-availability route: it would be an account-enumeration oracle |
| [ADR-0031](docs/adr/0031-registration.md) | **Three new content endpoints**, cacheable with an ETag and **anonymous** (registration needs them before a session exists): `GET /v1/content/reference/countries` → `{countries: [{code, dialCode, name}]}` ×251, `GET /v1/content/reference/currencies` → `{currencies: [{code, name, symbol}]}` ×160, `GET /v1/content/security-questions` → `{questions: [{id, text}]}` ×14. Envelopes rather than bare arrays, so a list that later needs a version or a count is not a breaking change on the day it needs one |
| [ADR-0031](docs/adr/0031-registration.md) | **Question ids** — `sq01`…`sq14`, invented by the client because the design carries only the English text. §4.3 **[FIX]** makes the id the identity, and the answer hash is keyed to it, so the ids have to be agreed before any account exists |
| [ADR-0031](docs/adr/0031-registration.md) | **The currency reference list needs an `exponent`.** It carries a code, a name, and a symbol, so the client reads minor units as two decimal digits — right for 157 of the 160 currencies and wrong for KWD, BHD, and OMR. A dinar typed `1.234` arrives as `123` minor units instead of `1234` |
| [ADR-0031](docs/adr/0031-registration.md) | **A verification email is sent on registration**, composed in the submitted `language` (ADR-0024). The client shows a strip above the tabs while `GET /v1/me` reports `emailVerified: false`, and ADR-0008's foreground revalidation is what clears it. A "resend" route belongs to Account (#17) |
| [ADR-0031](docs/adr/0031-registration.md) | **Two hosted pages, per environment** — Terms of Use and the Privacy Policy, `https` only, read from `HW_TERMS_URL` and `HW_PRIVACY_URL`. The consent checkbox links to them, and a staging build must be able to link to staging's copies so a change to the Terms can be reviewed before it is what a new user agrees to (Rule 7 — the domain is a placeholder until the Cloudflare credentials arrive) |
| [ADR-0032](docs/adr/0032-home.md) | **`GET /v1/screens/home`'s payload**, written by the client: `{greeting, name, dateLabel, monthLabel, spending{total, shareOfPayLabel, isFirstRun, categories[{id, name, amount, share, shareLabel, slot}]}, savings{saved, goal, zeroLabel, percentageLabel, position, verdict, remaining?}, tip{id, dayKey, text, currencyToken}, learning{streak, summary, nextLesson}, articles[{id, short, icon, accent}]}`. `share` and `position` are fractions `0…1` — geometry the server computes so the angles and the percentages cannot round differently. `verdict` is `low`/`onTrack`/`met` |
| [ADR-0032](docs/adr/0032-home.md) | **`saved` in the screen payload must be the engine's own figure**, not a re-derivation. The corpus asserts the two agree, and a difference is the assembly having calculated — which is the class of mistake defect D1 was |
| [ADR-0032](docs/adr/0032-home.md) | **`isFirstRun` is the server's to say.** "No categories" and "a new account" are the same empty array and different screens; only the server knows which, and the client must not infer it from `categories.isEmpty` |
| [ADR-0032](docs/adr/0032-home.md) | **The greeting and both date labels are server-side**, against the stored timezone (invariant 6). The prototype read `new Date().getHours()`, which a device-clock change moves |
| [ADR-0032](docs/adr/0032-home.md) | **New endpoint** — `GET /v1/content/tips` → `{tips: [{id, text}]}` ×**49**, cacheable and ETag'd, `{c}` verbatim, emphasis as **markdown** rather than HTML. This is what **Show me another** cycles in memory; the *day's* tip stays inside the screen payload, chosen by `dayKey` |
| [ADR-0032](docs/adr/0032-home.md) | **New endpoint** — `GET /v1/content/articles/:id` → `{id, title, lede, sections[{heading, paragraphs?, entries?, steps?, callout?}], sources[{title, url}]}`, cacheable and ETag'd, with **3** articles. Every block optional; the order is fixed. Sources are **official only** — this is education, not regulated advice |
| [ADR-0032](docs/adr/0032-home.md) | **Emphasis in all editorial content is markdown**, not HTML, from the extraction onwards — tips, article paragraphs, steps, and list entries. HTML cannot reach a SwiftUI `Text` |
| [ADR-0032](docs/adr/0032-home.md) | **`icon` and `accent` are a name and a slot**, not a path and a hex: `shield`/`globe`/`steps`/`lightbulb`/`alert`, and `1…5` for the tint. A colour reaching a use site by name is what keeps the later dark-mode swap a swap (ADR-0001) |
| [ADR-0033](docs/adr/0033-expenses.md) | **`GET /v1/screens/expenses`'s payload**, written by the client: `{monthLabel, summary{total, fixed, variable, income}, wants{used, allowance, percentageLabel, fill, isOver}, entry{code, symbol, displayCode, exponent}, categories[{id, name, hint, total, entryCountLabel?, kind, flow, icon, field?, entries[{id, label, amount, dateLabel}], lines[{id, name, amount, icon}]}]}`. `kind` is `log`/`lines`/`fixed`; `flow` is `out`/`in`; `field` is `place`/`source`/`transportMode`/`otherType`. `fill` is a fraction `0…1`, already clamped — geometry, so the bar's width and the percentage cannot round differently |
| [ADR-0033](docs/adr/0033-expenses.md) | **Everything the design computed in the browser moves server-side**: each category's running total, the Fixed/Variable/Income split, the wants allowance (the adaptive 50/30/20 engine — it exists **twice** in the prototype, which is invariant 3 violated in the source material), the `isOver` verdict, and the pluralised `entryCountLabel` |
| [ADR-0033](docs/adr/0033-expenses.md) | **`Entry.dateLabel` is a string and there is no timestamp in the payload** — "Today" / "Yesterday" / "N days ago" / "3 Aug", computed against the server's day boundary in the user's stored timezone (invariant 6). The prototype's `whenLabel()` read `new Date()`, so a device-clock change re-labelled history. Omitting the timestamp is deliberate: the client cannot derive the label because it has nothing to derive it from |
| [ADR-0033](docs/adr/0033-expenses.md) | **An incoming category's display string is signed by the server** — `+₹900`. A sign is formatting (ADR-0003), and the prototype's client-side `(c.income ? '+' : '')` puts it on the wrong side of an Arabic figure |
| [ADR-0033](docs/adr/0033-expenses.md) | **`kind` must never carry a value the client has not agreed to.** It decides which write the detail page offers, so the client fails the screen rather than guessing — unlike `icon` and `field`, which degrade. A new kind is a coordinated release |
| [ADR-0033](docs/adr/0033-expenses.md) | **`entry` says what the user is authoring in** — code, symbol, ISO code, and **exponent**. Money is stored exactly as authored with no storage base (§4.1 **[FIX]**), so this is the currency the client sends alongside the minor units; the exponent is what stops a dinar typed `1.234` arriving as 123 |
| [ADR-0033](docs/adr/0033-expenses.md) | **Four write routes**, each answering with the updated screen payload: `POST /v1/expenses {categoryId, amount{minor,currency}, optionId?, label?}`, `DELETE /v1/expenses/:id`, `PUT /v1/expenses/fixed/{categoryId} {amount}`, and `PUT /v1/expenses/lines/{categoryId} {lines:[{id?, name, amount}]}` |
| [ADR-0033](docs/adr/0033-expenses.md) | **The bills write replaces the whole set**, because that is the gesture the design has: a line with an `id` existed, one without is new, and anything not sent is gone. Four requests for one "Update bills" press would be four chances to fail halfway and four payloads of which only the last is true |
| [ADR-0033](docs/adr/0033-expenses.md) | **`POST /v1/expenses` must honour a caller-supplied `Idempotency-Key` across retries.** The client mints one key per user intent and re-sends it, so a write that reached the server and lost its response must be recognised rather than filed twice |
| [ADR-0033](docs/adr/0033-expenses.md) | **`optionId`, not the option's name.** The server resolves a pick-list id into a name in whichever language the reader asks for, so the entry an Arabic user files reads in Arabic and the same entry reads in English for an English one. Sending the displayed string would freeze one language into stored data |
| [ADR-0033](docs/adr/0033-expenses.md) | **`MONTH_CLOSED` must be answerable by a plain re-send.** The client reloads (to learn the live month's name), offers, and sends the *same* body again with a new key; the server derives `monthKey` at write time and the live month only moves forward (§4.5). No client-supplied month, and archives stay immutable |
| [ADR-0033](docs/adr/0033-expenses.md) | **New endpoint** — `GET /v1/content/picklists` → `{transport:[{id, name}] ×22, other:[{id, name, opensFreeText?}] ×20}`, cacheable and ETag'd. **The option that asks the user what it actually was is flagged, not matched by name**: the prototype tests `/something else/i` against English text, which stops working the moment the list is translated |
| [ADR-0033](docs/adr/0033-expenses.md) | **The currency reference list's missing `exponent`** (already recorded for ADR-0031) is now load-bearing in a second place: the screen payload carries one for the *display* currency, and registration still has none |
| [ADR-0034](docs/adr/0034-learn-unit-map.md) | **`GET /v1/screens/learn`'s payload**, written by the client: `{streak{value,display,accessibilityLabel}, xp{…}, nextLesson?{unitId, lessonId, title}, units[{id, isUnlocked}], lessons[{id, state, segments, filledSegments, progressLabel}]}`. `state` is `completed`/`available`/`locked`. **No date, timestamp, or day key anywhere in it** — invariant 6, in the stronger form `ExpensesScreen` uses for its entry labels: the client cannot re-derive the streak because it has nothing to derive it from |
| [ADR-0034](docs/adr/0034-learn-unit-map.md) | **Everything the design computed in the browser moves server-side**: `isOpen(id)` walking the flattened lesson list, `firstOpen()` scanning for the cursor, `unitOpen` reducing over a unit's lessons, and `qCount(l)` counting a lesson's question steps. The client renders the lock; **the server enforces it**, and `POST /v1/learn/lessons/:id/complete` (#20) must refuse a lesson whose predecessor is unfinished |
| [ADR-0034](docs/adr/0034-learn-unit-map.md) | **`nextLesson` is absent, not null-ish, when every lesson is finished.** A cursor pointing at a sixteenth lesson is the state a screen assuming one draws wrongly |
| [ADR-0034](docs/adr/0034-learn-unit-map.md) | **`segments` and `filledSegments` are the ring's geometry and must agree with the curriculum.** `segments` is the lesson's question count and `filledSegments` never exceeds it; a completed lesson's ring is **full** and a locked one is empty, so the tick and the ring cannot disagree |
| [ADR-0034](docs/adr/0034-learn-unit-map.md) | **`streak` and `xp` are `{value, display, accessibilityLabel}`** — `Money`'s shape for a figure that is not money. `display` because the client has no thousands separator (ADR-0003); `accessibilityLabel` because a count with a plural in it has six forms in Arabic (ADR-0011); `value` because nothing draws it and the corpus asserts numeric agreement with Home's `learning.streak` |
| [ADR-0034](docs/adr/0034-learn-unit-map.md) | **Home's `learning.nextLesson` must name a lesson the curriculum has.** It is a *title* rather than an id, so nothing about a wrong one would ever fail — `home-first-run.json` named "Money, plainly", which no unit carries. Better still would be Home carrying the id too |
| [ADR-0034](docs/adr/0034-learn-unit-map.md) | **New endpoint** — `GET /v1/curriculum` → `{units:[{id, number, accent, title, subtitle, blurb, lessons:[{id, icon, title, blurb, steps:[…]}]}]}`, cacheable and ETag'd, **anonymous-safe** and per-locale. **5** units / **15** lessons / **124** steps (58 teach + 66 question; 50 single-choice + 14 numeric + 2 multi-select), asserted **exactly**. `accent` is one of `sun`/`mint`/`coral`/`sky`/`violet`; `icon` is one of fifteen names plus a `book` fallback |
| [ADR-0034](docs/adr/0034-learn-unit-map.md) | **One `kind` per step, not two discriminators.** The design carries `t: "teach"｜"q"` and then `kind` on the questions, whose invalid combinations are representable. The wire form is one closed vocabulary: `teach` / `singleChoice` / `multiSelect` / `numeric` |
| [ADR-0034](docs/adr/0034-learn-unit-map.md) | **Answer keys ship** (invariant 10), on the responsiveness argument alone — grading is client-side and the server recomputes XP from submitted per-question results. `answers` is an **array of option indices** for both choice kinds, single-choice carrying one; `answer` on a numeric step is a **whole number**, and the grading tolerance is a strict `< 0.5` |
| [ADR-0034](docs/adr/0034-learn-unit-map.md) | **Editorial emphasis in the curriculum is markdown**, `{c}` verbatim, and the design's `?demo` block is never extracted. `<br><br>` inside a worked example becomes a blank line in one string, because the breaks are inside a single calculation rather than between paragraphs |
| [ADR-0034](docs/adr/0034-learn-unit-map.md) | **`/v1/curriculum` is cacheable and is deliberately not under `/v1/content`** — invariant 8's second family. The PDF (#25) and any per-unit or per-locale variant hang off the same root, and burying them under `content` would make `/v1/content/curriculum/pdf` the address of the app's headline feature |
| [ADR-0035](docs/adr/0035-lesson-player.md) | **New endpoint** — `POST /v1/learn/lessons/{id}/complete`, taking `{results:[{stepIndex, isCorrect}]}` and **nothing else**: no XP, no accuracy, no hearts, each of which is derivable from the results and none of which the server should have to trust. It answers with the **completion payload** (below). It must **refuse** an impossible submission with a `422` — a result naming a step that is not a question, a question answered twice, more wrong answers than there are hearts, or a lesson whose predecessor is unfinished |
| [ADR-0035](docs/adr/0035-lesson-player.md) | **`POST /v1/learn/lessons/{id}/complete`'s response**, written by the client: `{isFirstCompletion, xpEarned{value,display,accessibilityLabel}, accuracy{…}, streakLine, week:[{label, isComplete, isToday, accessibilityLabel}] ×7, screen{…}}`. `screen` is the whole updated Learn payload, so the map behind the player re-renders from server truth rather than reloading. **No date, timestamp, or day key anywhere in it** — the week strip's seven days are labelled and flagged server-side, against the user's stored timezone (invariant 6), because a client that knew which day was today could move the streak by moving the clock |
| [ADR-0035](docs/adr/0035-lesson-player.md) | **XP is 10 a correct answer plus a 20-point completion bonus, awarded on the first completion only** (defect D13). A replay may update the accuracy and earns **nothing**: `xpEarned` is `0` and the returned total is unchanged. The client cannot assert this and must not — a client that checked the sum would be a second implementation of it |
| [ADR-0035](docs/adr/0035-lesson-player.md) | **`xpEarned.display` is signed by the server** (`+50`), for the reason an incoming expense's is: a `+` pushed onto the front of a string by the client lands on the wrong side of an Arabic figure. `accuracy.display` carries its own `%`, whose position is a language's decision |
| [ADR-0035](docs/adr/0035-lesson-player.md) | **`streakLine` is a server sentence**, not two catalogue strings chosen by a flag: "your streak just grew to 5 days" is a count *and* a plural, and Arabic has six plural forms (ADR-0011) |
| [ADR-0035](docs/adr/0035-lesson-player.md) | **New endpoint** — `POST /v1/learn/progress {lessonId, stepIndex, results}`, answering with the updated Learn screen payload. It reports what happened rather than what the ring should show: `filledSegments` is a figure the screen draws, so the server decides it. The client sends this **once**, when a part-finished player closes, and ignores the outcome — there is no queue (ADR-0019) |
| [ADR-0036](docs/adr/0036-reports-archive.md) | **`GET /v1/screens/reports`'s payload**, written by the client: `{summary{goalsMetLabel, monthCount{value,display}, averageSpend, totalSaved}, trend{goalPosition, bars[{monthKey, label, fill, verdict, percentageLabel, accessibilityLabel}]}, years[{label, totalSaved, months[{monthKey, label, spent, percentageLabel, verdict, segments[{slot, share}]}]}]}`. `verdict` is `hit`/`near`/`miss` from §4.2's **one** table; `fill`, `goalPosition`, and `share` are fractions `0…1` — geometry, so a bar cannot be drawn below a goal line it clears |
| [ADR-0036](docs/adr/0036-reports-archive.md) | **The payload must carry no per-month `saved`, `goal`, or numeric percentage.** Defect D11 is two threshold tables over one number, and the client's half of the fix is having nothing to threshold — a percentage arrives as a sentence and a verdict as a verdict. This is asserted against the wire, so adding any of those three fields breaks the client's test suite deliberately |
| [ADR-0036](docs/adr/0036-reports-archive.md) | **The archive arrives grouped by year with each year's total, and the two orderings are both sent** — the trend oldest-first, the list newest-first. A bar and its month row must agree about the verdict and the percentage; the corpus asserts it, because the same number thresholded twice inside one assembly is D11 moved server-side |
| [ADR-0036](docs/adr/0036-reports-archive.md) | **Every date on the screen is a label** — "February", "Feb", "2026" — computed against the user's stored timezone (invariant 6). `monthKey` is an identity, not a date: it is the address of one month's detail. There is no timestamp and no month *number* anywhere in the payload, so the client could not name a month if it wanted to |
| [ADR-0036](docs/adr/0036-reports-archive.md) | **Each bar carries its own descriptor** — "February 2026, 91% of goal, ₹11,830 saved" — as a server sentence, because it joins a date label, a percentage, and a money figure (ADR-0011). The design puts it in a `title` attribute, which touch never surfaces |
| [ADR-0036](docs/adr/0036-reports-archive.md) | **A `goal` of 0 yields `hit`** (§4.2 — there is nothing to miss), and a fourth verdict is a **coordinated release**: the client fails the screen rather than degrading, because an archived month is immutable and a wrong verdict about it would be wrong for ever (invariant 7) |
| [ADR-0035](docs/adr/0035-lesson-player.md) | **`GET /v1/screens/learn` gains a `currencyToken`** — `₹`, or `AED ` with its space, exactly as Home's tip carries one. The curriculum is cacheable and ships `{c}` verbatim in all 124 steps, so the symbol has to travel with the per-user half; without it the reader sees `{c}` in every worked example |
| [ADR-0037](docs/adr/0037-reports-month-detail.md) | **`GET /v1/screens/reports/:monthKey`'s payload**, written by the client: `{monthKey, title, verdict, percentageLabel, totals{spent, fixed, variable, additionalIncome, isAdapted}, spending{shareOfIncomeLabel, categoryCountLabel, categories[{id, name, amount, share, shareLabel, slot}]}, savings{saved, goal, zeroLabel, position, shareOfIncomeLabel, remaining?, surplus?}, wants{used, allowance, percentageLabel, fill, isOver, remaining?, excess?}, split{income, segments[{portion, amount, share, target?}]}, groups[{id, name, slot, icon, flow, total, summaryLabel, entries[{label, dateLabel, amount}]}], facts[{kind, value, note?}]}`. One slice per category that has something in it; **seven** groups always, Additional Income last |
| [ADR-0037](docs/adr/0037-reports-month-detail.md) | **The split bar carries four segments and they sum to `income` exactly** — `needs`, `wants`, `min(saved, goal)`, `max(0, saved − goal)` (§4.2 **[FIX]**). The design's "left unspent" is identically zero under a residual `saved` and **must not be sent**: the client fails the screen on a fifth `portion`, because a bar whose parts no longer add up to the figure beside them is about a month nobody can correct (invariant 7). `target` is absent on `surplus` only |
| [ADR-0037](docs/adr/0037-reports-month-detail.md) | **An archived month is read through the FX rates pinned at close, and a currency change is a re-read.** The same `monthKey` in another display currency must return every figure converted and **every verdict, percentage, position, fill and share byte-identical**. The client has no conversion and no arithmetic to do it with, and the corpus carries one month in two currencies so that a server which recomputed a verdict breaks a test |
| [ADR-0037](docs/adr/0037-reports-month-detail.md) | **`isAdapted` is the engine's own flag**, not `needs > income / 2` for the client to work out: it chooses which of two sentences explains the month's split. Likewise `isOver` on the wants allowance, and the three savings optionals — `remaining` when the goal was missed, `surplus` when it was passed, **neither** when it was met to the unit, which is the third sentence the design does not have |
| [ADR-0037](docs/adr/0037-reports-month-detail.md) | **`facts` is a closed set of six `kind`s** — `salary`, `goal`, `saved`, `biggestCost`, `needs`, `leftOver`. The label is the app's copy keyed on the kind; `value` is a string because one of the six is a category *name*; and `note` is a **server sentence**, because it joins a figure to words. A seventh kind is dropped by the client rather than failing the month, so it is additive |
| [ADR-0037](docs/adr/0037-reports-month-detail.md) | **Every date is a label and there is no timestamp** — "14 Feb", or "Fixed each month" for a bill with no day (invariant 6). `summaryLabel` carries a count, a plural, and a percentage in one server sentence, because Arabic has six plural forms and the design wrote `n === 1 ? ' entry' : ' entries'` |
