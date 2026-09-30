//
//  MainView.swift
//  ServerDash
//

import SwiftUI

struct MainView: View {
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    @ObservedObject private var agent = Agent.shared

    var body: some View {
        Group {
            if agent.authorizationStatus == .authorized {
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
    }
}
