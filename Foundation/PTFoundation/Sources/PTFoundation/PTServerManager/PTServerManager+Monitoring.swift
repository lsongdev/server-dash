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
        executionLock.lock()
        let servers = serverContainer
        executionLock.unlock()

        let now = Date()
        for serverObject in servers.values
        where shouldUpdate(serverObject: serverObject, at: now) {
            if serverObject.supervisionStatus == nil {
                serverObject.supervisionStatus = .init(
                    serverDescriptor: serverObject.server.uuid
                )
            }
            serverObject.supervisionStatus?.pendingUpdate = true

            PTNotificationCenter.shared.postNotification(
                withName: .ServerManager_ServerStatusUpdated,
                attachment: serverObject.server.uuid
            )

            supervisionConcurrentQueue.async {
                self.serverSupervisionUpdateAtomically(fromServer: serverObject)
            }
        }
    }

    private func shouldUpdate(
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

    func finalizeServerStatusUpdate(
        fromServer server: ServerObject,
        errorOccurred: Bool
    ) {
        if server.supervisionStatus == nil {
            server.supervisionStatus = .init(
                serverDescriptor: server.server.uuid
            )
        }

        server.supervisionStatus?.previousUpdate = Date()
        server.supervisionStatus?.pendingUpdate = false
        server.supervisionStatus?.statusUpdated = !errorOccurred
        server.supervisionStatus?.errorOccurred = errorOccurred

        PTNotificationCenter.shared.postNotification(
            withName: .ServerManager_ServerStatusUpdated,
            attachment: server.server.uuid
        )
    }

    @discardableResult
    func serverSupervisionUpdateAtomically(
        fromServer server: ServerObject
    ) -> ServerInfo? {
        guard let info = acquireServerInfo(fromServer: server.server) else {
            finalizeServerStatusUpdate(
                fromServer: server,
                errorOccurred: true
            )
            return nil
        }

        if server.supervisionStatus == nil {
            server.supervisionStatus = .init(
                serverDescriptor: server.server.uuid
            )
        }

        let date = Date()
        server.supervisionStatus?.information = info
        finalizeServerStatusUpdate(
            fromServer: server,
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
