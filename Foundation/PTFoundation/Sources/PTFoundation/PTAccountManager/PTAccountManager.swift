//
//  PTAccountManager.swift
//  PTFoundation
//
//  Created by Lakr Aream on 12/13/20.
//

import Foundation

/*

 PTAccountManager
 是连接KeyChain和ServerManager的桥梁
 账号对应账号储存 使用相同的ID

 */

public final class PTAccountManager {
    // MARK: 结构体定义

    public typealias AccountHandler = String

    /// 用户结构体暴露的接口
    public struct Account {
        /// 用户名
        public let uuid: String
        /// 账户类型
        public let type: AccountType
        // MARK: INTERNAL

        /// 不允许外部初始化该结构体
        internal init(type: AccountType, keychainIdentity identity: String) {
            uuid = identity
            self.type = type
        }

        /// 内部转换方法
        internal func obtainAccountStoreObject() -> AccountStore {
            AccountStore(fromAccount: self)
        }

        // MARK: PUBLIC

        /// 解密数据结构体 暴露接口
        public struct DecryptedObject {
            public let identity: String
            public let plainLabel: String
            public let account: String
            public let key: String
            public let representedObject: Data?
        }

        /// Retrieve the SSH credential from the system Keychain.
        ///
        /// Existing installations may still have the old encrypted .ptk file.
        /// That legacy value is migrated on first read and then deleted.
        public func obtainDecryptedObject() -> DecryptedObject? {
            if let credential = PTCredentialStore.shared.retrieve(identity: uuid) {
                return DecryptedObject(
                    identity: uuid,
                    plainLabel: credential.label,
                    account: credential.account,
                    key: credential.secret,
                    representedObject: credential.payload
                )
            }

            guard PTFoundation.legacyCredentialStoreAvailable,
                  let legacy = PTKeyChain.shared.retrieveAccount(byKey: uuid)
            else {
                return nil
            }

            let credential = PTCredentialStore.Credential(
                label: legacy.plainLabel,
                account: legacy.account,
                secret: legacy.key,
                payload: legacy.representedObject
            )
            guard PTCredentialStore.shared.store(credential, identity: uuid) else {
                return nil
            }

            PTKeyChain.shared.removeAccountBy(key: uuid)
            return DecryptedObject(
                identity: uuid,
                plainLabel: credential.label,
                account: credential.account,
                key: credential.secret,
                representedObject: credential.payload
            )
        }
    }

    /// 储存使用的对象 需要额外注意 Codable
    internal struct AccountStore: Codable {
        /// 变量映射
        let identity: String
        let type: String

        /// 初始化
        internal init(fromAccount object: Account) {
            identity = object.uuid
            type = object.type.rawValue
        }

        /// 内部方法转换
        internal func retrieveAccountObject() -> Account? {
            guard let type = AccountType(rawValue: type) else {
                return nil
            }
            return Account(type: type, keychainIdentity: identity)
        }
    }

    /// 账户类型
    public enum AccountType: String, Codable {
        /// SSH 密码登录
        case secureShellWithPassword
        /// SSH 密钥登录 但是这里要注意并非所有密钥都需要密码
        case secureShellWithKey
    }

    // MARK: 类成员属性

    /// 单例
    public static let shared = PTAccountManager()
    private init() {}

    /// 储存位置定义
    internal static let StoreBase = "Accounts"
    internal var baseLocation = PTFoundation.uninitiatedURL

    /// 锁 全部改成手动上锁
    internal var executionLock = NSLock()
    internal var syncLock = NSLock()

    /// 同步数据的节流阀
    internal let syncThrottle = PTThrottle(minimumDelay: 1,
                                            queue: DispatchQueue.global(qos: .background))

    /// 属性变量
    internal var accounts: [String: Account] = [:]
}
