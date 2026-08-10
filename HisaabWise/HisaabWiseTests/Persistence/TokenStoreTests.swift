import Foundation
import Security
@testable import HisaabWise
import Testing

/// The two ``TokenStore`` conformances, and the Keychain attributes that are the whole of ADR-0007's
/// storage decision.
@Suite("TokenStore")
struct TokenStoreTests {

    // MARK: - The attributes

    /// Asserted against the dictionary the store passes to the Keychain rather than against a saved
    /// item's attributes read back. The simulator stamps every item with an access group, so a readback
    /// could never prove the absence this suite most needs to prove — and these run on every host,
    /// including one with no usable keychain at all.
    @Suite("KeychainTokenStore's item attributes")
    struct KeychainAttributes {
        /// Computed, not stored: a `[String: Any]` is not `Sendable` and a suite type must be.
        private var query: [String: Any] { KeychainTokenStore.addQuery(for: "refresh-1") }

        @Test("is accessible after first unlock, on this device only")
        func accessibilityIsAfterFirstUnlockThisDeviceOnly() {
            // `ThisDeviceOnly` is what stops a live 60-day session being restored onto a *new device*
            // from an encrypted iCloud backup. Plain `AfterFirstUnlock` permits exactly that, and
            // `WhenUnlocked` would stop the app reading its own token while the screen is locked.
            #expect(
                query[kSecAttrAccessible as String] as? String
                    == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String
            )
        }

        @Test("uses the data protection keychain")
        func usesTheDataProtectionKeychain() {
            // Without this the item can land in the file-based keychain, where the accessibility class
            // above is advisory rather than enforced.
            #expect(query[kSecUseDataProtectionKeychain as String] as? Bool == true)
        }

        @Test("declares no access group")
        func declaresNoAccessGroup() {
            // ADR-0007 — nothing shares this item. A widget later needs an entitlement change and a
            // one-time migration, which is a bounded cost and a smaller one than a group nobody asked for.
            #expect(query[kSecAttrAccessGroup as String] == nil)
        }

        @Test("is a generic password under one service and one account")
        func identifiesOneItem() {
            #expect(query[kSecClass as String] as? String == kSecClassGenericPassword as String)
            #expect(query[kSecAttrService as String] as? String == KeychainTokenStore.service)
            #expect(query[kSecAttrAccount as String] as? String == KeychainTokenStore.account)
        }

        @Test("reads, writes, and deletes the same item")
        func everyOperationNamesTheSameItem() {
            // Three dictionaries that disagreed about which item they meant would produce a store that
            // saves successfully and reads nothing — the failure that looks like the Keychain losing data.
            let base = KeychainTokenStore.baseQuery()
            let created = query

            for key in [kSecClass, kSecAttrService, kSecAttrAccount, kSecUseDataProtectionKeychain] {
                #expect(
                    String(describing: base[key as String]) == String(describing: created[key as String]),
                    "\(key) differs between the identifying query and the item as created"
                )
            }
        }

        @Test("carries the token as its value, and nowhere else in the item")
        func theTokenIsTheItemsValue() throws {
            let value = try #require(query[kSecValueData as String] as? Data)

            #expect(String(data: value, encoding: .utf8) == "refresh-1")
            // A token that also appeared as the account would be an identifier that hands the secret to
            // anything enumerating the keychain.
            #expect(KeychainTokenStore.account != "refresh-1")
        }
    }

    // MARK: - The real Keychain

    /// Skipped, not failed, where there is no keychain to test against — the same trade `LiveWorkerTests`
    /// makes. The attribute suite above is where the decision lives and it runs unconditionally; these
    /// prove the four operations agree with each other on a real store.
    ///
    /// `.serialized` because there is exactly **one** Keychain item and four tests that clear, write, and
    /// read it. Run in parallel they race: one test's `clear()` lands between another's `save` and its
    /// read, and the read comes back `nil` for a reason that has nothing to do with the store. There is no
    /// per-test isolation available here — the item is process-wide by definition, which is the point of it.
    @Suite(
        "KeychainTokenStore against the real Keychain",
        .serialized,
        .enabled("This host has no writable Keychain for the test bundle.") {
            await KeychainProbe.isWritable
        }
    )
    struct RealKeychain {
        @Test("round-trips a token, and rotation replaces rather than accumulates")
        func roundTrip() async throws {
            let store = KeychainTokenStore()
            try await store.clear()

            try await store.save(refreshToken: "refresh-1")
            #expect(try await store.refreshToken() == "refresh-1")

            // Each refresh replaces the token. Reading back the *previous* one would mean presenting a
            // revoked token and having the whole family revoked under us (backend ADR-0005).
            try await store.save(refreshToken: "refresh-2")
            #expect(try await store.refreshToken() == "refresh-2")

            try await store.clear()
            #expect(try await store.refreshToken() == nil)
        }

        @Test("clearing an empty store succeeds rather than reporting not-found")
        func clearingWhenEmptyIsNotAFailure() async throws {
            let store = KeychainTokenStore()

            try await store.clear()
            try await store.clear()
        }

        @Test("an empty store reads as no session, not as a failure")
        func anEmptyStoreIsNotAFailure() async throws {
            let store = KeychainTokenStore()
            try await store.clear()

            // The distinction `TokenStore` documents `throws` for: empty means nobody is signed in, and a
            // *read failure* must not be mistaken for it or a reboot would sign the user out.
            #expect(try await store.refreshToken() == nil)
        }

        @Test("an in-memory store writes nothing to the Keychain")
        func inMemoryLeavesNoDeviceFootprint() async throws {
            // The acceptance criterion for the unchecked box: the session ends at app termination, which
            // is true only if nothing was persisted. Asserted against the Keychain the *other*
            // conformance uses, since that is the one place an accidental write would land.
            let keychain = KeychainTokenStore()
            try await keychain.clear()

            try await InMemoryTokenStore().save(refreshToken: "refresh-1")

            #expect(try await keychain.refreshToken() == nil)
        }
    }

    // MARK: - In memory

    @Test("an in-memory store starts empty, so a fresh install has no session")
    func inMemoryStartsEmpty() async throws {
        #expect(try await InMemoryTokenStore().refreshToken() == nil)
    }

    @Test("an in-memory store holds what it was given and forgets it on clear")
    func inMemoryHoldsAndClears() async throws {
        let store = InMemoryTokenStore()

        try await store.save(refreshToken: "refresh-1")
        #expect(try await store.refreshToken() == "refresh-1")

        try await store.clear()
        #expect(try await store.refreshToken() == nil)
    }

    @Test("an in-memory store can be handed a session in progress")
    func inMemoryCanStartWithAToken() async throws {
        // How a test stands up a client that has something to refresh with, which is otherwise reachable
        // only by signing in.
        #expect(try await InMemoryTokenStore(refreshToken: "refresh-1").refreshToken() == "refresh-1")
    }
}

/// Whether the Keychain answers for this test bundle at all.
///
/// A test host without keychain entitlements reports `errSecMissingEntitlement`, which is nobody's bug
/// here and not a reason for the suite to be red.
enum KeychainProbe {
    static var isWritable: Bool {
        get async {
            let store = KeychainTokenStore()
            do {
                try await store.save(refreshToken: "probe")
                try await store.clear()
                return true
            } catch {
                return false
            }
        }
    }
}
