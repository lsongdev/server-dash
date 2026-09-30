//
//  DetailedServerView.swift
//  ServerDash
//

import PTFoundation
import SwiftUI

struct DetailedServerView: View {
    let serverDescriptor: PTServerManager.ServerDescriptor
    let kinfo: PTServerManager.ServerInfoHumanReadable

    @State private var timestamp: TimeInterval?
    @State private var info: PTServerManager.ServerInfo?

    init(serverDescriptor: PTServerManager.ServerDescriptor) {
        self.serverDescriptor = serverDescriptor
        kinfo = PTServerManager.ServerInfoHumanReadable(serverDescriptor: serverDescriptor)
    }

    var body: some View {
        Group {
            if let timestamp, let info {
                ScrollView {
                    VStack {
                        DetailedDataElementView(
                            timestamp: timestamp,
                            dataSource: info,
                            server: serverDescriptor
                        )
                        Divider()
                        NavigationLink(
                            destination: DetailedServerHistoryView(
                                serverDescriptor: serverDescriptor
                            )
                        ) {
                            HStack {
                                Image(systemName: "text.magnifyingglass")
                                Text(NSLocalizedString("HISTORY", comment: "History"))
                                Spacer()
                            }
                            .font(.system(size: 14, weight: .semibold))
                            .padding()
                            .background(Color.lightGray.cornerRadius(8))
                        }
                    }
                    .padding()
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading) {
                        Text("🤷‍♂️")
                        Divider().opacity(0)
                        Text(NSLocalizedString(
                            "NO_DATA_AVAILABLE_PLEASE_TRY_AGAIN_LATER",
                            comment: "No data available for this server, please try again later."
                        ))
                        .font(.system(size: 14, weight: .semibold))
                        Divider().opacity(0)
                        ServerStatusBlockView(descriptor: "", isPlaceHolder: true)
                    }
                    .padding()
                }
            }
        }
        .navigationTitle(kinfo.serverTitle)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink(destination: AssociatedTerminalView(serverDescriptor: serverDescriptor)) {
                    Image(systemName: "terminal")
                }
                .accessibilityLabel("Open Terminal")
            }
        }
        .onAppear {
            updateData()
        }
        .onReceive(NotificationCenter.default.publisher(for: .serverStatusUpdated)) { note in
            guard let updated = note.object as? String,
                  updated == serverDescriptor
            else {
                return
            }
            updateData()
        }
    }

    private func updateData() {
        guard
            let status = PTServerManager.shared.obtainServerStatus(withKey: serverDescriptor),
            let updatedAt = status.previousUpdate?.timeIntervalSince1970,
            let information = status.information
        else {
            return
        }
        timestamp = updatedAt
        info = information
    }
}

struct DetailedServerView_Previews: PreviewProvider {
    static var previews: some View {
        DetailedServerView(serverDescriptor: "")
            .previewLayout(.fixed(width: 400, height: 1000))
    }
}
