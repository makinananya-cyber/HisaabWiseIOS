import Foundation
@testable import HisaabWise
import Testing

/// Where the language choice survives a relaunch.
///
/// Both conformances, in one suite: the property that matters is the same for either, and asserting it
/// twice is what stops the real store being correct and the in-memory one being what every other suite
/// actually exercises.
@Suite("LanguageStore")
@MainActor
struct LanguageStoreTests {
    /// A `UserDefaults` suite of this test's own, removed afterwards.
    ///
    /// The app's own defaults are deliberately never touched: a suite that wrote to `.standard` would leave a
    /// language preference on the machine it ran on, and two tests would see each other's.
    ///
    /// The body is handed the suite *name* as well as a store, because two of the tests below have to reach
    /// past the store — one to assert what was written to the raw defaults, one to plant a value the store
    /// never wrote — and re-inlining the setup for those was four copies of one `defer`.
    private func withOwnDefaults(
        _ body: (UserDefaultsLanguageStore, String) throws -> Void
    ) throws {
        let suiteName = "hw.tests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
        try body(UserDefaultsLanguageStore(suiteName: suiteName), suiteName)
    }

    @Test("starts with nothing, because never having chosen is not a choice")
    func startsEmpty() throws {
        // `nil` is meaningful: the device's language stays in charge, and keeps staying in charge if the
        // user changes the phone's setting later.
        try withOwnDefaults { store, _ in #expect(store.language == nil) }
        #expect(InMemoryLanguageStore().language == nil)
    }

    @Test("gives back what was saved", arguments: AppLanguage.allCases)
    func roundTrips(_ language: AppLanguage) throws {
        try withOwnDefaults { store, _ in
            store.save(language)
            #expect(store.language == language)
        }

        let memory = InMemoryLanguageStore()
        memory.save(language)
        #expect(memory.language == language)
    }

    @Test("a second save replaces the first")
    func savesReplace() throws {
        try withOwnDefaults { store, _ in
            store.save(.arabic)
            store.save(.english)
            #expect(store.language == .english)
        }
    }

    @Test("a new store over the same defaults finds the choice — which is the whole point")
    func survivesTheStoreItself() throws {
        // The store object dies with the process; the preference must not. Two stores over one suite is the
        // closest a unit test gets to a relaunch.
        try withOwnDefaults { store, suiteName in
            store.save(.arabic)

            #expect(UserDefaultsLanguageStore(suiteName: suiteName).language == .arabic)
        }
    }

    @Test("writes the BCP-47 tag, not an ordinal")
    func writesTheTag() throws {
        // An ordinal would silently mean a different language the moment a case was inserted above it in
        // `AppLanguage`. Asserted against the raw defaults rather than through the store, because reading it
        // back through the store would pass either way.
        try withOwnDefaults { store, suiteName in
            store.save(.arabic)

            let raw = UserDefaults(suiteName: suiteName)?.string(forKey: UserDefaultsLanguageStore.key)
            #expect(raw == "ar")
        }
    }

    @Test("a stored tag this build no longer ships reads as no choice at all")
    func unshippedTagsReadAsEmpty() throws {
        // The forward-compatibility case: a language dropped from the shipped set, or a preference written by
        // a future build. Returning `nil` puts the user on the device's language rather than on a language
        // the app has no copy for.
        try withOwnDefaults { store, suiteName in
            UserDefaults(suiteName: suiteName)?.set("fr", forKey: UserDefaultsLanguageStore.key)

            #expect(store.language == nil)
        }
    }

    @Test("in memory, nothing reaches the device's preferences")
    func theInMemoryStoreLeavesNothingBehind() {
        // The counterpart of the Keychain assertion in `TokenStoreTests`: the store every other suite and
        // every preview uses has to be the one with no footprint, or the suite quietly configures the
        // machine it runs on.
        let store = InMemoryLanguageStore()
        store.save(.arabic)

        #expect(UserDefaults.standard.string(forKey: UserDefaultsLanguageStore.key) == nil)
        #expect(store.language == .arabic)
    }
}
