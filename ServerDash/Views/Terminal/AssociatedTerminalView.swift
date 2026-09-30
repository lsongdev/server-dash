//
//  AssociatedTerminalView.swift
//  ServerDash
//

import GhosttyTerminal
import PTFoundation
import SwiftUI

struct AssociatedTerminalView: View {
    let serverDescriptor: PTServerManager.ServerDescriptor

    @State private var openingConnection = false
    @State private var instance: PersistTerminalInstance?
    @State private var opened = false
    @State private var connectionFailed = false

    var body: some View {
        Group {
            if let instance {
                TerminalSurfaceView(context: instance.terminalState)
                    .ignoresSafeArea(.keyboard, edges: .bottom)
                    .onAppear {
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
            if let instance {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("TERMINATE", comment: "Terminate")) {
                        instance.terminate()
                        self.instance = nil
                    }
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
    }

    private func connect() {
        guard !opened else { return }
        opened = true
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
