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
enum AppLanguage: String, CaseIterable, Sendable {
    case english = "en"
    case arabic = "ar"

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
