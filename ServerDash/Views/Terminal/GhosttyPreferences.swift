import GhosttyTerminal
import SwiftUI

@MainActor
final class GhosttyPreferences: ObservableObject {
    static let shared = GhosttyPreferences()

    @Published var fontSize: Int {
        didSet { UserDefaults.standard.set(fontSize, forKey: "ghostty.fontSize") }
    }
    @Published var fontFamily: String {
        didSet { UserDefaults.standard.set(fontFamily, forKey: "ghostty.fontFamily") }
    }
    @Published var theme: String {
        didSet { UserDefaults.standard.set(theme, forKey: "ghostty.theme") }
    }

    private init() {
        let savedSize = UserDefaults.standard.integer(forKey: "ghostty.fontSize")
        fontSize = savedSize == 0 ? 10 : min(max(savedSize, 8), 24)
        fontFamily = UserDefaults.standard.string(forKey: "ghostty.fontFamily") ?? ""
        theme = UserDefaults.standard.string(forKey: "ghostty.theme") ?? "system"
    }

    func apply(to state: TerminalViewState) {
        let selectedTheme: TerminalTheme
        switch theme {
        case "alabaster":
            selectedTheme = TerminalTheme(light: .alabaster, dark: .alabaster)
        case "afterglow":
            selectedTheme = TerminalTheme(light: .afterglow, dark: .afterglow)
        default:
            selectedTheme = .default
        }
        state.setTheme(selectedTheme)

        var configuration = TerminalConfiguration.default.fontSize(Float(fontSize))
        if !fontFamily.isEmpty {
            configuration = configuration.fontFamily(fontFamily)
        }
        state.setTerminalConfiguration(configuration)
    }
}
