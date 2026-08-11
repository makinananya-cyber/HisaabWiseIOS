import Foundation
import Testing

/// The scans that carry ADR-0012 past the ticket that decided it.
///
/// Product Spec §9 makes accessibility a **parity requirement**, and its own risk table names treating it
/// as polish as the risk. A per-screen gate is only a gate if it is checked on every screen, and none of
/// these rules breaks in a way that fails to compile: a clamp added to a screen, a stored motion
/// preference, a VoiceOver label that spells a figure out itself — each of them builds, ships, and reads
/// as finished work.
///
/// Same standing as `LayeringTests`, `LocalisationTests`, and `StateTaxonomyTests`: strictly weaker than
/// a compiler, and the only enforcement there is.
@Suite("Accessibility")
struct AccessibilityTests {
    /// Where the clamp lives. Named, so a rename fails the owner check below rather than quietly turning
    /// the scan into one that reads nothing.
    private static let clampOwner = "DesignSystem/HWScaling.swift"

    /// Every Swift file in the app target, with the layer it sits in — the app root included, since two of
    /// the rules below are whole-app rules and a composition root is exactly where one gets broken.
    private static func everySourceFile() throws -> [(layer: String, file: URL)] {
        var files = try SourceTree.rootSwiftFiles().map { (layer: ".", file: $0) }
        for layer in SourceTree.layers {
            files += try SourceTree.swiftFiles(in: layer).map { (layer: layer, file: $0) }
        }
        return files
    }

    // MARK: - Text scales, charts are replaced

    /// **The scaling policy has one owner.** ADR-0012 clamps the four data visualisations and nothing else,
    /// so the range form of `dynamicTypeSize` appears in exactly one file — the one that pairs it with an
    /// alternative layout. Anywhere else it is a screen capping its own reading content, which is the
    /// accessibility failure the ADR is actually about.
    ///
    /// A preview pinning one size — `.dynamicTypeSize(.accessibility3)` — is not a clamp and is not
    /// scanned: it is showing AX3, which is the opposite of capping it.
    @Test("only the clamp pattern clamps Dynamic Type")
    func theClampHasOneOwner() throws {
        let owner = SourceTree.appSources.appending(path: Self.clampOwner)
        #expect(
            try SourceTree.codeLines(of: owner).contains { $0.contains("dynamicTypeSize(...") },
            "\(Self.clampOwner) no longer clamps anything — the scan below enforces nothing"
        )

        for (layer, file) in try Self.everySourceFile()
        where file.lastPathComponent != owner.lastPathComponent {
            let offender = try SourceTree.codeLines(of: file).first { $0.contains("dynamicTypeSize(...") }
            #expect(
                offender == nil,
                """
                \(layer)/\(file.lastPathComponent) clamps Dynamic Type — text scales unclamped, and a \
                visualisation clamps by going through hwVisualisation(replacedBy:) (ADR-0012)
                \(offender ?? "")
                """
            )
        }
    }

    /// The other way a screen opts out of scaling: shrinking the words to keep the layout. Already banned
    /// app-wide by `LocalisationTests` on this ADR's authority — repeated here as a pointer rather than a
    /// second owner, because the two suites are read by different people looking for different things.
    @Test("nothing shrinks its text to fit")
    func nothingShrinksToFit() throws {
        try SourceTree.expectAbsent(
            [".minimumScaleFactor(", ".allowsTightening("],
            from: SourceTree.layers,
            includingRoot: true,
            because: "text scales unclamped to AX5; shrinking to keep one line opts out of it (ADR-0012)"
        )
    }

    /// Every screen carries an accessibility-size preview, the way it already carries a right-to-left one.
    ///
    /// This is what "per-screen gate, not a Phase 5 sweep" costs: one preview per screen, written while the
    /// screen is being written. A screen added in #13–#25 without one is a screen whose AX5 layout nobody
    /// has looked at.
    @Test("every screen has an accessibility-size preview")
    func everyScreenHasAnAccessibilitySizePreview() throws {
        var checked = 0

        for file in try SourceTree.swiftFiles(in: "Views") {
            // `BaseView.swift` declares the protocol and the chrome; there is no screen in it to preview.
            guard file.lastPathComponent != "BaseView.swift" else { continue }
            let source = try String(contentsOf: file, encoding: .utf8)
            guard source.contains(": BaseView {") || source.contains(": View {") else { continue }

            checked += 1
            #expect(
                source.contains("dynamicTypeSize(.accessibility"),
                """
                \(file.lastPathComponent) has no accessibility-size preview — the Inspector pass is a \
                per-screen gate, and this is the half of it a reviewer can see (ADR-0012)
                """
            )
        }

        #expect(checked > 0, "no screen was found — this scan read nothing")
    }

    // MARK: - The OS owns the motion setting

    /// **No in-app motion toggle.** The only way the app may learn that the user wants less movement is by
    /// reading the environment; a second switch is a second source of truth, and the two disagree the
    /// moment somebody changes one of them.
    ///
    /// Asserted positively — every mention of the trait is the environment read itself — because the shapes
    /// a toggle could take are open-ended and the shape a legitimate use takes is not.
    @Test("Reduce Motion is only ever read from the environment")
    func reduceMotionIsOnlyRead() throws {
        var readers = 0

        for (_, file) in try Self.everySourceFile() {
            for line in try SourceTree.codeLines(of: file) where line.contains("accessibilityReduceMotion") {
                readers += 1
                #expect(
                    line.contains("@Environment(\\.accessibilityReduceMotion)"),
                    """
                    \(file.lastPathComponent) mentions Reduce Motion somewhere other than an @Environment \
                    read — the OS setting is the contract and the app keeps no copy of it (ADR-0012)
                    \(line)
                    """
                )
            }
        }

        #expect(readers > 0, "nothing reads Reduce Motion — this scan read nothing")
    }

    /// And nothing can keep one. A motion preference in a store is the toggle above wearing a different
    /// name, and it would survive a reinstall.
    ///
    /// Spelled out rather than scanning for the word `motion`, which would also catch a legitimate
    /// identifier and turn a rule into a nuisance. These are the forms a preference actually arrives in: a
    /// property, a defaults key, or an `@AppStorage` binding.
    @Test("no motion preference can be stored")
    func noMotionPreferenceIsStored() throws {
        try SourceTree.expectAbsent(
            ["reduceMotion", "ReduceMotion", "reduce_motion", "AppStorage"],
            from: ["Persistence", "Models"],
            because: "the OS setting is the contract; there is nothing about motion to persist (ADR-0012)"
        )
    }

    // MARK: - What VoiceOver says about money

    /// **A monetary value is announced from the server's display string, never re-spelled.** The client has
    /// no formatter (ADR-0003) and a VoiceOver label is the one place somebody would be tempted to build
    /// one, because "AED 4,200" read out as digits sounds wrong and the fix looks local.
    ///
    /// The scan is for the *number*: a presentation-layer file that never names `minor` or `exponent`
    /// cannot compose a figure of its own, whatever it does with the string it was given.
    @Test("no screen or component can spell a monetary value out itself")
    func moneyIsAnnouncedFromTheDisplayString() throws {
        // `.minor` survives in **one** place: `HomeView.footLine` asks whether `saved` is *zero*, to choose
        // between two catalogue sentences. Comparing a figure with nothing is not spelling one out — no digit
        // reaches the screen from it — and the alternative was a second server field meaning "is it zero".
        let permitted = ["case _ where savings.saved.minor == 0:"]

        for layer in ["Views", "Components"] {
            for file in try SourceTree.swiftFiles(in: layer) {
                let code = try SourceTree.codeLines(of: file)
                    .filter { line in !permitted.contains { line.contains($0) } }

                for symbol in [".minor", ".exponent", "minor:", "exponent:"] {
                    #expect(
                        code.first { $0.contains(symbol) } == nil,
                        """
                        \(layer)/\(file.lastPathComponent) references \(symbol) — a figure reaches VoiceOver as \
                        Money.display, which the server formatted (ADR-0003, ADR-0012)
                        """
                    )
                }
            }
        }
    }

    // MARK: - Focus order

    /// Focus order is document order. A sort priority is a second ordering with nothing keeping it in step
    /// with the visual one — it drifts silently the first time a row moves, and it drifts only for the
    /// users who cannot see the layout it disagrees with.
    ///
    /// Not eternal: a screen that genuinely needs one should change this scan and argue for it, which is
    /// the difference between a decision and a habit.
    @Test("nothing reorders VoiceOver focus")
    func focusOrderIsDocumentOrder() throws {
        try SourceTree.expectAbsent(
            ["accessibilitySortPriority"],
            from: SourceTree.layers,
            includingRoot: true,
            because: "focus order is document order, which is the only order that cannot drift (ADR-0012)"
        )
    }

    // MARK: - The chrome carries the defaults

    /// The criterion that a new screen gets its accessibility surface **by conforming rather than by
    /// remembering**: the container semantics are the chrome's, and the state announcement is
    /// ``StateView``'s — which is where the taxonomy already lives, so it is also the only place that can
    /// know a placeholder has been replaced by a different placeholder.
    @Test("the chrome and the state view carry the defaults a screen inherits")
    func theChromeCarriesTheDefaults() throws {
        let chrome = try SourceTree.codeLines(
            of: SourceTree.appSources.appending(path: "Views/BaseView.swift")
        )
        #expect(
            chrome.contains { $0.contains("accessibilityElement(children: .contain)") },
            "ScreenChrome no longer makes a screen one container — every screen would have to say so itself"
        )

        let stateView = try SourceTree.codeLines(
            of: SourceTree.appSources.appending(path: "DesignSystem/StateView.swift")
        )
        #expect(
            stateView.contains { $0.contains("HWAnnouncement") },
            "StateView no longer announces a state change — a placeholder replacing a placeholder is silent"
        )
    }

    /// Announcements go through the helper, so that the locale they resolve in is the app's chosen language
    /// rather than the device's. `AccessibilityNotification` reached directly is the one call that would
    /// look correct and speak the wrong language (ADR-0011, ADR-0024).
    @Test("nothing posts an announcement except through the helper")
    func announcementsHaveOneOwner() throws {
        let owner = "HWAnnouncement.swift"

        // Every layer and the app root, not only the layers that draw: the claim in ADR-0025 is that the
        // helper is the one caller *in the app*, and a scan narrower than the claim is a claim nothing keeps.
        for (layer, file) in try Self.everySourceFile() where file.lastPathComponent != owner {
            let offender = try SourceTree.codeLines(of: file)
                .first { $0.contains("AccessibilityNotification") }
            #expect(
                offender == nil,
                """
                \(layer)/\(file.lastPathComponent) posts its own announcement — HWAnnouncement is what \
                resolves the copy against the app's language rather than the device's (ADR-0012)
                \(offender ?? "")
                """
            )
        }
    }
}
