import Foundation
import Observation

/// The one owner of the app's language choice.
///
/// It sits beside ``ThemeManager`` for the same reason that one exists: a screen asks the graph what
/// language it is in rather than each screen deciding, so switching is one mutation rather than a
/// search through twelve files. Both are composed in `AppEnvironment` and handed down — no
/// singletons.
///
/// **What it owns today is the wire.** It conforms to ``LanguageSource``, so `APIClient` sets
/// `Accept-Language` from *this* object on every request, which is what makes the server's formatted
/// money strings come back in the language on screen (ADR-0003). Nothing else reads it yet.
///
/// **Issue #7 grows it, and deliberately not before.** The picker over the shipped set, the runtime
/// switch without a relaunch, the `Locale` and `LayoutDirection` a view reads, persistence of the
/// choice, and the `PUT` that tells the server so emails agree — each of those has a caller in #7 and
/// none has one here. What #3 needs is a language to put in a header, and inventing the rest now
/// would be guessing at an interface with no screen to shape it.
@MainActor
@Observable
final class LanguageManager: LanguageSource {
    /// The language in force.
    ///
    /// `private(set)` because nothing yet changes it: the picker and the server sync arrive with #7,
    /// which is also where the mutation this `@Observable` exists to broadcast gets its first caller —
    /// the same shape ``ThemeManager/apply(_:)`` has for the later palette.
    private(set) var selected: AppLanguage

    /// The explicit choice. Tests and previews use this so a request's header is a value they picked,
    /// not a property of the machine the suite runs on.
    init(selected: AppLanguage) {
        self.selected = selected
    }

    /// The device's choice, narrowed to what the app ships.
    ///
    /// `Locale.preferredLanguages` is the ordered list iOS resolved from the user's settings, so an
    /// Arabic-first device gets Arabic and anything else gets English. Injectable rather than read
    /// from the system inside, so the fallback is testable without a device set to French.
    init(preferring identifiers: [String] = Locale.preferredLanguages) {
        selected = AppLanguage(preferring: identifiers) ?? .english
    }

    var acceptLanguage: String {
        selected.rawValue
    }
}
