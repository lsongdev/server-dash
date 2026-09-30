//
//  SettingView.swift
//  ServerDash
//

import PTFoundation
import SwiftUI

struct SettingView: View {
    @ObservedObject private var appearance = AppearanceStore.shared
    @ObservedObject private var agent = Agent.shared

    @State private var appProtection = Agent.shared.applicationProtected
    @State private var terminalProtection = Agent.shared.terminalProtectionEnabled
    @State private var monitorInterval = Agent.shared.supervisionInterval
    @State private var recordHistory = Agent.shared.supervisionRecordEnabled
    @State private var askToPurgeHistory = false

    private let themeNames = [
        NSLocalizedString("FOLLOW_SYSTEM", comment: "Follow System"),
        NSLocalizedString("LIGHT_MODE", comment: "Light Mode"),
        NSLocalizedString("DARK_MODE", comment: "Dark Mode"),
    ]

    private var themeSelection: Binding<Int> {
        Binding(
            get: { appearance.storedColorScheme },
            set: { value in
                guard let scheme = InternalColorScheme(rawValue: value) else { return }
                appearance.storeColorScheme(withValue: scheme)
            }
        )
    }

    private var appProtectionSelection: Binding<Bool> {
        Binding(get: { appProtection }, set: updateAppProtection)
    }

    private var terminalProtectionSelection: Binding<Bool> {
        Binding(get: { terminalProtection }, set: updateTerminalProtection)
    }

    private var monitorIntervalSelection: Binding<Int> {
        Binding(
            get: { monitorInterval },
            set: { value in
                monitorInterval = value
                agent.supervisionInterval = value
            }
        )
    }

    private var recordHistorySelection: Binding<Bool> {
        Binding(
            get: { recordHistory },
            set: { value in
                recordHistory = value
                agent.supervisionRecordEnabled = value
                if !value {
                    askToPurgeHistory = true
                }
            }
        )
    }

    var body: some View {
        Form {
            Section {
                Picker(selection: themeSelection) {
                    ForEach(0..<themeNames.count, id: \.self) { index in
                        Text(themeNames[index]).tag(index)
                    }
                } label: {
                    SettingsRowLabel(title: NSLocalizedString("THEME", comment: "Theme"), systemImage: "paintbrush")
                }
                .pickerStyle(.menu)
            } header: {
                Text(NSLocalizedString("APPEARANCE", comment: "Appearance"))
            } footer: {
                Text(NSLocalizedString(
                    "THEME_TINT",
                    comment: "Override app's color scheme here"
                ))
            }

            Section {
                NavigationLink(destination: CredentialListView()) {
                    SettingsRowLabel(title: NSLocalizedString("CREDENTIALS", comment: "Credentials"), systemImage: "key")
                }

                Toggle(isOn: appProtectionSelection) {
                    SettingsRowLabel(
                        title: NSLocalizedString("APP_PROTECTION", comment: "App Protection"),
                        systemImage: "lock.shield"
                    )
                }

                Toggle(isOn: terminalProtectionSelection) {
                    SettingsRowLabel(
                        title: NSLocalizedString("APP_PROTECTION_SCRIPT", comment: "Terminal Protection"),
                        systemImage: "terminal"
                    )
                }
            } header: {
                Text(NSLocalizedString("SECURITY", comment: "Security"))
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(NSLocalizedString(
                        "APP_PROTECTION_TINT",
                        comment: "Authenticate when opening the app"
                    ))
                    Text(NSLocalizedString(
                        "APP_PROTECTION_SCRIPT_TINT",
                        comment: "Authenticate before opening a remote terminal"
                    ))
                }
            }

            Section {
                HStack(spacing: 8) {
                    SettingsRowLabel(
                        title: NSLocalizedString("MONITOR_INTERVAL", comment: "Monitor Interval"),
                        systemImage: "clock"
                    )
                    Spacer(minLength: 0)
                    Text(String(
                        format: NSLocalizedString("%d_SECOND", comment: "%ds"),
                        monitorInterval
                    ))
                    .foregroundColor(.secondary)
                    Stepper(
                        "",
                        value: monitorIntervalSelection,
                        in: 5...3600,
                        step: 5
                    )
                    .labelsHidden()
                }

                Toggle(isOn: recordHistorySelection) {
                    SettingsRowLabel(
                        title: NSLocalizedString("MONITOR_ENABLE_RECORD", comment: "Enable Record"),
                        systemImage: "clock"
                    )
                }
            } header: {
                Text(NSLocalizedString("MONITORING", comment: "Monitoring"))
            } footer: {
                Text(NSLocalizedString(
                    "MONITOR_INTERVAL_TINT",
                    comment: "Set the interval for each data gathering task"
                ))
            }

            Section {
                NavigationLink(destination: GhosttySettingsView()) {
                    SettingsRowLabel(title: "Ghostty", systemImage: "terminal")
                }

                NavigationLink(destination: AboutView()) {
                    SettingsRowLabel(title: NSLocalizedString("ABOUT", comment: "About"), systemImage: "info.circle")
                }

                NavigationLink(destination: SettingDiagView()) {
                    SettingsRowLabel(
                        title: NSLocalizedString("DIAGNOSTIC", comment: "Diagnostic"),
                        systemImage: "waveform.path.ecg"
                    )
                }
            }
        }
        .navigationTitle(NSLocalizedString("SETTINGS", comment: "Settings"))
        .alert(
            NSLocalizedString("DELETE_EXIST_RECORD", comment: "Delete existing records?"),
            isPresented: $askToPurgeHistory
        ) {
            Button(NSLocalizedString("CANCEL", comment: "Cancel"), role: .cancel) {}
            Button(NSLocalizedString("CONTINUE", comment: "Continue"), role: .destructive) {
                PTServerManager.shared.purgeDatabase()
            }
        }
    }

    private func updateAppProtection(_ enabled: Bool) {
        changeProtectedSetting(
            from: appProtection,
            to: enabled
        ) {
            appProtection = enabled
            agent.applicationProtected = enabled
        }
    }

    private func updateTerminalProtection(_ enabled: Bool) {
        changeProtectedSetting(
            from: terminalProtection,
            to: enabled
        ) {
            terminalProtection = enabled
            agent.terminalProtectionEnabled = enabled
        }
    }

    /// Enabling protection is immediate. Disabling an existing protection
    /// requires device-owner authentication.
    private func changeProtectedSetting(
        from currentValue: Bool,
        to newValue: Bool,
        apply: @escaping () -> Void
    ) {
        guard currentValue, !newValue else {
            apply()
            return
        }

        agent.authenticationWithBioID {
            DispatchQueue.main.async {
                apply()
            }
        } onFailure: { _ in
            // Keep the protected setting unchanged.
        }
    }
}

private struct SettingsRowLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 19))
                .foregroundColor(.overridableAccentColor)
                .frame(width: 24, height: 28)
            Text(title)
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .combine)
    }
}

struct SettingView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            SettingView()
        }
    }
}
