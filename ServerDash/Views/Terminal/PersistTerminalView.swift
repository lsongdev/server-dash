//
//  PersistTerminalView.swift
//  ServerDash
//

import GhosttyTerminal
import SwiftUI

struct PersistTerminalView: View {
    let instance: PersistTerminalInstance

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var ghosttyPreferences = GhosttyPreferences.shared

    var body: some View {
        TerminalThemedSurfaceView(state: instance.terminalState)
            .navigationTitle(
                instance.terminalState.title.isEmpty
                    ? instance.terminalTitle
                    : instance.terminalState.title
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        instance.terminate()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(NSLocalizedString("TERMINATE", comment: "Terminate"))
                }
            }
            .onAppear {
                ghosttyPreferences.apply(to: instance.terminalState)
                instance.terminalState.isSurfaceVisible = true
                instance.terminalState.requestFocus()
            }
            .onReceive(ghosttyPreferences.objectWillChange) { _ in
                DispatchQueue.main.async {
                    ghosttyPreferences.apply(to: instance.terminalState)
                }
            }
            .onDisappear {
                // Preserve terminal state and scrollback, but stop rendering a
                // session that is hidden behind another navigation screen.
                instance.terminalState.isSurfaceVisible = false
            }
    }
}

/// Uses Ghostty's resolved background, including theme changes and OSC 11.
struct TerminalThemedSurfaceView: View {
    @ObservedObject var state: TerminalViewState

    private var background: Color { Color(state.backgroundColor) }

    private var colorScheme: ColorScheme {
        let color = state.backgroundColor
        let luminance = (0.2126 * Double(color.red)
            + 0.7152 * Double(color.green)
            + 0.0722 * Double(color.blue)) / 255
        return luminance < 0.5 ? .dark : .light
    }

    @ViewBuilder
    var body: some View {
        if #available(iOS 16.0, *) {
            TerminalSurfaceView(context: state)
                .background(background.ignoresSafeArea())
                .toolbarBackground(background, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbarColorScheme(colorScheme, for: .navigationBar)
                .toolbarBackground(background, for: .tabBar)
                .toolbarBackground(.visible, for: .tabBar)
                .toolbarColorScheme(colorScheme, for: .tabBar)
        } else {
            TerminalSurfaceView(context: state)
                .background(background.ignoresSafeArea())
                .background(
                    TerminalNavigationBarBackground(
                        background: UIColor(background),
                        foreground: colorScheme == .dark ? .white : .black
                    )
                    .frame(width: 0, height: 0)
                )
        }
    }
}

/// iOS 15 lacks toolbarBackground, so style only the enclosing navigation bar.
private struct TerminalNavigationBarBackground: UIViewControllerRepresentable {
    let background: UIColor
    let foreground: UIColor

    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.background = background
        controller.foreground = foreground
        DispatchQueue.main.async { [weak controller] in
            controller?.apply()
        }
    }

    static func dismantleUIViewController(_ controller: Controller, coordinator: ()) {
        controller.restore()
    }

    final class Controller: UIViewController {
        var background: UIColor = .black
        var foreground: UIColor = .white

        private weak var styledBar: UINavigationBar?
        private var previousStandard: UINavigationBarAppearance?
        private var previousScrollEdge: UINavigationBarAppearance?
        private var previousCompact: UINavigationBarAppearance?
        private var previousTint: UIColor?
        private var previousBarStyle: UIBarStyle = .default
        private weak var styledTabBar: UITabBar?
        private var previousTabAppearance: UITabBarAppearance?
        private var previousTabScrollEdge: UITabBarAppearance?
        private var previousTabTint: UIColor?
        private var previousTabUnselectedTint: UIColor?

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            apply()
        }

        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            restore()
        }

        func apply() {
            if let bar = navigationController?.navigationBar {
                if styledBar !== bar {
                    restoreNavigationBar()
                    styledBar = bar
                    previousStandard = bar.standardAppearance
                    previousScrollEdge = bar.scrollEdgeAppearance
                    previousCompact = bar.compactAppearance
                    previousTint = bar.tintColor
                    previousBarStyle = bar.barStyle
                }

                let appearance = UINavigationBarAppearance()
                appearance.configureWithOpaqueBackground()
                appearance.backgroundColor = background
                appearance.shadowColor = .clear
                appearance.titleTextAttributes = [.foregroundColor: foreground]
                appearance.largeTitleTextAttributes = [.foregroundColor: foreground]
                bar.standardAppearance = appearance
                bar.scrollEdgeAppearance = appearance
                bar.compactAppearance = appearance
                bar.tintColor = foreground
                bar.barStyle = foreground == UIColor.white ? .black : .default
            }

            if let tabBar = tabBarController?.tabBar {
                if styledTabBar !== tabBar {
                    restoreTabBar()
                    styledTabBar = tabBar
                    previousTabAppearance = tabBar.standardAppearance
                    previousTabScrollEdge = tabBar.scrollEdgeAppearance
                    previousTabTint = tabBar.tintColor
                    previousTabUnselectedTint = tabBar.unselectedItemTintColor
                }

                let appearance = UITabBarAppearance()
                appearance.configureWithOpaqueBackground()
                appearance.backgroundColor = background
                appearance.shadowColor = .clear
                tabBar.standardAppearance = appearance
                tabBar.scrollEdgeAppearance = appearance
                tabBar.tintColor = foreground
                tabBar.unselectedItemTintColor = foreground.withAlphaComponent(0.6)
            }
        }

        func restore() {
            restoreNavigationBar()
            restoreTabBar()
        }

        private func restoreNavigationBar() {
            guard let bar = styledBar else { return }
            if let previousStandard { bar.standardAppearance = previousStandard }
            bar.scrollEdgeAppearance = previousScrollEdge
            if let previousCompact { bar.compactAppearance = previousCompact }
            bar.tintColor = previousTint
            bar.barStyle = previousBarStyle
            styledBar = nil
        }

        private func restoreTabBar() {
            guard let tabBar = styledTabBar else { return }
            if let previousTabAppearance { tabBar.standardAppearance = previousTabAppearance }
            tabBar.scrollEdgeAppearance = previousTabScrollEdge
            tabBar.tintColor = previousTabTint
            tabBar.unselectedItemTintColor = previousTabUnselectedTint
            styledTabBar = nil
        }
    }
}
