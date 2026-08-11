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

**unwritten tab root** — `UnwrittenTabRoot` plus `UnwrittenScreenViewModel`, the stand-in for the four screens
that are other tickets (#18, #19, #21, #23). A full `BaseView` conformance, so it renders through `StateView`,
and it **makes no request**: calling the ADR-0020 screen endpoint would put a fictional contract in the client
and render "Something went wrong" on four of five tabs. A screen that is not built is not a screen that is
broken. Its `footer` slot carries `LogoutControl` on Account. **Retired the moment each screen lands.**

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
serves the AX3 reader and the VoiceOver user both. The four consumers are the donut, the savings meter, the
split bar, and the week strip (#17, #21, #22). Everything else — tips, articles, lesson steps, every label —
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
`.standard` queues. Three callers: the toast, `StateView`, and Learn's combo and completion (#20).

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
validation is not a calculation in this sense.

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
create cannot be the one call that forgets. `PUT` and `DELETE` carry none — both are idempotent by
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
