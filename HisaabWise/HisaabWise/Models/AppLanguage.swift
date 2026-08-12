import Foundation

/// A language the app ships in.
///
/// Two of them. The design lists 87 and the picker shows the **shipped** ones only (Product Spec
/// §3.7 **[FIX]**, ADR-0011); the other 85 are a reference list, not a promise. English is the only
/// one with copy behind it today — Arabic arrives with the translation pass, and the point of
/// shipping the enum now is that `ar` is a layout-direction problem discovered from the first screen
/// rather than a Phase 5 relayout.
///
/// The raw value is the BCP-47 tag, because that is what goes on the wire in `Accept-Language`.
///
/// `Codable` through its raw value, so the tag on the wire and the tag in `Accept-Language` are one
/// string. A tag the app does not ship fails to decode rather than arriving as a case — which is the
/// right answer: `APIClient` turns that into ``APIError/malformedResponse``, and a language with no copy
/// behind it is not something a screen can render.
enum AppLanguage: String, CaseIterable, Codable, Sendable {
    case english = "en"
    case arabic = "ar"

    /// The whole shipped set, in the order a picker lists it.
    ///
    /// The picker's source, and the reason there is no 87-entry list anywhere in the app: the design's
    /// language list is *reference content* served by the backend, and this is the promise (Product Spec
    /// §3.7 **[FIX]**, ADR-0011). Named rather than left as `allCases` so that the picker reads the
    /// intent and not a synthesised conformance.
    static let shipped = allCases

    /// The first shipped language among `identifiers`, or `nil` when none of them ships.
    ///
    /// Matches on the **language subtag**, so `ar-AE`, `ar-EG`, and `ar` are one language: a user
    /// whose device is set to Emirati Arabic wants Arabic, and region is not this type's business.
    /// Order is honoured, so a device listing `["fr-FR", "ar-AE"]` gets Arabic rather than the
    /// fallback — the user's second choice beats our default.
    init?(preferring identifiers: [String]) {
        for identifier in identifiers {
            let subtag = Locale(identifier: identifier).language.languageCode?.identifier
            if let shipped = AppLanguage(rawValue: subtag ?? identifier) {
                self = shipped
                return
            }
        }
        return nil
    }
}

extension AppLanguage {
    /// The `Locale` a screen formats in while this language is selected.
    ///
    /// **It pins `latn` numbering**, including under `ar`. ADR-0011 chose Latin digits everywhere for two
    /// reasons that both bite here: the server's money display strings are Latin-digit (ADR-0003) and the
    /// client has no formatter to correct one, so a locale that produced `٠١٢٣` for a date beside a
    /// `AED 500` figure would print two digit systems in one row; and the Learn tab's numeric answers are
    /// graded at a strict `< 0.5` tolerance on both sides, which only holds if both sides read the same
    /// keystrokes as the same number.
    ///
    /// Built through `Locale.Components` rather than by writing `"ar-u-nu-latn"`, so the subtag syntax is
    /// Foundation's problem and the intent is legible at the call site.
    var locale: Locale {
        var components = Locale.Components(identifier: rawValue)
        components.numberingSystem = Locale.NumberingSystem("latn")
        return Locale(components: components)
    }

    /// Whether the script runs right to left.
    ///
    /// Foundation's answer for the language rather than a `self == .arabic` branch: the layout direction
    /// is a property of the script, and a third shipped language should not need this line edited to be
    /// laid out correctly. It stays a `Bool` here because `LayoutDirection` is SwiftUI's and `Models` has
    /// no view code in it — ``LanguageManager`` maps it.
    var isRightToLeft: Bool {
        Locale.Language(identifier: rawValue).characterDirection == .rightToLeft
    }

    /// The language's name **in itself** — "English", "العربية". The row a picker draws for it (#23).
    ///
    /// **The one string in the app that is deliberately not translated.** A language picker that named Arabic
    /// "Arabic" to an English reader and "الإنجليزية" to an Arabic one is a picker in which neither reader can
    /// find their own language: the whole point of the row is to be legible to somebody who cannot read the
    /// language the app is currently in. So each name is resolved in ``locale`` — its *own* locale — rather
    /// than in the reader's.
    ///
    /// Not a catalogue key either, for the same reason: a key would be translated, which is exactly the
    /// behaviour being avoided. `Locale` knows both names, so there is nothing here to author or to keep in
    /// step.
    ///
    /// The design lists 87 languages with a hand-written endonym each (`{"c":"ar","n":"Arabic","v":"العربية"}`);
    /// the app ships two and asks Foundation, which is the difference between converting the design's *decision*
    /// — show the endonym — and converting its data.
    var endonym: String {
        locale.localizedString(forLanguageCode: rawValue)?.localizedCapitalized ?? rawValue
    }
}
