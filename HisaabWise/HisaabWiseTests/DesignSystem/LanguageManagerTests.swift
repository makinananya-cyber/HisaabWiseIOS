import Foundation
import SwiftUI
@testable import HisaabWise
import Testing

/// The language choice: what it produces, and what changing it costs.
@Suite("LanguageManager")
@MainActor
struct LanguageManagerTests {
    // MARK: - What a screen and a request read

    @Test("supplies the header for the language in force", arguments: AppLanguage.allCases)
    func headerFollowsTheSelection(_ language: AppLanguage) async {
        // Read through the protocol rather than off the concrete type, because that is how `APIClient`
        // reads it: an isolated property witnessing an `async` requirement is the part that could break
        // without any call site changing.
        let source: any LanguageSource = LanguageManager(selected: language)

        #expect(await source.acceptLanguage == language.rawValue)
    }

    @Test("offers the shipped set and nothing wider")
    func offersTheShippedSet() {
        // The picker's source. The design lists 87 languages; this is the promise (Product Spec §3.7
        // **[FIX]**, ADR-0011), and it is a property of the manager rather than something each picker
        // filters for itself.
        #expect(LanguageManager(selected: .english).shipped == [.english, .arabic])
    }

    @Test("formats in the selected language, in Latin digits", arguments: AppLanguage.allCases)
    func localeFollowsTheSelection(_ language: AppLanguage) {
        let manager = LanguageManager(selected: language)

        #expect(manager.locale.language.languageCode?.identifier == language.rawValue)
        // ADR-0011's choice, at the object a screen actually reads. `AppLanguageTests` covers the digits
        // themselves; what this asserts is that the manager does not hand out a plain `Locale(identifier:)`.
        #expect(manager.locale.numberingSystem == Locale.NumberingSystem("latn"))
    }

    @Test("reads right to left in Arabic and left to right in English")
    func directionFollowsTheSelection() {
        #expect(LanguageManager(selected: .arabic).layoutDirection == .rightToLeft)
        #expect(LanguageManager(selected: .english).layoutDirection == .leftToRight)
    }

    // MARK: - Where the initial choice comes from

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

    @Test("a stored choice outranks the device's language")
    func aStoredChoiceWins() {
        // The reason the store is consulted first: a user who chose Arabic in the app and then set their
        // phone to English chose Arabic. Reading the device every launch would silently undo that.
        let manager = LanguageManager(
            store: InMemoryLanguageStore(language: .arabic),
            preferring: ["en-GB"]
        )

        #expect(manager.selected == .arabic)
    }

    @Test("an empty store leaves the device's language in charge")
    func anEmptyStoreDefersToTheDevice() {
        let manager = LanguageManager(store: InMemoryLanguageStore(), preferring: ["ar-AE"])

        #expect(manager.selected == .arabic)
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

    // MARK: - Changing it

    /// A manager wired the way `AppEnvironment` wires one, with the transport the test can inspect.
    private func makeConnected(
        selected: AppLanguage = .english,
        store: InMemoryLanguageStore = InMemoryLanguageStore(),
        transport: FixtureTransport
    ) -> LanguageManager {
        let manager = LanguageManager(selected: selected, store: store)
        _ = TestBench.connect(manager, to: transport)
        return manager
    }

    @Test("switches the app's language and tells the server, in one call")
    func switchesAndSyncs() async throws {
        let store = InMemoryLanguageStore()
        let transport = TestBench.languageTransport(agreeingTo: .arabic)
        let manager = makeConnected(store: store, transport: transport)

        try await manager.select(.arabic)

        #expect(manager.selected == .arabic)
        // Everything a screen reads moves together — one mutation, four consequences.
        #expect(manager.acceptLanguage == "ar")
        #expect(manager.layoutDirection == .rightToLeft)
        #expect(manager.locale.language.languageCode?.identifier == "ar")
        // And it is kept, so the next launch does not revert to the device's language.
        #expect(store.language == .arabic)
    }

    @Test("the request carries the language the user just chose, in the body and in the header")
    func theRequestCarriesTheNewLanguage() async throws {
        let transport = TestBench.languageTransport(agreeingTo: .arabic)
        let manager = makeConnected(transport: transport)

        try await manager.select(.arabic)

        let request = try #require(await transport.recordedRequests.first)
        #expect(request.method == "PUT")
        #expect(request.path == Endpoint.language)
        // The switch happens *before* the request, so the response comes back formatted in the language
        // the user asked for rather than in the one they are leaving (ADR-0020, ADR-0024).
        #expect(request.headers["Accept-Language"] == "ar")
        let body = try #require(request.body)
        #expect(String(decoding: body, as: UTF8.self) == #"{"language":"ar"}"#)
        // A `PUT` replaces a value, so there is nothing for an idempotency key to make safe.
        #expect(request.headers["Idempotency-Key"] == nil)
    }

    @Test("an offline switch changes nothing, on the device or in the store")
    func offlineSwitchesRevert() async throws {
        let store = InMemoryLanguageStore()
        let transport = FixtureTransport(stubs: [Endpoint.language: .notConnected])
        let manager = makeConnected(store: store, transport: transport)

        await #expect(throws: APIError.offline) { try await manager.select(.arabic) }

        // Reverted, rather than left switched with the server none the wiser. A client that kept the
        // change would show Arabic screens to a user whose reminder emails arrive in English, and nothing
        // would ever notice (ADR-0019, ADR-0024).
        #expect(manager.selected == .english)
        #expect(manager.layoutDirection == .leftToRight)
        #expect(store.language == nil)
    }

    @Test("a server failure reverts too, and the error reaches the caller")
    func serverFailuresRevert() async throws {
        let store = InMemoryLanguageStore()
        let transport = FixtureTransport(
            stubs: [Endpoint.language: .response(status: 500, body: Data("{}".utf8))]
        )
        let manager = makeConnected(store: store, transport: transport)

        await #expect(throws: (any Error).self) { try await manager.select(.arabic) }

        #expect(manager.selected == .english)
        #expect(store.language == nil)
    }

    @Test("a server that stored a different language is a failure, not a success")
    func aDisagreeingServerIsAFailure() async throws {
        let store = InMemoryLanguageStore()
        // The server answers `en` to a request that asked for `ar`. Accepting that is how screens and
        // email come to disagree with nothing to notice it.
        let transport = FixtureTransport(
            stubs: [Endpoint.language: .response(status: 200, body: TestBench.languagePreference(.english))]
        )
        let manager = makeConnected(store: store, transport: transport)

        await #expect(throws: LanguageManager.SwitchFailure.serverDisagreed(.english)) {
            try await manager.select(.arabic)
        }

        #expect(manager.selected == .english)
        #expect(store.language == nil)
    }

    @Test("re-selecting a language the server has already confirmed asks it nothing")
    func aConfirmedReselectionSendsNoRequest() async throws {
        let transport = FixtureTransport()
        // A stored choice is a confirmed one — the store is written only after the server agreed.
        let manager = makeConnected(
            selected: .arabic,
            store: InMemoryLanguageStore(language: .arabic),
            transport: transport
        )

        try await manager.select(.arabic)

        #expect(manager.selected == .arabic)
        // The transport has no stub for the path, so a request would have thrown — but asserting the count
        // says what is meant: a picker row tapped twice is not two round trips.
        #expect(await transport.recordedRequests.isEmpty)
    }

    @Test("selecting the device's language tells the server, because nobody ever did")
    func anUnconfirmedReselectionSyncs() async throws {
        // The first-run hole this closes. An Arabic phone puts the app in Arabic without anyone asking the
        // server, and login carries no language (ADR-0023) — so an account registered in English sends
        // English mail to a user reading an Arabic app. Returning early here would make the picker unable to
        // repair that: the row is already selected, and tapping it would do nothing.
        let store = InMemoryLanguageStore()
        let transport = TestBench.languageTransport(agreeingTo: .arabic)
        let manager = makeConnected(selected: .arabic, store: store, transport: transport)

        try await manager.select(.arabic)

        #expect(await transport.requestCount(for: Endpoint.language) == 1)
        #expect(store.language == .arabic)
        #expect(manager.selected == .arabic)
    }

    @Test("an unconnected manager refuses to switch rather than switching locally in silence")
    func anUnconnectedManagerRefuses() async throws {
        // The assembly bug `AppEnvironment.connect(to:)` exists to prevent. Asserted so that the
        // alternative — a language that changes on this device and is never recorded — is a decision
        // somebody rejected rather than a line nobody wrote.
        let manager = LanguageManager(selected: .english)

        await #expect(throws: LanguageManager.SwitchFailure.notConnected) {
            try await manager.select(.arabic)
        }
        #expect(manager.selected == .english)
    }
}
