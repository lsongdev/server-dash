//
//  PersistTerminalView.swift
//  ServerDash
//

import GhosttyTerminal
import SwiftUI

struct PersistTerminalView: View {
    let instance: PersistTerminalInstance

    var body: some View {
        TerminalSurfaceView(context: instance.terminalState)
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .navigationTitle(
                instance.terminalState.title.isEmpty
                    ? instance.terminalTitle
                    : instance.terminalState.title
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("TERMINATE", comment: "Terminate")) {
                        instance.terminate()
                    }
                }
            }
            .onAppear {
                instance.terminalState.isSurfaceVisible = true
                instance.terminalState.requestFocus()
            }
            .onDisappear {
                // Preserve terminal state and scrollback, but stop rendering a
                // session that is hidden behind another navigation screen.
                instance.terminalState.isSurfaceVisible = false
            }
    }
}
