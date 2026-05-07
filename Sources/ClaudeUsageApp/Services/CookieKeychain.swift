import Foundation
import OSLog
import Security

enum CookieKeychain {
    private static let service = "dev.louisdeng.claudeusage.session"
    private static let account = "claude_session"
    private static let log = Logger(subsystem: "dev.louisdeng.claudeusage", category: "CookieKeychain")

    @discardableResult
    static func save(_ cookie: String) -> Bool {
        let data = Data(cookie.utf8)
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let updateAttrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, updateAttrs as CFDictionary)
        if updateStatus == errSecSuccess { return true }
        if updateStatus != errSecItemNotFound {
            log.error("Keychain update failed status=\(updateStatus, privacy: .public)")
        }

        var addAttrs = baseQuery
        addAttrs[kSecValueData as String] = data
        addAttrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(addAttrs as CFDictionary, nil)
        if addStatus != errSecSuccess {
            log.error("Keychain add failed status=\(addStatus, privacy: .public)")
            return false
        }
        return true
    }

    static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        if status != errSecSuccess {
            log.error("Keychain read failed status=\(status, privacy: .public)")
            return nil
        }
        guard let data = result as? Data, let cookie = String(data: data, encoding: .utf8) else {
            return nil
        }
        return cookie
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            log.error("Keychain delete failed status=\(status, privacy: .public)")
        }
    }
}
