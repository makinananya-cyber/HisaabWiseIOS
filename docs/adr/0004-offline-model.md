# ADR-0004 — Offline shows stale server figures plus an explicit pending state

**Status:** accepted
**Amends:** Product Spec §6 ("enables offline lessons" → *after one online session*)

## Context

Two requirements collide and neither spec addresses the collision.

Invariant 3 and Product Spec §4.2 put the budget engine server-side, once, and state that the
client "never derives" `saved` or the goal verdict. But §3.4 requires offline expense entry. The
instant an entry queues, every figure on Home — donut, savings meter, wants bar, verdict pill —
is stale and provably contradicts what the user just typed.

Separately, nothing describes a **cold start with no network and no cache**. Landing is static
(§3.2, "No backend calls") so it renders, but registration is one atomic call, and §6 forbids
compiling content into the app binary — so a user who installs offline has no curriculum at all.

## Decision

**Stale figures plus an explicit pending state.** Cards keep the last server-supplied display
strings. Queued entries appear in lists with a distinct pending treatment, and a banner counts
them ("2 entries not yet counted"). The client performs no budget arithmetic — its only sum is
the pending entries' own total (ADR-0003).

**Cold start, no cache:** Landing renders. Get Started leads to a clear offline state with
retry — no fake progress, no queued registration. Content is fetched **eagerly on the first
successful registration or login**, not lazily when Learn is first opened, so the commute
session works. Until then the Learn tab shows an explicit "lessons not downloaded yet" state.

## Consequences

- Logging an expense offline feels **less responsive than the prototype, deliberately**. The
  donut failing to move is a nice-to-have missed; being wrong about someone's savings verdict is
  not.
- **Rejected:** a local optimistic mirror of the budget engine. It is a second implementation of
  the one rule the specs are most emphatic about having exactly once, and it would disagree at
  precisely the interesting margins — the adaptive degradation branch, the 100/70 verdict
  boundary — which is defect D11 rebuilt on the client.
- **Rejected:** refusing to log offline. Contradicts §3.4 outright.
- Product Spec §6 justifies shipping answer keys to the client because it "enables offline
  lessons". With content server-served and not bundled, that is true only **after one online
  session**, and §6 should say so — as written it promises more than the architecture delivers.
- `offline` must be a distinct `LoadState` case, never styled as `failed` (ADR-0016). Offline is
  a supported mode here, not a fault.
