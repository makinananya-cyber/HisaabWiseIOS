// swift-tools-version: 6.0

import PackageDescription

// ADR-0002 — the app lives in this local package; the `.xcodeproj` is a thin shell that owns
// `Info.plist`, entitlements, the app icon, the launch screen, and the composition root, and
// contains no feature code. Everything here builds and tests from the command line with no
// project file present.
//
// ADR-0001 — iOS 18.0 minimum, Swift 6 language mode with strict concurrency from the first
// commit. `macOS` is declared *only* so that `swift test` runs the pure-logic suites on the host
// without booting a simulator (ADR-0017); the shipped app is iPhone-only, portrait-only.
let package = Package(
    name: "HisaabWise",
    // ADR-0011 — strings are externalised from the first string, so that Phase 5 is translation
    // rather than relayout. This is what makes a `Text` in a package target resolve against the
    // module's own catalogue; the catalogues and the Arabic pass arrive with the localisation work.
    defaultLocalization: "en",
    platforms: [
        .iOS(.v18),
        .macOS(.v14),
    ],
    products: [
        .library(name: "HWCore", targets: ["HWCore"]),
        .library(name: "HWNetworking", targets: ["HWNetworking"]),
        .library(name: "HWPersistence", targets: ["HWPersistence"]),
        .library(name: "HWDesignSystem", targets: ["HWDesignSystem"]),
        .library(name: "HWFeatures", targets: ["HWFeatures"]),
        // `HWFixtures` is deliberately **not** a product. `#if DEBUG` keeps its code out of a
        // release binary; withholding the product keeps the app shell from linking it at all.
    ],
    targets: [
        // `HWCore` depends on nothing. That absence is the load-bearing one: it is what makes a
        // raw monetary number structurally unable to reach a view, the client-side analogue of
        // the backend's rule that only repositories touch collections. `HWArchitectureTests`
        // asserts it so it cannot regress silently.
        .target(name: "HWCore"),

        .target(name: "HWNetworking", dependencies: ["HWCore"]),

        .target(name: "HWPersistence", dependencies: ["HWCore"]),

        .target(name: "HWDesignSystem", dependencies: ["HWCore"]),

        .target(
            name: "HWFeatures",
            dependencies: ["HWCore", "HWNetworking", "HWPersistence", "HWDesignSystem"],
            resources: [.process("Resources")]
        ),

        // ADR-0002's table lists `HWCore` alone here; ADR-0017 records why this target also needs
        // `HWNetworking` — `FixtureTransport` conforms to `Transport`, which lives there.
        .target(
            name: "HWFixtures",
            dependencies: ["HWCore", "HWNetworking"],
            resources: [.process("Resources")]
        ),

        .testTarget(name: "HWCoreTests", dependencies: ["HWCore", "HWFixtures"]),
        .testTarget(name: "HWNetworkingTests", dependencies: ["HWNetworking", "HWFixtures"]),
        .testTarget(name: "HWFeaturesTests", dependencies: ["HWFeatures", "HWFixtures"]),
        .testTarget(name: "HWArchitectureTests"),
    ],
    swiftLanguageModes: [.v6]
)
