# ADR-0013 — Tests and previews share one fixture corpus

**Status:** accepted
**Amends:** Technical Spec §9 (the iOS section gains automated coverage)

## Context

Technical Spec §9's iOS verification is four **manual** steps — TestFlight install, force-quit
persistence, airplane mode — and `feature/mvp` has no CI by design (`DEVELOPMENT_PLAN.md` §2). So
nothing catches an iOS regression until a human notices one.

Previews are the other half of the problem: the server owns every number in this app, so previews
need fixtures, and fixtures rot silently the moment the API moves.

## Decision

**Swift Testing units on the package targets**, run by `xcodebuild test` on the `release` PR.
Coverage that earns its place:

- DTO decoding against fixture JSON;
- `Money` display-string rendering (ADR-0003);
- `PendingWrite` drain ordering, `MONTH_CLOSED` re-filing, poison-message handling (ADR-0005);
- local unlock ordering (ADR-0006);
- numeric input parsing at the 0.5 boundary (ADR-0011);
- single-flight refresh under concurrent 401s (ADR-0007).

**A thin snapshot suite** via `swift-snapshot-testing`, a **test-target-only** dependency: Home
populated, Home empty state, one RTL screen, one AX3 screen. The simulator device and iOS runtime
version are **pinned in CI**.

**`HWFixtures` behind `#if DEBUG`** supplies previews from **the same JSON files** the decoding
tests read.

## Consequences

- One corpus, two consumers: a fixture that drifts from the API breaks a **test** rather than
  quietly rotting a preview.
- `swift-snapshot-testing` never links into the app binary, so it touches neither
  `PrivacyInfo.xcprivacy` nor App Review, and it solves the parts a hand-rolled `ImageRenderer`
  comparison would do badly — device traits, RTL rendering, Dynamic Type variants, perceptual
  diffing.
- The snapshot suite stays deliberately small and pinned. An unpinned or sprawling snapshot suite
  goes flaky, and a flaky gate gets deleted rather than fixed.
- **A standing INR-salary fixture is the default preview.** A hardcoded `AED 8,000` then becomes
  visible in Xcode at design time rather than being caught by the D1 regression test in Phase 2 —
  which turns the project's worst historical defect into a compile-time-visible one.
- ADR-0002's package topology is what makes the pure-logic tests runnable without a simulator.
