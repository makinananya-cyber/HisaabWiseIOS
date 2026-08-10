# HisaabWiseIOS

The iOS app for HisaabWise — a UAE personal-finance app pairing expense tracking with financial
education. Pure SwiftUI, MVVM, iOS 18.0 minimum, Swift 6 language mode, iPhone portrait only.

Project rules, invariants, and conventions live in [`../CLAUDE.md`](../CLAUDE.md). The vocabulary is
in [`CONTEXT.md`](CONTEXT.md) and the design decisions behind it in [`docs/adr/`](docs/adr/).

## Layout

One Xcode project, one app target, grouped by MVVM layer
([ADR-0018](docs/adr/0018-app-target-and-mvvm.md)):

```
HisaabWise/
├── HisaabWise.xcodeproj
├── HisaabWise/
│   ├── HisaabWiseApp.swift   composition root — the only place that picks a Transport
│   ├── Models/               Money, CurrencyCode, BudgetSummary, ErrorCode, LoadState
│   ├── ViewModels/           one @Observable @MainActor view model per screen
│   ├── Views/                SwiftUI views; they read a view model and nothing else
│   ├── Networking/           Transport, APIClient, APIError
│   ├── Fixtures/             canned HTTP payloads + FixtureTransport, #if DEBUG only
│   ├── DesignSystem/         tokens and StateView, when they arrive
│   ├── Persistence/          Keychain token store, content store, downloaded PDF, when they arrive
│   └── Resources/            Assets.xcassets, Localizable.xcstrings
└── HisaabWiseTests/          mirrors the layers, plus Architecture/
```

The project uses filesystem-synchronized groups, so a new file is compiled by being on disk — there
is no per-file entry in `project.pbxproj` to keep in step.

## Build and test

```bash
cd HisaabWise && xcodebuild test -scheme HisaabWise -destination 'platform=iOS Simulator,name=iPhone 17'
```

```bash
cd HisaabWise && xcodebuild build -scheme HisaabWise -destination 'platform=iOS Simulator,name=iPhone 17'
```

The scheme is checked in and shared, so CI uses the same one. There is no `swift test` path: the
suite needs a booted simulator ([ADR-0018](docs/adr/0018-app-target-and-mvvm.md) explains what that
cost bought and what it cost).

The app runs today with no backend — the composition root wires the fixture transport in debug
builds, so `HomeView` renders the INR budget fixture.

## Conventions worth knowing before the first edit

- **The client never formats money.** Every monetary field carries the server's display string, and
  `Money` has no formatter, no conversion, and no rounding. The absence is the design
  ([ADR-0003](docs/adr/0003-money-presentation.md)).
- **`Transport` is the only seam.** Tests and previews swap the transport and exercise real
  decoding, real state transitions, and real view-model logic
  ([ADR-0013](docs/adr/0013-testing-and-previews.md)).
- **`offline` is never rendered as `failed`**, and the server's `message` field is never displayed
  ([ADR-0016](docs/adr/0016-presentation-details.md)).
- **The layering is enforced by source scans, not the compiler.** `HisaabWiseTests/Architecture`
  asserts that views do not reach the network and models depend on nothing. Add a new layer folder
  to `SourceTree.layers` or it goes unchecked.
