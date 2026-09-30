//
//  PTAccountManager.swift
//  PTFoundation
//
//  Created by Lakr Aream on 12/15/20.
//

import Foundation

public extension PTAccountManager {
    /// 创建账号 上执行锁 子方法可能上访问锁
    /// - Parameters:
    ///   - user: 用户
    ///   - candidate: 凭证
    ///   - attachData: 附加数据
    ///   - type: 类型
    /// - Returns: 账号句柄
    func createAccountWith(user: String,
                           candidate: String,
                           attachData: Data?,
                           type: AccountType) -> AccountHandler?
    {
        let identity = UUID().uuidString
        let credential = PTCredentialStore.Credential(
            label: type.rawValue,
            account: user,
            secret: candidate,
            payload: attachData
        )
        guard PTCredentialStore.shared.store(credential, identity: identity) else {
            PTLog.shared.join(self,
                              "failed to store account in system Keychain",
                              level: .warning)
            return nil
        }

        let createdAccount = Account(
            type: type,
            keychainIdentity: identity
        )

        executionLock.lock()
        accounts[identity] = createdAccount
        executionLock.unlock()

        synchronizeObjects()
        return identity
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
