# ADR-0003 — The server converts *and formats* money; the client never computes it

**Status:** accepted
**Amends:** Technical Spec §1 (FX leaves the iOS content cache), §5 (`GET /v1/budget` states its
currency; monetary fields gain display strings; `GET /v1/expenses` returns per-category totals)

## Context

Product Spec §4.1 says display goes "via the `HWMoney` conversion layer, converting **once, at
read**" — but never says which side of the wire that layer sits on. The evidence in the specs
points both ways:

- `GET /v1/budget` (§5) returns `income`, `needs`, `saved`, `surplus` with **no currency
  stated**, which only makes sense if the server has already converted.
- Technical Spec §1's diagram gives the iOS app a content cache of "curriculum, tips, articles,
  **FX**" — a client-side FX cache is only useful if the *client* converts.

The formatting rules are the sharper half. §4.1's magnitude-aware rounding (nearest 100 above
100,000, nearest 10 above 10,000), symbol spacing (`AED 500` vs `₹500`), and "round at the
leaves and derive totals from unrounded values" are **business rules**, not presentation
trivia. Defects D10, D11, and D16 were each produced by one rule living in two places.

A further problem for any client-side summing: money is stored **as authored** (§4.1), so a
single month legitimately contains entries in different currencies.

## Decision

**The server converts and formats.** Every monetary field in every response carries both the
exact `Money` (`{minor, currency, exponent}`) and a **display string**, formatted server-side
honouring `Accept-Language`.

**The client renders display strings.** It never converts, never rounds, never applies symbol
spacing, and never sums server-supplied values.

**No FX cache on the client.** FX leaves Technical Spec §1's iOS cache list.

**Changing display currency is online-only** — it is a `PUT /v1/me/currency` followed by a
refetch, so it required the network regardless.

**`GET /v1/expenses` returns per-category totals**, so §3.4's per-category running total is not
a client computation.

**One exception, narrowly scoped:** the client may sum the `minor` units of its *own pending*
entries to produce ADR-0004's pending badge. Those are single-currency by construction (the
user's display currency at entry time) and never mixed into a server figure.

## Consequences

- Swift never holds a floating-point monetary value, and never holds a rounding threshold.
- Summing a response's entries client-side *looks* safe once responses are single-currency —
  which is exactly why it is dangerous: the safety would be a property of a response shape
  nobody wrote down, and the day a mixed-currency payload appears the result is silent nonsense.
  Removing the capability removes the class of bug.
- Payload grows by a handful of short strings per response. Accepted.
- Requires Technical Spec §5 to state the budget response's currency explicitly, which it
  currently does not.
- Offline, the app renders the display strings it last received. They are correct for the
  currency then in force; currency switching offline is unavailable by design.
- ADR-0016 carries the one place a currency symbol is assembled client-side — `{c}` in tip text
  — and it uses server-supplied metadata so the spacing rule still has a single owner.
