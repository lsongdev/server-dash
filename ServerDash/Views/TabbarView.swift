//
//  TabbarView.swift
//  ServerDash
//

import SwiftUI

extension Notification.Name {
    static let openTerminalForServer = Notification.Name("openTerminalForServer")
}

private struct TerminalRoute: Hashable {
    let serverDescriptor: String
    let id = UUID()
}

struct TabBarView: View {
    private enum Tab: Hashable {
        case servers
        case terminal
        case settings
    }

    @State private var selectedTab: Tab = .servers
    @State private var terminalPath: [TerminalRoute] = []

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationView {
                DashboardView()
            }
            .tabItem {
                Label(
                    NSLocalizedString("DOCK_SERVERS", comment: "Servers"),
                    systemImage: "server.rack"
                )
            }
            .tag(Tab.servers)

            NavigationStack(path: $terminalPath) {
                TerminalLoader()
                    .navigationDestination(for: TerminalRoute.self) { route in
                        AssociatedTerminalView(serverDescriptor: route.serverDescriptor)
                    }
            }
            .tabItem {
                Label(
                    NSLocalizedString("DOCK_TERMINAL", comment: "Terminal"),
                    systemImage: "terminal"
                )
            }
            .tag(Tab.terminal)

            NavigationView {
                SettingView()
            }
            .tabItem {
                Label(
                    NSLocalizedString("DOCK_SETTINGS", comment: "Settings"),
                    systemImage: "gearshape"
                )
            }
            .tag(Tab.settings)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openTerminalForServer)) { note in
            guard let descriptor = note.object as? String else { return }
            selectedTab = .terminal
            terminalPath.append(TerminalRoute(serverDescriptor: descriptor))
        }
    }
}

struct TabBarView_Previews: PreviewProvider {
    static var previews: some View {
        TabBarView()
    }
}
