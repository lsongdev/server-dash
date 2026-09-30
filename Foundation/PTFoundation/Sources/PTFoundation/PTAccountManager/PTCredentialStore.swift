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
    }

    private let service = "org.lsong.serverdash.ssh"
    private init() {}

    func store(_ credential: Credential, identity: String) -> Bool {
        guard let data = try? PropertyListEncoder().encode(credential) else {
            return false
        }

        let key = query(identity: identity)
        SecItemDelete(key as CFDictionary)

        var item = key
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
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
