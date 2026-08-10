# ADR-0018 — The code lives in the app target, and the pattern is MVVM

**Status:** accepted
**Supersedes:** [ADR-0002](0002-project-topology.md) in full — both the package topology and the
"MV with `@Observable` stores … no per-screen view models" pattern
**Supersedes:** [ADR-0017](0017-package-topology-amendments.md), which amended a package that no
longer exists
**Decided by:** the project owner, 2026-08-10, overriding the two decisions above

## Context

ADR-0002 put the app in `Packages/HisaabWise` with six library targets, and chose MV with one
`@Observable` store per tab. ADR-0013 and issue #2 were built on that: `swift test` ran the whole
suite in under a second with no simulator, and a test asserted the dependency graph so that
`HWCore` could not see `HWNetworking`.

The owner has decided against both halves. The stated preference is a conventional single-target
iOS layout, navigable in Xcode, with per-screen view models — the pattern the team works in.

This ADR records the reversal and its costs rather than leaving them implicit. The costs are real
and were raised before the change: they are the price of the layout, not an argument against the
decision.

## Decision

**All Swift lives in the `HisaabWise` app target**, grouped by MVVM layer:

```
HisaabWise/HisaabWise/
├── HisaabWiseApp.swift     composition root — the only place that picks a Transport
├── Models/                 Money, CurrencyCode, BudgetSummary, ErrorCode, LoadState
├── ViewModels/             one @Observable @MainActor view model per screen
├── Views/                  SwiftUI views; they read a view model and nothing else
├── Networking/             Transport, APIClient, APIError
├── Fixtures/               canned HTTP payloads + FixtureTransport, #if DEBUG
├── DesignSystem/           tokens and StateView, when they arrive
├── Persistence/            Keychain token store, write queue, content store, when they arrive
└── Resources/              Assets.xcassets, Localizable.xcstrings
```

**The pattern is MVVM with a view model per screen.** `HomeStore` is now `HomeViewModel`. A view
model owns presentation state and performs the fetch; it does not *derive* figures, because every
figure is computed server-side by decision (invariant 3) and `Money` has no formatting API to call
(ADR-0003). *View model* is no longer a rejected synonym in `CONTEXT.md`; *store* is gone.

**Tests live in a `HisaabWiseTests` unit-test target** using `@testable import HisaabWise`, run by
`xcodebuild test` against a pinned simulator, through a checked-in shared scheme.

**The project's own build settings now carry ADR-0001** rather than the Xcode template's defaults.
The template had set iOS 26.5, Swift 5, and iPhone+iPad — which is precisely what ADR-0001 was
written to prevent. Corrected to iOS 18.0, Swift 6 language mode, iPhone-only, portrait-only, and
`SWIFT_DEFAULT_ACTOR_ISOLATION = nonisolated` so that the `Sendable` models, `actor` client, and
`@MainActor` view models mean what their annotations say.

## Consequences

- **`swift test` is gone.** The suite runs only through `xcodebuild test` on a booted simulator:
  seconds instead of milliseconds, and a working Xcode install instead of a Swift toolchain. This
  reverses the premise of issue #1 — that iOS work need not wait on the `.xcodeproj` — so the
  project file is load-bearing again.
- **The dependency graph no longer enforces anything.** One module means a `Views` file can reach
  `APIClient`, and the compiler will not object. `LayeringTests` replaces the graph with source
  scans: no view touches the networking layer, no model touches networking or SwiftUI, no view
  model imports SwiftUI. That is strictly weaker than a module boundary — a scan can be evaded and
  only sees what it is told to look for — and it is now the only thing standing between the layering
  and a convention. Anyone adding a layer must add it to `SourceTree.layers`.
- **Fixture `.json` payloads ship in the release app bundle.** `#if DEBUG` keeps the fixture *code*
  out, but a resource in an app target has no equivalent switch. Roughly a kilobyte of fake data,
  and nothing sensitive — but the package's "never in a release binary" guarantee is now a
  guarantee about code only.
- **Issue #2's acceptance criteria 1, 2, and 10 cannot be met** and should be closed as superseded
  rather than left looking unfinished: `swift test` from the repo root, the six targets, and the
  `HWCore`-does-not-import-`HWNetworking` assertion. AC 3–9 and 11 are all still met.
- Sibling issues #3 and #6 name `HWNetworking` and `HWDesignSystem` as the homes for their work;
  read those as the `Networking/` and `DesignSystem/` folders.
- The five-tab shell (#5) will put one view model per tab into `@Environment`. `HomeView` currently
  takes its view model by initialiser so that a test can construct it over a fixture transport.
- **Rejected:** keeping the package and adding MVVM folders inside it. Offered, and declined.
