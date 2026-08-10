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
