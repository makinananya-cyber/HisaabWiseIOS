import Foundation
import Testing

/// Locates the package on disk relative to this file, so the structural suites work from a fresh
/// clone with no configuration.
enum PackageTree {
    static let libraryTargets = [
        "HWCore", "HWNetworking", "HWPersistence", "HWDesignSystem", "HWFeatures", "HWFixtures",
    ]

    /// `Tests/HWArchitectureTests/PackageTree.swift` → `Packages/HisaabWise`.
    static let root = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static func manifest() throws -> String {
        try String(contentsOf: root.appending(path: "Package.swift"), encoding: .utf8)
    }

    static func swiftFiles(in target: String) throws -> [URL] {
        let directory = root.appending(path: "Sources").appending(path: target)
        guard let walker = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            throw StructureError.unreadable(target)
        }
        let files = walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        // An empty result would make every absence assertion below pass without reading anything.
        guard !files.isEmpty else { throw StructureError.unreadable(target) }
        return files.sorted { $0.path < $1.path }
    }

    /// The file's lines with comment-only lines removed.
    ///
    /// Without this the suites would trip over their own documentation — the ADRs are quoted freely
    /// in these files, and a doc comment explaining that `Money` holds no `Double` must not read as
    /// one.
    static func codeLines(of file: URL) throws -> [String] {
        try String(contentsOf: file, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter {
                let trimmed = $0.trimmingCharacters(in: .whitespaces)
                return !trimmed.hasPrefix("//") && !trimmed.hasPrefix("*") && !trimmed.hasPrefix("/*")
            }
    }

    /// Asserts that none of `symbols` appears in any non-comment line of any source file in
    /// `targets`.
    static func expectAbsent(
        _ symbols: [String],
        from targets: [String],
        because reason: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        for target in targets {
            for file in try swiftFiles(in: target) {
                let code = try codeLines(of: file)
                for symbol in symbols {
                    let offender = code.first { $0.contains(symbol) }
                    #expect(
                        offender == nil,
                        """
                        \(target)/\(file.lastPathComponent) references \(symbol) — \(reason)
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
