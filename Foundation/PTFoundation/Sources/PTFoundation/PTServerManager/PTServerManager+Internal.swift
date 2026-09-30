//
//  PTServerManager.swift
//  PTFoundation
//
//  Created by Lakr Aream on 12/14/20.
//

import Foundation

extension PTServerManager {
    /// 初始化 初始化完成以后就只写不读了
    /// - Parameter toDir: 可读写目录
    /// - Returns: 错误 如果有
    func initialization(toDir: URL, startMonitoring: Bool) -> PTFoundation.InitializationError? {
        // 二次检查
        if PTFoundation.ensureDirExists(atLocation: toDir) != nil {
            return .filePermissionDenied
        }

        // 创建根储存
        baseLocation = toDir.appendingPathComponent(PTServerManager.StoreBase)
        if PTFoundation.ensureDirExists(atLocation: baseLocation) != nil {
            return .filePermissionDenied
        }

        // 注册的储存路径
        let path = baseLocation
            .appendingPathComponent("Registration")
            .appendingPathExtension("plist")

        // 如果文件存在就读取
        if FileManager.default.fileExists(atPath: path.path) {
            do {
                let read = try Data(contentsOf: path)
                if read.count > 0 {
                    let items = try PTFoundation.plistDecoder.decode([String: ServerObject].self, from: read)
                    serverContainer = items
                }
            } catch {
                PTLog.shared.join(self,
                                  "failed to load server registration status from file",
                                  level: .critical)
                return .filePermissionDenied
            }
        }

        // 重制更新状态
        for (_, value) in serverContainer {
            value.supervised = value.server.supervisionTimeInterval > 0
            value.supervisionStatus?.pendingUpdate = false
        }

        // 创建数据库
        if !ensureDatabaseTableExistsSucceed() {
            return .serverManagerDatabaseInitializationFailed
        }

        synchronizeObjects(triggeredByServer: nil)

        PTLog.shared.join(self,
                          "initialization reported \(serverContainer.count) server(s) registered",
                          level: .info)

        serverContainer.filter { _, val -> Bool in
            val.supervised
        }.forEach { _, val in
            PTLog.shared.join(self,
                              "supervision started for: \(val.server.obtainPossibleName())",
                              level: .info)
        }

        if startMonitoring {
            startMonitoringScheduler()
        }

        return nil
    }

    /// 拉取服务器信息
    /// - Parameter server: 服务器对象
    /// - Returns: 信息结构体
    func acquireServerInfo(fromServer server: Server) -> ServerInfo? {
        executionLock.lock()
        supervisionInProgressCount += 1
        executionLock.unlock()
        defer {
            executionLock.lock()
            supervisionInProgressCount -= 1
            executionLock.unlock()
        }
        let function = PTSSHClient.shared

        guard let connectionCandidate = function.setupConnection(withServer: server) else {
            PTLog.shared.join(self,
                              "retrieve server connection candidate failed",
                              level: .error)
            return nil
        }
        let connectionObject = function.connect(withCandidate: connectionCandidate)
        guard let connection = connectionObject.0 else {
            PTLog.shared.join(self,
                              "connection to server at \(server.host):\(server.port) failed with error \(connectionObject.1 ?? "unknown")",
                              level: .error)
            return nil
        }

        let start = Date()
        PTLog.shared.join(self,
                          "Updating server \(server.uuid) status dispatched \(Int(start.timeIntervalSince1970))",
                          level: .info)

        // will disconnect after return
        // will wait for it after dispatch
        defer {
            function.disconnect(withConnection: connection)
        }

        guard let information = function.obtainServerInfo(withConnection: connection) else {
            PTLog.shared.join(self,
                              "update process on server: \(server.uuid) returned invalid information",
                              level: .error)
            return nil
        }

        PTLog.shared.join(self,
                          "Updated server \(server.uuid) status in \(Int(Date().timeIntervalSince(start)))s  \(information.ServerSystemInfo.releaseName) <-> \(server.obtainPossibleName())",
                          level: .info)
        return information
    }

    func synchronizeObjects(triggeredByServer uuid: ServerDescriptor? = nil) {
        // 节流阀
        syncThrottle.throttle {
            // 合成撰写数据
            do {
                // 引用传递 encode 完成再解锁吧
                self.executionLock.lock()
                let copied = self.serverContainer
                let data = try PTFoundation.plistEncoder.encode(copied)
                self.executionLock.unlock()

                self.fileSyncLock.lock()
                try data.write(to: self.baseLocation
                    .appendingPathComponent("Registration")
                    .appendingPathExtension("plist"),
                    options: .atomic)
                self.fileSyncLock.unlock()
            } catch {
                self.fileSyncLock.unlock()
                PTFoundation.runtimeErrorCall(.resourceBroken)
            }

            debugPrint("PTServerManager sync completed")
        }

        // triggeredByServer
        PTNotificationCenter.shared.postNotification(withName: .ServerManager_RegistrationChanged,
                                                     attachment: uuid)
    }
}
