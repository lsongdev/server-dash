//
//  TabbarView.swift
//  ServerDash
//

import SwiftUI

struct TabBarView: View {
    var body: some View {
        TabView {
            NavigationView {
                DashboardView()
            }
            .tabItem {
                Label(
                    NSLocalizedString("DOCK_SERVERS", comment: "Servers"),
                    systemImage: "server.rack"
                )
            }

            NavigationView {
                TerminalLoader()
            }
            .tabItem {
                Label(
                    NSLocalizedString("DOCK_TERMINAL", comment: "Terminal"),
                    systemImage: "terminal"
                )
            }

            NavigationView {
                SettingView()
            }
            .tabItem {
                Label(
                    NSLocalizedString("DOCK_SETTINGS", comment: "Settings"),
                    systemImage: "gearshape"
                )
            }
        }
    }
}

struct TabBarView_Previews: PreviewProvider {
    static var previews: some View {
        TabBarView()
    }
}
