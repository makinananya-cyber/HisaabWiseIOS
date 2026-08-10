import Foundation
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

    @Test("names the shipped set as the picker's source, and it is the whole set")
    func shippedIsThePickersSource() {
        // The picker reads `shipped`. If the two ever diverged, the app would ship a language nothing
        // offered — or offer one it has no copy for.
        #expect(AppLanguage.shipped == AppLanguage.allCases)
    }

    // MARK: - The locale a screen formats in

    @Test("formats in Latin digits, in every shipped language", arguments: AppLanguage.allCases)
    func latinDigitsEverywhere(_ language: AppLanguage) {
        // ADR-0011's central choice, and the one that is invisible until it is wrong: an `ar` locale
        // without `latn` prints `٠١٢٣`, which would sit beside a Latin-digit server figure in the same row.
        let formatted = 1234.formatted(.number.grouping(.never).locale(language.locale))

        #expect(formatted == "1234")
        // Named explicitly as well, because `1234` happens to render the same under several numbering
        // systems the app could be handed by accident.
        #expect(language.locale.numberingSystem == Locale.NumberingSystem("latn"))
    }

    @Test("carries no Eastern Arabic-Indic digit under ar")
    func noEasternArabicIndicDigits() {
        let easternArabicIndic = Set((0x0660...0x0669).map { Character(UnicodeScalar($0)!) })
        // Every digit 0–9, since a numbering system can differ per digit in principle and the assertion
        // above only exercised four of them.
        let digits = (0...9).map { $0.formatted(.number.locale(AppLanguage.arabic.locale)) }.joined()

        #expect(digits.allSatisfy { !easternArabicIndic.contains($0) })
        #expect(digits == "0123456789")
    }

    @Test("keeps the language subtag it was asked for, `latn` notwithstanding")
    func theLocaleIsStillTheLanguage() {
        // The numbering system is pinned; the language is not overwritten by pinning it. Without this the
        // locale could silently become `en` and every date label would come back in the wrong language.
        #expect(AppLanguage.arabic.locale.language.languageCode?.identifier == "ar")
        #expect(AppLanguage.english.locale.language.languageCode?.identifier == "en")
    }

    // MARK: - Direction and naming

    @Test("reads its direction from the script rather than from a case comparison")
    func directionFollowsTheScript() {
        #expect(AppLanguage.arabic.isRightToLeft)
        #expect(!AppLanguage.english.isRightToLeft)
    }

    // MARK: - The wire

    @Test("codes as the bare BCP-47 tag, which is what Accept-Language carries")
    func codesAsItsTag() throws {
        let encoded = try JSONEncoder().encode(AppLanguage.arabic)

        #expect(String(decoding: encoded, as: UTF8.self) == "\"ar\"")
        #expect(try JSONDecoder().decode(AppLanguage.self, from: encoded) == .arabic)
    }

    @Test("refuses to decode a language the app does not ship")
    func unshippedTagsDoNotDecode() {
        // The server answering `fr` is a disagreement, not a language: there is no copy behind it, so
        // failing here — and reaching the user as `malformedResponse` — beats a case that renders keys.
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(AppLanguage.self, from: Data(#""fr""#.utf8))
        }
    }
}
