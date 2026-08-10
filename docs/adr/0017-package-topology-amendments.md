# ADR-0017 — Two amendments to the package topology, found while building it

**Status:** superseded by [ADR-0018](0018-app-target-and-mvvm.md), which removed the package this
amended. Its one lasting observation is the String Catalogue note under Consequences.
**Amends:** [ADR-0002](0002-project-topology.md) (the `HWFixtures` row of the target table);
[ADR-0001](0001-platform-baseline.md) (adds a host platform for testing, not for shipping)

## Context

ADR-0002's target table was written before any Swift existed. Two rows of it do not survive contact
with a package that actually builds, and both were resolved in code comments during the Phase 0
bootstrap — which is the wrong place for a topology decision in a repo that records them as ADRs.

**`HWFixtures` cannot depend on `HWCore` alone.** ADR-0002 gives it `HWCore`, but the whole point of
the fixture corpus is that it is served through the transport seam (ADR-0013), and `FixtureTransport`
therefore has to conform to `Transport`. `Transport` is the networking seam and belongs in
`HWNetworking`; moving it into `HWCore` to preserve the table would mean `HWCore` declaring the
protocol whose absence from `HWCore` is the point of the table.

**`swift test` needs a host platform.** ADR-0001 is iOS 18.0, iPhone-only. A package declaring only
`.iOS` cannot be tested with `swift test` — every suite requires a simulator, which is precisely the
cost ADR-0002 and ADR-0013 exist to avoid.

## Decision

**`HWFixtures` depends on `HWCore` *and* `HWNetworking`.** The dependency the table exists to
protect — `HWCore` not seeing `HWNetworking` — is untouched, and `HWArchitectureTests` asserts it
directly.

**`HWFixtures` is not a package product.** `#if DEBUG` keeps its code out of a release binary;
withholding the product means the app shell cannot link it even by accident. Test targets reference
the target directly, so nothing is lost.

**The package declares `.macOS(.v14)` alongside `.iOS(.v18)`, for tests only.** `macOS 14` is the
floor `@Observable` requires. Nothing in the app may use a macOS-conditional API, and the iOS build
stays the one that ships:

```bash
xcodebuild build -scheme HisaabWise-Package -destination 'generic/platform=iOS Simulator' -workspace Packages/HisaabWise
```

## Consequences

- The pure-logic suites run in well under a second with no simulator, which is what makes ADR-0013's
  coverage cheap enough to keep. The snapshot suite still needs a pinned simulator.
- A macOS platform means SwiftUI views compile for two platforms, so a view using an iOS-only API
  breaks `swift test` rather than only the iOS build. That is a real constraint, accepted: the
  alternative is a test suite nobody runs.
- `swift test` from the repository root needs `--package-path Packages/HisaabWise`, because
  ADR-0002 puts the manifest under `Packages/`. Issue #2's first acceptance criterion reads
  "`swift test` passes from the repo root"; the flag is the reconciliation, and the command is
  documented in `README.md`.
- **A String Catalogue does not resolve under `swift test`.** SwiftPM's own build copies
  `Localizable.xcstrings` into the resource bundle verbatim; only the Xcode build system compiles it
  to `en.lproj/Localizable.strings`. So a key renders as itself under `swift test` and correctly under
  `xcodebuild`. Copy assertions therefore read the catalogue *source* rather than resolving keys, and
  anything genuinely about resolved strings belongs in the `xcodebuild test` run. Worth knowing before
  the localisation work concludes the catalogues are broken.
- **Rejected:** moving `Transport` into `HWCore`. It would put the networking seam in the target
  defined by not having one.
- **Rejected:** a second manifest at the repository root so that bare `swift test` works. Two
  manifests over one source tree is a worse problem than a flag.
