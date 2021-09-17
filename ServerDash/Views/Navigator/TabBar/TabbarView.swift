//
//  TabbarView.swift
//  ServerDash
//
//  Created by Lakr Aream on 4/18/21.
//

import SwiftUI

struct TabBarView: View {
    enum TabBarTag: Int, Equatable, Identifiable {
        var id: TabBarTag { self }

        case Board
        case Terminal
        case Script
        case Misc
    }

    @State var selection: TabBarTag? = .Board

    let LSDockItemBoard = NSLocalizedString("DOCK_SERVERS", comment: "Servers")
    let LSDockItemScripts = NSLocalizedString("DOCK_SCRIPTS", comment: "Script")
    let LSDockItemTerminal = NSLocalizedString("DOCK_TERMINAL", comment: "Terminal")
    let LSDockItemSettings = NSLocalizedString("DOCK_SETTINGS", comment: "Settings")

    var body: some View {
        UIKitTabView([
            UIKitTabView.Tab(
                view: TabBarBoardView(),
                barItem: UITabBarItem(title: LSDockItemBoard,
                                      image:
                                      UIImage(named: "TABBAR_BOARD")?
                                          .withRenderingMode(.alwaysTemplate),
                                      selectedImage: nil)
            ),
            
            UIKitTabView.Tab(
                view: TabBarTerminalView(),
                barItem: UITabBarItem(title: LSDockItemTerminal,
                                      image:
                                      UIImage(named: "TABBAR_TERMINAL")?
                                          .withRenderingMode(.alwaysTemplate),
                                      selectedImage: nil)
            ),
            UIKitTabView.Tab(
                view: TabBarScriptsView(),
                barItem: UITabBarItem(title: LSDockItemScripts,
                                      image:
                                      UIImage(named: "TABBAR_PAPERPLANE")?
                                          .withRenderingMode(.alwaysTemplate),
                                      selectedImage: nil)
            ),
            UIKitTabView.Tab(
                view: TabBarMiscView(),
                barItem: UITabBarItem(title: LSDockItemSettings,
                                      image:
                                      UIImage(named: "TABBAR_GEAR")?
                                          .withRenderingMode(.alwaysTemplate),
                                      selectedImage: nil)
            ),
        ])
    }
}

struct TabBarView_Previews: PreviewProvider {
    static var previews: some View {
        TabBarView()
    }
}

struct UIKitTabView: View {
    var viewControllers: [UIHostingController<AnyView>]

    init(_ tabs: [Tab]) {
        viewControllers = tabs.map {
            let host = UIHostingController(rootView: $0.view)
            host.tabBarItem = $0.barItem
            return host
        }
    }

    var body: some View {
        TabBarController(controllers: viewControllers)
            .edgesIgnoringSafeArea(.all)
    }

    struct Tab {
        var view: AnyView
        var barItem: UITabBarItem

        init<V: View>(view: V, barItem: UITabBarItem) {
            self.view = AnyView(view)
            self.barItem = barItem
        }
    }
}

struct TabBarController: UIViewControllerRepresentable {
    var controllers: [UIViewController]

    func makeUIViewController(context _: Context) -> UITabBarController {
        let tabBarController = UITabBarController()
        tabBarController.viewControllers = controllers
        return tabBarController
    }

    func updateUIViewController(_: UITabBarController, context _: Context) {}
}
