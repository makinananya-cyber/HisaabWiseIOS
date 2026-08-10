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

    /// Everything long-lived is composed in `AppEnvironment` and handed down (issue #11). A `.shared` is
    /// the shortcut that undoes that: it makes a dependency invisible at the use site and makes two
    /// tests able to see each other's state. Framework singletons are not in scope here — this is about
    /// ours.
    @Test("nothing in the app is a singleton")
    func nothingIsASingleton() throws {
        try SourceTree.expectAbsent(
            ["static let shared", "static var shared", "static let current", "static var current"],
            from: SourceTree.layers,
            includingRoot: true,
            because: "the object graph is composed in AppEnvironment and injected (issue #11)"
        )
    }

    /// ADR-0001 makes dark mode "architected for, not shipped", and the architecture is that every
    /// colour reaches a use site through a semantic name in the asset catalogue. One inline literal is
    /// one colour the later palette swap will miss — and it will miss it silently.
    @Test("no colour reaches a use site except by semantic name")
    func noColourLiterals() throws {
        try SourceTree.expectAbsent(
            [
                // Built from components — invisible to a palette swap.
                "Color(red:", "Color(hue:", "Color(.sRGB", "Color(white:", "#colorLiteral",
                "UIColor(red:", "UIColor(hue:", "UIColor(white:",
                // Looked up by string, which bypasses the generated symbols and so bypasses the
                // compile error that a deleted asset should cause.
                #"Color(""#, "UIColor(named:",
                // Bridged in from UIKit, semantic name or not.
                "Color(uiColor:", "Color(UIColor",
                // System colours. A palette swap cannot reach these either.
                "Color.red", "Color.green", "Color.blue", "Color.orange", "Color.yellow",
                "Color.pink", "Color.purple", "Color.gray", "Color.black", "Color.white",
                "Color.primary", "Color.secondary", "Color.accentColor",
            ],
            from: SourceTree.layers,
            includingRoot: true,
            because: "colours come from the asset catalogue by semantic name (ADR-0001, issue #6)"
        )
    }

    /// The seven palette values are `galaxy`, `planetary`, `universe`, `venus`, `sky`, `meteor`, and
    /// `milky`. None of them may name a colour at a use site — a screen asks for a *role* — which is
    /// the whole mechanism behind "dark mode is a later palette swap" (ADR-0001).
    @Test("no raw palette name appears anywhere")
    func noRawPaletteNames() throws {
        try SourceTree.expectAbsent(
            ["hwGalaxy", "hwPlanetary", "hwUniverse", "hwVenus", "hwSky", "hwMeteor", "hwMilky",
             "Color.galaxy", "Color.planetary", "Color.universe", "Color.venus", "Color.meteor",
             "Color.milky"],
            from: SourceTree.layers,
            includingRoot: true,
            because: "the palette reaches a use site only through a role (ADR-0001, ADR-0021)"
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
