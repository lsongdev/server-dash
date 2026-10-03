//
//  TerminalLoader.swift
//  ServerDash
//

import SwiftUI

/// Shows retained terminal sessions, including disconnected shells.
struct TerminalLoader: View {
    private let agent = Agent.shared
    @State private var sessions: [PersistTerminalInstance] = []
    @State private var serverDescriptors: [String] = []
    @State private var terminateAll = false
    @State private var showingNewSession = false

    var body: some View {
        List {
            ForEach(sessions, id: \.id) { instance in
                PersistTerminalInstanceView(instanceRef: instance)
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if sessions.isEmpty {
                emptyState
            }
        }
        .sheet(isPresented: $showingNewSession, onDismiss: {
            sessions = agent.terminalInstanceSender
        }) {
            NavigationView {
                SessionServerPickerView(serverDescriptors: serverDescriptors)
            }
            .navigationViewStyle(.stack)
        }
        .navigationTitle(NSLocalizedString("DOCK_TERMINAL", comment: "Terminal"))
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if !sessions.isEmpty {
                    Button {
                        terminateAll = true
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(NSLocalizedString("TERMINATE_ALL", comment: "Terminate All"))
                }

                Button {
                    serverDescriptors = agent.serverDescriptorsSorted
                    showingNewSession = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(NSLocalizedString("NEW_SESSION", comment: "New Session"))
            }
        }
        .alert(isPresented: $terminateAll) {
            Alert(
                title: Text(NSLocalizedString("TERMINATE_ALL", comment: "Terminate All")),
                message: Text(NSLocalizedString(
                    "TERMINATE_ALL_TINT",
                    comment: "Are you sure you want to terminate all sessions?"
                )),
                primaryButton: .cancel(Text(NSLocalizedString("CANCEL", comment: "Cancel"))),
                secondaryButton: .destructive(
                    Text(NSLocalizedString("CONTINUE", comment: "Continue"))
                ) {
                    sessions.forEach { $0.terminate() }
                    sessions.removeAll()
                }
            )
        }
        .onAppear {
            sessions = agent.terminalInstanceSender
            serverDescriptors = agent.serverDescriptorsSorted
        }
        .onReceive(agent.$terminalInstance) { updated in
            sessions = updated
        }
        .onReceive(agent.$serverDescriptorsSorted) { updated in
            serverDescriptors = updated
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "terminal")
                .font(.system(size: 56, weight: .semibold))
            Text(NSLocalizedString("NO_SESSION_OPENED", comment: "No Session Opened"))
                .font(.headline)
            Text(NSLocalizedString(
                serverDescriptors.isEmpty
                    ? "NO_SESSION_CAN_OPEN"
                    : "TAP_ADD_TO_OPEN_SESSION",
                comment: "Tap the add button to start a terminal session"
            ))
                .multilineTextAlignment(.center)
        }
        .foregroundColor(.secondary)
        .padding()
    }
}

private struct SessionServerPickerView: View {
    let serverDescriptors: [String]
    @Environment(\.dismiss) private var dismiss
    @State private var connectingDescriptor: String?
    @State private var connectionFailed = false

    var body: some View {
        List {
            ForEach(serverDescriptors, id: \.self) { descriptor in
                Button {
                    createSession(for: descriptor)
                } label: {
                    HStack {
                        TerminalFromServerView(descriptor: descriptor)
                        if connectingDescriptor == descriptor {
                            ProgressView()
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(connectingDescriptor != nil)
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if serverDescriptors.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 56, weight: .semibold))
                    Text(NSLocalizedString("NO_SERVER_AVAILABLE", comment: "No Server Available"))
                        .font(.headline)
                    Text(NSLocalizedString(
                        "NO_SESSION_CAN_OPEN",
                        comment: "Add a server before opening a session"
                    ))
                    .multilineTextAlignment(.center)
                }
                .foregroundColor(.secondary)
                .padding()
            }
        }
        .navigationTitle("New Session")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") { dismiss() }
                    .disabled(connectingDescriptor != nil)
            }
        }
        .interactiveDismissDisabled(connectingDescriptor != nil)
        .alert("Connection Failed", isPresented: $connectionFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Could not create a session. Check the server and credentials, then try again.")
        }
    }

    private func createSession(for descriptor: String) {
        guard connectingDescriptor == nil else { return }
        connectingDescriptor = descriptor

        PersistTerminalInstance.openConnection(withServer: descriptor) { instance in
            DispatchQueue.main.async {
                connectingDescriptor = nil
                if instance != nil {
                    dismiss()
                } else {
                    connectionFailed = true
                }
            }
        }
    }
}
