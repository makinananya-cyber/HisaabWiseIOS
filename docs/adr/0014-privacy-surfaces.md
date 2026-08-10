# ADR-0014 — Privacy surfaces: switcher overlay, Sentry deny-by-default, separate telemetry buffer, deferred push prompt

**Status:** accepted

## Context

Four client-side privacy decisions the specs leave open or under-specified.

**The app-switcher snapshot.** Open decision O3's standing default is "not at launch; keep screens
free of secrets in app-switcher snapshot". But Home *is* salary and spending, so satisfying that
sentence requires actual work — it is not a no-op.

**Sentry.** It is a third-party processor, and this app's error context is salary, email, and
expense amounts. Library defaults are not sufficient.

**Telemetry.** §8's event list must reach `POST /v1/events` without competing with ADR-0005's
must-never-lose write queue.

**Push permission.** §4.4 makes the streak reminder opt-in only, and no spec says when the system
prompt appears — which in practice means it appears at launch and gets denied permanently.

## Decision

**Privacy overlay** — logo on solid `galaxy` — applied at `scenePhase == .inactive`,
unconditionally, with no setting. This is distinct from app lock: returning requires no
authentication, there are simply no figures in the switcher.

**Sentry, deny-by-default:** `sendDefaultPii = false`; **no** screenshot attachment, **no**
view-hierarchy attachment, **no** Session Replay; no request or response bodies; `beforeSend`
strips `Authorization` and scrubs keys matching amount/salary/email/phone/dob/token. The user is
identified by **server user id only** — never email or display name.

**Telemetry gets its own buffer**, file-backed, not `PendingWrite`. Flush at 20 events / 60 s /
backgrounding; hard cap ~500 with oldest dropped; at most one retry. `installId` is a UUID in
`UserDefaults`, **not** the Keychain. A **typed event enum in `HWCore`** mirrors the server's name
allowlist (backend ADR-0012).

**Notification permission is requested only at the moment of streak opt-in**, after an in-app
explainer of exactly what arrives, never at launch. Register with APNs and `POST
/v1/me/push-tokens` only once authorization is granted; if denied, flip the toggle back off and
offer a Settings deep link. Not `.provisional`.

## Consequences

- iOS captures the switcher snapshot at `.inactive`, so the overlay also flashes during permission
  prompts and share sheets. `.background` is too late to help, so the flash is accepted.
- The overlay makes O3's app lock a small step later — a gate in front of an existing overlay —
  rather than a new subsystem.
- A screenshot of Home is a financial-data leak into a third party, which is why the attachment
  options are off explicitly rather than left at their defaults.
- Events and expenses have **opposite guarantees**: an event may always be dropped, an expense the
  user typed may never be. A shared table would either weaken the strict guarantee or
  over-engineer the lossy one, and a poison event could delay a real write.
- A reinstall mints a new `installId`, which is what activation metrics want — Keychain persistence
  would defeat that.
- The typed event enum means a free-form name cannot be emitted and then silently discarded by the
  server allowlist. §8's "first expense within 24 h" and the distinct goal-set / goal-skipped
  events can never be backfilled, so silent loss is the failure that matters.
- Sentry belongs in the Privacy Policy and the App Privacy declarations as a processor; §8 item 17's
  "confirm Sentry ships its own signed manifest" remains a real task.
- A once-a-day streak nudge delivered `.provisional` (quietly, unprompted) would go unseen, which
  defeats the feature's entire purpose.
