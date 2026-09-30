//
//  AssociatedTerminalView.swift
//  ServerDash
//

import GhosttyTerminal
import PTFoundation
import SwiftUI

struct AssociatedTerminalView: View {
    let serverDescriptor: PTServerManager.ServerDescriptor
    let onTerminate: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var ghosttyPreferences = GhosttyPreferences.shared

    @State private var openingConnection = false
    @State private var instance: PersistTerminalInstance?
    @State private var connectionFailed = false

    init(
        serverDescriptor: PTServerManager.ServerDescriptor,
        onTerminate: (() -> Void)? = nil
    ) {
        self.serverDescriptor = serverDescriptor
        self.onTerminate = onTerminate
    }

    var body: some View {
        Group {
            if let instance {
                TerminalSurfaceView(context: instance.terminalState)
                    .onAppear {
                        ghosttyPreferences.apply(to: instance.terminalState)
                        instance.terminalState.requestFocus()
                    }
            } else if openingConnection {
                ProgressView()
            } else {
                Button(NSLocalizedString("CONNECT", comment: "Connect")) {
                    connect()
                }
            }
        }
        .navigationTitle(instance?.terminalTitle ?? NSLocalizedString("SHELL", comment: "Shell"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if let instance = instance {
                    Button {
                        instance.terminate()
                        if let onTerminate {
                            onTerminate()
                        } else {
                            dismiss()
                        }
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(NSLocalizedString("TERMINATE", comment: "Terminate"))
                }
            }
        }
        .alert(
            NSLocalizedString("ERROR", comment: "Error"),
            isPresented: $connectionFailed
        ) {
            Button(NSLocalizedString("DONE", comment: "Done"), role: .cancel) {}
        } message: {
            Text(NSLocalizedString(
                "CONNECT_FAILED",
                comment: "Failed to open session for shell, please try again later."
            ))
        }
        .task {
            connect()
        }
        .onReceive(ghosttyPreferences.objectWillChange) { _ in
            DispatchQueue.main.async {
                if let instance = self.instance {
                    ghosttyPreferences.apply(to: instance.terminalState)
                }
            }
        }
    }

    private func connect() {
        guard !openingConnection, instance == nil else { return }
        openingConnection = true

        PersistTerminalInstance.openConnection(withServer: serverDescriptor) { instance in
            DispatchQueue.main.async {
                self.instance = instance
                openingConnection = false
                connectionFailed = instance == nil
            }
        }
    }
}
