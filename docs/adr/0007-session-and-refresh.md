# ADR-0007 — Refresh-token storage is device-bound, and refresh is single-flight

**Status:** accepted
**Amends:** Product Spec §3.2 (defines the unchecked "Keep me signed in" path); Technical Spec §9
(adds a concurrency case to the auth/session checks)

## Context

**"Keep me signed in" has no defined off-state.** §3.2 has the checkbox and §5 says the Keychain
refresh token "is what makes 'Keep me signed in' work", but neither says what *unchecked* does,
and §9 tests only the checked case.

**Concurrent refresh is a silent-logout bug.** Refresh rotation revokes the whole `familyId` when
an already-revoked token is presented (§5, backend ADR-0005). An expired access token with several
screens in flight produces several concurrent refreshes; the losers present the same
soon-to-be-revoked token and **the family is revoked — the user is logged out**. It reproduces
mainly on slow networks, which is this app's target context.

## Decision

**Storage.** Checked → refresh token in the Keychain with
`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` and `kSecUseDataProtectionKeychain = true`, no
access group. Unchecked → `InMemoryTokenStore`; the session ends at app termination. The access
token is never persisted and is owned by the `APIClient` actor.

**Single-flight refresh.** One shared `Task<Token, Error>` inside the actor; every caller that
sees a 401 awaits that same task and retries its original request once. A **proactive** refresh
fires when under roughly 60 s of token life remains, so the 401 path stays rare.

**Failure branches are distinguished, or the bug returns from the other side:**

- definitive `401` on refresh (family revoked) → hard logout to landing, delete the Keychain item;
- network failure → **keep the session**, surface offline state, never log out.

**Seam.** A `TokenStore` protocol in `HWCore` with `Keychain` and `InMemory` conformances. O3's
app lock becomes a third conformance rather than a refactor.

## Consequences

- `ThisDeviceOnly` prevents a live 60-day session being **restored onto a new device from an
  encrypted iCloud backup**. Plain `AfterFirstUnlock` would permit exactly that.
- `AfterFirstUnlock` rather than `WhenUnlocked` is required so ADR-0008's drain can run after a
  reboot before the user has unlocked in that session.
- No access group today. Adding a widget or extension later needs an entitlement change and a
  one-time item migration — a known, bounded cost.
- ADR-0002's actor boundary is what makes single-flight expressible without a lock.
- Technical Spec §9 should gain the case: several in-flight requests spanning an access-token
  expiry must not log the user out.
