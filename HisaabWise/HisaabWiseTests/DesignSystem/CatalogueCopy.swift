import Foundation
@testable import HisaabWise
import Testing

/// The String Catalogue, as something a suite can read and assert about.
///
/// Extracted from `HomeViewTests` when `StateView` gave the shared `state.*` keys a second consumer:
/// a key with nothing behind it shows the user the key, and that regression should fail in one place
/// however many suites care about it.
enum CatalogueCopy {
    /// The catalogue's `strings` table, read **from the source tree**.
    ///
    /// Not from `Bundle.app`, which is where this used to look. Which of the two is readable depends on the
    /// build system: `swift build` copies the `.xcstrings` verbatim, and the Xcode build compiles it to
    /// `en.lproj/Localizable.strings` so the catalogue never reaches the bundle at all. Since `xcodebuild`
    /// is the only build path now, looking in the bundle meant every catalogue assertion silently did
    /// nothing — the tests were green and reading no copy. The source tree is there under either.
    static func strings() throws -> [String: Any] {
        let source = try JSONSerialization.jsonObject(with: try Data(contentsOf: SourceTree.catalogue))
        let root = try #require(source as? [String: Any], "the String Catalogue is not a JSON object")
        return try #require(root["strings"] as? [String: Any], "the String Catalogue has no strings table")
    }

    /// One catalogue entry by key.
    static func entry(_ key: String) throws -> [String: Any] {
        try #require(try strings()[key] as? [String: Any], "no catalogue entry for \(key)")
    }

    /// The English string for one catalogue entry, or `nil` if it has none.
    static func english(in entry: [String: Any]) -> String? {
        ((entry["localizations"] as? [String: Any])?["en"] as? [String: Any])
            .flatMap { $0["stringUnit"] as? [String: Any] }
            .flatMap { $0["value"] as? String }
    }

    /// The languages an entry carries copy for.
    static func localisations(in entry: [String: Any]) -> Set<String> {
        Set((entry["localizations"] as? [String: Any])?.keys ?? [:].keys)
    }

    /// Asserts that a key a screen renders has English copy behind it.
    ///
    /// Two checks where two are possible. The catalogue on disk is authoritative and always readable; the
    /// bundle's compiled form is what the *user* gets, and resolving through it catches a key that is in
    /// the catalogue and did not survive the build.
    static func expectEnglishCopy(
        forKeys keys: [String],
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let strings = try strings()

        for key in keys {
            let entry = try #require(
                strings[key] as? [String: Any],
                "no catalogue entry for \(key)",
                sourceLocation: sourceLocation
            )
            #expect(
                english(in: entry)?.isEmpty == false,
                "no English copy for \(key)",
                sourceLocation: sourceLocation
            )
            #expect(
                Bundle.app.localizedString(forKey: key, value: nil, table: nil) != key,
                "\(key) has catalogue copy that did not survive the build",
                sourceLocation: sourceLocation
            )
        }
    }
}
