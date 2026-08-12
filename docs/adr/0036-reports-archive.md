# ADR-0036 — The Reports archive: one verdict table, two orderings, and an inert row

**Status:** accepted
**Issue:** #21 — Reports: month archive and savings-goal trend chart
**Builds on:** [ADR-0020](0020-screen-scoped-endpoints.md) (screen-scoped endpoints),
[ADR-0016](0016-presentation-details.md) (chart tooling by kind),
[ADR-0012](0012-accessibility.md) (replace, never shrink),
[ADR-0032](0032-home.md) (the donut-versus-meter rule)

## Context

Reports is the retrospective: which months have closed, what each cost, and whether the savings goal was met.
The design draws it as one galaxy hero — a savings-goal trend chart with a dashed goal line and three summary
figures — over an archive of month rows grouped by year.

It is also where **defect D11** lives. The prototype carries *two disagreeing goal-verdict threshold tables* for
the same pill on the same number: Reports thresholds at 100/70 and Home at 80/45. Product Spec §4.2 settles it —
one table, 100/70, server-computed — and says the client never derives it.

Everything else on the screen was derived in the browser too. `spentTotal(m)` summed six categories per month,
`paintHero()` averaged those six totals and reduced the saved figures, `paintList()` kept a running year and
re-filtered the whole archive to total each group as it rendered, and `goalPct(m)` divided saved by goal so
`verdict(m)` could threshold the quotient.

Two further questions had to be answered before anything could be drawn. The month detail — one closed month in
full — is **#22**, so the design's row is a button with nowhere to go. And the design's own seeded archive is six
months of one year, which makes "grouped by year" unobservable.

## Decision

### One `GET /v1/screens/reports`, and nothing in it to threshold

The payload carries the archive **already grouped**, with each year's savings total, and the trend's bars with
their heights, their percentages, and their verdicts. `ReportsViewModel` is the shortest view model in the app: it
holds no presentation state at all, because an archive is a record — there is nothing to choose about it and
nothing to type into it.

The client's half of §4.2's settlement is **absence**. No `saved`, no `goal`, and no percentage as a number
reaches it, in any month or any bar; a percentage arrives as a sentence and a verdict arrives as a verdict.
`ReportsViewModelTests` asserts that against the *wire* rather than against the decoded type, because a
`Decodable` ignores keys it does not name — a server that started sending `saved` per month would be invisible to
a test that only read `ReportsScreen`.

The same absence is why the corpus checks no arithmetic here: with no per-month `saved`, there is no sum for a
test to verify and none for a client to make.

### `hit` / `near` / `miss`, and this one **refuses to guess**

`HomeScreen.Verdict` names the design's three pill classes — `low` / `onTrack` / `met` — for the live month.
Reports names §4.2's table's own three words. Two names for one rule is a translation, not a second rule: both
arrive computed, and neither screen can threshold anything.

Home's verdict **degrades** an unrecognised value to the neutral one. Reports' **fails the screen**, and the
difference is what the value describes. Home's pill is about a month still running, so a hedge is a hedge about
something that has not happened. Reports' is about a month that has closed and is immutable (invariant 7): a
fourth verdict drawn as `near` would tell a reader that a month they smashed or missed outright nearly hit its
goal, and it would keep saying so for ever. An archive whose story changes is what invariant 7 exists to prevent,
so a fourth verdict is a coordinated release — exactly as `ExpensesScreen.Kind` and `LearnScreen.LessonState` are.

### Two orderings, both sent

The trend reads oldest to newest, because time reads that way; the archive reads newest first, because the month a
reader wants is the one that just closed. Ordering is a calculation (ADR-0020), so the payload carries both arrays
rather than one the client sorts twice. `FixtureCorpusTests` asserts that every bar and its month row carry the
same verdict and the same percentage — the same number thresholded twice inside one assembly would be D11 moved
from the client into the server.

### `BarMark` plus a dashed `RuleMark`, and the heights are the server's

ADR-0016 already chose the tooling. What this ticket adds is that **both come from the server as fractions of the
plot area** — `Bar.fill` and `Trend.goalPosition` — and the y-domain is fixed at `0...1`. The design scales the
chart to `max(125, tallest × 1.08)` so a good month has headroom to overshoot; a bar's extent and the goal line's
place are two readings of that one scale, and a client computing either could draw a bar at 101% *below* a line at
100% — the chart contradicting the badge beside it, which is D11's shape in pixels.

**A raw percentage would not do**, which is the alternative worth naming because it is the obvious one: sending
`91` and letting the client scale it hands the client the number D11 was about, and makes it apply the headroom
rule as well. A fraction of the plot is the only form that is both drawable and unthresholdable. The cost is real
and accepted — `0...1` of a 74pt plot is a fact about *this* view, so a second renderer would inherit a scale it
cannot see — and it is the same trade `Wants.fill` and `Savings.position` already made (ADR-0032, ADR-0033).

The chart is keyed on `monthKey` rather than on the label: two Februaries in two years share a label, and a
category axis keyed on the label collapses them into one bar.

### The chart is replaced by rows; the proportion bar is not

`hwVisualisation(describesItself: true)`, so every `BarMark`'s own descriptor is what VoiceOver reads below the
threshold and a list of month rows with verdict badges is what replaces the plot above it. Each bar's descriptor is
a **server sentence** — "February 2026, 91% of goal, ₹11,830 saved" — which is what the design puts in a `title`
attribute that touch never surfaces.

The month row's `.m-bar` is the one visualisation in the app that is **neither clamped nor replaced**. The clamp
pattern exists for fixed-layout figures that break when type grows; this holds no text at all — no label, no axis,
no legend, and no `aria-label` in the design either — so there is nothing to grow and nothing to overlap. Its
replacement would be itself.

### The affordance arrives with the destination

`HWMonthRow` takes an optional action. Without one it is a row: no chevron, no button trait, and no tap. #22 passes
a closure and the row becomes the design's control. A chevron pointing at an unwritten screen is the same broken
promise in a smaller font, and the hint copy that describes the tap arrives with the tap rather than sitting in the
catalogue as a sentence nothing shows.

Reports pushes its own detail rather than being handed a route by the shell: unlike Home's two destinations, which
are *tabs* the shell owns the selection of, a month is a page inside this tab.

### The design's verdict colours had two owners already, and now have one

`.m-badge.hit/.near/.miss` on the archive and `.mf-r` with its `.warn` and `.low` variants on the savings meter are
the *same three* soft/ink pairs, written twice in the CSS. `HWSavingsMeter` had been drawing a **third** treatment —
a saturated fill with milky ink, picked rather than transcribed — so the app held two colour tables about one
verdict, which is the shape D11 took about a threshold table. There is one `HWVerdictBadge` now, one
`HWPalette.Verdicts` behind it, and the meter maps its three pill states onto the same three.

The trend's bars are the *other* treatment and keep their own owner: the design colours them off the savings
ombré's `--r5` / `--r3` / `--r1`, because a pastel wash is invisible on the galaxy card. `HWPalette.Meter.stop(for:)`
sits beside the gradient it picks from.

### The fixture spans two years, and the seeded months are not a contract

Product Spec §3.6 seeds Feb–Jul 2026, and the ticket says explicitly not to treat their shape as a contract. So
`reports-inr.json` keeps the design's six months and its *percentages* — one of each verdict, two met in six, as
§3.6 counts them — re-denominated in the rupees the rest of the corpus is authored in, with the goal left at
₹13,000 across a salary rise, which is §4.2's rule that a raise does not move the target. `reports-two-years.json`
is three months across a year boundary, because one year group proves that a header renders and nothing about the
grouping.

`reports-empty.json` is the third, and it makes `SnapshotCase.empty` a real screen's empty state at last: this is
the first `LoadState.empty` the app can reach — Expenses' first run keeps all seven categories and is `.loaded`,
and Home's keeps four of its five cards.

## Consequences

- **Six new colour sets** in the catalogue, transcribed from the design and asserted at 4.5:1 ink-on-wash rather
  than trusted. The verdict badge is the one pair on this palette where the ink travels with the fill.
- **Three new geometry `Double`s** in `Models` — `Bar.fill`, `Trend.goalPosition`, `Segment.share`. Two of
  the three **borrow the names already exempt** in `MoneyFormattingAbsenceTests` rather than adding `height` and
  `width`: that scan matches on the declaration text, and `height`/`width` are generic enough that any future
  `Double` called either would pass in silence, where `share` and `fill` name a *quantity* and would be a lie on
  anything else. Review caught the first version doing it the generic way, so the allow-list grew by one
  distinctive name instead of two vague ones.
- **`Swift Charts does not carry the app's environment objects into axis content.`** An `AxisValueLabel` reading
  `ThemeManager` traps inside a chart that was itself rendered inside one, which `ReportsViewTests` found by
  photographing the page. The manager is read in the `body` and re-injected around the label. Worth knowing before
  the next chart: the same trap is waiting in any `.chart*Axis` content that uses a design-system modifier.
- **An unused `@Environment` of a non-optional observable object is not free.** `ReportsArchivePage` declared one it
  never read, and the page trapped in a render whose theme was installed *outside* it.
- `TabViewModels` gains its third real view model and Account is the last placeholder. `ReportsViewModel` is the
  only one that takes nothing but the client: the archive is per-user and has no cacheable half.
- **`/v1/screens/reports/:monthKey` is deliberately not declared yet.** A path with no caller and no payload is a
  guessed contract sitting in the client, which the corpus's coverage scan exists to keep out. It arrives with #22.

## What this leaves

- The **month detail** (#22): the split bar, the entry accordion, the facts grid, and the invariant-7 regression
  test that a currency change repaints the figures and never the verdict. It also brings the row's chevron, its
  hint copy, and `navigationDestination`.
- **Nothing about the archive is refreshable.** There is no pull-to-refresh anywhere in the app yet; the chrome's
  `.task` is the only load, and the retry is `StateView`'s. An archive changes once a month, so this is the last
  screen that would want one.
