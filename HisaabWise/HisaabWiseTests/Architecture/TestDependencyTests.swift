import Foundation
import Testing

/// What may be linked into the app, and what may only be linked into the tests.
///
/// ADR-0013 makes `swift-snapshot-testing` a **test-target-only** dependency, and the reason is not tidiness:
/// linked into the app it would reach `PrivacyInfo.xcprivacy` and App Review. That is a rule about the project
/// file, so it is checked against the project file — and **here** rather than in the snapshot suite, which
/// skips on every host but the pinned one (`SnapshotPin`). A guard rail that only runs on one simulator is a
/// guard rail that is not there.
///
/// It is asserted **before** the dependency exists on purpose. Adding a package is a GUI step that this Xcode
/// gives no CLI path to (ADR-0027), and whoever performs it will click a target picker: this is what fails if
/// they click the wrong one.
@Suite("Test-only dependencies")
struct TestDependencyTests {
    /// The app target's object id, from `project.pbxproj`. Named once here rather than at each use, and the
    /// assertions below check the block was actually found — an id that no longer resolves fails loudly
    /// instead of scanning an empty string.
    private static let appTargetID = "9A407CF03029D1D600A9FA73"

    /// The test target's, so the positive half of the rule can be read from the same file.
    private static let testTargetID = "HW00000000000000000010"

    @Test("the app target links no package products")
    func theAppLinksNoPackages() throws {
        let block = try Self.targetBlock(Self.appTargetID)

        // Empty, and empty in the shape Xcode writes it: an entry would appear as a line between these two.
        #expect(
            block.contains("packageProductDependencies = (\n\t\t\t);"),
            "the app target links a package product — nothing in the app may (ADR-0013)"
        )
        #expect(!block.contains("SnapshotTesting"))
    }

    /// The app's `Frameworks` phase, which is the other place a link would appear. Empty today, and it is the
    /// emptiness that is the rule rather than the absence of one particular name.
    @Test("the app target's Frameworks phase links nothing")
    func theAppFrameworksPhaseIsEmpty() throws {
        let project = try Self.project()
        let phase = try #require(project.range(of: "9A407CEE3029D1D600A9FA73 /* Frameworks */ = {"))
        let body = project[phase.upperBound...].prefix(while: { $0 != "}" })

        #expect(body.contains("files = (\n\t\t\t);"), "the app target links a framework: \(body)")
    }

    /// The positive half: when the snapshot library arrives it belongs to the test target. Written as a
    /// conditional rather than a requirement, because the dependency is not here yet and a test that demanded
    /// it would be red until somebody opens Xcode — see ADR-0027's blocked half.
    @Test("if the snapshot library is in the project at all, it is the test target's")
    func theSnapshotLibraryIsTestOnly() throws {
        let project = try Self.project()
        guard project.contains("SnapshotTesting") else { return }

        #expect(try Self.targetBlock(Self.testTargetID).contains("SnapshotTesting"))
        #expect(project.contains("swift-snapshot-testing"), "a product with no package reference behind it")
    }

    private static func project() throws -> String {
        try String(contentsOf: SourceTree.projectFile, encoding: .utf8)
    }

    /// One `PBXNativeTarget` block, from its object id to the `productType` line that closes it.
    private static func targetBlock(_ id: String) throws -> String {
        let project = try project()
        let start = try #require(project.range(of: "\(id) /*"))
        let end = try #require(
            project.range(of: "productType = ", range: start.upperBound..<project.endIndex)
        )
        return String(project[start.upperBound..<end.lowerBound])
    }
}
