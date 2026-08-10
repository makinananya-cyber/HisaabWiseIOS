# HisaabWiseIOS

The iOS app for HisaabWise — a UAE personal-finance app pairing expense tracking with financial
education. Pure SwiftUI, iOS 18.0 minimum, Swift 6 language mode.

Project rules, invariants, and conventions live in [`../CLAUDE.md`](../CLAUDE.md). The vocabulary is
in [`CONTEXT.md`](CONTEXT.md) and the design decisions behind it in [`docs/adr/`](docs/adr/).

## Layout

The app lives in a local Swift package, so it builds and tests from the command line with no Xcode
project involved ([ADR-0002](docs/adr/0002-project-topology.md)):

```
Packages/HisaabWise/     the app — six library targets
HisaabWise/              the app shell: Info.plist, entitlements, icon, composition root
```

| Target | Holds | Depends on |
|---|---|---|
| `HWCore` | `Money`, DTOs, `LoadState`, `ErrorCode` | nothing |
| `HWNetworking` | `Transport`, `actor APIClient` | `HWCore` |
| `HWPersistence` | Keychain token store, write queue, content store | `HWCore` |
| `HWDesignSystem` | colours, type scale, `StateView` | `HWCore` |
| `HWFeatures` | the five tabs and their `@Observable` stores | all of the above |
| `HWFixtures` | canned HTTP payloads and `FixtureTransport`, `#if DEBUG` only | `HWCore`, `HWNetworking` |

`HWCore` depending on nothing is what makes a raw monetary number structurally unable to reach a
view. `HWArchitectureTests` asserts it. `HWFixtures` is not a package product, so the app shell
cannot link it ([ADR-0017](docs/adr/0017-package-topology-amendments.md)).

## Build and test

From the repository root, with no Xcode project needed:

```bash
swift test --package-path Packages/HisaabWise
```

Or from inside the package:

```bash
cd Packages/HisaabWise && swift test
```

Everything except the snapshot suite runs on the host without booting a simulator — which is why
the package declares a macOS platform alongside iOS 18
([ADR-0017](docs/adr/0017-package-topology-amendments.md)). The shipped app is iPhone-only and
portrait-only ([ADR-0001](docs/adr/0001-platform-baseline.md)).

To check the iOS build, which is the one that ships:

```bash
xcodebuild build -scheme HisaabWise-Package -destination 'generic/platform=iOS Simulator' -workspace Packages/HisaabWise
```

## Conventions worth knowing before the first edit

- **The client never formats money.** Every monetary field carries the server's display string, and
  `Money` has no formatter, no conversion, and no rounding. The absence is the design
  ([ADR-0003](docs/adr/0003-money-presentation.md)).
- **`Transport` is the only seam.** Tests and previews swap the transport and exercise real
  decoding, real state transitions, and real store logic
  ([ADR-0013](docs/adr/0013-testing-and-previews.md)).
- **`offline` is never rendered as `failed`**, and the server's `message` field is never displayed
  ([ADR-0016](docs/adr/0016-presentation-details.md)).
