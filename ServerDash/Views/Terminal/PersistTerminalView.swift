//
//  PersistTerminalView.swift
//  ServerDash
//

import GhosttyTerminal
import SwiftUI

struct PersistTerminalView: View {
    let instance: PersistTerminalInstance

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var ghosttyPreferences = GhosttyPreferences.shared

    var body: some View {
        TerminalSurfaceView(context: instance.terminalState)
            .navigationTitle(
                instance.terminalState.title.isEmpty
                    ? instance.terminalTitle
                    : instance.terminalState.title
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        instance.terminate()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(NSLocalizedString("TERMINATE", comment: "Terminate"))
                }
            }
            .onAppear {
                ghosttyPreferences.apply(to: instance.terminalState)
                instance.terminalState.isSurfaceVisible = true
                instance.terminalState.requestFocus()
            }
            .onReceive(ghosttyPreferences.objectWillChange) { _ in
                DispatchQueue.main.async {
                    ghosttyPreferences.apply(to: instance.terminalState)
                }
            }
            .onDisappear {
                // Preserve terminal state and scrollback, but stop rendering a
                // session that is hidden behind another navigation screen.
                instance.terminalState.isSurfaceVisible = false
            }
    }
}
