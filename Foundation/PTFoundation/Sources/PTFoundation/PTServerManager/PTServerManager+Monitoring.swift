//
//  PTServerManager+Monitoring.swift
//  PTFoundation
//

import Foundation

extension PTServerManager {
    /// Starts the scheduler that checks which supervised servers are due.
    /// SSH work itself runs on supervisionConcurrentQueue.
    func startMonitoringScheduler() {
        guard monitoringTimer == nil else { return }

        let timer = DispatchSource.makeTimerSource(queue: monitoringQueue)
        timer.schedule(
            deadline: .now() + 3,
            repeating: .milliseconds(500),
            leeway: .milliseconds(100)
        )
        timer.setEventHandler { [weak self] in
            self?.dispatchMonitoringUpdates()
        }
        monitoringTimer = timer
        timer.resume()
    }

    func stopMonitoringScheduler() {
        monitoringTimer?.setEventHandler {}
        monitoringTimer?.cancel()
        monitoringTimer = nil
    }

    private func dispatchMonitoringUpdates() {
        let now = Date()

        executionLock.lock()
        let due = serverContainer.values.filter {
            shouldUpdateLocked(serverObject: $0, at: now)
        }
        for serverObject in due {
            if serverObject.supervisionStatus == nil {
                serverObject.supervisionStatus = .init(
                    serverDescriptor: serverObject.server.uuid
                )
            }
            serverObject.supervisionStatus?.pendingUpdate = true
        }
        executionLock.unlock()

        for serverObject in due {
            postStatusUpdate(for: serverObject)
            supervisionConcurrentQueue.async {
                self.serverSupervisionUpdateAtomically(fromServer: serverObject)
            }
        }
    }

    /// Must be called while executionLock is held.
    private func shouldUpdateLocked(
        serverObject: ServerObject,
        at now: Date
    ) -> Bool {
        guard serverObject.supervised,
              !(serverObject.supervisionStatus?.pendingUpdate ?? false)
        else {
            return false
        }

        let interval = serverObject.server.supervisionTimeInterval
        guard interval > 0 else {
            PTLog.shared.join(
                self,
                "monitoring interval is invalid for \(serverObject.server.obtainPossibleName())",
                level: .warning
            )
            return false
        }

        let previous = serverObject.supervisionStatus?.previousUpdate
            ?? Date(timeIntervalSince1970: 0)
        return Int(now.timeIntervalSince(previous)) >= interval
    }

    private func postStatusUpdate(for server: ServerObject) {
        PTNotificationCenter.shared.postNotification(
            withName: .ServerManager_ServerStatusUpdated,
            attachment: server.server.uuid
        )
    }

    private func finishUpdate(
        server: ServerObject,
        info: ServerInfo?,
        errorOccurred: Bool
    ) {
        executionLock.lock()
        if server.supervisionStatus == nil {
            server.supervisionStatus = .init(
                serverDescriptor: server.server.uuid
            )
        }
        server.supervisionStatus?.previousUpdate = Date()
        server.supervisionStatus?.pendingUpdate = false
        server.supervisionStatus?.statusUpdated = !errorOccurred
        server.supervisionStatus?.errorOccurred = errorOccurred
        if let info {
            server.supervisionStatus?.information = info
        }
        executionLock.unlock()

        postStatusUpdate(for: server)
    }

    @discardableResult
    func serverSupervisionUpdateAtomically(
        fromServer server: ServerObject
    ) -> ServerInfo? {
        guard let info = acquireServerInfo(fromServer: server.server) else {
            finishUpdate(
                server: server,
                info: nil,
                errorOccurred: true
            )
            return nil
        }

        let date = Date()
        finishUpdate(
            server: server,
            info: info,
            errorOccurred: false
        )

        databaseConcurrentQueue.async {
            guard PTFoundation.requestingUserDefault(
                forKey: .supervisionRecordEnabled,
                defaultValue: true
            ) else {
                return
            }
            self.recordServerStatus(
                serverDescriptor: server.server.uuid,
                info: info,
                date: date
            )
        }

        synchronizeObjects()
        return info
    }
}
