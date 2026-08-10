import Foundation
import Security

/// The refresh token in the Keychain — what "Keep me signed in" means (ADR-0007).
///
/// Three attributes carry the whole of the decision, and each has a plausible wrong answer that no
/// test would otherwise catch:
///
/// - **`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.** `ThisDeviceOnly` is what stops a live
///   60-day session being restored onto a *new device* from an encrypted iCloud backup — plain
///   `AfterFirstUnlock` permits exactly that. And `AfterFirstUnlock` rather than `WhenUnlocked`
///   because the app is woken with the screen locked and must still be able to read the token.
/// - **`kSecUseDataProtectionKeychain`.** Without it the item can land in the file-based keychain,
///   where the data-protection class is advisory rather than enforced.
/// - **No `kSecAttrAccessGroup`.** Nothing shares this item today. A widget or extension later needs
///   an entitlement change and a one-time migration — a known, bounded cost, and a smaller one than
///   an access group nobody asked for.
///
/// The queries are built by ``baseQuery`` and ``addQuery(for:)`` and are `static` so the suite asserts
/// **the dictionary this store actually passes to the Keychain**. Reading the attributes back off a
/// saved item cannot do that job: the simulator stamps every item with an access group, so a readback
/// could never prove the absence the third point above is about.
struct KeychainTokenStore: TokenStore {
    /// Namespaced by reverse-DNS so the item cannot collide with anything else this app or a future
    /// extension stores. Not read from the bundle identifier: that changes per build configuration, and
    /// a session that disappeared when someone switched to a Staging build would look like a bug in the
    /// session code rather than in the key.
    static let service = "com.hisaabwise.session"

    /// One session per install, so a fixed account rather than the user's email — which would leave a
    /// stale item behind for every account that ever signed in on the device.
    static let account = "refreshToken"

    /// What identifies the item. Every operation starts from this, so a read, a write, and a delete
    /// cannot disagree about which item they mean.
    static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    /// The item as it is created, which is where the accessibility class is set.
    static func addQuery(for refreshToken: String) -> [String: Any] {
        var query = baseQuery()
        query[kSecValueData as String] = Data(refreshToken.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return query
    }

    func refreshToken() async throws -> String? {
        var query = Self.baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let token = String(data: data, encoding: .utf8) else {
                throw KeychainError.unreadableItem
            }
            return token
        case errSecItemNotFound:
            // Empty, which is not a failure: it is a device nobody has signed in on, or one that signed
            // out. The distinction from a *read* failure is what `TokenStore` documents `throws` for.
            return nil
        default:
            throw KeychainError.status(status)
        }
    }

    func save(refreshToken: String) async throws {
        // Delete-then-add rather than add-then-update-on-duplicate. `SecItemUpdate` leaves the existing
        // item's `kSecAttrAccessible` alone, so an item created once under a weaker class would keep it
        // forever — the attributes above would be true of new installs and false of upgraded ones.
        SecItemDelete(Self.baseQuery() as CFDictionary)

        let status = SecItemAdd(Self.addQuery(for: refreshToken) as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    func clear() async throws {
        let status = SecItemDelete(Self.baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.status(status)
        }
    }
}

/// Why a Keychain operation did not do what was asked.
///
/// `status` carries the `OSStatus` rather than a translated message: the codes are the only
/// documentation the framework has, and a test that expects one wants to name it.
enum KeychainError: Error, Equatable, Sendable {
    case status(OSStatus)
    /// The item was there and was not a UTF-8 string — something other than this store wrote it.
    case unreadableItem
}
