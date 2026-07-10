import Foundation
import Security

/// What actually gets persisted to the Keychain: the long-lived refresh
/// token plus minimal user identity for display. The short-lived access
/// token is NEVER persisted — see the note below for why.
struct StoredSession: Codable, Equatable {
    let refreshToken: String
    let userId: String
    let email: String
}

/// Persists `StoredSession` in the user's login Keychain via
/// SecItemAdd/CopyMatching/Delete — the HIG-correct place for credentials
/// on a native Mac app. Never UserDefaults, never a plaintext file.
///
/// Deliberately named `CredentialStore`, not anything containing "Login",
/// to avoid confusion with Login/LoginItemManager.swift — that's a wholly
/// unrelated "Launch at Login" OS feature, not account sign-in.
///
/// Only the refresh token is stored (~7 day lifetime per backend config).
/// The access token (~15 min) is never written to disk — it's cheap to
/// re-derive via a refresh-token call on every launch, and persisting a
/// token that's usually already expired by the next time you open the app
/// would be pointless and would just widen the at-rest attack surface for
/// no benefit.
enum CredentialStore {
    // Overridable via ZSC_CONTROL_TEST_KEYCHAIN_SERVICE (mirrors the
    // ZSC_CONTROL_DEV_LABEL/ZSC_CONTROL_API_BASE_URL pattern used
    // elsewhere) — Scripts/run-tests.sh sets this so the test suite always
    // operates on a completely separate Keychain entry, never the real
    // one. This isn't just hygiene: the test binary is unsigned while the
    // shipped app is (ad-hoc) signed, and macOS's Data Protection Keychain
    // scopes items by the creating app's identity, so a test run's
    // SecItemDelete can silently fail to see/remove a real signed-in
    // session's item — while SecItemAdd's uniqueness check still collides
    // with it. Without this override, running tests risks corrupting or
    // losing whatever account is actually signed into the real app.
    private static var service: String {
        ProcessInfo.processInfo.environment["ZSC_CONTROL_TEST_KEYCHAIN_SERVICE"] ?? "cc.zeroserver.control.account"
    }
    // Exactly one account can be signed in at a time in this app, so a
    // fixed account key (not one per email) keeps lookups trivial.
    private static let account = "current-session"

    enum KeychainError: Error { case unhandled(OSStatus) }

    static func save(_ session: StoredSession) throws {
        let payload = try JSONEncoder().encode(session)
        delete() // SecItemAdd errors on a pre-existing item; delete-then-add is the standard upsert idiom.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: payload,
            // Available once the Mac's been unlocked once since boot;
            // explicitly NOT synced to iCloud Keychain — a refresh token
            // shouldn't silently roam to every device on this Apple ID.
            // ThisDeviceOnly (M2, security audit): without it, the item is
            // eligible for inclusion in encrypted backups and restorable
            // via Migration Assistant onto a different Mac, extending the
            // token's exposure window beyond this one device.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unhandled(status) }
    }

    static func load() -> StoredSession? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(StoredSession.self, from: data)
    }

    static func clear() { delete() }

    private static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
