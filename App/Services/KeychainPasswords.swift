import CamTwistCore
import CamTwistRendering
import Foundation
import Security

/// Keeps passwords in the Mac's keychain.
struct KeychainPasswords: PasswordKeeping {
    /// What the keychain files the app's passwords under.
    private static let service = "\(CameraContract.deviceName) VNC"

    func password(for account: String) -> String? {
        var query = Self.query(for: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var found: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &found) == errSecSuccess, let data = found as? Data else {
            return nil
        }
        return String(decoding: data, as: UTF8.self)
    }

    func setPassword(_ password: String, for account: String) {
        let query = Self.query(for: account)
        SecItemDelete(query as CFDictionary)
        guard KeychainRules.keeps(password) else { return }
        var item = query
        item[kSecValueData as String] = Data(password.utf8)
        SecItemAdd(item as CFDictionary, nil)
    }

    private static func query(for account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
