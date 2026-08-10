import Foundation

/// The language choice in `UserDefaults`.
///
/// `UserDefaults` rather than the Keychain or a file: the choice is a preference, not a credential, and
/// it has to be readable synchronously before the first frame — which is the whole reason
/// ``LanguageStore`` is not `async` (ADR-0024).
///
/// It writes the BCP-47 tag rather than an ordinal, so the stored value survives a case being added to
/// ``AppLanguage`` in a different position. A stored tag the build no longer ships reads as `nil`, which
/// puts the user back on the device's language rather than on a language with no copy behind it.
@MainActor
final class UserDefaultsLanguageStore: LanguageStore {
    /// The key, spelled once. Namespaced because `UserDefaults` is a shared bag and an unprefixed
    /// `language` is exactly the key something else would also pick.
    static let key = "hw.language"

    private let defaults: UserDefaults

    /// - Parameter suiteName: `nil` for the app's own defaults. A test passes a name so that the suite
    ///   does not read or write the preferences of the machine it runs on, and can remove its own
    ///   afterwards.
    init(suiteName: String? = nil) {
        defaults = suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    var language: AppLanguage? {
        defaults.string(forKey: Self.key).flatMap(AppLanguage.init(rawValue:))
    }

    func save(_ language: AppLanguage) {
        defaults.set(language.rawValue, forKey: Self.key)
    }
}
