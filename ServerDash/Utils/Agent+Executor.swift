//
//  Agent+Dispatcher.swift
//  ServerDash
//
//  Created by Lakr Aream on 4/30/21.
//

import LocalAuthentication
import PTFoundation
import UIKit

private let authenticationRequestLock = NSLock()
private var authenticationRequestInProgress = false
private var recentAuthenticationSucceeded = false
private let terminalSessionLock = NSLock()

extension Agent {
    func startUserAuthentication() {
        authenticationRequestLock.lock()
        guard !authenticationRequestInProgress else {
            authenticationRequestLock.unlock()
            return
        }
        authenticationRequestInProgress = true
        authenticationRequestLock.unlock()

        authenticationWithBioID {
            authenticationRequestLock.lock()
            authenticationRequestInProgress = false
            authenticationRequestLock.unlock()
            self.authorizationStatusSender = .authorized
        } onFailure: { _ in
            authenticationRequestLock.lock()
            authenticationRequestInProgress = false
            authenticationRequestLock.unlock()
            self.authorizationStatusSender = .unauthorized
        }
    }

    func authenticationWithBioID(onSuccess: @escaping () -> Void,
                                 onFailure: @escaping (String) -> Void)
    {
        authenticationRequestLock.lock()
        let recentlySucceeded = recentAuthenticationSucceeded
        authenticationRequestLock.unlock()
        if recentlySucceeded {
            onSuccess()
            return
        }

        let localAuthenticationContext = LAContext()
        localAuthenticationContext.localizedFallbackTitle = NSLocalizedString("USE_PASSWORD", comment: "Please use password")

        var authorizationError: NSError?
        let reason = NSLocalizedString("AUTH_ERQUIRED", comment: "Authentication enabled and required")

        if localAuthenticationContext.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authorizationError) {
            localAuthenticationContext.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, evaluateError in
                if success {
                    authenticationRequestLock.lock()
                    recentAuthenticationSucceeded = true
                    authenticationRequestLock.unlock()
                    DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
                        authenticationRequestLock.lock()
                        recentAuthenticationSucceeded = false
                        authenticationRequestLock.unlock()
                    }
                    onSuccess()
                } else {
                    guard let error = evaluateError else { return }
                    onFailure(error.localizedDescription)
                }
            }
        } else {
            guard let error = authorizationError else { return }
            onFailure(error.localizedDescription)
        }
    }

    func authenticationWithBioIDSyncAndReturnIsSuccessOrError() -> (Bool, String?) {
        let sem = DispatchSemaphore(value: 0)
        var success = false
        var error: String?
        DispatchQueue.global().async {
            self.authenticationWithBioID {
                success = true
                sem.signal()
            } onFailure: { str in
                error = str
                sem.signal()
            }
        }
        _ = sem.wait(wallTimeout: .now() + 60)
        return (success, error)
    }

    func createTerminal(withInstance: PersistTerminalInstance) {
        terminalSessionLock.lock()
        var sessions = terminalInstanceSender
        sessions.append(withInstance)
        terminalInstanceSender = sessions
        terminalSessionLock.unlock()
    }

    func removeTerminal(withInstance: PersistTerminalInstance) {
        terminalSessionLock.lock()
        terminalInstanceSender = terminalInstanceSender.filter {
            $0.id != withInstance.id
        }
        terminalSessionLock.unlock()
    }
}
