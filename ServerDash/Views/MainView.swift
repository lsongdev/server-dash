//
//  MainView.swift
//  ServerDash
//

import SwiftUI

struct MainView: View {
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    private let agent = Agent.shared
    @State private var authorizationStatus = Agent.shared.authorizationStatus

    var body: some View {
        Group {
            if authorizationStatus == .authorized {
                if horizontalSizeClass == .compact || !isPad {
                    TabBarView()
                } else {
                    SideBarView()
                }
            } else {
                ProgressView()
                    .onAppear {
                        agent.startUserAuthentication()
                    }
            }
        }
        .onReceive(agent.$authorizationStatus) { authorizationStatus = $0 }
    }
}
