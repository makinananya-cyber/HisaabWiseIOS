# ADR-0001 — iOS 18.0, Swift 6 strict concurrency, iPhone portrait only

**Status:** accepted
**Amends:** Technical Spec §2 (the deployment target was deferred, and the SwiftData/CoreData
hedge is settled by it); Product Spec §5.2 (adds device and orientation scope)

## Context

Neither spec names a minimum deployment target. Technical Spec §2 explicitly defers a
dependent choice to it — "SwiftData; fall back to CoreData if the chosen minimum iOS version
requires" — so the target is a prerequisite, not a detail. The local toolchain is Xcode 26.6.

Neither spec mentions iPad or orientation, which means the Xcode project template would decide
both by default, and the first landscape bug report would be answered by an omission rather
than a decision.

## Decision

**iOS 18.0.** iOS 17 and iOS 18 support the *same device list* (iPhone XS and later), so
raising the floor from 17 to 18 costs no hardware reach — only users who have not updated,
which by a 2026 launch is a small tail. What it buys is material: SwiftData shipped real
migration and predicate defects in 17.0 and settles in 18, and the offline write queue
(ADR-0005) is the last place in this app to want framework bugs. iOS 26 cuts genuinely
current devices in exchange for nothing this app needs.

This settles §2's hedge: **SwiftData, no CoreData fallback.**

**Swift 6 language mode with strict concurrency, from the first commit.** `Sendable` DTOs, an
`actor` networking client, `@MainActor` stores.

**iPhone only, portrait only.** iPad users get the app in compatibility mode.

## Consequences

- Available and depended on downstream: `SectorMark` and `chartAngleSelection` (17+,
  ADR-0016), `@Observable` (17+, ADR-0002), `.sensoryFeedback` (17+, ADR-0012), String
  Catalogs (ADR-0011), Swift Testing (ADR-0013).
- Strict concurrency is a tax on every early file and a rewrite if deferred. The migration
  would otherwise land during Phase 2, when the offline queue makes it hardest. This codebase
  is the easy case: one networking actor, one SwiftData store, `@MainActor` view state, no
  legacy.
- Landscape is not supported. The donut, savings meter, and split bar are laid out for one
  orientation only, and ADR-0012's accessibility-size alternatives are the only alternate
  layouts that exist.
- Product Spec §5.2 should record the device and orientation scope so it is a decision on the
  record.
