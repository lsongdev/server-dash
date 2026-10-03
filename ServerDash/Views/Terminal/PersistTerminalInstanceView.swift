//
//  PersistTerminalInstanceView.swift
//  ServerDash
//

import SwiftUI

private let terminalSessionDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .none
    formatter.timeStyle = .short
    return formatter
}()

struct PersistTerminalInstanceView: View {
    @ObservedObject var instanceRef: PersistTerminalInstance

    var body: some View {
        NavigationLink(destination: PersistTerminalView(instance: instanceRef)) {
            HStack(spacing: 12) {
                Image(systemName: "terminal.fill")
                    .frame(width: 24)
                    .foregroundColor(.accentColor)

                VStack(alignment: .leading, spacing: 3) {
                    Text(instanceRef.terminalTitle)
                        .font(.headline)

                    Text(
                        String(
                            format: NSLocalizedString("CREATE_AT", comment: "Create At") + " %@",
                            terminalSessionDateFormatter.string(from: instanceRef.openDate)
                        )
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                    if instanceRef.connectionStatus != .connected {
                        Text(instanceRef.connectionStatusLabel)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }
            .padding(.vertical, 4)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                instanceRef.terminate()
            } label: {
                Image(systemName: "xmark")
            }
            .accessibilityLabel(NSLocalizedString("TERMINATE", comment: "Terminate"))
        }
    }
}
