import Foundation
import Testing

/// Locates the app's source on disk relative to this file, so the structural suites work from a fresh
/// clone with no configuration.
///
/// ADR-0018 moved the code into one app target, which means the compiler no longer enforces any layer
/// boundary — a `Views` file can reach `APIClient` and nothing stops it. These scans are what took the
/// place of that enforcement, so they are the only thing standing between the MVVM layering and a
/// convention.
enum SourceTree {
    /// `HisaabWiseTests/Architecture/SourceTree.swift` → `HisaabWise/HisaabWise` (the app target).
    static let appSources = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "HisaabWise")

    /// `…/HisaabWise/Configuration` — the `.xcconfig` files and the two `Info.plist`s (ADR-0010).
    ///
    /// Outside the app target on purpose: these are build inputs, not source, and a folder inside the
    /// synchronized group would put them in the compiler's way and in `layers`' way both.
    static let configuration = appSources
        .deletingLastPathComponent()
        .appending(path: "Configuration")

    /// `…/HisaabWise/Resources/Localizable.xcstrings` — the String Catalogue, read as the JSON it is.
    ///
    /// Read from the source tree rather than from `Bundle.app`, because which of the two exists depends on
    /// the build system: the Xcode build compiles the catalogue to `en.lproj/Localizable.strings` and the
    /// `.xcstrings` never reaches the bundle. A scan about the catalogue's *contents* — which languages it
    /// carries, whether a format string is positional — has to read the source either way.
    static let catalogue = appSources.appending(path: "Resources/Localizable.xcstrings")

    /// The repository root — one level above the directory holding the `.xcodeproj`.
    ///
    /// Where the things that are not Swift live: `.github/`, the ADRs, `CONTEXT.md`. A test that reads a
    /// workflow file needs it, and deriving it from `#filePath` keeps that working from a fresh clone.
    static let repositoryRoot = appSources
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    /// `…/.github/workflows` — the CI definitions, which are checked in and therefore checkable.
    static let workflows = repositoryRoot.appending(path: ".github/workflows")

    /// `…/.github/scripts` — the two Python steps the workflow runs (ADR-0028).
    static let ciScripts = repositoryRoot.appending(path: ".github/scripts")

    /// `…/HisaabWise.xcodeproj/project.pbxproj` — the build settings that are *not* in an `.xcconfig`.
    ///
    /// Read as text, deliberately: the two settings that interest a test — the device family and the
    /// supported orientations — are per-configuration entries in a format with no parser here, and what is
    /// being asserted is that no configuration carries a different value. A substring scan answers that
    /// question exactly, and a plist parse of a pbxproj would answer a harder one.
    static let projectFile = appSources
        .deletingLastPathComponent()
        .appending(path: "HisaabWise.xcodeproj/project.pbxproj")

    /// `…/HisaabWise.xcodeproj/xcshareddata/xcschemes` — the shared schemes.
    ///
    /// Checked in, and therefore checkable. The pseudolanguage harness lives in one of these, and a
    /// harness nobody would notice had stopped working is not one.
    static let schemes = appSources
        .deletingLastPathComponent()
        .appending(path: "HisaabWise.xcodeproj/xcshareddata/xcschemes")

    /// Every layer folder under the app target. **A new folder must be added here**, or the scans
    /// below silently stop covering it — the failure mode is a green suite, not an error.
    static let layers = [
        "Models", "ViewModels", "Views", "Components",
        "Networking", "Fixtures", "DesignSystem", "Persistence",
    ]

    /// The Swift files sitting at the app root rather than in a layer — `HisaabWiseApp.swift` and any
    /// future sibling. Without this they would be covered by no rule at all.
    static func rootSwiftFiles() throws -> [URL] {
        try FileManager.default
            .contentsOfDirectory(at: appSources, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
            .sorted { $0.path < $1.path }
    }

    static func swiftFiles(in layer: String) throws -> [URL] {
        let directory = appSources.appending(path: layer)
        guard let walker = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            throw StructureError.unreadable(layer)
        }
        let files = walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        // An empty result would make every absence assertion below pass without reading anything.
        guard !files.isEmpty else { throw StructureError.unreadable(layer) }
        return files.sorted { $0.path < $1.path }
    }

    /// The file's lines with comment-only lines removed.
    ///
    /// Without this the suites would trip over their own documentation — the ADRs are quoted freely in
    /// these files, and a doc comment explaining that `Money` holds no `Double` must not read as one.
    static func codeLines(of file: URL) throws -> [String] {
        try String(contentsOf: file, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter {
                let trimmed = $0.trimmingCharacters(in: .whitespaces)
                return !trimmed.hasPrefix("//") && !trimmed.hasPrefix("*") && !trimmed.hasPrefix("/*")
            }
    }

    /// Asserts that none of `symbols` appears in any non-comment line of any source file in `layers`.
    ///
    /// - Parameter includingRoot: also scan the Swift at the app root. Only whole-app rules want this —
    ///   a layer-specific rule must not, since the composition root legitimately touches every layer.
    static func expectAbsent(
        _ symbols: [String],
        from layers: [String],
        includingRoot: Bool = false,
        because reason: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let rootFiles = includingRoot ? try rootSwiftFiles() : []
        for (index, layer) in layers.enumerated() {
            for file in try swiftFiles(in: layer) + (index == 0 ? rootFiles : []) {
                let code = try codeLines(of: file)
                for symbol in symbols {
                    let offender = code.first { $0.contains(symbol) }
                    #expect(
                        offender == nil,
                        """
                        \(layer)/\(file.lastPathComponent) references \(symbol) — \(reason)
                        \(offender ?? "")
                        """,
                        sourceLocation: sourceLocation
                    )
                }
            }
        }
    }

    enum StructureError: Error {
        case unreadable(String)
    }
}
