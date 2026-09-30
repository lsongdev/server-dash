//
//  TerminalLoader.swift
//  ServerDash
//

import SwiftUI

/// Shows active terminal sessions. The add button opens server selection.
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
        .background {
            NavigationLink(
                destination: SessionServerPickerView(
                    isPresented: $showingNewSession,
                    serverDescriptors: serverDescriptors
                ),
                isActive: $showingNewSession
            ) {
                EmptyView()
            }
            .hidden()
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
            if !showingNewSession {
                sessions = updated
            }
        }
        .onReceive(agent.$serverDescriptorsSorted) { updated in
            if !showingNewSession {
                serverDescriptors = updated
            }
        }
        .onChange(of: showingNewSession) { active in
            if !active {
                sessions = agent.terminalInstanceSender
            }
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
    @Binding var isPresented: Bool
    let serverDescriptors: [String]

    var body: some View {
        List {
            ForEach(serverDescriptors, id: \.self) { descriptor in
                NavigationLink(
                    destination: AssociatedTerminalView(
                        serverDescriptor: descriptor,
                        onTerminate: { isPresented = false }
                    )
                ) {
                    TerminalFromServerView(descriptor: descriptor)
                }
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
        .navigationTitle(NSLocalizedString("NEW_SESSION", comment: "New Session"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
