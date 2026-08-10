# ADR-0020 — Every calculation is server-side, and reads are screen-shaped

**Status:** accepted
**Amends:** Technical Spec §5 (the read surface becomes screen-scoped; writes return the updated
screen payload); Product Spec §3.3–§3.7 (no figure on any screen is derived client-side)
**Extends:** [ADR-0003](0003-money-presentation.md) from money to every derived value
**Decided by:** the project owner, 2026-08-10

## Context

ADR-0003 already put money conversion and formatting on the server, and invariant 3 already put the
budget engine there. But the rule was scoped to money, and plenty of derived values on these screens
are not money:

- "% of pay" on Home, and the savings percentage in the meter pill
- the date labels "Today / Yesterday / N days ago" on Expenses
- per-category running totals
- Learn accuracy, XP totals, streak counts, and progress-ring fractions
- the goal verdict — which the prototype computed two different ways (defect D11)
- per-year savings totals on Reports

Each is a calculation, and each is one a client could plausibly do. The resource-shaped contract in
Technical Spec §5 invites exactly that: `GET /v1/budget` returns figures, `GET /v1/expenses` returns
entries, and Home also needs a tip, a streak, and an article list — so the client ends up composing
four responses and deriving the join. The moment it derives the join, it is calculating.

## Decision

**Every calculation is server-side. The client renders.** No screen derives a figure, a percentage, a
count, a date label, a verdict, a total, or an ordering. If a value appears on screen, a response
contained it.

**Reads are screen-scoped.** One endpoint per screen, returning exactly what that screen renders,
fully formatted:

| Screen | Endpoint |
|---|---|
| Home | `GET /v1/screens/home` |
| Expenses | `GET /v1/screens/expenses` |
| Learn | `GET /v1/screens/learn` |
| Reports | `GET /v1/screens/reports` |
| Reports — one month | `GET /v1/screens/reports/:monthKey` |
| Account | `GET /v1/screens/account` |

**Writes stay resource-shaped, and return the updated screen payload.** `POST /v1/expenses`,
`DELETE /v1/expenses/:id`, `POST /v1/learn/lessons/:id/complete`, `PUT /v1/me/*` keep their own
addresses — a write is not a screen. But each returns the same payload the screen endpoint would,
so the client re-renders from server truth instead of patching its own copy. This is what removes the
last temptation to calculate: there is no local state to keep consistent.

**Cacheable content stays separate.** Invariant 8 lists `/v1/content/*`, `/v1/curriculum*` as
cacheable; folding them into a per-user screen response would make them per-user and throw that away.
So:

- **Inline in the screen payload:** the *selected* tip of the day (one tip, server-chosen by `dayKey`,
  small) and article *teasers*.
- **Separate and cacheable:** article bodies, the curriculum, and the reference lists (countries,
  currencies, the security-question bank), each ETag'd and held in the content store (ADR-0009).

**One deliberate exception, already on the record.** Invariant 10 makes Learn grading client-side for
responsiveness, and that is a calculation. It stays, unchanged: the client grades to keep the lesson
responsive, submits per-question results, and the server recomputes XP and rejects impossible
submissions. The client's answer is never authoritative. Nothing else in the app gets this treatment.

Local input validation — is this a well-formed number, is this email shaped like an email — is not a
calculation in this sense. It never produces a displayed figure and the server revalidates.

## Consequences

- **A screen change becomes a backend change.** This is the real cost of screen-shaped endpoints and
  it is the usual objection to them. Accepted: the alternative is a client that composes and therefore
  derives, which is how D1, D10, D11, and D16 all happened.
- **The client cannot drift from the server**, because there is nothing for it to drift *with*. Every
  card on Home agrees on `saved` for the structural reason that one response carried all of them —
  the D1 regression test becomes hard to fail rather than merely tested.
- **Date labels come from the server.** "Today / Yesterday / N days ago" is computed against the
  server-owned day boundary in the user's stored timezone (invariant 6), so a device-clock change
  cannot relabel an entry — which the client version would have allowed.
- **One request per screen instead of four**, which matters more on a UAE mobile connection than the
  extra payload costs.
- **View models get simpler and thinner.** `fetch()` becomes a single call, and `BaseViewModel`'s
  single-request shape (#11) fits every screen rather than needing a compose-several-requests variant.
- **`Money` still holds no arithmetic**, and now neither does anything else. The existing source scans
  keep formatters out; the enforcement for the rest is that the models carry no derived fields to
  compute *into*.
- **Fixtures get bigger and more screen-shaped**, which is a fair trade: a fixture that is exactly one
  screen's payload is easier to read and to keep honest than four that must be composed correctly.
- **Six new endpoints are a backend commitment**, recorded in `CONTEXT.md`. They do not exist and
  `HisaabWiseBackend` has no `src/`, so every screen ticket is built against fixtures shaped to this
  contract and wired when the routes land. Agree the payload shapes with the backend before building
  rather than inventing them per screen.
- **Rejected:** folding cacheable content into the screen payloads to get a literal single request.
  It would turn a CDN-cacheable curriculum and three long-form articles into per-user bytes re-sent on
  every screen load.
- **Rejected:** keeping the resource-shaped read surface and forbidding composition by convention.
  The convention is what has failed before.
