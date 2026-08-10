import Foundation
import Testing

/// The load-bearing suite in the bootstrap.
///
/// Most of what ADR-0002 decides is enforced by **absence** — no `HWNetworking` import in `HWCore`.
/// Absences erode quietly and nothing else in a test suite notices when one does, so they are
/// asserted directly against the source tree. This suite reads files rather than symbols on purpose:
/// the thing being protected is the shape of the package, which no amount of behavioural testing can
/// observe.
@Suite("Dependency graph")
struct DependencyGraphTests {
    /// `HWCore` depending on nothing is what makes a raw monetary number *structurally* unable to
    /// reach a view — the client-side analogue of the backend's rule that only repositories touch
    /// collections (ADR-0002).
    @Test("HWCore imports no other module in the package")
    func coreImportsNothingFromThePackage() throws {
        let siblings = PackageTree.libraryTargets.filter { $0 != "HWCore" }

        try PackageTree.expectAbsent(
            siblings.map { "import \($0)" },
            from: ["HWCore"],
            because: "HWCore depends on nothing (ADR-0002)"
        )
    }

    @Test("the manifest declares HWCore with no dependencies")
    func manifestGivesCoreNoDependencies() throws {
        let manifest = try PackageTree.manifest()

        // Anchored on `.target(name:` rather than `name:` alone — the products list mentions every
        // target by name too, and matching there made this assertion unfailable.
        guard let start = manifest.range(of: #".target(name: "HWCore""#) else {
            Issue.record("no `.target(name: \"HWCore\"` declaration found in Package.swift")
            return
        }
        // The declaration runs to whatever target is declared next.
        let rest = manifest[start.upperBound...]
        let end = rest.range(of: ".target(")?.lowerBound ?? rest.endIndex

        #expect(
            !rest[..<end].contains("dependencies:"),
            "HWCore's target declaration gained a dependency; it depends on nothing (ADR-0002)"
        )
    }

    /// `HWCore` is the direction that matters, but a features-to-core inversion would be just as
    /// wrong, so the lower targets are checked too.
    @Test("no lower target imports HWFeatures")
    func nothingBelowFeaturesImportsFeatures() throws {
        try PackageTree.expectAbsent(
            ["import HWFeatures"],
            from: PackageTree.libraryTargets.filter { $0 != "HWFeatures" },
            because: "HWFeatures sits at the top of the graph (ADR-0002)"
        )
    }

    /// ADR-0013 and ADR-0017 — `HWFixtures` never reaches a release binary. `#if DEBUG` keeps its
    /// code out; withholding the product keeps the app shell from linking it at all.
    @Test("every HWFixtures source file is behind #if DEBUG")
    func fixturesAreDebugOnly() throws {
        for file in try PackageTree.swiftFiles(in: "HWFixtures") {
            let source = try String(contentsOf: file, encoding: .utf8)
            #expect(source.contains("#if DEBUG"), "\(file.lastPathComponent) is not behind #if DEBUG")
        }
    }

    @Test("HWFixtures is not exposed as a product")
    func fixturesAreNotAProduct() throws {
        #expect(!(try PackageTree.manifest().contains(#".library(name: "HWFixtures""#)))
    }
}
