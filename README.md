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
├── Configuration/            Debug/Staging/Release .xcconfig + the two Info.plists (ADR-0010)
├── HisaabWise/
│   ├── HisaabWiseApp.swift   composition root — the only place that picks a Transport
│   ├── AppConfig.swift       the base URL, parsed out of the build configuration
│   ├── AppEnvironment.swift  the object graph the root assembles and injects
│   ├── SessionCoordinator.swift  who is signed in — restore, sign in, sign out, foreground
│   ├── Models/               Money, CurrencyCode, BudgetSummary, ErrorCode, LoadState, AppLanguage, AccessToken, TokenStore
│   ├── ViewModels/           BaseViewModel + one @Observable @MainActor view model per screen
│   ├── Views/                BaseView + SwiftUI screens; they read a view model and nothing else
│   ├── Components/           shared controls — buttons, fields, labels, cards, chips
│   ├── Networking/           Transport, URLSessionTransport, APIClient, APIError
│   ├── Fixtures/             canned HTTP payloads + FixtureTransport, #if DEBUG only
│   ├── DesignSystem/         palette, type scale, motion, radii, elevation, StateView, LanguageManager
│   ├── Persistence/          the two token stores; content store and downloaded PDF when they arrive
│   └── Resources/            Assets.xcassets, Localizable.xcstrings
└── HisaabWiseTests/          mirrors the layers, plus Architecture/
```

The project uses filesystem-synchronized groups, so a new file is compiled by being on disk — there
is no per-file entry in `project.pbxproj` to keep in step. `Configuration/` is deliberately outside
that group: those files are build inputs, not source.

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

There are **three configurations** — `Debug` · `Staging` · `Release` — each with an `.xcconfig` in
`Configuration/` supplying `HW_API_BASE_URL` ([ADR-0010](docs/adr/0010-configuration-and-auth-links.md)).
Debug points at `http://localhost:8080`, which is what the backend's `npm run dev` serves on. Build another with `-configuration Staging`.

The app talks to a real server in every configuration, so a Debug build wants the backend running:

```bash
cd ../HisaabWiseBackend && npx wrangler dev
```

Without it, every screen shows the offline state — which is the honest rendering of that situation,
and the reason the fixture transport is now what tests and previews run on rather than what the app
runs on ([ADR-0022](docs/adr/0022-production-transport.md)). One suite drives a real request against
that Worker and **skips, rather than fails**, when it is not answering.

## Conventions worth knowing before the first edit

- **The client never formats money.** Every monetary field carries the server's display string, and
  `Money` has no formatter, no conversion, and no rounding. The absence is the design
  ([ADR-0003](docs/adr/0003-money-presentation.md)).
- **`Transport` is the only seam.** Tests and previews swap the transport and exercise real
  decoding, real state transitions, and real view-model logic
  ([ADR-0013](docs/adr/0013-testing-and-previews.md)).
- **`Networking/` knows nothing about environments.** There is no default base URL: it is parsed from
  the build configuration by `AppConfig` and injected at the composition root, which is also the only
  place in the app target that names `Bundle.main`. A scan in `LayeringTests` keeps a "temporary"
  localhost default out ([ADR-0010](docs/adr/0010-configuration-and-auth-links.md)).
- **Every request carries `Accept-Language` and bypasses the cache** — the first because the server
  formats money honouring it, the second because a HIT on per-user data is a breach. Both hold for the
  write verbs too, and the API session keeps no `URLCache` at all
  ([ADR-0003](docs/adr/0003-money-presentation.md), [ADR-0022](docs/adr/0022-production-transport.md)).
- **`offline` is never rendered as `failed`**, and the server's `message` field is never displayed
  ([ADR-0016](docs/adr/0016-presentation-details.md)).
- **One refresh, however many callers.** A request presents the access token by default; a 401 is
  answered by refreshing once — shared by every caller that saw one — and retrying once. Concurrent
  refreshes would present a spent token, and the backend revokes the whole family for that, so the
  bug it prevents is a silent logout. A definitive 401 on refresh clears the store and signals a hard
  logout; a transport failure, a 5xx, and a Keychain that cannot be read all **keep** the session
  ([ADR-0007](docs/adr/0007-session-and-refresh.md),
  [ADR-0023](docs/adr/0023-session-plumbing.md)).
- **The access token is never persisted and never leaves the client.** It lives in memory on the
  `APIClient` actor; only the refresh token reaches a `TokenStore`, and no view, component, or view
  model may name a token at all. Both are source scans.
- **An in-app screen is a `BaseView` over a `BaseViewModel`.** It declares its view model, the copy
  for the states with nothing in them, and what to draw when it has data — and inherits the spinner,
  the empty state, the offline state, the failure state, the retry, the ground it sits on, and the
  `.task` that starts the load. `APIError` becomes a `LoadState` in one place (`BaseViewModel
  .load()`), the taxonomy is switched on in one place (`StateView`), and an error code becomes copy
  in one place (`ErrorCopy`). All three are asserted by source scans in
  `HisaabWiseTests/Architecture/StateTaxonomyTests.swift`. The chrome paints the **`surface`**
  appearance, so it covers the five in-app screens; Landing and Auth are `brand`-backed and are not
  conformances ([ADR-0021](docs/adr/0021-two-surfaces-and-token-collapse.md)).
- **Every calculation is server-side, and reads are screen-shaped.** One endpoint per screen
  returning exactly what it renders — no figure, percentage, count, date label, or total is derived
  on the client. The one exception is Learn grading, client-side for responsiveness and recomputed
  server-side ([ADR-0020](docs/adr/0020-screen-scoped-endpoints.md)).
- **A screen never styles a control itself.** New variants go in `Components/`, which is
  presentational: it takes values and closures and cannot fetch.
- **Colours come from the asset catalogue by semantic name**, reached through `ThemeManager` in the
  environment. Two scans enforce it — no raw palette name anywhere, and no colour built from
  components, looked up by string, bridged from UIKit, or taken from the system palette — and
  `ColorAssetTests` checks every value against the design's own hex
  ([ADR-0021](docs/adr/0021-two-surfaces-and-token-collapse.md)).
- **The layering is enforced by source scans, not the compiler.** `HisaabWiseTests/Architecture`
  asserts that views do not reach the network, models depend on nothing, and components hold no view
  model. A new layer folder must go in `SourceTree.layers` — and a test now checks that list against
  what is on disk, so forgetting fails rather than passing quietly.
