# ADR-0021 — The design has two surfaces, and its tokens are collapsed on the way in

**Status:** accepted
**Amends:** the workspace `CLAUDE.md` iOS conventions ("Light-only theme" needs one word of
clarification)
**Context for:** issue #6, and every screen ticket that draws with these tokens

## Context

Issue #6 asked for the palette, type scale, and motion curves "extracted from the CSS custom
properties … the design's own values are the source of truth; do not re-pick them by eye". Extracting
them turned up several things the ticket did not anticipate, each needing a decision rather than a
transcription.

## Decision

### The design has two surfaces, and neither is a dark mode

`landing` and `auth` are **galaxy-backed** — `--text: milky`, `--muted: venus`,
`--card: rgba(sky, .07)`, on a near-black ground. The five in-app screens are **light** —
`--bg: milky`, `--card: #FFFFFF`, `--ink: galaxy`.

The clearest evidence that this is two surfaces rather than a light and a dark theme is `--danger`,
which has **two different values**: `#C0453A` in-app and `#FFC9C0` on auth. A single role, two
surfaces, both shipping at once.

So `HWPalette` has a `surface` group and a `brand` group, and the asset catalogue has exactly **one
appearance** per colour set. `CLAUDE.md`'s "light-only theme" means *one appearance ships, no dark
variant* — it does not mean every screen is light, and the pre-auth screens never were.

A dark appearance sneaking into the catalogue one colour set at a time is exactly how "architected
for, not shipped" erodes, so `ColorAssetTests` asserts no set declares an appearance variant.

### The tokens are collapsed, deliberately

The design is a prototype and its numbers say so: **33 distinct font sizes**, many separated by half a
pixel; **29 corner radii** from 2 to 46pt; **20-odd animation durations**. Shipping all of them would be
transcription, not a design system — the point of a scale is that a screen cannot pick 320ms over 300ms
and call it a decision.

- **Type: eight steps**, by frequency cluster. Each is anchored to a `Font.TextStyle`, not a fixed
  point size, because that is what makes text scale to AX5 unclamped (ADR-0012). The cost is that a
  step lands on Apple's metric rather than the design's exact pixel; the deltas are recorded on each
  case.
- **The smallest step rounds up.** The design's eyebrows are 9–10.5px. Apple's smallest text style is
  11pt, and shrinking to match the prototype would make the smallest text in a financial app harder
  to read. Rounding up is the accessible direction and it is intentional.
- **Radii: six steps.** The design has **29 distinct radii from 2 to 46pt**. Five are a ladder; the
  sixth is `pill`, because 30 / 38 / 46 account for 22 uses and every one of them is a pill-shaped
  control whose radius is really "half my height". A fixed number would be a pill at exactly one
  height, so `pill` is an absurd radius that SwiftUI clamps — `Capsule()` where the shape stands alone.
- **Durations: four**, from the design's frequency distribution: 200ms (64 uses), 250ms (60), 420ms
  (17), 500ms (22). Beware when re-counting — a regex matching `\b[\d.]+(ms|s)` reads `.2s` as `2s`
  and inflates everything by a factor of ten.

### `--ease-back` has two spellings; the majority wins

Five documents say `cubic-bezier(.34,1.4,.5,1)`; `learn` says `.34,1.5,.5,1`. The majority value
ships. Averaging them would invent a third curve nobody drew, and silently matching `learn` would
make four screens wrong.

**`Animation` is not the token; `HWCurve` is.** Issue #6 asks for the curves "as `Animation`
constants". An `Animation` cannot be read back, so the design's control points would be unassertable
and the "do not re-pick them by eye" rule unenforceable. The token is therefore a value type carrying
the four control points, with `animation(_:)` composing it against a duration.

**Issue #6 says "the two easing curves"; there are three.** `--ease-out`, `--ease-io`, and
`--ease-back` are all used, and `--ease-back`'s overshoot is a distinct effect rather than a variant
of the other two. All three ship, and a test asserts that only `easeBack` overshoots — "tidying" its
`1.4` down to `1.0` would quietly turn it into an ordinary ease.

### Shadows and radii ship too, though the ticket did not list them

They are CSS custom properties in the same `:root` block as the colours and curves the ticket does
name (`--shadow-s/m/l`, `border-radius`), and `Components/` (#26) cannot build a card without them.

Two conversions change the numbers, and both matter:

- **CSS blur is roughly twice SwiftUI's shadow radius.**
- **CSS spread has no SwiftUI equivalent, and every one of these shadows uses a negative spread** to
  pull the shadow in. Dropping it would make each shadow materially larger and darker than drawn, so it
  is folded into the radius: `radius = (blur + spread) / 2`. `--shadow-m: 0 12px 28px -12px` gives 8,
  not 14.

## Consequences

- **`Reports` deviates and was not followed.** It uses `--bg: #FDFEFF` / `--bg-2: #F1F6FF` — "a
  whisper of Sky in the white", per its own comment — where the other four in-app screens use
  milky/meteor. The canonical pair ships. Issue #21 should either adopt the canonical background or
  make the whisper a named token; it should not hardcode the deviation.
- **The six category slots carry a constraint, not just values.** The design states that every slot
  clears 3:1 on the white card and that the order alternates cool/warm so neighbouring donut wedges
  stay apart for colour-blind users. The contrast half is now asserted; the alternation is preserved
  by keeping slot *order*, so change hues rather than positions.
- **The fifth Learn accent is spelled differently in the design.** Four are triads (`--sun`,
  `--mint`, `--coral`, `--violet`, each with `-soft` and `-deep`); the fifth comes through the palette
  as `--acc: planetary` / `--acc-soft: sky` / `--acc-deep: galaxy`. All five are exposed with the same
  shape so a unit can be styled without knowing which one it got.
- **`ThemeManager` is an indirection with one implementation**, and it is worth having only because
  ADR-0001 promises the dark palette is a swap. `apply(_:)` has no caller: `@Observable` on a type
  whose properties can never change is decoration, and that method is the mutation the macro exists to
  broadcast.
- **Colour values are asserted, not just resolved.** `ColorAssetTests` checks every set against the
  design's hex, so a nudged hue fails a test rather than shipping. That is the only way "do not
  re-pick them by eye" survives contact with a future editor in Xcode.
- **The `on-` prefix was abandoned as a naming convention.** `hwOnSurface` implied ink that belongs on
  `hwSurface`, but the design has one `--ink` used on both the card *and* the ground. The assets are
  `hwInk` / `hwInkSecondary` / `hwInkTertiary` — the design's own role names, which do not promise a
  pairing that does not exist.
- **No raw palette name reaches a use site, and that is now scanned.** `--universe` was briefly
  exposed as `hwUniverse`, which is the same defect as `Color.galaxy` one name over; it is used at
  ~35 sites for secondary text and borders, so it is `hwAccentMuted`. `LayeringTests` now fails on any
  of the seven palette names appearing anywhere.
- **The fifth unit accent reuses the accent colour sets** rather than carrying three byte-identical
  copies of them, which is what the design does too (`--acc: planetary`).
- **Rejected:** an asset-catalogue dark appearance for the landing and auth surfaces. It would make
  the pre-auth screens follow the device's appearance setting, which is not what the design does — they
  are galaxy-backed always.
- **Rejected:** shipping the design's exact pixel sizes with `.system(size:)`. Faithful at the default
  Dynamic Type setting and pinned at every other, which fails ADR-0012's parity requirement.
