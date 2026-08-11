import Foundation
@testable import HisaabWise
import Testing

/// The scans that keep ADR-0011 true after the ticket that decided it.
///
/// Arabic here is a **layout-direction** problem more than a translation one, and ADR-0011's whole
/// argument is that four phases of `left`, hardcoded literals, and hand-assembled sentences is a repo-wide
/// retrofit landing at the busiest point in the schedule. That argument only holds if the rules are
/// checked continuously — a screen written next month is where they break, and none of them breaks in a
/// way that fails to compile.
///
/// Same standing as `LayeringTests` and `StateTaxonomyTests`: strictly weaker than a compiler, and the
/// only enforcement there is.
@Suite("Localisation")
struct LocalisationTests {
    /// The layers that put words and layout on a screen. A `Model` has neither.
    private static let presentationLayers = ["Views", "Components", "DesignSystem"]

    // MARK: - Layout that mirrors

    /// `.leading` and `.trailing` mirror in Arabic; `.left` and `.right` do not. `ComponentVocabularyTests`
    /// already held `Components/` to this — the rule is app-wide, and a screen is where it will be broken.
    @Test("nothing anywhere pins an edge to the left or the right")
    func nothingPinsAnEdge() throws {
        try SourceTree.expectAbsent(
            [
                "alignment: .left", "alignment: .right",
                ".topLeft", ".topRight", ".bottomLeft", ".bottomRight",
                "edge: .left", "edge: .right",
                // The text alignments, which mirror under `.leading`/`.trailing` and do not under these.
                "multilineTextAlignment(.left", "multilineTextAlignment(.right",
                // Padding and position, where an edge set is an edge that stays put.
                "padding(.left", "padding(.right",
                ".leftMirrored", ".rightMirrored",
            ],
            from: SourceTree.layers,
            includingRoot: true,
            because: "layout mirrors in Arabic, which leading/trailing does and left/right does not (ADR-0011)"
        )
    }

    /// A glyph that means "forward" must *be* forward, not be an arrow that happens to point right in
    /// English. `chevron.forward` mirrors under RTL; `chevron.right` is a right-pointing chevron in every
    /// language, so an Arabic reader gets a "next" affordance pointing back the way they came.
    @Test("no direction-encoding image reaches a screen")
    func imagesDoNotEncodeDirection() throws {
        try SourceTree.expectAbsent(
            [
                // Prefixes, so the `.circle` / `.square` / `.fill` variants of each are covered too.
                "chevron.left", "chevron.right",
                "arrow.left", "arrow.right",
                "arrowtriangle.left", "arrowtriangle.right",
                "text.alignleft", "text.alignright",
                "arrow.turn.up.left", "arrow.turn.up.right",
                "arrow.uturn.left", "arrow.uturn.right",
                // And the modifier that would put a fixed direction back on a mirroring glyph.
                "flipsForRightToLeftLayoutDirection(false)",
            ],
            from: SourceTree.layers,
            includingRoot: true,
            because: "a glyph must mirror with the layout — `.forward`/`.backward`, never `.left`/`.right` (ADR-0011)"
        )
    }

    // MARK: - Digits

    /// ADR-0011 chooses **Latin digits everywhere, including under `ar`**, and records Eastern Arabic-Indic
    /// digits as deliberately not offered: UAE financial figures are conventionally written in Western
    /// digits, and the server's money display strings are Latin-digit with no client formatter to correct
    /// one (ADR-0003).
    @Test("no Eastern Arabic-Indic digit appears anywhere in the app")
    func latinDigitsOnly() throws {
        try SourceTree.expectAbsent(
            (0x0660...0x0669).map { String(UnicodeScalar($0)!) },
            from: SourceTree.layers,
            includingRoot: true,
            because: "Latin digits everywhere, including under ar — Eastern Arabic-Indic are not offered (ADR-0011)"
        )
    }

    /// The app's language is `LanguageManager`'s, not the device's — once a user has chosen, the two
    /// disagree on purpose. A screen that formats against `Locale.current` would print an Arabic date under
    /// an English app, or an English one under an Arabic app, and would do it only for users who changed
    /// the setting.
    @Test("nothing in the app formats against the system locale")
    func nothingReadsTheSystemLocale() throws {
        // Every layer, including `DesignSystem` — which is where `LanguageManager` and `StateView` live, so
        // scanning everything *but* the owner would be the one omission that mattered.
        try SourceTree.expectAbsent(
            ["Locale.current", "Locale.autoupdatingCurrent"],
            from: SourceTree.layers,
            includingRoot: true,
            because: "the locale comes from LanguageManager through the environment, not from the device (ADR-0011)"
        )

        // And a screen may not build one either. `Models` is exempt from this half and not from the half
        // above: `AppLanguage` resolves the device's preferred *identifiers* into a shipped language, which
        // is parsing a tag rather than formatting against a locale.
        try SourceTree.expectAbsent(
            ["Locale(identifier:"],
            from: Self.presentationLayers,
            because: "a screen reads the locale from the environment; deciding what it is belongs to AppLanguage"
        )
    }

    // MARK: - Sentences

    /// A sentence assembled from pieces cannot be translated: word order is not a property the pieces
    /// carry. The catalogue form — one entry with the value interpolated into it — is the only one that
    /// survives a language whose verb goes last.
    @Test("no sentence is composed from fragments")
    func noSentenceIsConcatenated() throws {
        let reason = """
            a sentence's word order belongs to the translation, so a value is interpolated into a \
            catalogue entry and never joined onto one (ADR-0011)
            """

        try SourceTree.expectAbsent(
            [
                // `Text` concatenation, in the forms it gets written in.
                "+ Text(", ") + Text", "Text(\"\") +",
                // And the halfway house: a format string built at the call site rather than in the catalogue.
                "String(format:",
            ],
            from: SourceTree.layers,
            includingRoot: true,
            because: reason
        )

        // `.appending(` is scanned in the presentation layers only, because `URL.appending(path:)` is a
        // different method with the same name and `APIClient` builds every request URL with it. Narrowing
        // costs nothing here: a sentence is only ever assembled where sentences are drawn, and no file in
        // these three layers builds a URL — `LayeringTests` already forbids it.
        try SourceTree.expectAbsent(
            [".appending(", "localizedString + ", "+ localizedString"],
            from: Self.presentationLayers,
            because: reason
        )
    }

    /// The other half of that rule, on the catalogue side: a format string with more than one argument must
    /// number them. `"%@ of %@"` is untranslatable into a language that wants the second first;
    /// `"%2$@ من %1$@"` is what fixes it, and it is only available if the source string is positional.
    ///
    /// One argument needs no number — there is no order to swap — so `%@` alone is correct and the scan
    /// says so rather than demanding ceremony.
    ///
    /// There is genuinely one interpolated string in the app today and it takes a single argument, so this
    /// scan asserts nothing yet on purpose — it is here for the screens that will have two, which is every
    /// screen that says "AED 500 of AED 2,000".
    @Test("every multi-argument format string numbers its arguments")
    func formatStringsArePositional() throws {
        for (key, entry) in try CatalogueCopy.strings() {
            guard let entry = entry as? [String: Any],
                  let value = CatalogueCopy.english(in: entry)
            else { continue }

            let specifiers = Self.formatSpecifiers(in: value)
            guard specifiers.count > 1 else { continue }

            #expect(
                specifiers.allSatisfy { $0.contains("$") },
                """
                \(key) takes \(specifiers.count) arguments and numbers none of them: "\(value)".
                A translation that needs them in another order cannot ask for it (ADR-0011)
                """
            )
        }
    }

    /// The `%` specifiers in a format string, `%%` excluded — it is a literal percent sign and takes no
    /// argument, which matters in an app whose copy says "% of pay".
    private static func formatSpecifiers(in value: String) -> [String] {
        var specifiers: [String] = []
        var remainder = Substring(value)

        while let start = remainder.firstIndex(of: "%") {
            var index = remainder.index(after: start)
            guard index < remainder.endIndex else { break }
            if remainder[index] == "%" {
                remainder = remainder[remainder.index(after: index)...]
                continue
            }
            // Everything up to and including the conversion character: digits, `$`, and flags on the way.
            while index < remainder.endIndex, !remainder[index].isLetter {
                index = remainder.index(after: index)
            }
            guard index < remainder.endIndex else { break }
            specifiers.append(String(remainder[start...index]))
            remainder = remainder[remainder.index(after: index)...]
        }

        return specifiers
    }

    // MARK: - Room for a longer language

    /// The double-length pseudolanguage exists so that a label which will overflow overflows *now*. What
    /// makes the shell survive it is structural: nothing clamps a line count, so text wraps into a taller
    /// row instead of being cut off. A single `.lineLimit(1)` is one label the harness can no longer tell
    /// you about.
    ///
    /// The shrink-to-fit pair — `.minimumScaleFactor` and `.allowsTightening` — is banned on ADR-0012's
    /// authority rather than ADR-0011's: text scales *unclamped* to AX5, and a control that shrinks its copy
    /// to keep one line is a control that has quietly opted out of that. Neither ban is eternal. A screen
    /// that genuinely needs a clamp should change this scan, argue for it, and take the pseudolanguage run's
    /// blind spot knowingly — which is the whole difference between a decision and a habit.
    @Test("nothing truncates or shrinks its text")
    func nothingTruncates() throws {
        try SourceTree.expectAbsent(
            [".lineLimit(", ".truncationMode(", ".minimumScaleFactor(", ".allowsTightening("],
            from: SourceTree.layers,
            includingRoot: true,
            because: "doubled copy wraps rather than being cut off, and type scales unclamped (ADR-0011, ADR-0012)"
        )
    }

    /// Every screen carries an RTL preview, the way every component already does.
    ///
    /// ADR-0011's argument for doing this in Phase 1 is that Arabic is a **layout** problem, and a layout
    /// problem is found by looking. So the preview is the deliverable and this is what keeps it one: a screen
    /// added in #13–#18 without a mirrored preview is a screen whose RTL review will happen in Phase 5,
    /// which is the schedule the ADR exists to avoid.
    ///
    /// Satisfied either by setting the layout direction outright or by selecting Arabic through
    /// `LanguageManager`. The second is better — it exercises the code that ships — and both are accepted,
    /// because a scan that insisted on one would be picking a house style rather than protecting a property.
    @Test("every screen has an RTL preview")
    func everyScreenHasAnRTLPreview() throws {
        var checked = 0

        for file in try SourceTree.swiftFiles(in: "Views") {
            // `BaseView.swift` declares the protocol and `ScreenChrome`, which is chrome rather than a
            // screen — nothing to preview, and previewing a container with no content would show nothing.
            // Named rather than pattern-matched, because it is one file and a pattern would be a guess.
            guard file.lastPathComponent != "BaseView.swift" else { continue }
            let source = try String(contentsOf: file, encoding: .utf8)
            // Any drawn type in `Views/` — `: BaseView` covers the five in-app screens and `: View` catches
            // Landing and Auth (#13–#16), which are not conformances (ADR-0021) and mirror all the same.
            guard source.contains(": BaseView {") || source.contains(": View {") else { continue }

            checked += 1
            let name = file.lastPathComponent
            #expect(source.contains("#Preview"), "\(name) has no preview")
            #expect(
                source.contains("layoutDirection, .rightToLeft") || source.contains("selected: .arabic"),
                "\(name) has no right-to-left preview — Arabic is a layout problem, found by looking (ADR-0011)"
            )
        }

        #expect(checked > 0, "no screen was found — this scan read nothing")
    }

    /// The pseudolanguage run, as a checked-in shared scheme carrying the argument that turns it on.
    @Test("the double-length pseudolanguage scheme is present and still switched on")
    func theDoubleLengthSchemeExists() throws {
        let scheme = SourceTree.schemes.appending(path: "HisaabWise (Double-Length).xcscheme")
        let source = try String(contentsOf: scheme, encoding: .utf8)

        // Both argv elements: `UserDefaults` reads the argument domain as `-key value` pairs, so a single
        // entry spelled `-NSDoubleLocalizedStrings YES` would arrive as one string and do nothing.
        #expect(source.contains(#"argument = "-NSDoubleLocalizedStrings""#))
        #expect(source.contains(#"argument = "YES""#))
        #expect(source.contains(#"isEnabled = "YES""#))
    }

    // MARK: - Every key a view renders

    /// **The acceptance criterion, as a scan.** A key with nothing behind it does not fail, warn, or fall
    /// back — it renders the key, so the user reads `home.income.label` where a caption should be.
    ///
    /// Every key is found by reading the source rather than by being listed in a test, which is the
    /// difference between this and the per-suite key lists it backs up: a screen added next month is
    /// covered without anybody remembering to add it.
    @Test("every key a view renders has English copy behind it")
    func everyRenderedKeyHasCopy() throws {
        let rendered = try Self.renderedKeys()
        // A scan that found no keys would pass while reading nothing.
        #expect(rendered.count > 1, "found \(rendered.count) keys in the source — this scan read nothing")
        // And the case the extraction is most likely to lose without anyone noticing: a key followed by an
        // interpolated argument rather than by the closing quote.
        #expect(
            rendered["home.income.accessibilityLabel"] != nil,
            "the key extraction no longer finds keys inside format strings — it is reading less than it says"
        )

        try CatalogueCopy.expectEnglishCopy(forKeys: rendered.keys.sorted())
    }

    /// And the converse. A catalogue entry nothing renders is copy that was left behind when a screen
    /// changed: it costs a translator money, it reads as a promise the app does not keep, and nothing about
    /// it is visible from the code it used to belong to.
    @Test("every catalogue entry is rendered by something")
    func noCatalogueEntryIsOrphaned() throws {
        let rendered = try Self.renderedKeys()

        for key in try CatalogueCopy.strings().keys.sorted() {
            #expect(
                rendered[key] != nil,
                "\(key) is in the String Catalogue and nothing renders it — delete it or use it (ADR-0011)"
            )
        }
    }

    /// Only English, and deliberately so. ADR-0011 externalises the strings in Phase 1 and leaves the
    /// *translation* to Phase 5, so a half-translated catalogue is not the intended state: a `state`
    /// of `translated` on an Arabic value nobody reviewed would ship untranslated-looking copy as though
    /// it were finished.
    @Test("the catalogue carries English and nothing else yet")
    func theCatalogueIsEnglishOnly() throws {
        let source = try JSONSerialization.jsonObject(with: try Data(contentsOf: SourceTree.catalogue))
        let root = try #require(source as? [String: Any])
        #expect(root["sourceLanguage"] as? String == "en")

        for (key, entry) in try CatalogueCopy.strings() {
            guard let entry = entry as? [String: Any] else { continue }
            let languages = CatalogueCopy.localisations(in: entry)
            #expect(
                languages == ["en"],
                "\(key) carries \(languages.sorted()) — English only until the Phase 5 translation pass (ADR-0011)"
            )
        }
    }

    /// Every localisation key named in the presentation layers, with the file that names it.
    ///
    /// Keys are recognised by the shape the app spells them in — dotted, lower-camel segments at the start
    /// of a literal — which is also the shape of an SF Symbol name, so a symbol's argument is **cut out of
    /// the line** before the keys are read. Cutting rather than skipping the line is the fix for a real
    /// blind spot: a control that takes both a title and a glyph writes them on one line, and skipping it
    /// lost the title.
    ///
    /// **One place writes a symbol name with no label at all**: `AppTab.systemImage`, where the five tab
    /// glyphs are returned from a `switch` exactly as the five tab *titles* are — so no token on the line can
    /// tell `"chart.bar"` from `"shell.tab.reports"`. Rather than guess from the text, the scan asks `AppTab`
    /// what its symbols are and takes those out. Exact, and it stays right when a glyph changes.
    ///
    /// The key may be followed by a space rather than the closing quote, because that is what a format
    /// string looks like in SwiftUI: `Text("home.income.accessibilityLabel \(figure)")` is one key and one
    /// argument, and requiring the quote would have missed exactly the interpolated strings this suite most
    /// wants covered.
    private static func renderedKeys() throws -> [String: String] {
        let keyShaped = try Regex(#"\"([a-z][A-Za-z0-9]*(?:\.[A-Za-z0-9]+)+)(?=[\s\"])"#)
        // A symbol's *argument*, removed from the line before the keys are read. Skipping the whole line —
        // which this did until Landing wrote `HWButton("landing.cta", systemImage: "arrow.forward")` — loses
        // any key that shares a line with a glyph, and loses it silently: the key then reads as an orphaned
        // catalogue entry rather than as a missing scan.
        let symbolArgument = try Regex(#"(?:systemName|systemImage|symbol)\s*[:=]\s*\"[^\"]*\""#)
        let tabGlyphs = Set(AppTab.allCases.map(\.systemImage))
        var keys: [String: String] = [:]

        for layer in presentationLayers {
            for file in try SourceTree.swiftFiles(in: layer) {
                for line in try SourceTree.codeLines(of: file) {
                    let withoutSymbols = line.replacing(symbolArgument, with: "")
                    for match in withoutSymbols.matches(of: keyShaped) {
                        guard let key = match[1].substring, !tabGlyphs.contains(String(key)) else { continue }
                        keys[String(key)] = file.lastPathComponent
                    }
                }
            }
        }

        return keys
    }
}
