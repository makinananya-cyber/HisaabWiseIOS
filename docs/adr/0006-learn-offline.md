# ADR-0006 — Learn plays offline; a completion counts for the day it arrives

**Status:** accepted
**Amends:** Product Spec §5.2 (the offline queue carries lesson completions, not only expenses)

## Context

Product Spec §6 justifies shipping answer keys to the client because doing so "enables offline
lessons" — the single largest content-security concession in the product. But §5.2 scopes the
offline queue to *expenses only*, and XP, the streak, and sequential unlocking are all
server-owned, validated at `POST /v1/learn/lessons/:id/complete`. So the stated rationale for the
concession was not delivered by anything in the plan.

Making Learn work offline then exposes a hole neither spec addresses. Invariant 6 and defect D5
require the day boundary to be server-owned in the user's stored timezone, and state that
"device-clock manipulation must not move a streak". A lesson completed offline on Monday at 22:00
and synced on Wednesday morning has **no server-observed Monday**.

## Decision

**Learn is playable offline**, using the cached curriculum and its answer keys. Completions ride
the ADR-0005 queue as `completeLesson`.

**Arrival-day attribution.** The server derives the day key from **receipt time** in the user's
stored timezone. The client sends `completedAt` for analytics only, explicitly labelled
untrusted.

**The client enforces unlock order locally** while offline, mirroring — never replacing — the
server's rule, so the queue cannot submit lesson 4 before lesson 3 and earn a guaranteed `422`.

**Pending, never guessed.** While offline the completion screen shows XP and streak as *pending*
with "your streak updates when you reconnect". The client never renders a locally-computed streak
number.

## Consequences

- The day boundary keeps **exactly one owner**, which is the entire point of invariant 6.
- The cost is narrow and bounded: losing credit requires being offline *across a local day
  boundary* **and** studying in that window. The target session — a metro commute — reconnects
  the same day.
- **Rejected:** trusting the client's `completedAt`. It reopens D5 directly.
- **Rejected:** clamping to `min(clientCompletedAt, receivedAt)`. It blocks forward-clock streak
  farming but still lets a backdated clock retro-fill a missed day, and "you cannot skip forward
  but you can fill backward" is a rule nobody will remember in six months.
- Requires the curriculum to be available offline as a *guarantee*, not a cache hint — hence
  ADR-0009's explicit on-disk store.
