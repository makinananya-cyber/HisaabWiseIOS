import Foundation

/// The device and runtime the snapshot baselines were recorded on.
///
/// **A pinned pair is what stops a snapshot suite going flaky**, and a flaky gate gets deleted rather than
/// fixed (ADR-0013). Pixels are a function of the whole stack: a different simulator has a different screen
/// and safe area, and a different iOS version has different system fonts, different control metrics, and
/// different rendering of the same SwiftUI. Baselines recorded here and compared there produce failures that
/// are nobody's bug — which is exactly how a suite loses its credibility.
///
/// So the pair is a value, it is asserted, and the suite that uses it **skips** rather than fails when the
/// host does not match. Skipping is the trade a pinned suite has to make to be allowed to exist: a developer
/// on another simulator sees it skip with the reason, and CI (#10) pins the destination so it actually runs.
enum SnapshotPin {
    /// The simulator the baselines belong to, and the name `xcodebuild -destination` takes verbatim. The CI
    /// workflow (#10) pins the same one; until it exists this is the only place the device is written down.
    static let device = "iPhone 17"

    /// The runtime the baselines belong to, major and minor. The patch is deliberately not pinned: Apple's
    /// patch releases do not move SwiftUI's rendering, and pinning it would make the suite skip on every
    /// developer's machine within a fortnight.
    static let runtime = (major: 26, minor: 5)

    /// Whether the host this suite is running on is the pinned pair.
    static var matchesHost: Bool {
        matchesDevice && matchesRuntime
    }

    /// The device name as the **simulator** reports it, which is the same string `-destination` names.
    ///
    /// From the environment rather than from `UIDevice.current.name`: that is main-actor isolated under Swift 6
    /// concurrency and this value is read from a suite trait, which is not. `SIMULATOR_MODEL_IDENTIFIER` is the
    /// other candidate and is a model code (`iPhone17,3`) rather than a name, so it would not match a
    /// destination if it were pinned instead.
    static var hostDevice: String {
        ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? "not a simulator"
    }

    static var hostRuntime: (major: Int, minor: Int) {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return (version.majorVersion, version.minorVersion)
    }

    private static var matchesDevice: Bool {
        hostDevice == device
    }

    private static var matchesRuntime: Bool {
        hostRuntime == runtime
    }

    /// What to tell whoever is looking at a skipped suite.
    static let reason = """
        The snapshot baselines are pinned to \(device) on iOS \(runtime.major).\(runtime.minor); this host is \
        \(hostDevice) on iOS \(hostRuntime.major).\(hostRuntime.minor). Run the suite with \
        `-destination 'platform=iOS Simulator,name=\(device)'` on that runtime, or re-record the baselines and \
        move the pin.
        """
}
