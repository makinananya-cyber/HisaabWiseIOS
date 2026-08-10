# ADR-0019 — No offline writes; the curriculum is downloadable as a server-generated PDF

**Status:** accepted
**Supersedes:** [ADR-0004](0004-offline-model.md), [ADR-0005](0005-write-queue.md),
[ADR-0006](0006-learn-offline.md) — in full
**Amends:** [ADR-0008](0008-app-lifecycle.md) (the drain step goes; the rest of the foreground
sequence stands) and [ADR-0009](0009-content-cache.md) (the content store survives, its rationale
narrows)
**Amends:** Product Spec §3.4, §4.5, §5.2, §6; Technical Spec §1, §2, Phase 2; the workspace
`CLAUDE.md` iOS conventions
**Decided by:** the project owner, 2026-08-10

## Context

Both specs, the workspace `CLAUDE.md`, and four ADRs read "works offline" as **offline writes**: a
SwiftData queue of `PendingWrite` rows drained on reconnect, with pending badges, poison-message
handling, `MONTH_CLOSED` re-filing, and arrival-day attribution for lesson completions. Product
Spec §5.2 listed it as a *resolved* decision.

That is not what was meant. The intent behind "offline" was that a user can **take the learning
content away with them** — a document they can read without a connection — not that the app accepts
writes while disconnected.

This matters because the two readings have almost nothing in common. One is a synchronisation
subsystem; the other is a download.

## Decision

**No offline writes.** Every write requires a connection. There is no write queue, no SwiftData, no
pending state, no drain, no poison-message handling, and no arrival-day attribution. A write
attempted without a connection fails to `LoadState.offline` and the user retries.

**The curriculum is downloadable as a PDF, generated server-side.** A new endpoint returns the
curriculum as a locale-aware PDF; the app downloads it, stores it, and offers it through the share
sheet. It is not per-user, so it is cacheable (invariant 8).

**Server-generated, not client-rendered.** One layout serves iOS, Android, and email, and every
figure inside it stays formatted by the side that owns formatting (ADR-0003). The cost is a hard
dependency on backend work that has not started, so the iOS side is built against a fixture PDF.

**Reading stays cached; writing does not queue.** ADR-0009's content store survives — curriculum,
picklists, categories, and reference lists still persist with per-resource ETags. Its justification
changes from "the commute session must work" to latency and data use, and it is no longer what makes
Learn usable without a connection. The PDF is.

**ADR-0008's foreground sequence loses one step.** It becomes: proactive refresh if near expiry →
revalidate `GET /v1/me` → revalidate content ETags at most once per launch. `NWPathMonitor`-on-regain
and `BGAppRefreshTask` go with the queue.

## Consequences

- **A user on the metro cannot log an expense.** This is the substantive product cost and it was
  accepted knowingly. Expenses is an online-only screen.
- **A lesson cannot be completed without a connection**, so answer keys no longer ship "to enable
  offline lessons" (Product Spec §6). They still ship, for the reason invariant 10 already gives:
  grading is client-side for responsiveness and the server recomputes. The justification changes; the
  behaviour does not.
- **`Money` needs no arithmetic at all.** The single exception ADR-0003 carved out — summing `minor`
  of the app's own pending entries for the pending badge — had the pending badge as its only caller.
  With no pending entries, `Money` has no `+`, and the "client never computes money" rule becomes
  absolute rather than almost-absolute. A strengthening, not a loss.
- **`MONTH_CLOSED` does not disappear.** A request in flight across a rollover boundary, or a client
  left open past midnight on the 1st, still hits it. The client must still handle it and offer
  re-filing into the live month (§4.5) — what goes is the queue-replay machinery around it, not the
  error.
- **`DELETE /v1/expenses/:id` no longer *needs* to be idempotent.** ADR-0005 required it because a
  retried delete would otherwise never drain. Without retries the commitment is optional; it remains
  good hygiene. Recorded as downgraded in `CONTEXT.md` rather than dropped.
- **ADR-0001's iOS 18 floor stands, but on fewer legs.** One stated reason was that SwiftData's
  migration and predicate defects settle in 18 and "the offline write queue is the last place in this
  app to want framework bugs". No SwiftData is used now. The floor is still right for `SectorMark`,
  `@Observable`, `.sensoryFeedback`, String Catalogs, and Swift Testing, and §2's SwiftData-versus-
  CoreData hedge is simply moot.
- **The PDF is a new backend commitment**, added to `CONTEXT.md`'s outside-this-repo table: an
  endpoint returning the curriculum as a PDF, honouring `Accept-Language`, cacheable, with an ETag.
  Until it exists the iOS ticket is blocked; it is built and tested against a fixture PDF.
- **The vocabulary shrinks.** `pending`, `stale`, `PendingWrite`, `drain`, `poison message`, and
  `arrival-day attribution` are retired from `CONTEXT.md`. Six terms nobody has to learn.
- **Rejected:** keeping the queue for expenses only. Offered; declined. The whole subsystem goes or
  none of it does — a queue that carries one kind of write costs nearly as much as one that carries
  three.
- **Rejected:** client-side PDF rendering. Faster to ship with no backend dependency, but it puts a
  second document layout in the app and would drift from whatever the web and email eventually send.
