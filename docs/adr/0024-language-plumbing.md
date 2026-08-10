# ADR-0024 — Language plumbing: one owner, an optimistic switch, and `PUT /v1/me/language`

**Status:** accepted
**Extends:** [ADR-0011](0011-localisation.md) (which decided *that* strings are externalised in Phase 1,
Latin digits everywhere, and en + ar as the shipped set — not how the choice is owned or synchronised)
**Requires elsewhere:** a new backend route, `PUT /v1/me/language` (recorded in `CONTEXT.md`)

## Context

ADR-0011 settled the localisation strategy and issue #3 gave `LanguageManager` its first job: supply
`Accept-Language`. Growing it into the thing every screen reads raises four questions the earlier
decision does not answer.

**Who owns the locale a screen formats in.** `Locale.current` is the device's, and once a user picks a
language in the app the two disagree on purpose. Nothing works if half the app reads one and half the
other.

**What happens when the switch cannot reach the server.** The header alone makes every screen right and
every *email* wrong: a password reset or a streak reminder is composed hours after the app was last
open, from a stored preference rather than from a request header. So the choice has to be written
server-side, and a write needs a connection (ADR-0019) — which means there is a failure case, and the
failure case is where client and server come to disagree with nothing to notice it.

**Where the network call lives.** `LanguageManager` is in `DesignSystem/` because screens read it from
`@Environment` beside `ThemeManager`. `APIClient` is in `Networking/`. Neither may import the other, and
the graph genuinely has a cycle in it: the client reads the language on every request, and a language
change is recorded through the client.

**How a language nobody can read yet gets tested.** Only English copy ships until Phase 5, so a language
switch changes no visible sentence. Everything it *does* change — direction, numbering, the header — is
invisible in the one language the app has copy for.

## Decision

**One owner, four views of one choice.** `LanguageManager` is `@Observable`, `@MainActor`, composed in
`AppEnvironment`, and exposes `selected`, `shipped`, `locale`, `layoutDirection`, and `acceptLanguage`.
Nothing in the app reads `Locale.current`; the locale and the layout direction are injected once at the
root by `hwLanguage(_:)`, not per screen — Landing and Auth are not `BaseView` conformances (ADR-0021)
and have to mirror too.

**The locale pins `latn` numbering**, in both languages, which is ADR-0011's Latin-digit choice made
concrete at the object a screen actually reads.

**`shipped` is the picker's source.** Two languages. The design's 87-language list is reference content
the backend serves; nothing in the app enumerates it.

**The switch is optimistic, with a revert.** `select(_:)` changes `selected` first, then sends
`PUT /v1/me/language`, then persists. Local-first because the request must *carry* the new language, so
the response comes back formatted in the language the user just chose and a screen re-renders from server
truth (ADR-0020). Persist-last because a store written before the server agreed would let a relaunch
resurrect a language the server never accepted. And **revert on any failure** — offline, 5xx, or a server
that answers with a different language — with the error rethrown for the screen to render.

**The choice is kept in `UserDefaults`**, behind `LanguageStore` in `Models/`, synchronously and
`@MainActor`. Synchronous unlike `TokenStore`: the manager is constructed before the first frame, so an
`async` read could only be adopted afterwards, and a launch that shows English to an Arabic reader and
then swaps under them is worse than the asymmetry. An explicit choice outranks the device's language.

**Two protocols in `Models/`, so the dependency points down.** `LanguageSource` (existing) is read by the
client; `LanguageSink` (new) is conformed to by the client. `AppEnvironment` closes the cycle with one
`connect(to:)` call, and an unconnected manager **throws** rather than switching the language locally in
silence.

**The harness is continuous, not a Phase 5 exercise.** A checked-in shared scheme,
`HisaabWise (Double-Length)`, carries `-NSDoubleLocalizedStrings YES`; every screen carries a
right-to-left preview; and `LocalisationTests` asserts over every layer and the app root that nothing pins
an edge, no image encodes direction, no Eastern Arabic-Indic digit appears, nothing reads `Locale.current`,
no sentence is concatenated, and no text truncates or shrinks to fit. Two further scans read the String
Catalogue: every key a view renders has English copy, and no entry is orphaned.

## Consequences

- Screens and email agree, or the switch visibly failed. There is no state in which the app is Arabic and
  the server thinks it is English.
- `select(_:)` needs a session, because the route does. That is correct rather than a limitation: the
  picker lives on Account, behind sign-in, and a signed-out user's language is the device's.
- **Login carries no language, so the first run can start out of step**, and this ADR does not fix that on
  its own. An Arabic phone puts the app in Arabic without asking the server; an account registered in
  English then sends English mail to a user reading an Arabic app. Two consequences: re-selecting the
  language already on screen is *not* a no-op unless the store confirms it, so the picker can repair the
  disagreement; and the proper fix is for `login` and `refresh` to carry the language exactly as ADR-0023
  made them carry `timeZone`, for the same reason — it is the only place it can happen without a user
  action. That is recorded in `CONTEXT.md` as a change required elsewhere.
- **Accepted deliberately:** the two-phase `connect(to:)`. The alternative to a half-built manager is a
  half-built client, which is worse — every request would have to tolerate a missing language. The
  half-built window is one line long, `AppEnvironmentTests` asserts it closes, and a manager that was
  never connected fails loudly.
- **The environment locale is the whole mechanism, because `Text` honours it over the resource's own.**
  This was worth establishing rather than assuming. Copy in this app travels as `LocalizedStringResource`
  values created as literals in type initialisers — `StateCopy`'s defaults, `ErrorCopy`'s table, every
  component's control copy — and a resource captures a locale at creation. Had `Text` honoured *that*
  locale, the switch would reach none of it, and with English-only copy the failure would be invisible. It
  does not: `Text` substitutes the environment's locale, and re-pointing a resource's own has no effect on
  what is drawn. Both halves are pinned by a test, because the "no relaunch" requirement rests entirely on
  them and a stamping helper at every render site is the alternative.
- **A `BaseView` render always lands on `.loading`,** because the chrome's `.task` restarts the load and
  `ImageRenderer` yields before it captures. So the mirroring assertions go through `StateView`, which has
  no task, and a screen render is a smoke test. Worth knowing before writing a snapshot suite (#9): pinned
  snapshots of loaded screens need a way to render one without its task.
- Latin digits under `ar` is now asserted three ways — on `AppLanguage.locale`, on `LanguageManager`, and
  as a source scan — which is the level of belt-and-braces the Learn tab's `< 0.5` grading tolerance earns.
