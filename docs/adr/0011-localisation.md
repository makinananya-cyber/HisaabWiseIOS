# ADR-0011 — Strings externalised from Phase 1; Latin digits and POSIX numeric parsing

**Status:** accepted — extended by [ADR-0024](0024-language-plumbing.md), which decides how the choice
is owned, switched at runtime, and synchronised with the server
**Amends:** `DEVELOPMENT_PLAN.md` §5 (string externalisation moves from Phase 5 to Phase 1;
translation and the RTL pass stay in Phase 5)

## Context

The plan puts en + ar and the full RTL pass in **Phase 5**, which sits badly against its own
cross-phase rule that retrofitting is expensive. Arabic here is not primarily a translation task —
it is a **layout-direction** task, and four phases of hardcoded English literals and
`left`/`right` alignment is a repo-wide retrofit landing at the busiest point in the schedule.

A sharper problem hides in the Learn tab. The 14 numeric questions are graded at a **strict**
`|submitted − correct| < 0.5` (§3.5) on **both** client and server. Under `ar` the locale decimal
separator is not `.`, so locale-aware parsing of the same keystrokes yields a different number on
each side — and at a 0.5 tolerance boundary that flips answers between right and wrong.

## Decision

**Externalise from the first screen.** String Catalogs (`.xcstrings`) per target, English only
until Phase 5. `leading`/`trailing` never `left`/`right`; no direction-encoding images; no
manually composed sentences. The double-length pseudolanguage and RTL previews run continuously
from Phase 1, not as a Phase 5 discovery exercise.

**Latin digits everywhere**, including under `ar` — `latn` numbering — matching ADR-0003's
server-formatted display strings.

**Numeric answer input:** `.decimalPad` with an explicit Latin-digit input filter, parsed with
`en_US_POSIX`, submitted canonically with `.` as the separator.

## Consequences

- Client and server parse byte-identical input, so "the server re-grades every submission and must
  agree" actually holds at the tolerance boundary.
- Digit shapes cannot differ between a cached display string and a fresh one.
- **Accepted deliberately:** Eastern Arabic-Indic digits (٠١٢٣) are not offered, even though some
  Arabic readers prefer them. UAE financial figures are conventionally written in Western digits,
  and consistency with the server's formatting wins over the more locale-pure choice.
- Phase 1 pays a small ongoing cost (every string via a catalogue) to avoid a large Phase 5 one.
  Phase 5's remaining work becomes translation plus a genuine RTL *review*, rather than relayout.
