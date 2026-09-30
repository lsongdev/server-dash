//
//  PTCredentialStore.swift
//  PTFoundation
//

import Foundation
import Security

/// Stores SSH credentials in Apple's data-protection Keychain.
///
/// Server metadata remains in the normal app store. Passwords, private keys,
/// and passphrases never need a second application-managed encryption layer.
internal final class PTCredentialStore {
    static let shared = PTCredentialStore()

    struct Credential: Codable {
        let label: String
        let account: String
        let secret: String
        let payload: Data?
        let publicKey: String?
        /// False for credentials entered only for one server.
        /// Missing on older records, which remain reusable.
        let reusable: Bool?
    }

    private let service = "org.lsong.serverdash.ssh"
    private init() {}

    func store(_ credential: Credential, identity: String) -> Bool {
        guard let data = try? PropertyListEncoder().encode(credential) else {
            return false
        }

        let key = query(identity: identity)
        let status = SecItemUpdate(
            key as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if status == errSecSuccess { return true }

        var item = key
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let addStatus = SecItemAdd(item as CFDictionary, nil)
        if addStatus == errSecSuccess { return true }
        PTLog.shared.join(self,
                          "Keychain update failed (\(status)); add failed (\(addStatus))",
                          level: .warning)
        return false
    }

    func retrieve(identity: String) -> Credential? {
        var request = query(identity: identity)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else {
            return nil
        }

        return try? PropertyListDecoder().decode(Credential.self, from: data)
    }

    func remove(identity: String) {
        SecItemDelete(query(identity: identity) as CFDictionary)
    }

    private func query(identity: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: identity,
        ]
    }
}
