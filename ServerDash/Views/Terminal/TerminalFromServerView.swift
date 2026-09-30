//
//  TerminalFromServerView.swift
//  ServerDash
//

import PTFoundation
import SwiftUI

struct TerminalFromServerView: View {
    let descriptor: PTServerManager.ServerDescriptor

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: accountType == .secureShellWithKey ? "key.fill" : "terminal.fill")
                .frame(width: 24)
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 3) {
                Text(server?.obtainPossibleName() ?? "Unknown")
                    .font(.headline)

                Text(address)
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var server: PTServerManager.Server? {
        PTServerManager.shared.obtainServer(withKey: descriptor)
    }

    private var address: String {
        guard let server else { return "Unknown Host" }
        return "\(server.host):\(server.port)"
    }

    private var accountType: PTAccountManager.AccountType {
        guard let server else { return .secureShellWithPassword }
        return PTAccountManager.shared
            .retrieveAccountWith(key: server.accountDescriptor)?
            .type ?? .secureShellWithPassword
    }
}
