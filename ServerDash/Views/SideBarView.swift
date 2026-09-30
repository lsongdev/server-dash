//
//  SideBar.swift
//  ServerDash
//
//  Created by Lakr Aream on 4/18/21.
//

import PTFoundation
import SwiftUI

enum NavigationTag: Int, Equatable, Identifiable {
    var id: NavigationTag { self }
    case Dashboard
    case ServerManager
    case ServerDetailed
    case EmptyServerå
    case RemoteLogin
    case Setting
    case Help
}

struct SideBarView: View {
    let fntSideBarSectionHead = Font.system(size: 18, weight: .semibold)

    @State var whichPane: NavigationTag? = nil

    @ObservedObject var agent = Agent.shared

    @State private var showingAddServer = false

    var body: some View {
        Group {
            sidebar
        }
    }

    var sidebar: some View {
        NavigationView {
            List {
                Group {
                    NavigationLink(destination: DashboardView(),
                       tag: NavigationTag.Dashboard,
                       selection: $whichPane) {
                        Label("Dashboard", systemImage: "square.stack.3d.down.right.fill")
                    }
                }

                Group {
                    Text("Servers").font(fntSideBarSectionHead)
                    ForEach(agent.serverDescriptorsSorted, id: \.self) { item in
                        NavigationLink(
                            destination: DetailedServerView(serverDescriptor: item),
                            label: {
                                let s = PTServerManager.shared.obtainServer(withKey: item)
                                Label(s?.obtainPossibleName() ?? "?", systemImage: "server.rack")
                            }
                        )
                    }.onDelete { indexSet in
                        let list = agent.serverDescriptorsSorted
                        guard let index = indexSet.first else { return }
                        if index < 0 || index >= list.count { return }
                        PTServerManager.shared.removeServerFromRegisteredList(withKey: list[index])
                    }
                    Button {
                        showingAddServer = true
                    } label: {
                        Label("Add Server", systemImage: "plus.square")
                    }
                }

                Group {
                    Text("Utilities")
                        .font(fntSideBarSectionHead)
                    NavigationLink(destination: TerminalLoader(),
                                   tag: NavigationTag.RemoteLogin,
                                   selection: $whichPane) {
                        Label("Terminal", systemImage: "rectangle.stack.person.crop")
                    }
                }

                Group {
                    Text("Application")
                        .font(fntSideBarSectionHead)
                    NavigationLink(destination: SettingView(),
                                   tag: NavigationTag.Setting,
                                   selection: $whichPane) {
                        Label("Settings", systemImage: "gear")
                    }
                
                }
            }
            .listStyle(SidebarListStyle())
            .navigationTitle("Server Dash")
            .sheet(isPresented: $showingAddServer) {
                NavigationView { AddServerView() }
            }
            DashboardView()
        }
    }
}

struct SideBarView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            SideBarView()
                .previewLayout(.fixed(width: 1024, height: 768))
        }
    }
}

#if DEBUG

    func askAndSetBootFailed(window: UIWindow?) {
        let alert = UIAlertController(title: "⚠️",
                                      message: "Set lastBootSucceed to false?",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Yes", style: .destructive, handler: { _ in
            ServerDashApp.lastBootSucceed = false
            let alert = UIAlertController(title: "⚠️",
                                          message: "Exit?",
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Yes", style: .destructive, handler: { _ in
                UIControl().sendAction(#selector(NSXPCConnection.suspend),
                                       to: UIApplication.shared, for: nil)
                DispatchQueue.global().async {
                    sleep(1)
                    exit(0)
                }
            }))
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
            let vc = window?.topMostViewController
            vc?.present(alert, animated: true, completion: nil)
        }))
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        let vc = window?.topMostViewController
        vc?.present(alert, animated: true, completion: nil)
    }

#endif
