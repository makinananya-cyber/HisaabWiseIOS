import Foundation
import Testing

/// The load-bearing suite.
///
/// Under ADR-0002 the package's dependency graph made a raw monetary number *structurally* unable to
/// reach a view: `Models` could not see `Networking` because the module could not import it. ADR-0018
/// collapsed that into one target, so the compiler enforces nothing and these scans are the whole of
/// the enforcement. They are cheaper than the graph they replaced and strictly weaker — worth knowing
/// when reading them.
@Suite("MVVM layering")
struct LayeringTests {
    /// A view that can reach the network is a view that will eventually fetch, and fetching in a view
    /// is what MVVM exists to prevent. Views talk to view models.
    @Test("no view touches the networking layer")
    func viewsDoNotReachTheNetwork() throws {
        try SourceTree.expectAbsent(
            ["APIClient", "URLSession", "URLRequest", "Transport"],
            from: ["Views"],
            because: "views read a view model; only view models fetch (ADR-0018)"
        )
    }

    /// The direction that matters. A model reaching for the client is the inversion the package's graph
    /// used to make impossible.
    @Test("no model touches the networking layer or the view layer")
    func modelsDependOnNothing() throws {
        try SourceTree.expectAbsent(
            ["APIClient", "URLSession", "URLRequest", "Transport", "SwiftUI", "ViewModel"],
            from: ["Models"],
            because: "models sit at the bottom of the graph and know nothing above them (ADR-0018)"
        )
    }

    /// A view model that imports SwiftUI is one `Color` away from being a view.
    @Test("no view model imports SwiftUI")
    func viewModelsHoldNoViewCode() throws {
        try SourceTree.expectAbsent(
            ["import SwiftUI"],
            from: ["ViewModels"],
            because: "presentation state is not presentation (ADR-0018)"
        )
    }

    /// Components take values and closures. One that can fetch, or that holds a view model, is a
    /// screen wearing a component's name — and it stops being reusable the moment it knows what it is
    /// showing.
    @Test("no component fetches or holds a view model")
    func componentsArePresentational() throws {
        try SourceTree.expectAbsent(
            ["APIClient", "URLSession", "URLRequest", "Transport", "ViewModel"],
            from: ["Components"],
            because: "components are presentational — they take values and closures (ADR-0018)"
        )
    }

    /// Every layer is covered by the scans. A folder missing from `SourceTree.layers` fails silently,
    /// so the list is checked against what is actually on disk rather than trusted.
    @Test("every layer folder on disk is in SourceTree.layers")
    func layerListIsComplete() throws {
        let onDisk = try FileManager.default
            .contentsOfDirectory(at: SourceTree.appSources, includingPropertiesForKeys: nil)
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map(\.lastPathComponent)
            // `Resources` holds the asset catalogue and String Catalogue, not Swift.
            .filter { $0 != "Resources" }

        for folder in onDisk {
            #expect(
                SourceTree.layers.contains(folder),
                "\(folder)/ is not in SourceTree.layers, so no layering rule covers it"
            )
        }
    }

    /// ADR-0013 — fixture *code* never compiles into a release build. The `.json` payloads do ship in
    /// the app bundle now, which is a cost of the single-target layout recorded in ADR-0018.
    @Test("every fixture source file is behind #if DEBUG")
    func fixturesAreDebugOnly() throws {
        for file in try SourceTree.swiftFiles(in: "Fixtures") {
            let source = try String(contentsOf: file, encoding: .utf8)
            #expect(source.contains("#if DEBUG"), "\(file.lastPathComponent) is not behind #if DEBUG")
        }
    }
}
