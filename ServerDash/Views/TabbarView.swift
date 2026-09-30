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
    @State private var legacyTerminalDescriptor: String?
    @State private var legacyTerminalActive = false

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

            Group {
                if #available(iOS 16.0, *) {
                    NavigationStack(path: $terminalPath) {
                        TerminalLoader()
                            .navigationDestination(for: TerminalRoute.self) { route in
                                AssociatedTerminalView(serverDescriptor: route.serverDescriptor)
                            }
                    }
                } else {
                    NavigationView {
                        TerminalLoader()
                            .background {
                                if let descriptor = legacyTerminalDescriptor {
                                    NavigationLink(
                                        destination: AssociatedTerminalView(serverDescriptor: descriptor),
                                        isActive: $legacyTerminalActive
                                    ) {
                                        EmptyView()
                                    }
                                    .hidden()
                                }
                            }
                    }
                    .navigationViewStyle(.stack)
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
            if #available(iOS 16.0, *) {
                terminalPath.append(TerminalRoute(serverDescriptor: descriptor))
            } else {
                legacyTerminalDescriptor = descriptor
                DispatchQueue.main.async {
                    legacyTerminalActive = true
                }
            }
        }
    }
}

struct TabBarView_Previews: PreviewProvider {
    static var previews: some View {
        TabBarView()
    }
}
