# ADR-0015 — Deletion is findable and password-gated; restore needs an endpoint that does not exist

**Status:** accepted
**Amends:** Technical Spec §5 (adds `ACCOUNT_PENDING_DELETION` and `POST /v1/auth/restore`)

## Context

Product Spec §3.7 commits to a 30-day soft delete during which sign-in is blocked "with a recovery
path", and the email stays reserved because "the recovery path needs it". But **§5 has no restore
endpoint**, and the whole flow is absent from the designs — §3.7 marks it as a new screen.

Separately, Technical Spec §8 item 19 requires a working demo account for App Review. Review hits
**production**, and the seeded Feb–Jul 2026 archive months are explicitly dev/staging-only (§3.6,
§6). So a fresh production account presents a reviewer with an empty Reports tab and a grey donut.

## Decision

**Deletion.** A dedicated screen in Account — App Store 5.1.1(v) requires it be *findable*, not
buried behind a web page. It states exactly what is erased and the erase date, is gated on
**password re-entry**, then one final alert, then logs out showing the date. `GET /v1/me/export` is
offered on the same screen.

**Recovery.** Sign-in during the grace period returns `ACCOUNT_PENDING_DELETION` carrying the erase
date; the app shows a restore screen whose action calls `POST /v1/auth/restore`. Both are new
backend surface.

**Demo account.** An **ordinary production account**, populated by a guarded one-off write that
requires an explicit target user id and touches nothing else, run via an admin-secret-gated route
rather than a local machine pointed at production (Rule 4). Review notes explain that Reports fills
at month end.

**No demo code path ships in the binary, ever** — the same instinct as never extracting the
prototype's `?demo` auto-fill block (§6).

## Consequences

- Password re-entry rather than a typed "DELETE" confirmation: typing a word is friction theatre
  when you already hold the password, and the password is the thing an attacker with a borrowed
  unlocked phone does not have.
- Offering export on the deletion screen is PDPL-aligned (§12 data-subject rights) and measurably
  reduces regret deletions.
- Reviewers do reject features that look unimplemented, so an empty Reports tab is a real
  submission risk rather than a cosmetic one.
- `POST /v1/auth/restore` must refuse to resurrect a user whose `purge:deleted` has already run —
  after the hard erase there is nothing to restore, only a tombstone.
- The 30-day grace period means the demo account must not be left in a soft-deleted state between
  submissions.
