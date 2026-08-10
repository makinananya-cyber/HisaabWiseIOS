import Foundation
@testable import HisaabWise
import Testing

/// Asserts that a key a screen renders has English copy behind it.
///
/// Extracted from `HomeViewTests` when `StateView` gave the shared `state.*` keys a second consumer:
/// a key with nothing behind it shows the user the key, and that regression should fail in one place
/// however many suites care about it.
enum CatalogueCopy {
    /// Which check is possible depends on the build system. `swift build` copies the catalogue
    /// verbatim, so keys do not resolve at runtime; the Xcode build system compiles it to
    /// `en.lproj/Localizable.strings` and they do. Both paths verify the thing that regresses.
    static func expectEnglishCopy(
        forKeys keys: [String],
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        guard let strings = try sourceStrings() else {
            for key in keys {
                #expect(
                    Bundle.app.localizedString(forKey: key, value: nil, table: nil) != key,
                    "no copy for \(key)",
                    sourceLocation: sourceLocation
                )
            }
            return
        }

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
        }
    }

    /// The English string for one catalogue entry, or `nil` if it has none.
    static func english(in entry: [String: Any]) -> String? {
        ((entry["localizations"] as? [String: Any])?["en"] as? [String: Any])
            .flatMap { $0["stringUnit"] as? [String: Any] }
            .flatMap { $0["value"] as? String }
    }

    /// The catalogue's `strings` table as it is on disk, or `nil` when only the compiled form shipped.
    static func sourceStrings() throws -> [String: Any]? {
        guard let catalogue = Bundle.app.url(forResource: "Localizable", withExtension: "xcstrings") else {
            return nil
        }
        let source = try JSONSerialization.jsonObject(with: try Data(contentsOf: catalogue))
        return (source as? [String: Any])?["strings"] as? [String: Any] ?? [:]
    }
}
