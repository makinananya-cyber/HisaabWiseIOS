# ADR-0029 — Landing: the illustration is an asset, the brand button arrives, and the screen scrolls

**Status:** accepted
**Extends:** [ADR-0021](0021-two-surfaces-and-token-collapse.md) (two surfaces; the `brand` appearance was
parked until it had a caller), [ADR-0012](0012-accessibility.md) (unclamped type; Landing is its named
exception for motion)
**Applies:** Product Spec §3.1 **[FIX]** — the strapline that named a currency

## Context

Landing is the first screen converted from the design, and it is static, so everything difficult about it is
conversion rather than data. Six questions, and the last two were found by looking at the running app rather
than by reasoning.

**The hero illustration is a 5 KB inline SVG** — an open book on a hand, growth bars, a coin, orbit rings,
drifting dots — with about thirty path elements and six CSS-driven animations.

**The call to action has no vocabulary entry.** `Components/` resolves the `surface` appearance only, and
`CONTEXT.md` parked `brand` until "two callers shape it better than one guess".

**Landing has no request**, which the base contract has no shape for: `BaseViewModel` *is* one request and the
mapping of its outcome.

**The design is one fixed viewport.** `justify-content:space-between` on a 390×844 frame assumes the content
always fits.

**Two things only the running app said.** At AX5 the first build drew the headline through the strapline and
pushed the footnote off the bottom. And in Arabic the wordmark read "WiseHisaab".

## Decision

**The illustration ships as an SVG asset, extracted verbatim.** `hwHeroBook` in the asset catalogue, with
`preserves-vector-representation`. The alternatives were both worse: hand-translating thirty `d` attributes into
SwiftUI `Path`s is a page of unreadable numbers with no way to tell a transcription error from a design choice,
and rebuilding the illustration from primitives is re-picking by eye, which ADR-0021 forbids. Xcode renders its
gradients, opacities, and strokes correctly — verified on the simulator, not assumed.

Three consequences, all accepted. **Its six internal animations do not ship** — the hand rising, the pages
opening, the bars growing, the trend line drawing, the coin flipping, the rings turning — because they are CSS
on classes the asset carries but nothing reads. The asset needed **two opacities baked in**: `.aura` and `.fan`
get theirs from CSS alone, so without it they rendered at full strength; both are now attributes at the value
the design's own `prefers-reduced-motion` block settles them at, so the asset is the illustration exactly as a
motion-sensitive reader sees it. And **the illustration's colours sit outside the palette seam**: seven hexes
are baked into the SVG, so the dark palette ADR-0001 promises as "a swap" would not reach them. Recorded rather
than solved — an asset catalogue cannot resolve a colour set inside an SVG, and the alternatives are the two
this decision already rejected.

**The `brand` appearance arrives, and the design settles it rather than a guess.** `HWAppearance` is a
parameter on `HWButton`, defaulting to `surface`. The reason it is safe with one screen rather than two: the
landing `.cta` and auth's `.btn-primary` carry the *same* fill and the *same* ink, two points of height apart —
so this is the second half of a control the vocabulary already had. Brand buttons are **pills**: the design's
radii are `29` and `30` on controls it draws at 58 and 60, which is half the height, and `HWRadius.pill` is what
"half my height" means for a control whose height is a *minimum* here (`HWButton.minimumHeight` is 52 and grows
with the type). In-app buttons keep the 18pt card radius. **Two variants share one treatment on brand**, folded
into a single arm so the collapse is visible: the design has no `.btn-soft` there and its secondary filled
control *is* `.btn-ghost`. `HWButtonTests` states that as an exception to "no two variants draw alike", which
holds on `surface` and cannot on `brand`, and asserts that no variant looks the same on both surfaces.

**Landing is not a `BaseView` and its view model has no `fetch()`.** It also holds an **index, not the words**:
copy lives in the presentation layer where `LocalisationTests` looks for it, and a String Catalogue key in
`ViewModels/` would read as an orphaned entry. And it owns no clock — the view's `.task` calls `advance()`,
which is what lets Reduce Motion suppress the rotation by never starting it.

**Reduce Motion removes the rotation rather than replacing it**, which is ADR-0012's own exception: "one
strapline, stable for the session". A strapline that changed without animating would be a caption rewriting
itself under the reader. Nothing else on the screen moves either.

**The aurora band ships; its grain does not.** The design layers four things behind the content: two large
soft blobs (planetary off the top-left, universe off the bottom-right, each a radial fade to nothing at 68%
with a 6pt blur), an eight-point star field at its own fractions and its own three inks, and `.grain` — a
3%-opacity fractal-noise SVG tiled over everything. The first three are transcribed. The grain is dropped:
SwiftUI has no `feTurbulence`, and the alternatives are a noise image asset or a `Canvas` of random dots, which
at 3% is texture nobody can name. The stars are the design's eight rather than a random field, because a
`Canvas` of random points would be a different sky on every launch and these were placed.

**Five animations ship, four do not.** Shipped: the strapline rotation (the criterion) **with the design's own
asymmetric transition** — out upward, in from below — which needs an `.id()` on the `Text`, since SwiftUI does
not animate a string in place and without it the sentence hard-cuts for everybody; the entrance stagger
(the design's six transcribed delays — `0`, `.12`, `.30`, `.52`, `.76`, `.98`, which accelerate, so they are a
list rather than a formula), the hero's 6-second float, and the pill dot's pulse. Dropped: the headline sheen
(the gradient itself ships, static — it is the visual; the sliding is not), the button sweep, and the ring
around the wordmark, the star field's `twinkle` — an opacity oscillation on a half-transparent 1.4pt dot — and
the arrow's `nudge`. Ambient loops measure their period in seconds, so `HWCurve.loop(seconds:)` exists beside
`animation(_:)` — the four-duration scale is for *transitions*, and rounding a 6-second breath into 500ms would
make it twitch.

**The screen scrolls when the type outgrows it.** A `ScrollView` whose content has a minimum height of one
screen: when everything fits the spacers spread it exactly as `space-between` does and there is nothing to
scroll, and when the type grows the screen grows with it. The design's fixed viewport is a web assumption, and
AX5 is where it fails.

**The wordmark is one `Text` carrying an `AttributedString`.** The design is one text node with a styled span,
and that is what an attributed string is. Both alternatives are wrong: `Text + Text` is how an untranslatable
sentence gets assembled and is banned app-wide, and two `Text`s in an `HStack` **reorder under RTL** — which is
how the wordmark became "WiseHisaab" in Arabic. A brand name is one word whichever way the layout runs.

**The strapline is a labelled element whose *value* is the sentence.** The design marks it `aria-live="polite"`,
which re-reads it every 3.8 seconds; on a screen whose only action is one button, that is a screen talking over
its own user. Issue #13's criterion is that the rotation "does not interrupt or re-announce", so the label is
static ("What HisaabWise does") and the sentence is the accessibility *value*.

**The [FIX].** "Every rupee, tracked without thinking about it." becomes "Every expense, tracked without
thinking about it." The app shows the currency the user is paid in, formatted by the server (ADR-0003), so copy
that names one is wrong for everybody it is not. A test scans all four straplines for currency words, so the
original cannot return in a translation pass.

**Get Started navigates for real.** `PreAuthRoute` with one case and a `NavigationStack` in the signed-out
branch of the root, so the button goes somewhere rather than being the third dead control in this repo. The
destination is a placeholder reusing the unwritten-screen sentence; #14 replaces one `case`.

## Consequences

- **`ImageRenderer` draws neither a `TabView` nor a `NavigationStack`** — both come back as the unsupported-view
  glyph, byte for byte identical. The root's two branches were being compared as pixels, which meant that
  assertion would have passed with the branch inverted. `RootView.world(isSignedIn:)` is now the decision as a
  value, and the render is a smoke test that says so. Worth knowing for #9's snapshot harness: the third thing
  in this app that needs a hosted capture.
- **A blind spot in the localisation scan is closed.** It skipped any line naming an SF Symbol, so
  `HWButton("landing.cta", systemImage: "arrow.forward")` lost its key — and the loss showed up as an
  *orphaned catalogue entry*, which reads like the opposite problem. It now cuts the symbol argument out of the
  line instead of skipping the line.
- The wordmark's tile stays 34pt while its text scales, so at AX5 the lockup is unbalanced. That is Dynamic
  Type working: the tile is an image and the name is text.
- **Auth (#14) inherits three things**: the `brand` button appearance with its ghost and quiet variants already
  transcribed, `hwEnters(step:suppressed:)` for the same entrance stagger, and `PreAuthRoute` to be a case of.
- The illustration is 5 KB of SVG in the app bundle. The `.mark` PNG (#5) and this are the only images the app
  ships.
