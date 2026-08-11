# ADR-0026 — Shell plumbing: a `TabView`, five held view models, one exit, and one reader of `scenePhase`

**Status:** accepted
**Extends:** [ADR-0001](0001-platform-baseline.md) (iPhone-only, portrait-only),
[ADR-0014](0014-privacy-surfaces.md) (the switcher overlay), [ADR-0021](0021-two-surfaces-and-token-collapse.md)
(`surface` and `brand` ship together)
**Changes a recorded fact:** the design's `.mark` now *has* an asset — see the last consequence

## Context

Issue #5 is "the app you can navigate", and the navigation is the easy part: a `TabView` with five tabs is
half a screen of code. Five other questions are not.

**Where a tab's view model lives.** The criterion says "created at the composition root and injected via
`@Environment`", and neither half is free. A view model created in a `body` is re-created on every re-render,
which resets a screen every time the user switches away and back — and the reset looks like a slow network
rather than a bug. Injecting five of them individually does not work either: four are the same type today, so
they would overwrite each other in the environment. And a screen cannot read `AppEnvironment` instead, because
that holds the `APIClient` and `LayeringTests` keeps the networking layer out of `Views/`.

**What the four unbuilt tabs are.** The shell is five tabs and four of the five screens are other tickets
(#18, #19, #21, #23). They still have to be `BaseView` conformances, because that is a criterion — so
something has to stand in, and what it does when it stands in is a decision.

**Where log out lives, and how many of them there are.** "The only exit is log out" is a claim about the whole
app, not about one button, and nothing in a `TabView` enforces it.

**Who reads `scenePhase`.** Two features need it — ADR-0008's foreground sequence and ADR-0014's privacy
overlay — and the note left on `HisaabWiseApp` said the shell would take both over.

**How a signed-out user gets back in.** Landing is #13 and sign-in is #14. Both are open.

## Decision

**A `TabView`, and the design's `.tabbar` is not converted.** Re-implementing a system container would mean
re-implementing the safe-area inset, the material, the selection semantics, and VoiceOver's "tab 2 of 5" —
Rule 1 rules it out and it would be worse at all four. The design's *decisions* are converted instead: labels
always visible under the glyphs, and selection marked with `--galaxy` through `surface.ink`. Its five stroke
icons become the SF Symbols that draw the same things — `house`, `creditcard`, `book`, `chart.bar`, `person`.

**A `NavigationStack` per tab**, wrapped by the shell rather than by each screen: a screen that owned its own
stack could be pushed onto another one.

**`TabViewModels`, made by the composition root and injected.** Five named properties rather than a
dictionary, so every tab has one by construction and nothing unwraps an optional in a `body`. It conforms to
`Observable` by hand rather than through the macro, which is the honest spelling: every property is a `let`,
and what changes is the state *inside* each view model.

**Its lifetime is the session's.** The root replaces the whole set when `isSignedIn` goes false, because a view
model holds the last response it got — a signed-out `HomeViewModel` is still holding a salary, and the next
sign-in would paint the previous user's figures for the frame between the shell appearing and its `.task`
running `load()`. Invariant 8's reasoning about caches applies to objects too: per-user data that outlives the
user is a leak, not a warm start. It is the *root's* job rather than `SessionCoordinator`'s, which owns who is
signed in and has no business knowing that screens exist, and rather than `RootView`'s, which owns no
lifetimes.

**An unwritten tab root is honest about being unwritten.** `UnwrittenScreenViewModel` holds no client and
makes no request. Calling the screen endpoint ADR-0020 commits to would put a fictional contract in the
client — none of `GET /v1/screens/{expenses,learn,reports,account}` exists yet — and a request against an
unwritten route renders as "Something went wrong" on four of the five tabs. A screen that is not built is not
a screen that is broken. The path through `BaseViewModel.load()` is the real one, which is what the criterion
asks for.

**One `LogoutControl`, and a source scan that says so.** The confirmation is a system `confirmationDialog`
rather than the design's own modal overlay: it puts the destructive action in the platform's red, reads to
VoiceOver as an alert, and cannot be dismissed by accident. The design's *copy* is converted verbatim,
including "Stay signed in" for the cancel. `AppShellTests` asserts that `signOut()` has exactly one caller in
the presentation layers — a second caller would be a second exit, and it would not be one anybody chose.

**`scenePhase` is read once, at the composition root, and passed.** `hwPrivacyOverlay(covering:)` takes the
phase as an argument, and `PrivacyOverlay.covers(_:)` is the rule as a value. The shell takes over neither the
observer nor the overlay, which is the opposite of the note that was there — and the reason is better than the
tidiness would have been: a `RootView` that read the phase itself would make the session branch untestable,
because a renderer's phase is not something a test can set.

**The overlay covers every phase but `.active`, and it does not animate.** iOS takes the snapshot at
`.inactive`, so a cross-fade would put a half-transparent overlay — half a screen of figures — into the
picture the system keeps. The one place ADR-0012's replace-not-remove does not apply, because there is no
motion to replace.

**`LandingView` is a placeholder with no way in.** A button that could not sign anybody in would be worse than
an honest absence, so until #14 lands the app launches at Landing and stays there, and the shell is reachable
in previews and tests.

## Consequences

- **The shell is not reachable by running the app yet**, and that is a property of #14 being open rather than
  of the shell. It is worth stating plainly rather than discovering: a Debug build launches to the Landing
  placeholder. `RootView`'s previews and `AppShellTests` are how the shell is exercised until then.
- **`ImageRenderer` cannot draw a `TabView`.** It yields the unsupported-view glyph — a yellow field with a
  red bar — so no test here asserts the tab bar's pixels, and the ones that render the shell say what they
  actually prove: that the `body` evaluates with the environment it was given. The tab bar's appearance needs
  a hosted render, which is the snapshot harness's problem (#9) and is the second thing that suite will need a
  host for after a loaded `BaseView`.
- **Three of the design's four selection cues do not survive the `TabView`, and this is the price of not
  converting `.tabbar`.** The design marks the selected tab with colour (`.tab.on{color:var(--galaxy)}`), a 4px
  `--planetary` dot beneath it (`.tab-dot`), an icon lift and scale (`translateY(-2px) scale(1.1)`), and
  `--ink-3` on the unselected ones. Only the colour is converted: the tint is the one thing SwiftUI exposes,
  and the dot, the lift, and the unselected colour all need `UITabBar.appearance()` — a UIKit global, and a
  global at that. Enumerated here rather than dropped quietly, because "iconography taken from the design's
  bottom navigation" is a criterion and three quarters of the *selected state* is what it cost. Reopen this
  only with a real complaint about the tab bar being hard to read, not to match a screenshot.
- Four unwritten tab roots means the app has a screen that says "This screen is not built yet" in shipped
  copy. It is one String Catalogue key, used by the placeholder and by Landing, and it is deleted by whichever
  of #13, #18, #19, #21, #23 is last.
- The destructive button shape is still absent (`CONTEXT.md` records it as Account's, #23), so the log out
  control is `.soft` with the *dialog's* confirm carrying the destructive role. That is where the colour
  matters, so nothing is lost by waiting.
- **The design's `.mark` has an asset now**, which changes a fact `CONTEXT.md` recorded: the logo is a base64
  PNG in five places in the design and is extracted to `hwMark`. `HWMark` draws it on the milky tile the design
  specifies, and the privacy overlay is the caller that needed it — "logo on solid galaxy" is what the overlay
  *is*. `HWTopBar` can adopt it whenever #17 wants it; the design's tile is `--card` there and `--milky` on
  brand, which is one argument better had with two callers.
