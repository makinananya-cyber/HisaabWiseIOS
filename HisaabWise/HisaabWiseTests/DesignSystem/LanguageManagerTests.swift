@testable import HisaabWise
import Testing

/// The language choice, and the header it produces.
///
/// What #3 needs from the manager is one thing — a value for `Accept-Language` — and that is all that
/// is asserted here. The picker, the runtime switch, persistence, and the server sync arrive with #7,
/// each with a test of its own then rather than a placeholder now.
@Suite("LanguageManager")
@MainActor
struct LanguageManagerTests {
    @Test("supplies the header for the language in force", arguments: AppLanguage.allCases)
    func headerFollowsTheSelection(_ language: AppLanguage) async {
        // Read through the protocol rather than off the concrete type, because that is how `APIClient`
        // reads it: an isolated property witnessing an `async` requirement is the part that could break
        // without any call site changing.
        let source: any LanguageSource = LanguageManager(selected: language)

        #expect(await source.acceptLanguage == language.rawValue)
    }

    @Test("takes the device's language when the device asks for one the app ships")
    func takesTheDevicesLanguage() {
        #expect(LanguageManager(preferring: ["ar-AE", "en-GB"]).selected == .arabic)
    }

    @Test("falls back to English when nothing on the device ships")
    func fallsBackToEnglish() {
        // English rather than a crash or a nil language: a French-speaking UAE resident gets the app in
        // the language it has copy for, and ADR-0011's shipped set stays two.
        #expect(LanguageManager(preferring: ["fr-FR"]).selected == .english)
        #expect(LanguageManager(preferring: []).selected == .english)
    }

    @Test("two managers are two choices, so nothing is shared between them")
    func managersShareNothing() {
        // The same property `AppEnvironment` has, for the same reason: no `.shared`, so two tests cannot
        // see each other's language.
        let arabic = LanguageManager(selected: .arabic)
        let english = LanguageManager(selected: .english)

        #expect(arabic.selected == .arabic)
        #expect(english.selected == .english)
    }
}
