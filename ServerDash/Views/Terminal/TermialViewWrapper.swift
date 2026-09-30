//
//  TermialViewWrapper.swift
//  ServerDash
//

import GhosttyTerminal
import SwiftUI

/// Read-mostly terminal surface used by command/script output.
///
/// Interactive SSH sessions use PersistTerminalInstance. This wrapper remains
/// intentionally tiny so output rendering does not own any SSH state.
struct TerminalViewWrapper: View {
    @StateObject private var state = TerminalViewState()

    private let session: InMemoryTerminalSession

    init() {
        session = InMemoryTerminalSession(
            write: { _ in },
            resize: { _ in },
            suppressesPixelOnlyResizes: true
        )
    }

    var body: some View {
        TerminalSurfaceView(context: state)
            .onAppear {
                state.configuration = TerminalSurfaceOptions(
                    backend: .inMemory(session)
                )
            }
    }

    func feed(text: String) {
        session.receive(text)
    }
}
