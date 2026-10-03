//
//  Agent.swift
//  ServerDash
//
//  Created by Lakr Aream on 2021/4/30.
//

import PTFoundation
import UIKit

class Agent: ObservableObject {
    static let shared = Agent()
    private init() {
        if applicationProtected {
            authorizationStatus = .unauthorized
        } else {
            authorizationStatus = .authorized
        }
        prepareNotifications()
    }

    public enum AppAuthorizationStatus: String {
        case unauthorized
        case authorized
    }

    @UserDefaultsWrapper(key: "wiki.qaq.pillowtalk.supervisionInterval", defaultValue: 60)
    var supervisionInterval: Int

    @UserDefaultsWrapper(key: "wiki.qaq.pillowtalk.supervisionRecordEnabled", defaultValue: true)
    var supervisionRecordEnabled: Bool

    @UserDefaultsWrapper(key: "wiki.qaq.pillowtalk.applicationProtected", defaultValue: false)
    var applicationProtected: Bool

    @UserDefaultsWrapper(key: "org.lsong.serverdash.terminalProtection", defaultValue: false)
    var terminalProtectionEnabled: Bool

    // MARK: - -- SENDER ⬇️ ANY THREAD -> MAIN THREAD

    @Atomic var serverDescriptorsSender: [String] = [] {
        didSet {
            let value = serverDescriptorsSender.sorted(by: { a, b in
                let sa = PTServerManager.shared.obtainServer(withKey: a)
                let sb = PTServerManager.shared.obtainServer(withKey: b)
                guard let saa = sa else { return true }
                guard let sbb = sb else { return false }
                return saa.obtainPossibleName() < sbb.obtainPossibleName()
            })
            let filteredForSupervised = value.filter { PTServerManager.shared.isServerSupervised(withKey: $0) }
            DispatchQueue.main.async {
                if value == self.serverDescriptorsSorted { return }
                self.serverDescriptorsSorted = value
            }
            DispatchQueue.main.async {
                if filteredForSupervised == self.serverDescriptorsSortedSupervised { return }
                self.serverDescriptorsSortedSupervised = filteredForSupervised
            }
        }
    }

    @Atomic var serverSectionsSender: [String] = [] {
        didSet {
            let value = serverSectionsSender.sorted()
            if value == serverSectionsSorted { return }
            DispatchQueue.main.async {
                self.serverSectionsSorted = value
            }
        }
    }

    @Atomic var authorizationStatusSender: AppAuthorizationStatus = .unauthorized {
        didSet {
            let value = authorizationStatusSender
            if value == oldValue { return }
            DispatchQueue.main.async {
                self.authorizationStatus = value
            }
        }
    }

    @Atomic var terminalInstanceSender: [PersistTerminalInstance] = [] {
        didSet {
            let value = terminalInstanceSender
            if value == oldValue { return }
            DispatchQueue.main.async {
                self.terminalInstance = value
            }
        }
    }

    // MARK: SENDER ⬆️ ANY THREAD -> MAIN THREAD ---

    // MARK: - -- DONT TOUCH THESE VALUES ⬇️

    @Published var serverDescriptorsSorted: [String] = []
    @Published var serverSectionsSorted: [String] = []
    @Published var serverDescriptorsSortedSupervised: [String] = []
    @Published var authorizationStatus = AppAuthorizationStatus.unauthorized
    @Published var terminalInstance = [PersistTerminalInstance]()

    var notificationObservers: [NSObjectProtocol] = []
    private var terminalBackgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var terminalBackgroundTimeExpired = false
    private var isInBackground = false

    // MARK: DONT TOUCH THESE VALUES ⬆️ ---

    func applicationBecomeActive() {
        isInBackground = false
        terminalBackgroundTimeExpired = false
        endTerminalBackgroundTask()
        terminalInstanceSender.forEach { $0.checkConnectionOnResume() }
        if applicationProtected, authorizationStatus != .authorized {
            startUserAuthentication()
        }
    }

    func applicationBecomeInactive() {
        if applicationProtected {
            authorizationStatusSender = .unauthorized
        }
    }

    func applicationEnterBackground() {
        isInBackground = true
        applicationBecomeInactive()
        beginTerminalBackgroundTaskIfNeeded()
    }

    func terminalConnectionDidOpen() {
        guard isInBackground else { return }
        if terminalBackgroundTimeExpired {
            terminalInstanceSender.forEach { $0.suspendMaintenance() }
        } else {
            beginTerminalBackgroundTaskIfNeeded()
        }
    }

    func terminalConnectionDidClose() {
        let hasConnection = terminalInstanceSender.contains {
            $0.connectionStatus == .connected || $0.connectionStatus == .checking
        }
        if !hasConnection { endTerminalBackgroundTask() }
    }

    private func beginTerminalBackgroundTaskIfNeeded() {
        guard !terminalBackgroundTimeExpired, terminalBackgroundTask == .invalid,
              terminalInstanceSender.contains(where: {
                  $0.connectionStatus == .connected || $0.connectionStatus == .checking
              }) else { return }
        terminalBackgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Terminal SSH") { [weak self] in
            guard let self else { return }
            self.terminalBackgroundTimeExpired = true
            self.terminalInstanceSender.forEach { $0.suspendMaintenance() }
            self.endTerminalBackgroundTask()
        }
        if terminalBackgroundTask == .invalid {
            terminalBackgroundTimeExpired = true
            terminalInstanceSender.forEach { $0.suspendMaintenance() }
        }
    }

    private func endTerminalBackgroundTask() {
        guard terminalBackgroundTask != .invalid else { return }
        let task = terminalBackgroundTask
        terminalBackgroundTask = .invalid
        UIApplication.shared.endBackgroundTask(task)
    }
}
