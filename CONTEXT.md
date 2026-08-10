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
app runs on and what base URL it points at. Nothing below it knows what an environment is.

**view model** — an `@Observable` `@MainActor` class owning one screen's presentation state,
holding the fetch and the ``LoadState`` mapping. It never *derives* a figure: every figure is
computed server-side (invariant 3) and `Money` exposes no arithmetic to derive one with.
Formerly called a *store* (ADR-0002); that term is retired.

**component** — one entry in the shared control vocabulary in `Components/`: a button variant,
a field, a label style, a card, a chip, a sheet, a row. **Presentational** — it takes values and
closures, holds no view model, and cannot fetch. A screen never styles a control itself; a new
variant is added here rather than inlined there. The inventory follows the design's own CSS
(`.btn` and its four variants, `.iconbtn`, `.field-box`, `.label`, `.eyebrow`, `.card`, the chip
and sheet families, `.row` / `.key-row`, `.toast`).

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

**layering scans** — the source scans in `HisaabWiseTests/Architecture` that assert no view
touches `Networking`, no model touches `Networking` or SwiftUI, no view model imports SwiftUI, and
no component fetches or holds a view model. In one target the compiler enforces no layer boundary, so these are the enforcement —
weaker than the package graph they replaced, and the only thing that keeps the layering from
being a convention.

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
not. O3's app lock would be a third conformance, not a refactor.
See [ADR-0007](docs/adr/0007-session-and-refresh.md).

**single-flight refresh** — at most one refresh in progress per process. Every caller that
sees a 401 awaits the same `Task`. Not an optimisation: concurrent refreshes present a
revoked token and trigger backend family revocation, logging the user out.

## Content

**content store** — the explicit on-disk JSON store for curriculum, picklists, categories, and
the reference lists, with a persisted ETag per resource. Distinct from `URLCache`, which carries
only tips and articles. It exists for latency and data use; it is **not** what makes the app
usable without a connection — the curriculum PDF is
([ADR-0019](docs/adr/0019-no-offline-writes-curriculum-pdf.md)).
See [ADR-0009](docs/adr/0009-content-cache.md).

**`{c}`** — the currency token left verbatim in tip text. Substituted client-side from
server-supplied currency metadata. Amounts printed next to it are **illustrative and never
converted**.
See [ADR-0016](docs/adr/0016-presentation-details.md).

## Presentation

**LoadState** — the four-case enum every screen's data goes through: loading, empty, offline,
failed. `offline` is never rendered as `failed`.

**privacy overlay** — the logo-on-`galaxy` view applied at `scenePhase == .inactive` so the
app-switcher snapshot carries no financial figures. Not app lock: returning requires no
authentication.
See [ADR-0014](docs/adr/0014-privacy-surfaces.md).

**fixture corpus** — the JSON files in `Fixtures/Resources`, read by both the decoding tests and the
SwiftUI previews, so a fixture that drifts from the API breaks a test rather than rotting a
preview.
See [ADR-0013](docs/adr/0013-testing-and-previews.md).

---

## Changes these decisions require outside this repo

Recorded here because they are commitments, not suggestions. None has been made yet.

| Source | Change |
|---|---|
| [ADR-0003](docs/adr/0003-money-presentation.md) | Technical Spec §5 — state the currency of `GET /v1/budget`'s figures; every monetary field gains a server-formatted display string honouring `Accept-Language` |
| [ADR-0003](docs/adr/0003-money-presentation.md) | Technical Spec §1 — drop FX from the iOS content cache; `GET /v1/expenses` returns per-category totals |
| [ADR-0020](docs/adr/0020-screen-scoped-endpoints.md) | **Six new endpoints** — `GET /v1/screens/{home,expenses,learn,reports,account}` and `/v1/screens/reports/:monthKey`, each returning exactly what the screen renders, fully formatted. Every derived value included: "% of pay", the meter percentage, "Today / Yesterday / N days ago", per-category totals, Learn accuracy and progress fractions, the goal verdict, per-year totals |
| [ADR-0020](docs/adr/0020-screen-scoped-endpoints.md) | Writes — `POST /v1/expenses`, `DELETE /v1/expenses/:id`, `POST /v1/learn/lessons/:id/complete`, `PUT /v1/me/*` — **return the updated screen payload**, so the client never patches its own copy |
| [ADR-0019](docs/adr/0019-no-offline-writes-curriculum-pdf.md) | **New endpoint** — the curriculum as a **server-generated PDF**, honouring `Accept-Language`, cacheable (not per-user) with an ETag. The iOS download ticket is blocked on it and is built against a fixture PDF until it lands |
| ~~[ADR-0005](docs/adr/0005-write-queue.md)~~ | ~~`DELETE /v1/expenses/:id` must be explicitly idempotent~~ — **downgraded to optional** by [ADR-0019](docs/adr/0019-no-offline-writes-curriculum-pdf.md): with no retries, an already-deleted id can never be re-sent. Still good hygiene |
| [ADR-0010](docs/adr/0010-configuration-and-auth-links.md) | `POST /v1/auth/reset-password` must be callable from a web form, not only from the app |
| [ADR-0015](docs/adr/0015-deletion-and-demo-account.md) | Technical Spec §5 — sign-in during the grace period returns `ACCOUNT_PENDING_DELETION` with the erase date; add `POST /v1/auth/restore` |
| [ADR-0019](docs/adr/0019-no-offline-writes-curriculum-pdf.md) | Product Spec §6 — answer keys no longer ship "to enable offline lessons"; they ship because grading is client-side for responsiveness and the server recomputes (invariant 10) |
| [ADR-0016](docs/adr/0016-presentation-details.md) | Product Spec §6 — amounts inside tips are illustrative and are never converted |
| [ADR-0001](docs/adr/0001-platform-baseline.md) | Product Spec §5.2 — record iPhone-only, portrait-only |
| [ADR-0011](docs/adr/0011-localisation.md) | `DEVELOPMENT_PLAN.md` §5 — string externalisation moves from Phase 5 to Phase 1 (translation stays in Phase 5) |
| [ADR-0007](docs/adr/0007-session-and-refresh.md) | Technical Spec §9 — add a concurrency case: several in-flight requests across an access-token expiry must not log the user out |
