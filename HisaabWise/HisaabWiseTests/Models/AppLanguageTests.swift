@testable import HisaabWise
import Testing

/// The shipped set, and the matching rule that decides which of it a device gets.
@Suite("AppLanguage")
struct AppLanguageTests {
    @Test("ships English and Arabic, and nothing else")
    func shipsTwoLanguages() {
        // The design lists 87 languages and the picker shows the **shipped** ones only (Product Spec
        // §3.7 **[FIX]**). A third case appearing here without copy behind it would show a user the
        // keys instead of sentences.
        #expect(AppLanguage.allCases == [.english, .arabic])
        #expect(AppLanguage.allCases.map(\.rawValue) == ["en", "ar"])
    }

    @Test(
        "matches on the language subtag, so a region does not make a new language",
        arguments: ["ar", "ar-AE", "ar-EG", "ar_SA", "ar-Arab-AE"]
    )
    func regionsAndScriptsCollapse(_ identifier: String) {
        #expect(AppLanguage(preferring: [identifier]) == .arabic)
    }

    @Test("honours the order the device asked for")
    func honoursPreferenceOrder() {
        #expect(AppLanguage(preferring: ["ar-AE", "en-GB"]) == .arabic)
        #expect(AppLanguage(preferring: ["en-GB", "ar-AE"]) == .english)
    }

    @Test("skips a language the app does not ship rather than giving up at it")
    func skipsUnshippedLanguages() {
        // A device set to French with Arabic second wants Arabic, not the default. Stopping at the first
        // entry would hand that user English.
        #expect(AppLanguage(preferring: ["fr-FR", "hi-IN", "ar-AE"]) == .arabic)
    }

    @Test("has no answer when nothing on the device ships")
    func noShippedLanguageMeansNoAnswer() {
        // `nil` rather than `.english`: choosing the fallback is `LanguageManager`'s decision to make
        // and to document, not something to hide inside a lookup.
        #expect(AppLanguage(preferring: ["fr-FR"]) == nil)
        #expect(AppLanguage(preferring: []) == nil)
    }
}
