//
//  TerminalLoader.swift
//  ServerDash
//

import PTFoundation
import SwiftUI

/// Terminal home: active sessions first, then known servers.
///
/// Opening a server navigates directly into its terminal. The terminal view
/// owns connection/retry state, so this screen does not duplicate SSH state.
struct TerminalLoader: View {
    @ObservedObject private var agent = Agent.shared
    @State private var terminateAll = false

    var body: some View {
        Group {
            if agent.terminalInstance.isEmpty && agent.serverDescriptorsSorted.isEmpty {
                emptyState
            } else {
                List {
                    if !agent.terminalInstance.isEmpty {
                        Section(header: Text(NSLocalizedString("SESSIONS", comment: "Sessions"))) {
                            ForEach(agent.terminalInstance, id: \.id) { instance in
                                PersistTerminalInstanceView(instanceRef: instance)
                            }
                        }
                    }

                    if !agent.serverDescriptorsSorted.isEmpty {
                        Section(header: Text(NSLocalizedString(
                            "OPEN_SESSION_FROM_SERVER",
                            comment: "Open Session From Server"
                        ))) {
                            ForEach(agent.serverDescriptorsSorted, id: \.self) { descriptor in
                                NavigationLink(
                                    destination: AssociatedTerminalView(serverDescriptor: descriptor)
                                ) {
                                    TerminalFromServerView(descriptor: descriptor)
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle(NSLocalizedString("DOCK_TERMINAL", comment: "Terminal"))
        .navigationBarItems(
            trailing: Button(NSLocalizedString("TERMINATE_ALL", comment: "Terminate All")) {
                terminateAll = true
            }
            .disabled(agent.terminalInstance.isEmpty)
            .opacity(agent.terminalInstance.isEmpty ? 0 : 1)
        )
        .alert(isPresented: $terminateAll) {
            Alert(
                title: Text(NSLocalizedString("TERMINATE_ALL", comment: "Terminate All")),
                message: Text(NSLocalizedString(
                    "TERMINATE_ALL_TINT",
                    comment: "Are you sure you want to terminate all session?"
                )),
                primaryButton: .cancel(Text(NSLocalizedString("CANCEL", comment: "Cancel"))),
                secondaryButton: .destructive(
                    Text(NSLocalizedString("CONTINUE", comment: "Continue"))
                ) {
                    agent.terminalInstance.forEach { $0.terminate() }
                }
            )
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "terminal")
                .font(.system(size: 56, weight: .semibold))
            Text(NSLocalizedString(
                "NO_SESSION_CAN_OPEN",
                comment: "No session can be opened, please add a server first!"
            ))
            .font(.headline)
            .multilineTextAlignment(.center)
        }
        .foregroundColor(.secondary)
        .padding()
    }
}
