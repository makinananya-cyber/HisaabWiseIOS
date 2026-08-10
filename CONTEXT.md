# CONTEXT — HisaabWiseIOS

Glossary for the iOS app. These terms have precise meanings; use them exactly, in code,
tests, and issues. Where a term has a tempting synonym, the synonym is named and rejected.

Backend vocabulary (`Money`, `saved`, `verdict`, `monthKey`, `dayKey`, `live month`,
`closed month`, `token family`, `securityEpoch`, …) is defined in
`../HisaabWiseBackend/CONTEXT.md` and is **not** redefined here. This file covers only what
is client-side.

Decisions that established these terms live in `docs/adr/`.

## Structure

**app shell** — the `.xcodeproj` target. Owns `Info.plist`, entitlements, app icon, launch
screen, and the composition root. Contains no feature code.
See [ADR-0002](docs/adr/0002-project-topology.md).

**HWCore · HWNetworking · HWPersistence · HWDesignSystem · HWFeatures · HWFixtures** — the
six library targets of `Packages/HisaabWise`. `HWCore` has no dependency on `HWNetworking`,
which is what stops a raw number reaching a view. `HWFixtures` is `#if DEBUG` only.

**store** — an `@Observable` class owning one tab's state, injected via `@Environment`.
Rejected synonym: *view model* (there is no per-screen view model; the server is the model
layer).

## Money on the client

**display string** — the pre-formatted, localised, currency-symbol-spaced string the server
returns alongside each `Money`. **The only thing the client renders for a monetary value.**
See [ADR-0003](docs/adr/0003-money-presentation.md).

**client money arithmetic** — forbidden, with exactly one exception: summing the `minor`
units of the app's own *pending* entries for the pending badge. The client never converts,
never rounds, never applies symbol spacing, and never sums server-supplied entries.

## Offline

**pending** — a state, not an error. A write the user has made that the server has not yet
acknowledged. Pending entries appear in lists with a distinct treatment and are counted in a
banner; the figures on cards remain the last server-supplied ones.
See [ADR-0004](docs/adr/0004-offline-model.md).

**stale** — server figures that predate one or more pending writes. Displayed as-is, never
adjusted locally, never styled as a failure.

**PendingWrite** — one row in the single offline queue:
`{id: UUID, kind, payload, createdAt, attempts, lastError}`. Kinds: `createExpense`,
`deleteExpense`, `completeLesson`. Drained in `createdAt` order.
See [ADR-0005](docs/adr/0005-write-queue.md).

**drain** — one attempt to flush the queue. Guaranteed at foreground and on network regain;
opportunistic in a `BGAppRefreshTask`. Rejected synonym: *sync* (there is no bidirectional
sync — this is a write queue).
See [ADR-0008](docs/adr/0008-app-lifecycle.md).

**poison message** — a queued write the server will never accept (a `422` lesson completion,
a `404` delete). Dropped, not retried.

**arrival-day attribution** — the rule that an offline lesson completion counts for the day
the *server receives* it, not the day the device believes it happened. `completedAt` is sent
for analytics only and is explicitly untrusted.
See [ADR-0006](docs/adr/0006-learn-offline.md).

## Session

**TokenStore** — the protocol in `HWCore` behind which the refresh token lives.
`KeychainTokenStore` when "Keep me signed in" is checked, `InMemoryTokenStore` when it is
not. O3's app lock would be a third conformance, not a refactor.
See [ADR-0007](docs/adr/0007-session-and-refresh.md).

**single-flight refresh** — at most one refresh in progress per process. Every caller that
sees a 401 awaits the same `Task`. Not an optimisation: concurrent refreshes present a
revoked token and trigger backend family revocation, logging the user out.

## Content

**content store** — the explicit on-disk JSON store for offline-critical content (curriculum,
picklists, categories, reference lists) with a persisted ETag per resource. Distinct from
`URLCache`, which carries only tips and articles.
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

**fixture corpus** — the JSON files in `HWFixtures`, read by both the decoding tests and the
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
| [ADR-0005](docs/adr/0005-write-queue.md) | `DELETE /v1/expenses/:id` must be explicitly idempotent — a `404` on an already-deleted id is success, or a retried delete becomes a poison message |
| [ADR-0010](docs/adr/0010-configuration-and-auth-links.md) | `POST /v1/auth/reset-password` must be callable from a web form, not only from the app |
| [ADR-0015](docs/adr/0015-deletion-and-demo-account.md) | Technical Spec §5 — sign-in during the grace period returns `ACCOUNT_PENDING_DELETION` with the erase date; add `POST /v1/auth/restore` |
| [ADR-0004](docs/adr/0004-offline-model.md) | Product Spec §6 — "enables offline lessons" should read *after one online session* |
| [ADR-0016](docs/adr/0016-presentation-details.md) | Product Spec §6 — amounts inside tips are illustrative and are never converted |
| [ADR-0001](docs/adr/0001-platform-baseline.md) | Product Spec §5.2 — record iPhone-only, portrait-only |
| [ADR-0011](docs/adr/0011-localisation.md) | `DEVELOPMENT_PLAN.md` §5 — string externalisation moves from Phase 5 to Phase 1 (translation stays in Phase 5) |
| [ADR-0007](docs/adr/0007-session-and-refresh.md) | Technical Spec §9 — add a concurrency case: several in-flight requests across an access-token expiry must not log the user out |
