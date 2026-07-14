import Foundation
import Security

final class KeychainHelper: Sendable {
    static let shared = KeychainHelper()
    private let service = "com.ashutoshsingh.kalpanadrive.nvidia-api"
    private let keyAccount = "nvidia-api-key"

    var localOnlyMode: Bool {
        get { UserDefaults.standard.bool(forKey: "com.ashutoshsingh.kalpanadrive.localOnlyMode") }
        set { UserDefaults.standard.set(newValue, forKey: "com.ashutoshsingh.kalpanadrive.localOnlyMode") }
    }

    func saveApiKey(_ key: String) -> Bool {
        guard let data = key.data(using: .utf8) else { return false }
        
        // Delete any existing key first
        deleteApiKey()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: keyAccount,
            kSecValueData as String: data
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    func loadKeychainApiKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: keyAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)

        if status == errSecSuccess, let data = dataTypeRef as? Data {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }

    func loadApiKey() -> String? {
        if localOnlyMode { return nil }
        return loadKeychainApiKey()
    }

    func deleteApiKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: keyAccount
        ]
        SecItemDelete(query as CFDictionary)
    }
}
