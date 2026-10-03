//
//  PersistTerminalInstance.swift
//  ServerDash
//

import GhosttyTerminal
import NMSSH
import PTFoundation
import SwiftUI

/// Owns one long-lived SSH shell and the Ghostty terminal state attached to it.
///
/// SSH is the transport; Ghostty is only the terminal emulator/rendering layer.
/// Keeping those responsibilities separate lets us replace either side without
/// touching the other.
final class PersistTerminalInstance: NSObject, Identifiable, ObservableObject {
    let id = UUID()

    var terminalTitle = ""
    private(set) var openDate = Date()

    enum ConnectionStatus {
        case connecting, connected, checking, disconnected, closed
    }

    @Published private(set) var connectionStatus: ConnectionStatus = .connecting
    @Published private(set) var disconnectReason: String?

    private var serverDescriptor: PTServerManager.ServerDescriptor?
    private var maintenanceTimer: Timer?
    private var maintenanceInFlight = false
    private var probeStartedAt: TimeInterval?
    private var lastHeartbeat: TimeInterval = 0
    private var connectionAttempt = UUID()
    private var channelDelegate: TerminalChannelDelegate?
    private var maintenanceGeneration = UUID()
    private var viewportSize: (columns: UInt, rows: UInt)?
    // Retain PTFoundation's host-key verifier (NMSSH's session delegate is weak).
    private var connectionStorage: PTSSHClient.PTSSHConnection?
    private var session: NMSSHSession?
    private var queue: DispatchQueue?
    private let stateLock = NSLock()
    private var terminalStateStorage: TerminalViewState?
    // SwiftUI dismantles its UIViewRepresentable when a navigation destination
    // is popped. Keep the native view alive with the SSH session so Ghostty's
    // surface and scrollback survive until the session is terminated.
    private var terminalViewStorage: TerminalView?

    lazy var terminalSession = InMemoryTerminalSession(
        write: { [weak self] data in
            self?.writeInput(data)
        },
        resize: { [weak self] viewport in
            guard let self else { return }
            self.stateLock.lock()
            self.viewportSize = (UInt(viewport.columns), UInt(viewport.rows))
            self.stateLock.unlock()
            self.withConnection { session in
                session.channel.requestSizeWidth(UInt(viewport.columns), height: UInt(viewport.rows))
            }
        },
        suppressesPixelOnlyResizes: true
    )

    @MainActor
    var terminalState: TerminalViewState {
        stateLock.lock()
        defer { stateLock.unlock() }

        if let terminalStateStorage {
            return terminalStateStorage
        }

        let state = TerminalViewState()
        state.configuration = TerminalSurfaceOptions(
            backend: .inMemory(terminalSession)
        )
        state.makePlatformView = { [weak self] in
            guard let self else { return TerminalView(frame: .zero) }
            if let view = self.terminalViewStorage {
                return view
            }
            let view = TerminalView(frame: .zero)
            self.terminalViewStorage = view
            return view
        }
        GhosttyPreferences.shared.apply(to: state)
        terminalStateStorage = state
        return state
    }

    private func withConnection(_ work: @escaping (NMSSHSession) -> Void) {
        stateLock.lock()
        let session = self.session
        let queue = self.queue
        stateLock.unlock()

        guard let session, let queue else { return }
        queue.async { [weak self] in
            guard let self else { return }
            self.stateLock.lock()
            let isCurrent = self.session === session
            self.stateLock.unlock()
            guard isCurrent else { return }
            work(session)
        }
    }

    private func writeInput(_ data: Data) {
        withConnection { [weak self] session in
            if !session.channel.write(data, error: nil, timeout: 2) {
                DispatchQueue.main.async {
                    self?.disconnect(session, reason: NSLocalizedString("TERMINAL_TRANSPORT_FAILED", comment: "Transport failed"))
                }
            }
        }
    }

    // Lifecycle changes and published UI state are confined to the main queue.
    private func setConnection(_ shell: PTSSHClient.PTSSHConnection) {
        dispatchPrecondition(condition: .onQueue(.main))
        stateLock.lock()
        connectionStorage = shell
        session = shell.representedConnection
        queue = shell.springLoadedQueue
        stateLock.unlock()
        connectionStatus = .connected
        disconnectReason = nil
        probeStartedAt = nil
        lastHeartbeat = 0
        stateLock.lock()
        let viewport = viewportSize
        stateLock.unlock()
        withConnection { session in
            session.timeout = 2
            session.channel.configureKeepAlive(withInterval: 30)
            if let viewport {
                session.channel.requestSizeWidth(viewport.columns, height: viewport.rows)
            }
        }
        startMaintenance()
    }

    static func openConnection(
        withServer descriptor: PTServerManager.ServerDescriptor,
        onComplete: @escaping (PersistTerminalInstance?) -> Void
    ) {
        DispatchQueue.main.async {
            let instance = PersistTerminalInstance()
            instance.serverDescriptor = descriptor
            instance.connect { success in
                if success {
                    Agent.shared.createTerminal(withInstance: instance)
                    Agent.shared.terminalConnectionDidOpen()
                }
                onComplete(success ? instance : nil)
            }
        }
    }

    func reconnect() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard connectionStatus == .disconnected else { return }
        // Reset shell-specific terminal modes without clearing scrollback.
        terminalSession.receive("\u{1B}[?1049l\u{1B}[!p\u{1B}[?2004l\r\n[*] Reconnecting — starting a new shell\r\n")
        connect { success in
            if success { Agent.shared.terminalConnectionDidOpen() }
        }
    }

    private func connect(onComplete: @escaping (Bool) -> Void) {
        guard let descriptor = serverDescriptor else { onComplete(false); return }
        connectionStatus = .connecting
        disconnectReason = nil
        let attempt = UUID()
        connectionAttempt = attempt
        let delegate = TerminalChannelDelegate(instance: self, attempt: attempt)
        channelDelegate = delegate
        DispatchQueue.global(qos: .userInitiated).async {
            var shell: PTSSHClient.PTSSHConnection?
            var title: String?
            let authorized = !Agent.shared.terminalProtectionEnabled
                || Agent.shared.authenticationWithBioIDSyncAndReturnIsSuccessOrError().0
            if authorized, let server = PTServerManager.shared.obtainServer(withKey: descriptor) {
                title = server.obtainPossibleName()
                shell = PTServerManager.shared.openShellConnection(
                    onServer: server.uuid, withEnvironment: [:], withDelegate: delegate
                )
            }
            DispatchQueue.main.async {
                guard self.connectionAttempt == attempt, self.connectionStatus != .closed else {
                    if let shell {
                        shell.springLoadedQueue.async { shell.representedConnection.disconnect() }
                    }
                    onComplete(false)
                    return
                }
                guard let shell else {
                    self.connectionStatus = .disconnected
                    self.disconnectReason = NSLocalizedString("CONNECT_FAILED", comment: "Connection failed")
                    onComplete(false)
                    return
                }
                if self.terminalTitle.isEmpty { self.openDate = Date() }
                self.terminalTitle = title ?? self.terminalTitle
                self.setConnection(shell)
                // The shell may exit before openShellConnection returns.
                self.checkConnectionOnResume()
                onComplete(true)
            }
        }
    }

    private func startMaintenance() {
        maintenanceTimer?.invalidate()
        let interval: TimeInterval = connectionStatus == .checking ? 1 : 10
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.maintainConnection()
        }
        RunLoop.main.add(timer, forMode: .common)
        maintenanceTimer = timer
    }

    func suspendMaintenance() {
        maintenanceTimer?.invalidate()
        maintenanceTimer = nil
        // Suspended wall-clock time must not count toward a probe timeout.
        probeStartedAt = nil
        maintenanceGeneration = UUID()
    }

    func checkConnectionOnResume() {
        guard connectionStatus == .connected || connectionStatus == .checking else { return }
        maintenanceGeneration = UUID()
        connectionStatus = .checking
        probeStartedAt = ProcessInfo.processInfo.systemUptime
        startMaintenance()
        maintainConnection()
    }

    private func maintainConnection() {
        // The queue may be busy writing. Enforce the probe deadline from the
        // main timer rather than waiting for a queued SSH operation to return.
        if connectionStatus == .checking,
           UIApplication.shared.applicationState == .active,
           let started = probeStartedAt,
           ProcessInfo.processInfo.systemUptime - started >= 15 {
            stateLock.lock()
            let current = session
            stateLock.unlock()
            if let current {
                disconnect(current, reason: NSLocalizedString("TERMINAL_CHECK_TIMEOUT", comment: "Check timed out"))
            }
            return
        }
        guard !maintenanceInFlight,
              connectionStatus == .connected || connectionStatus == .checking else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let checking = connectionStatus == .checking
        guard checking || now - lastHeartbeat >= 10 else { return }
        stateLock.lock()
        let current = session
        let connectionQueue = queue
        stateLock.unlock()
        guard let current, let connectionQueue else { return }
        maintenanceInFlight = true
        let generation = maintenanceGeneration
        connectionQueue.async { [weak self] in
            guard let self else { return }
            self.stateLock.lock()
            let isCurrent = self.session === current
            self.stateLock.unlock()
            var result = NMSSHConnectionProbeStatus.pending
            if isCurrent {
                if checking {
                    result = current.channel.checkConnection()
                } else {
                    result = current.channel.sendKeepAlive() ? .responsive : .failed
                }
            }
            DispatchQueue.main.async {
                self.maintenanceInFlight = false
                self.stateLock.lock()
                let isCurrent = self.session === current
                self.stateLock.unlock()
                guard isCurrent, self.maintenanceGeneration == generation else { return }
                self.lastHeartbeat = ProcessInfo.processInfo.systemUptime
                switch result {
                case .responsive:
                    if checking {
                        self.connectionStatus = .connected
                        self.probeStartedAt = nil
                        self.startMaintenance()
                    }
                case .failed:
                    self.disconnect(current, reason: NSLocalizedString("TERMINAL_TRANSPORT_FAILED", comment: "Transport failed"))
                case .pending:
                    break
                @unknown default:
                    break
                }
            }
        }
    }

    private func disconnect(_ expected: NMSSHSession, reason: String) {
        stateLock.lock()
        guard session === expected else { stateLock.unlock(); return }
        let connectionQueue = queue
        connectionStorage = nil
        session = nil
        queue = nil
        stateLock.unlock()
        suspendMaintenance()
        connectionStatus = .disconnected
        disconnectReason = reason
        terminalSession.receive("\r\n[*] \(reason)\r\n")
        PTLog.shared.join("Terminal", "Connection disconnected: \(reason)", level: .info)
        // Detach callbacks before cleanup; a late callback cannot affect a new shell.
        connectionQueue?.async {
            expected.channel.delegate = nil
            expected.disconnect()
        }
        Agent.shared.terminalConnectionDidClose()
    }

    fileprivate func receive(_ data: Data, from channel: NMSSHChannel, attempt: UUID) {
        DispatchQueue.main.async {
            guard self.connectionAttempt == attempt, self.connectionStatus != .closed else { return }
            // Initial output can arrive before the connection has been installed.
            if self.connectionStatus == .connecting || self.isCurrent(channel) {
                self.terminalSession.receive(data)
            }
        }
    }

    private func isCurrent(_ channel: NMSSHChannel) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return session === channel.session
    }

    fileprivate func shellDidClose(_ channel: NMSSHChannel, attempt: UUID) {
        DispatchQueue.main.async {
            guard self.connectionAttempt == attempt, self.isCurrent(channel) else { return }
            let reason = channel.shellError?.localizedDescription
                ?? NSLocalizedString("TERMINAL_CONNECTION_CLOSED", comment: "Connection closed")
            self.disconnect(channel.session, reason: reason)
        }
    }

    func terminate() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard connectionStatus != .closed else { return }
        connectionAttempt = UUID()
        stateLock.lock()
        let current = session
        stateLock.unlock()
        if let current {
            disconnect(current, reason: NSLocalizedString("TERMINAL_CONNECTION_CLOSED", comment: "Connection closed"))
        }
        suspendMaintenance()
        connectionStatus = .closed
        let runtime = UInt64(max(0, Date().timeIntervalSince(openDate) * 1000))
        terminalSession.finish(exitCode: 0, runtimeMilliseconds: runtime)
        Agent.shared.removeTerminal(withInstance: self)
    }

    deinit {
        maintenanceTimer?.invalidate()
    }
}

/// Each connection attempt has its own delegate. Late output and close callbacks
/// from an old connection must never change the replacement shell's state.
private final class TerminalChannelDelegate: NSObject, NMSSHChannelDelegate {
    private weak var instance: PersistTerminalInstance?
    private let attempt: UUID

    init(instance: PersistTerminalInstance, attempt: UUID) {
        self.instance = instance
        self.attempt = attempt
    }

    @objc func channel(_ channel: NMSSHChannel, didReadRawData data: Data) {
        instance?.receive(data, from: channel, attempt: attempt)
    }

    @objc func channel(_ channel: NMSSHChannel, didReadRawError error: Data) {
        instance?.receive(error, from: channel, attempt: attempt)
    }

    @objc func channelShellDidClose(_ channel: NMSSHChannel) {
        instance?.shellDidClose(channel, attempt: attempt)
    }
}
