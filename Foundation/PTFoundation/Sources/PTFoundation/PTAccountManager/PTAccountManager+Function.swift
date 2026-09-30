//
//  PTAccountManager.swift
//  PTFoundation
//
//  Created by Lakr Aream on 12/15/20.
//

import Foundation

public extension PTAccountManager {
    func createCredential(label: String, username: String, secret: CredentialSecret) -> AccountHandler? {
        createCredential(label: label, username: username, secret: secret, reusable: true)
    }

    /// Store credentials entered directly for one server without adding them
    /// to the reusable credential picker.
    func createServerCredential(label: String, username: String, secret: CredentialSecret) -> AccountHandler? {
        createCredential(label: label, username: username, secret: secret, reusable: false)
    }

    private func createCredential(label: String, username: String, secret: CredentialSecret, reusable: Bool) -> AccountHandler? {
        guard let credential = makeCredential(label: label, username: username, secret: secret, reusable: reusable) else {
            return nil
        }
        let identity = UUID().uuidString
        guard PTCredentialStore.shared.store(credential, identity: identity) else {
            PTLog.shared.join(self,
                              "failed to store account in system Keychain",
                              level: .warning)
            return nil
        }

        let createdAccount = Account(
            type: secret.type,
            keychainIdentity: identity
        )

        executionLock.lock()
        accounts[identity] = createdAccount
        executionLock.unlock()

        synchronizeObjects()
        return identity
    }

    @discardableResult
    func updateCredential(id: AccountHandler, label: String, username: String, secret: CredentialSecret) -> Bool {
        guard let account = retrieveAccountWith(key: id), account.type == secret.type,
              let credential = makeCredential(label: label, username: username, secret: secret, reusable: true)
        else { return false }
        return PTCredentialStore.shared.store(credential, identity: id)
    }

    func listCredentials() -> [CredentialSummary] {
        executionLock.lock()
        let snapshot = accounts
        executionLock.unlock()
        return snapshot.compactMap { id, account in
            guard PTCredentialStore.shared.retrieve(identity: id)?.reusable != false,
                  let detail = account.obtainDecryptedObject()
            else { return nil }
            return CredentialSummary(
                id: id,
                label: detail.plainLabel,
                username: detail.account,
                type: account.type,
                publicKey: detail.publicKey
            )
        }
        .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    @discardableResult
    func deleteCredential(id: AccountHandler) -> Bool {
        guard !PTServerManager.shared.obtainServerList().contains(where: { $0.accountDescriptor == id }),
              retrieveAccountWith(key: id) != nil
        else { return false }
        removeAccount(withKey: id)
        return true
    }

    func removeServerCredentialIfUnused(id: AccountHandler) {
        guard PTCredentialStore.shared.retrieve(identity: id)?.reusable == false,
              !PTServerManager.shared.obtainServerList().contains(where: { $0.accountDescriptor == id })
        else { return }
        removeAccount(withKey: id)
    }

    private func makeCredential(label: String, username: String, secret: CredentialSecret, reusable: Bool) -> PTCredentialStore.Credential? {
        let cleanLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanLabel.isEmpty, !cleanUsername.isEmpty else { return nil }
        switch secret {
        case let .password(password):
            guard !password.isEmpty else { return nil }
            return .init(label: cleanLabel, account: cleanUsername, secret: password, payload: nil, publicKey: nil, reusable: reusable)
        case let .privateKey(key, passphrase, publicKey):
            guard key.contains("-----BEGIN "), key.contains("PRIVATE KEY-----"),
                  let data = key.data(using: .utf8)
            else { return nil }
            return .init(label: cleanLabel, account: cleanUsername, secret: passphrase, payload: data, publicKey: publicKey, reusable: reusable)
        }
    }

    /// 取回账号 上执行锁访问锁
    /// - Parameter key: 句柄
    /// - Returns: 账号对象
    func retrieveAccountWith(key: String) -> Account? {
        executionLock.lock()
        let copy = accounts[key]
        executionLock.unlock()
        return copy
    }

    /// 删除账号 上执行锁 访问锁
    /// - Parameter key: 句柄
    func removeAccount(withKey key: AccountHandler) {
        executionLock.lock()
        accounts.removeValue(forKey: key)
        executionLock.unlock()
        synchronizeObjects()
        PTCredentialStore.shared.remove(identity: key)
        if PTFoundation.legacyCredentialStoreAvailable {
            PTKeyChain.shared.removeAccountBy(key: key)
        }
    }

    /// 获取账户句柄列表
    /// - Returns: 列表
    func obtainAccountKeyList() -> [AccountHandler] {
        executionLock.lock()
        let copy = accounts.keys
        executionLock.unlock()
        return [AccountHandler](copy)
    }
}
