# ADR-0016 — Chart tooling by kind, one state taxonomy, server-keyed tip selection

**Status:** accepted
**Amends:** Product Spec §6 (amounts inside tips are illustrative and never converted)

## Context

Three separate things get called "charts" in the specs and they do not want the same tool: the donut
needs tap-to-isolate (§3.3), the trend chart needs hit/near/miss bars against a dashed goal line
(§3.6), and the savings meter is a red→green gradient with a sliding pin and a percentage pill
(§3.3).

Five tabs times four data states is twenty-plus screens; without a shared taxonomy each gets
bespoke copy and bespoke VoiceOver.

And §3.3 selects the tip of the day from 49 by day-of-year with `{c}` tokens "resolved to the
display currency" — but resolving them server-side would make `GET /v1/content/tips` a **per-user**
response, while invariant 8 lists it as **cacheable**. The spec quietly wants two incompatible
things.

## Decision

**Charts, split by kind.** Donut → Swift Charts `SectorMark` with `chartAngleSelection` for
isolate. Trend → `BarMark` plus a dashed `RuleMark` goal line. Savings meter and the four-segment
split bar → **hand-built** with `LinearGradient` and shapes; they are not charts, and Swift Charts
has no gradient-track-with-pin primitive — forcing one produces worse code than a small
`GeometryReader`.

**One state taxonomy.** `LoadState<T>` in `HWCore` plus a single `StateView` in `HWDesignSystem`
covering loading / empty / offline / failed, each screen supplying copy and CTA. Two rules:

- **`offline` is never styled as `failed`** — offline is a supported mode (§3.4, ADR-0004), not a
  fault.
- **Never display the server's `message` field.** Map `error.code` to localised copy in one place;
  an unmapped code shows a generic message.

**Tips keep `{c}` verbatim and stay cacheable.** The client substitutes using server-supplied
currency metadata (code, symbol, spacing), so ADR-0003's spacing rule still has exactly one owner.
Day selection uses a **server-supplied `dayKey`**, never `Date()`. "Show me another" cycles in
memory, resetting next launch.

## Consequences

- `SectorMark` supplies per-mark accessibility descriptors that a hand-rolled donut would not
  (ADR-0012), so the tool choice pays for itself twice.
- Sending `{c}` verbatim is also what §6 already mandates ("`{c}` currency tokens preserved
  verbatim"), so server-side resolution would have contradicted the content spec as well as
  invariant 8.
- Using a server `dayKey` keeps the device clock out of tip selection. Cosmetic on its own, but this
  is a codebase whose streak design exists specifically to avoid device-clock dependencies, and one
  exception invites others.
- **The amounts inside tips are illustrative and are never converted.** "Save {c}500 a month" means
  something quite different as ₹500 than as AED 500, so this is a **content-authoring constraint**
  for §6, not something code can fix.
- Without the error-code mapping, an Arabic user would read English server prose in every failure
  state.
