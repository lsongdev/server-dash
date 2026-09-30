//
//  FunctionSet+SSH.swift
//  PTFoundation
//
//  Created by Lakr Aream on 12/13/20.
//

import Foundation
import NMSSH

/// Pins SSH host fingerprints using trust-on-first-use.
///
/// Credentials prove who the user is to the server; this independently proves
/// that future connections reach the same server. Fingerprints are not secret,
/// so UserDefaults is sufficient storage for this pin.
fileprivate final class PTSSHHostKeyVerifier: NSObject, NMSSHSessionDelegate {
    private let storageKey: String

    init(host: String, port: Int32) {
        storageKey = "wiki.qaq.serverdash.hostkey.\(host.lowercased()):\(port)"
    }

    func session(
        _ session: NMSSHSession,
        shouldConnectToHostWithFingerprint fingerprint: String
    ) -> Bool {
        let defaults = UserDefaults.standard
        if let known = defaults.string(forKey: storageKey) {
            let matches = known == fingerprint
            if !matches {
                PTLog.shared.join(
                    "SSH",
                    "host key changed for \(session.host):\(session.port)",
                    level: .critical
                )
            }
            return matches
        }

        // Trust on first use. A later connection must present exactly the
        // same host key fingerprint or it is rejected before authentication.
        defaults.set(fingerprint, forKey: storageKey)
        PTLog.shared.join(
            "SSH",
            "trusted first host key for \(session.host):\(session.port)",
            level: .info
        )
        return true
    }
}

/// SSH 方法集
public final class PTSSHClient {
    public static let shared = PTSSHClient()
    private init() {}

    /// A live SSH connection and its serialized access queue.
    public struct PTSSHConnection {
        public let representedConnection: NMSSHSession
        public let springLoadedQueue: DispatchQueue
        // NMSSH keeps its delegate weak; retain the verifier for this session.
        fileprivate let hostKeyVerifier: PTSSHHostKeyVerifier

        fileprivate init(
            connection: NMSSHSession,
            queue: DispatchQueue,
            hostKeyVerifier: PTSSHHostKeyVerifier
        ) {
            representedConnection = connection
            springLoadedQueue = queue
            self.hostKeyVerifier = hostKeyVerifier
        }
    }

    /// Single remote command used to collect one monitoring snapshot.
    internal let outputSeparator = "[*******]"
    internal enum ScriptCollection: String, CaseIterable {
        case identifySystem = "/usr/bin/env uname -s"
        case obtainSnapshot =
            """
            export LC_ALL=C
            printf '__SERVER_DASH_CPU_0__\\n'
            /bin/cat /proc/stat
            printf '__SERVER_DASH_NET_0__\\n'
            /bin/cat /proc/net/dev
            printf '__SERVER_DASH_MEMORY__\\n'
            /bin/cat /proc/meminfo
            printf '__SERVER_DASH_FILESYSTEM__\\n'
            /bin/df -Pk
            printf '__SERVER_DASH_HOSTNAME__\\n'
            /usr/bin/env uname -n
            printf '__SERVER_DASH_UPTIME__\\n'
            /bin/cat /proc/uptime
            printf '__SERVER_DASH_LOAD__\\n'
            /bin/cat /proc/loadavg
            printf '__SERVER_DASH_RELEASE__\\n'
            /bin/cat /etc/os-release
            /bin/sleep 1
            printf '__SERVER_DASH_CPU_1__\\n'
            /bin/cat /proc/stat
            printf '__SERVER_DASH_NET_1__\\n'
            /bin/cat /proc/net/dev
            printf '__SERVER_DASH_END__\\n'
            """
        case obtainDarwinSnapshot =
            """
            export LC_ALL=C
            printf '__SERVER_DASH_TOP__\\n'
            /usr/bin/top -l 1 -n 0 -s 0
            printf '__SERVER_DASH_MEMORY__\\n'
            /usr/sbin/sysctl -n hw.memsize
            /usr/bin/vm_stat
            /usr/sbin/sysctl -n vm.swapusage
            printf '__SERVER_DASH_FILESYSTEM__\\n'
            /bin/df -Pk /System/Volumes/Data 2>/dev/null || /bin/df -Pk /
            printf '__SERVER_DASH_HOSTNAME__\\n'
            /usr/bin/uname -n
            printf '__SERVER_DASH_UPTIME__\\n'
            /usr/sbin/sysctl -n kern.boottime
            printf '__SERVER_DASH_RELEASE__\\n'
            /usr/bin/sw_vers -productVersion
            printf '__SERVER_DASH_NET_0__\\n'
            /usr/sbin/netstat -ibn
            /bin/sleep 1
            printf '__SERVER_DASH_NET_1__\\n'
            /usr/sbin/netstat -ibn
            printf '__SERVER_DASH_END__\\n'
            """
    }

    /// 用于构建传递参数
    internal struct SystemLoadInternal {
        var runningProcess: Int = 0
        var totalProcess: Int = 0
        var load1avg: Float = 0
        var load5avg: Float = 0
        var load15avg: Float = 0
    }

    /// 连接凭证
    public struct PTSSHConnectionCandidate {
        let host: String
        let port: Int32
        let user: String
        let pass: String
        let keypass: String
        let treatPassAsKey: Bool
        internal init(host: String,
                      port: Int32,
                      user: String,
                      pass: String,
                      keypass: String,
                      treatPassAsKey: Bool)
        {
            self.host = host
            self.port = port
            self.user = user
            self.pass = pass
            self.keypass = keypass
            self.treatPassAsKey = treatPassAsKey
        }
    }

    /// 初始化连接
    /// - Parameter server: 服务器对象
    /// - Returns: 连接凭证 PTSSHConnectionCandidate
    public func setupConnection(withServer server: PTServerManager.Server) -> PTSSHConnectionCandidate? {
        guard let account = PTAccountManager.shared.retrieveAccountWith(key: server.accountDescriptor) else {
            return nil
        }

        switch account.type {
        case .secureShellWithPassword:
            guard let accessObject = account.obtainDecryptedObject() else {
                return nil
            }
            return PTSSHConnectionCandidate(host: server.host, port: server.port,
                                            user: accessObject.account, pass: accessObject.key, keypass: "",
                                            treatPassAsKey: false)
        case .secureShellWithKey:
            guard let accessObject = account.obtainDecryptedObject() else {
                return nil
            }
            guard let attach = accessObject.representedObject,
                  let keyStr = String(data: attach, encoding: .utf8)
            else {
                return nil
            }
            return PTSSHConnectionCandidate(host: server.host, port: server.port,
                                            user: accessObject.account, pass: keyStr, keypass: accessObject.key,
                                            treatPassAsKey: true)
        }
    }

    /// 获取用户名
    /// - Parameter candidate: 连接凭证 PTSSHConnectionCandidate
    /// - Returns: 用户名
    public func getUsername(withCandidate candidate: PTSSHConnectionCandidate) -> String {
        candidate.user
    }

    /// 获取密钥
    /// - Parameter candidate: 连接凭证 PTSSHConnectionCandidate
    /// - Returns: 密钥字符串
    public func getKeyFileString(withCandidate candidate: PTSSHConnectionCandidate) -> String? {
        candidate.treatPassAsKey ? candidate.pass : nil
    }

    /// 连接
    /// - Parameter candidate: 连接凭证 PTSSHConnectionCandidate
    /// - Returns: 连接的句柄 和 错误字符串 如果有
    public typealias PTSSHConnectionAttempt = (PTSSHConnection?, String?)
    public func connect(withCandidate ticket: PTSSHConnectionCandidate) -> PTSSHConnectionAttempt {
        let queue = DispatchQueue(label: "wiki.qaq.libssh2.serial.\(UUID().uuidString)")
        var ret: PTSSHConnectionAttempt = (nil, nil)
        queue.sync {
            let ssh = NMSSHSession(host: ticket.host, port: Int(ticket.port), andUsername: ticket.user)
            let hostKeyVerifier = PTSSHHostKeyVerifier(host: ticket.host, port: ticket.port)
            ssh.delegate = hostKeyVerifier
            // Prefer SHA-1 over NMSSH's historical MD5 default. This is only
            // used as a stable host-key identifier for TOFU pinning.
            if let sha1 = NMSSHSessionHash(rawValue: 1) {
                ssh.fingerprintHash = sha1
            }
            ssh.connect()
            if !ssh.isConnected {
                ret = (nil, "[SSH] failed to connect")
                return
            }
            if ticket.treatPassAsKey {
                ssh.authenticateBy(inMemoryPublicKey: nil, privateKey: ticket.pass, andPassword: ticket.keypass)
            } else {
                ssh.authenticate(byPassword: ticket.pass)
            }
            if !ssh.isAuthorized {
                ret = (nil, "[SSH] failed to authorize")
                return
            }
            ret = (
                PTSSHConnection(
                    connection: ssh,
                    queue: queue,
                    hostKeyVerifier: hostKeyVerifier
                ),
                nil
            )
        }
        return ret
    }

    /// 断开连接
    /// - Parameter object: 连接句柄 PTSSHConnection
    public func disconnect(withConnection object: PTSSHConnection) {
        object.springLoadedQueue.sync {
            object.representedConnection.disconnect()
        }
    }

    /// 获取远端服务器信息
    /// - Parameters:
    /// - Parameter connection: 连接句柄 PTSSHConnection
    ///   - command: 脚本
    /// - Returns: 执行输出
    private func downloadResultFrom(withConnection object: PTSSHConnection, command: ScriptCollection) -> String? {
        
        guard (
            object.representedConnection.isConnected
                && object.representedConnection.isAuthorized
        ) else {
            PTLog.shared.join(self,
                              "connection broken, cancel request",
                              level: .error)
            return nil
        }

        var result: String?
        object.springLoadedQueue.sync {
            result = object.representedConnection.channel.execute(command.rawValue, error: nil)
        }
        if result?.count ?? 0 < 1 { result = nil }
        return result
    }

    /// Collect one complete server snapshot in a single remote command.
    ///
    /// CPU and network deltas share the same one-second sample window. Static
    /// data is collected between the two samples, so one refresh performs one
    /// SSH exec instead of a chain of independent round trips.
    public func obtainServerInfo(withConnection connection: PTSSHConnection) -> PTServerManager.ServerInfo? {
        guard let platform = downloadResultFrom(withConnection: connection, command: .identifySystem) else {
            return nil
        }
        if platform.trimmingCharacters(in: .whitespacesAndNewlines) == "Darwin" {
            guard let intake = downloadResultFrom(withConnection: connection, command: .obtainDarwinSnapshot) else {
                return nil
            }
            return buildDarwinServerInfo(intake: intake)
        }

        guard let intake = downloadResultFrom(withConnection: connection, command: .obtainSnapshot) else {
            return nil
        }

        let sections = buildSnapshotSections(intake)
        guard
            let cpu0 = sections["__SERVER_DASH_CPU_0__"],
            let cpu1 = sections["__SERVER_DASH_CPU_1__"],
            let net0 = sections["__SERVER_DASH_NET_0__"],
            let net1 = sections["__SERVER_DASH_NET_1__"],
            let memory = sections["__SERVER_DASH_MEMORY__"],
            let fileSystem = sections["__SERVER_DASH_FILESYSTEM__"],
            let hostname = sections["__SERVER_DASH_HOSTNAME__"],
            let uptime = sections["__SERVER_DASH_UPTIME__"],
            let load = sections["__SERVER_DASH_LOAD__"],
            let release = sections["__SERVER_DASH_RELEASE__"]
        else {
            PTLog.shared.join(self, "server snapshot is missing one or more sections", level: .error)
            return nil
        }

        let processInfo = buildServerProcessInfo(intake: cpu0 + outputSeparator + cpu1)
        let memoryInfo = buildMemoryInfo(intake: memory)
        let fileSystemInfo = buildServerFileSystemInfo(intake: fileSystem)
        let networkInfo = buildServerNetworkInfo(intake: net0 + outputSeparator + net1)
        let loadInfo = buildLoadStatus(intake: load)
        let systemInfo = PTServerManager.ServerSystemInfo(
            release: buildReleaseName(intake: release),
            uptimeInSec: buildUptime(intake: uptime),
            hostname: buildHostname(intake: hostname),
            runningProcs: loadInfo.runningProcess,
            totalProcs: loadInfo.totalProcess,
            load1: loadInfo.load1avg,
            load5: loadInfo.load5avg,
            load15: loadInfo.load15avg
        )

        if processInfo == PTServerManager.ServerProcessInfo(),
           memoryInfo == PTServerManager.ServerMemoryInfo()
        {
            return nil
        }

        return PTServerManager.ServerInfo(
            ServerProcessInfo: processInfo,
            ServerFileSystemInfo: fileSystemInfo,
            ServerMemoryInfo: memoryInfo,
            ServerSystemInfo: systemInfo,
            ServerNetworkInfo: networkInfo
        )
    }

    /// macOS has no Linux /proc tree. Translate its standard tools into the
    /// same snapshot model used by the dashboard and history views.
    internal func buildDarwinServerInfo(intake: String) -> PTServerManager.ServerInfo? {
        let sections = buildSnapshotSections(intake)
        guard let top = sections["__SERVER_DASH_TOP__"],
              let memory = sections["__SERVER_DASH_MEMORY__"],
              let fileSystem = sections["__SERVER_DASH_FILESYSTEM__"],
              let hostname = sections["__SERVER_DASH_HOSTNAME__"],
              let uptime = sections["__SERVER_DASH_UPTIME__"],
              let release = sections["__SERVER_DASH_RELEASE__"],
              let net0 = sections["__SERVER_DASH_NET_0__"],
              let net1 = sections["__SERVER_DASH_NET_1__"],
              let processInfo = buildDarwinProcessInfo(top),
              let memoryInfo = buildDarwinMemoryInfo(memory)
        else {
            PTLog.shared.join(self, "macOS snapshot is incomplete", level: .error)
            return nil
        }

        let diskInfo = buildServerFileSystemInfo(intake: fileSystem).map { item in
            if item.mountPoint == "/System/Volumes/Data" {
                return PTServerManager.ServerFileSystemInfo(
                    mountPoint: "/", free: item.freeBytes, used: item.usedBytes
                )
            }
            return item
        }
        let load = buildDarwinLoadInfo(top)
        let bootTime = uptime
            .components(separatedBy: "sec = ")
            .dropFirst()
            .first?
            .split(separator: ",")
            .first
            .flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        let uptimeSeconds = bootTime.map { max(0, Int(Date().timeIntervalSince1970) - $0) } ?? 0
        let version = release.trimmingCharacters(in: .whitespacesAndNewlines)

        return PTServerManager.ServerInfo(
            ServerProcessInfo: processInfo,
            ServerFileSystemInfo: diskInfo,
            ServerMemoryInfo: memoryInfo,
            ServerSystemInfo: PTServerManager.ServerSystemInfo(
                release: version.isEmpty ? "macOS" : "macOS \(version)",
                uptimeInSec: uptimeSeconds,
                hostname: buildHostname(intake: hostname),
                runningProcs: load.runningProcess,
                totalProcs: load.totalProcess,
                load1: load.load1avg,
                load5: load.load5avg,
                load15: load.load15avg
            ),
            ServerNetworkInfo: buildDarwinNetworkInfo(first: net0, second: net1)
        )
    }

    private func buildDarwinProcessInfo(_ top: String) -> PTServerManager.ServerProcessInfo? {
        guard let line = top.components(separatedBy: "\n").first(where: { $0.hasPrefix("CPU usage:") }) else {
            return nil
        }
        let values = line.components(separatedBy: ",")
        guard values.count >= 3,
              let user = Float((values[0].components(separatedBy: "%").first ?? "")
                  .replacingOccurrences(of: "CPU usage:", with: "")
                  .trimmingCharacters(in: .whitespaces)),
              let system = Float((values[1].components(separatedBy: "%").first ?? "")
                  .trimmingCharacters(in: .whitespaces)),
              let idle = Float((values[2].components(separatedBy: "%").first ?? "")
                  .trimmingCharacters(in: .whitespaces))
        else {
            return nil
        }
        let summary = PTServerManager.ServerProcessInfoCalculatedElement(
            system: system,
            user: user,
            iowait: 0,
            nice: 0,
            sum: max(0, min(100, 100 - idle))
        )
        return PTServerManager.ServerProcessInfo(summary: summary, cores: [:])
    }

    private func buildDarwinLoadInfo(_ top: String) -> SystemLoadInternal {
        var result = SystemLoadInternal()
        for line in top.components(separatedBy: "\n") {
            if line.hasPrefix("Processes:") {
                let fields = line.components(separatedBy: ",")
                result.totalProcess = Int(fields.first?
                    .replacingOccurrences(of: "Processes:", with: "")
                    .split(separator: " ").first ?? "") ?? 0
                if fields.count > 1 {
                    result.runningProcess = Int(fields[1]
                        .trimmingCharacters(in: .whitespaces)
                        .split(separator: " ").first ?? "") ?? 0
                }
            } else if line.hasPrefix("Load Avg:") {
                let values = line.replacingOccurrences(of: "Load Avg:", with: "")
                    .split(separator: ",")
                    .compactMap { Float($0.trimmingCharacters(in: .whitespaces)) }
                if values.count == 3 {
                    result.load1avg = values[0]
                    result.load5avg = values[1]
                    result.load15avg = values[2]
                }
            }
        }
        return result
    }

    private func buildDarwinMemoryInfo(_ intake: String) -> PTServerManager.ServerMemoryInfo? {
        let lines = intake.components(separatedBy: "\n")
        guard let totalBytes = lines.first.flatMap({ UInt64($0.trimmingCharacters(in: .whitespaces)) }),
              let pageLine = lines.first(where: { $0.contains("page size of ") }),
              let pageSize = pageLine.components(separatedBy: "page size of ").last?
                  .split(separator: " ").first.flatMap({ UInt64($0) })
        else {
            return nil
        }

        func pages(_ name: String) -> UInt64 {
            guard let line = lines.first(where: { $0.hasPrefix(name) }),
                  let value = line.split(separator: ":").last?
                      .trimmingCharacters(in: .whitespacesAndNewlines)
                      .replacingOccurrences(of: ".", with: ""),
                  let count = UInt64(value)
            else { return 0 }
            return count
        }

        let freeKB = Float(pages("Pages free:") * pageSize) / 1024
        let cachedKB = Float((pages("Pages inactive:") + pages("Pages speculative:")) * pageSize) / 1024
        let totalKB = Float(totalBytes) / 1024
        let swapTokens = lines.first(where: { $0.hasPrefix("total = ") })?
            .split(whereSeparator: \.isWhitespace).map(String.init) ?? []
        func swapValue(after key: String) -> Float {
            guard let index = swapTokens.firstIndex(of: key), index + 2 < swapTokens.count else { return 0 }
            return darwinSizeKB(swapTokens[index + 2])
        }

        return PTServerManager.ServerMemoryInfo(
            total: totalKB,
            free: min(freeKB, totalKB),
            buffers: 0,
            cached: min(cachedKB, max(0, totalKB - freeKB)),
            swapTotal: swapValue(after: "total"),
            swapFree: swapValue(after: "free")
        )
    }

    private func darwinSizeKB(_ raw: String) -> Float {
        guard let unit = raw.last,
              let value = Float(raw.dropLast())
        else { return 0 }
        switch unit {
        case "K": return value
        case "M": return value * 1024
        case "G": return value * 1024 * 1024
        case "T": return value * 1024 * 1024 * 1024
        default: return Float(raw) ?? 0
        }
    }

    private func buildDarwinNetworkInfo(first: String, second: String) -> [PTServerManager.ServerNetworkInfo] {
        func counters(_ raw: String) -> [String: (rx: Int, tx: Int)] {
            var result: [String: (rx: Int, tx: Int)] = [:]
            for line in raw.components(separatedBy: "\n") {
                let fields = line.split(whereSeparator: \.isWhitespace)
                guard fields.count >= 10,
                      fields[2].hasPrefix("<Link#"),
                      let rx = Int(fields[6]),
                      let tx = Int(fields[9])
                else { continue }
                result[String(fields[0]).replacingOccurrences(of: "*", with: "")] = (rx, tx)
            }
            return result
        }

        let before = counters(first)
        let after = counters(second)
        return before.compactMap { name, initial in
            guard let current = after[name],
                  current.rx >= initial.rx,
                  current.tx >= initial.tx
            else { return nil }
            return PTServerManager.ServerNetworkInfo(
                device: name,
                rxBytesPerSec: current.rx - initial.rx,
                txBytesPerSec: current.tx - initial.tx
            )
        }
    }

    private func buildSnapshotSections(_ intake: String) -> [String: String] {
        var result: [String: String] = [:]
        var current: String?

        for rawLine in intake.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if line.hasPrefix("__SERVER_DASH_"), line.hasSuffix("__") {
                if line == "__SERVER_DASH_END__" {
                    current = nil
                } else {
                    current = line
                    result[line] = ""
                }
                continue
            }

            guard let current else { continue }
            result[current, default: ""] += line + "\n"
        }

        return result
    }

    internal func buildServerProcessInfo(intake: String) -> PTServerManager.ServerProcessInfo {
        let sep = intake.components(separatedBy: outputSeparator)
        if sep.count != 2 {
            PTLog.shared.join(self,
                              "captured info from remote proc file system is invalid",
                              level: .error)
            return .init()
        }
        let priv = sep[0]
        let curr = sep[1]

        func buildUp(raw: String) -> (PTServerManager.ServerProcessStatus?, [String: PTServerManager.ServerProcessStatus]) {
            var result = [String: PTServerManager.ServerProcessStatus]()
            var summary: PTServerManager.ServerProcessStatus?
            for line in raw.components(separatedBy: "\n") where line.hasPrefix("cpu") {
                var line = line
                while line.contains("  ") {
                    line = line.replacingOccurrences(of: "  ", with: " ")
                }
                let cut = line.components(separatedBy: " ")
                if cut.count != 11 {
                    PTLog.shared.join(self,
                                      "information from remote system failed to match data set",
                                      level: .error)
                    PTLog.shared.join(self,
                                      "* \(line)",
                                      level: .error)
                    continue
                }
                let info = PTServerManager.ServerProcessStatus(user: Float(cut[1]) ?? 0,
                                                               nice: Float(cut[2]) ?? 0,
                                                               system: Float(cut[3]) ?? 0,
                                                               idle: Float(cut[4]) ?? 0,
                                                               iowait: Float(cut[5]) ?? 0,
                                                               irq: Float(cut[6]) ?? 0,
                                                               softIrq: Float(cut[7]) ?? 0,
                                                               steal: Float(cut[8]) ?? 0,
                                                               guest: Float(cut[9]) ?? 0)
                if cut[0] == "cpu" {
                    summary = info
                    continue
                }
                if result[cut[0]] != nil {
                    PTLog.shared.join(self,
                                      "information from remote system is broken",
                                      level: .error)
                    return (nil, [:])
                }
                result[cut[0]] = info
            }
            return (summary, result)
        }

        let resultPriv = buildUp(raw: priv)
        let resultCurr = buildUp(raw: curr)

        guard let privSum = resultPriv.0 else {
            PTLog.shared.join(self,
                              "captured info from remote proc file system is invalid",
                              level: .error)
            return .init()
        }
        let privAll = resultPriv.1
        guard let currSum = resultCurr.0 else {
            PTLog.shared.join(self,
                              "captured info from remote proc file system is invalid",
                              level: .error)
            return .init()
        }
        let currAll = resultCurr.1

        func calculateInfo(priv: PTServerManager.ServerProcessStatus,
                           curr: PTServerManager.ServerProcessStatus)
            -> PTServerManager.ServerProcessInfoCalculatedElement
        {
            let preAll = priv.user + priv.nice + priv.system + priv.idle + priv.iowait + priv.irq + priv.softIrq + priv.steal + priv.guest
            let nowAll = curr.user + curr.nice + curr.system + curr.idle + curr.iowait + curr.irq + curr.softIrq + curr.steal + curr.guest

            let total = nowAll - preAll
            let privUsedTotal = priv.user + priv.nice + priv.system + priv.iowait
            let currUsedTotal = curr.user + curr.nice + curr.system + curr.iowait

            return PTServerManager.ServerProcessInfoCalculatedElement(system: (curr.system - priv.system) / total * 100,
                                                                      user: (curr.user - priv.user) / total * 100,
                                                                      iowait: (curr.iowait - priv.iowait) / total * 100,
                                                                      nice: (curr.nice - priv.nice) / total * 100,
                                                                      sum: (currUsedTotal - privUsedTotal) / total * 100)
        }

        let sumInit: PTServerManager.ServerProcessInfoCalculatedElement = calculateInfo(priv: privSum, curr: currSum)
        var resultPerCore = [String: PTServerManager.ServerProcessInfoCalculatedElement]()

        for (key, priv) in privAll {
            if let curr = currAll[key] {
                resultPerCore[key] = calculateInfo(priv: priv, curr: curr)
            } else {
                PTLog.shared.join(self,
                                  "captured info from remote proc file system is invalid",
                                  level: .error)
                return .init()
            }
        }

        return PTServerManager.ServerProcessInfo(summary: sumInit, cores: resultPerCore)
    }

    /// 获取服务器内存信息
    /// - Parameter connection: 连接句柄 PTSSHConnection
    /// - Returns: 内存信息
    internal func buildMemoryInfo(intake: String) -> PTServerManager.ServerMemoryInfo {
        var info = [String: Float]()
        for line in intake.components(separatedBy: "\n") where line.count > 0 {
            var line = line
            while line.contains("  ") {
                line = line.replacingOccurrences(of: "  ", with: " ")
            }
            line = line.replacingOccurrences(of: ":", with: "")
            let cut = line.components(separatedBy: " ")
            switch cut.count {
            case 2:
                continue
            case 3:
                if cut[2].uppercased() == "KB" {
                    info[cut[0].uppercased()] = Float(cut[1])
                }
            default:
                PTLog.shared.join(self, "remote memory info does not match to known [\(line)]", level: .verbose)
                continue
            }
        }
        return PTServerManager.ServerMemoryInfo(total: info["MemTotal".uppercased()] ?? 0,
                                                free: info["MemFree".uppercased()] ?? 0,
                                                buffers: info["Buffers".uppercased()] ?? 0,
                                                cached: info["Cached".uppercased()] ?? 0,
                                                swapTotal: info["SwapTotal".uppercased()] ?? 0,
                                                swapFree: info["SwapFree".uppercased()] ?? 0)
    }

    /// 获取服务器磁盘信息
    /// - Parameter connection: 连接句柄 PTSSHConnection
    /// - Returns: 磁盘信息
    internal func buildServerFileSystemInfo(intake: String) -> [PTServerManager.ServerFileSystemInfo] {
        var result = [PTServerManager.ServerFileSystemInfo]()
        for line in intake.split(separator: "\n").dropFirst() {
            // Limit to six fields so a mount point containing spaces remains
            // intact as the final field.
            let cut = line.split(
                maxSplits: 5,
                omittingEmptySubsequences: true,
                whereSeparator: { $0 == " " || $0 == "\t" }
            )
            guard cut.count == 6,
                  let freeKB = Float(cut[3]),
                  let usedKB = Float(cut[2]),
                  freeKB >= 0,
                  usedKB >= 0
            else {
                PTLog.shared.join(self,
                                  "remote file system info does not match to known [\(line)]",
                                  level: .verbose)
                continue
            }

            result.append(PTServerManager.ServerFileSystemInfo(
                mountPoint: String(cut[5]),
                free: freeKB * 1024,
                used: usedKB * 1024
            ))
        }
        return result
    }

    /// 获取服务器系统信息
    /// - Parameter connection: 连接句柄 PTSSHConnection
    /// - Returns: 系统信息
    internal func buildHostname(intake: String) -> String {
        intake.replacingOccurrences(of: "\n", with: "")
    }

    /// 构建服务器运行时间
    /// - Parameter raw: 执行脚本的输出对象
    /// - Returns: 运行时间
    internal func buildUptime(intake: String) -> Int {
        let get = intake
        guard let ans = Double(get
            .components(separatedBy: " ")
            .first ?? "")
        else {
            return 0
        }
        if ans < Double(Int.min + 5) || ans > Double(Int.max - 5) {
            return 0
        }
        return Int(ans)
    }

    /// 构建服务器负载信息
    /// - Parameter raw: 执行脚本的输出对象
    /// - Returns: 负载信息
    internal func buildLoadStatus(intake: String) -> SystemLoadInternal {
        var ret = SystemLoadInternal()
        var get = intake
        while get.contains("  ") {
            get = get.replacingOccurrences(of: "  ", with: " ")
        }
        let cut = get.components(separatedBy: " ")
        if cut.count != 5 {
            PTLog.shared.join(self,
                              "remote loadavg info does not match to known [\(get)]",
                              level: .verbose)
        } else {
            if let l1 = Float(cut[0]), l1 != .infinity { ret.load1avg = l1 } else { return .init() }
            if let l5 = Float(cut[1]), l5 != .infinity { ret.load5avg = l5 } else { return .init() }
            if let l15 = Float(cut[2]), l15 != .infinity { ret.load15avg = l15 } else { return .init() }
            let process = cut[3].components(separatedBy: "/")
            if process.count == 2,
               let running = Int(process[0]),
               let total = Int(process[1])
            {
                ret.runningProcess = running
                ret.totalProcess = total
            } else {
                return .init()
            }
        }
        return ret
    }

    /// 构建服务器发行版名称
    /// - Parameter raw: 执行脚本的输出对象
    /// - Returns: 名称
    internal func buildReleaseName(intake: String) -> String {
        var release: String = ""
        var pretty: String?
        var name: String?
        for item in intake.components(separatedBy: "\n") {
            if item.hasPrefix("PRETTY_NAME=") {
                pretty = String(item.dropFirst("PRETTY_NAME=".count))
                break
            }
            if item.hasPrefix("NAME=") {
                name = String(item.dropFirst("NAME=".count))
            }
        }
        if let name = pretty {
            if
                ((name.hasPrefix("\"") && name.hasSuffix("\"")) ||
                    (name.hasPrefix("'") && name.hasSuffix("'"))),
                name.count > 2
            {
                release = String(name.dropFirst().dropLast())
            } else {
                release = name
            }
        } else {
            if let name = name {
                if
                    ((name.hasPrefix("\"") && name.hasSuffix("\"")) ||
                        (name.hasPrefix("'") && name.hasSuffix("'"))),
                    name.count > 2
                {
                    release = String(name.dropFirst().dropLast())
                } else {
                    release = name
                }
            } else {
                release = "Generic Linux"
            }
        }
        return release
    }

    /// 获取服务器网络信息
    /// - Parameter connection: 连接句柄 PTSSHConnection
    /// - Returns: 网络信息
    internal func buildServerNetworkInfo(intake: String) -> [PTServerManager.ServerNetworkInfo] {
        let sep = intake.components(separatedBy: outputSeparator)
        if sep.count != 2 {
            PTLog.shared.join(self, "captured info from remote proc file system is invalid", level: .error)
            return .init()
        }
        let priv = sep[0]
        let curr = sep[1]

        typealias RxTxPair = (Int, Int)

        func build(str: String) -> [String: RxTxPair] {
            var result = [String: RxTxPair]()
            go: for item in str.components(separatedBy: "\n") where item.contains(":") {
                let sepName = item.components(separatedBy: ":")
                if sepName.count != 2 {
                    continue go
                }
                guard var key = sepName.first,
                      var payload = sepName.last
                else {
                    continue go
                }
                while key.hasPrefix(" ") {
                    key.removeFirst()
                }
                while key.hasSuffix(" ") {
                    key.removeLast()
                }
                while payload.contains("  ") {
                    payload = payload.replacingOccurrences(of: "  ", with: " ")
                }
                while payload.hasPrefix(" ") {
                    payload.removeFirst()
                }
                while payload.hasSuffix(" ") {
                    payload.removeLast()
                }
                let split = payload.components(separatedBy: " ")
                if split.count < 10 {
                    continue go
                }
                // 0     1       2    3    4    5     6          7
                // bytes packets errs drop fifo frame compressed multicast
                // 8     9       10   11   12   13    14      15
                // bytes packets errs drop fifo colls carrier compressed
                guard let rxBytes = Int(split[0]),
                      let txBytes = Int(split[8])
                else {
                    continue go
                }
                if result[key] != nil {
                    result.removeValue(forKey: key)
                    continue
                }
                result[key] = (rxBytes, txBytes)
            }
            return result
        }

        let getPriv = build(str: priv)
        let getCurr = build(str: curr)
        var result = [PTServerManager.ServerNetworkInfo]()
        for item in getPriv {
            if let target = getCurr[item.key] {
                let rxIncrease = target.0 - item.value.0
                let txIncrease = target.1 - item.value.1
                if rxIncrease < 0 || txIncrease < 0 {
                    continue
                }
                result.append(PTServerManager.ServerNetworkInfo(device: item.key, rxBytesPerSec: rxIncrease, txBytesPerSec: txIncrease))
            }
        }

        return result
    }

    /// 打开 Shell
    /// - Parameters:
    ///   - connection: 连接句柄 PTSSHConnection
    ///   - withEnvironment: 执行环境
    ///   - delegate: 方法委托
    /// - Returns: 退出状态
    public func openShell(withConnection object: PTSSHConnection,
                          withEnvironment: [String: String],
                          delegate: NMSSHChannelDelegate? = nil) -> PTSSHConnection?
    {
        var booted = false

        object.springLoadedQueue.sync {
            
            object.representedConnection.channel.requestPty = true
            object.representedConnection.channel.ptyTerminalType = .xterm
            object.representedConnection.channel.delegate = delegate

            guard (
                object.representedConnection.isConnected
                    && object.representedConnection.isAuthorized
            ) else {
                PTLog.shared.join(self,
                                  "connection broken, cancel request",
                                  level: .error)
                return
            }
            
            do {
                try object.representedConnection.channel.startShell()
            } catch {
                PTLog.shared.join(self,
                                  "failed to open shell",
                                  level: .error)
                return
            }
            
            // after start shell
            object.representedConnection.channel.environmentVariables = withEnvironment
            
            booted = true
        }
        return booted ? object : nil
    }
}
