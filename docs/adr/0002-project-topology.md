# ADR-0002 — A local Swift package holds the app; the Xcode project is a thin shell

**Status:** superseded in full by [ADR-0018](0018-app-target-and-mvvm.md) — both the package
topology and the MV-with-stores pattern. Kept for the reasoning; do not build to it.
**Supersedes:** `DEVELOPMENT_PLAN.md` §1 ("Xcode project … **hard blocker on all iOS work**")
and the §5 task 25 → 26 ordering

## Context

The plan calls the missing `.xcodeproj` a hard blocker on all iOS work, and `CLAUDE.md`
correctly notes that creating it is a GUI-only step. But that blocker only exists if code lives
in the app target. A **local Swift package builds and tests from the command line with no
project file at all**, so the blocker is a consequence of an unchosen topology rather than a
property of the platform.

Separately, no spec states an architecture pattern, so the first file written would set it by
accident.

## Decision

**`Packages/HisaabWise` — one package, several targets:**

| Target | Holds | Depends on |
|---|---|---|
| `HWCore` | `Money` DTOs, `LoadState`, `TokenStore` protocol, event-name enum, errors | nothing |
| `HWNetworking` | `actor APIClient`, auth and refresh | `HWCore` |
| `HWPersistence` | SwiftData write queue, on-disk content store | `HWCore` |
| `HWDesignSystem` | colour asset catalogue, type scale, shared components | `HWCore` |
| `HWFeatures` | the five tabs and their stores | all of the above |
| `HWFixtures` | fixture JSON, `#if DEBUG` only | `HWCore` |

The `.xcodeproj` app shell owns `Info.plist`, entitlements, app icon, launch screen, and the
composition root. It contains no feature code.

**Pattern: MV with `@Observable` stores** — one store per tab, injected via `@Environment`. No
per-screen view models.

## Consequences

- iOS work starts **now**, before the GUI step. That step shrinks to creating a shell target
  and adding a local package dependency, which is minutes rather than a phase gate.
- `HWCore` having no dependency on `HWNetworking` means a raw number is *structurally* unable
  to reach a view — the client-side analogue of the backend's rule that only repositories
  touch collections.
- Pure-logic tests run without a simulator, which is what makes ADR-0013 cheap enough to be
  worth having.
- A `HomeViewModel` that only forwards `GET /v1/budget` to a view is ceremony. The server *is*
  the model layer here — every figure on Home is computed server-side by decision (invariant 3),
  so a client-side model layer would have nothing to model.
- **Rejected:** XcodeGen/Tuist — a generated project is defensible, but it adds a toolchain
  `CLAUDE.md` does not sanction for a one-target app. **Rejected:** one package per feature —
  manifest tax with no benefit at this size.
