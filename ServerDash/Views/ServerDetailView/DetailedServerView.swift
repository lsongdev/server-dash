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
    @State private var presentTerminal = false
    @State private var notificationLinkID = ""

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
        .background(
            NavigationLink(
                destination: AssociatedTerminalView(serverDescriptor: serverDescriptor),
                isActive: $presentTerminal
            ) {
                EmptyView()
            }
            .hidden()
        )
        .navigationTitle(kinfo.serverTitle)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    presentTerminal = true
                } label: {
                    Image(systemName: "terminal")
                }
            }
        }
        .onAppear {
            observeUpdates()
            updateData()
        }
        .onDisappear {
            guard !notificationLinkID.isEmpty else { return }
            PTNotificationCenter.shared.removeNotificatino(
                withKey: notificationLinkID,
                underName: .ServerManager_ServerStatusUpdated
            )
            notificationLinkID = ""
        }
    }

    private func observeUpdates() {
        guard notificationLinkID.isEmpty else { return }
        let descriptor = serverDescriptor
        let link = PTNotificationCenter.NotificationLink(
            name: .ServerManager_ServerStatusUpdated,
            throttle: nil
        ) { pass in
            guard let updated = pass.representedObject as? String,
                  updated == descriptor
            else {
                return
            }
            DispatchQueue.main.async {
                self.updateData()
            }
        }
        PTNotificationCenter.shared.registeringNotification(withLink: link)
        notificationLinkID = link.uuid
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
