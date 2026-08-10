# ADR-0008 — Foreground and network regain are the only guaranteed drain points

**Status:** accepted, amended by [ADR-0019](0019-no-offline-writes-curriculum-pdf.md) — the drain step and the network-regain/background-refresh hooks are gone; the rest of the foreground sequence stands.

## Context

ADR-0005's queue and ADR-0009's content store both need a lifecycle owner, and ADR-0010's
web-based email verification means the app must notice a state change **it did not cause** — the
user taps a link in Mail, verifies in Safari, and returns to an app still showing the
"verify your email" banner (§3.2).

`BGAppRefreshTask` is the obvious answer and the wrong one to depend on: iOS schedules it
opportunistically against usage patterns, and for a low-usage app it may simply never run.

## Decision

**On `scenePhase == .active`**, in order:

1. proactive token refresh if near expiry (ADR-0007);
2. drain `PendingWrite` in `createdAt` order;
3. revalidate `GET /v1/me`;
4. revalidate content ETags, at most once per launch.

**On network regain** — `NWPathMonitor` — drain.

**`BGAppRefreshTask` is scheduled but treated as a bonus.** No UI copy may imply that a queued
expense syncs while the app is closed.

Backoff is capped; after repeated failure the pending badge escalates to "couldn't sync — tap for
details" rather than retrying invisibly forever.

## Consequences

- Step 3 is what clears the unverified-email banner after an out-of-app verification, and it also
  picks up a salary or display-currency change made elsewhere — one revalidation covers three
  needs, so it is cheap to justify.
- Users are told the truth about when their data leaves the device. An app that promises
  background sync and gets no background execution produces support tickets that are impossible to
  reproduce.
- The ordering matters: refreshing before draining means the drain does not spend its first
  request discovering an expired token, and revalidating `/v1/me` *after* the drain means the
  figures fetched reflect the writes just sent.
