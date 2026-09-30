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
final class PersistTerminalInstance: NSObject, Identifiable, NMSSHChannelDelegate {
    let id = UUID()

    var terminalTitle = ""
    private(set) var openDate = Date()

    private var session: NMSSHSession?
    private var queue: DispatchQueue?
    private let stateLock = NSLock()
    private var terminalStateStorage: TerminalViewState?

    lazy var terminalSession = InMemoryTerminalSession(
        write: { [weak self] data in
            self?.withConnection { session in
                _ = session.channel.write(data, error: nil, timeout: 0)
            }
        },
        resize: { [weak self] viewport in
            self?.withConnection { session in
                session.channel.requestSizeWidth(
                    UInt(viewport.columns),
                    height: UInt(viewport.rows)
                )
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
        terminalStateStorage = state
        return state
    }

    private func withConnection(_ work: @escaping (NMSSHSession) -> Void) {
        stateLock.lock()
        let session = self.session
        let queue = self.queue
        stateLock.unlock()

        guard let session, let queue else { return }
        queue.async {
            work(session)
        }
    }

    private func setConnection(_ shell: PTSSHClient.PTSSHConnection) {
        stateLock.lock()
        session = shell.representedConnection
        queue = shell.springLoadedQueue
        stateLock.unlock()
    }

    static func openConnection(
        withServer descriptor: PTServerManager.ServerDescriptor,
        onComplete: @escaping (PersistTerminalInstance?) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            if Agent.shared.terminalProtectionEnabled {
                let authResult = Agent.shared.authenticationWithBioIDSyncAndReturnIsSuccessOrError()
                guard authResult.0 else {
                    onComplete(nil)
                    return
                }
            }

            guard let server = PTServerManager.shared.obtainServer(withKey: descriptor) else {
                onComplete(nil)
                return
            }

            let instance = PersistTerminalInstance()
            guard let shell = PTServerManager.shared.openShellConnection(
                onServer: server.uuid,
                withEnvironment: [:],
                withDelegate: instance
            ) else {
                onComplete(nil)
                return
            }

            instance.setConnection(shell)
            instance.openDate = Date()
            instance.terminalTitle = server.obtainPossibleName()
            Agent.shared.createTerminal(withInstance: instance)
            onComplete(instance)
        }
    }

    // MARK: - NMSSHChannelDelegate

    @objc
    func channel(_: NMSSHChannel, didReadRawData data: Data) {
        terminalSession.receive(data)
    }

    @objc
    func channel(_: NMSSHChannel, didReadRawError error: Data) {
        terminalSession.receive(error)
    }

    @objc
    func channelShellDidClose(_: NMSSHChannel) {
        terminalSession.receive("\r\n[*] Connection closed\r\n")
        let runtime = UInt64(max(0, Date().timeIntervalSince(openDate) * 1000))
        terminalSession.finish(exitCode: 0, runtimeMilliseconds: runtime)
    }

    func terminate() {
        withConnection { session in
            session.channel.closeShell()
            session.disconnect()
        }
        Agent.shared.removeTerminal(withInstance: self)
    }
}
