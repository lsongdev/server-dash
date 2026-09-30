import SwiftUI

struct GhosttySettingsView: View {
    @ObservedObject private var preferences = GhosttyPreferences.shared

    var body: some View {
        Form {
            Section {
                Stepper(value: $preferences.fontSize, in: 8...24) {
                    HStack {
                        Text(NSLocalizedString("TERMINAL_FONT_SIZE", comment: "Font Size"))
                        Spacer()
                        Text("\(preferences.fontSize) pt")
                            .foregroundColor(.secondary)
                    }
                }

                Picker(NSLocalizedString("TERMINAL_FONT", comment: "Font"), selection: $preferences.fontFamily) {
                    Text(NSLocalizedString("SYSTEM_DEFAULT", comment: "System Default")).tag("")
                    Text("Menlo").tag("Menlo")
                    Text("Courier New").tag("Courier New")
                }
            } header: {
                Text(NSLocalizedString("TERMINAL_TEXT", comment: "Text"))
            }

            Section {
                Picker(NSLocalizedString("TERMINAL_THEME", comment: "Terminal Theme"), selection: $preferences.theme) {
                    Text(NSLocalizedString("FOLLOW_SYSTEM", comment: "Follow System")).tag("system")
                    Text("Alabaster").tag("alabaster")
                    Text("Afterglow").tag("afterglow")
                }
            } footer: {
                Text(NSLocalizedString("GHOSTTY_SETTINGS_HINT", comment: "Applied to all terminal sessions."))
            }
        }
        .navigationTitle("Ghostty")
    }
}
