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

    var body: some View {
        Form {
            Section {
                Picker(
                    NSLocalizedString("THEME", comment: "Theme"),
                    selection: Binding(
                        get: { appearance.storedColorScheme },
                        set: { value in
                            guard let scheme = InternalColorScheme(rawValue: value) else {
                                return
                            }
                            appearance.storeColorScheme(withValue: scheme)
                        }
                    )
                ) {
                    ForEach(0..<themeNames.count, id: \.self) { index in
                        Text(themeNames[index]).tag(index)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text(NSLocalizedString("THEME", comment: "Theme"))
            } footer: {
                Text(NSLocalizedString(
                    "THEME_TINT",
                    comment: "Override app's color scheme here"
                ))
            }

            Section {
                Toggle(
                    NSLocalizedString("APP_PROTECTION", comment: "App Protection"),
                    isOn: Binding(
                        get: { appProtection },
                        set: { updateAppProtection($0) }
                    )
                )

                Toggle(
                    NSLocalizedString("APP_PROTECTION_SCRIPT", comment: "Terminal Protection"),
                    isOn: Binding(
                        get: { terminalProtection },
                        set: { updateTerminalProtection($0) }
                    )
                )
            } footer: {
                Text(NSLocalizedString(
                    "APP_PROTECTION_SCRIPT_TINT",
                    comment: "Authenticate before opening a remote terminal"
                ))
            }

            Section {
                Stepper(
                    value: Binding(
                        get: { monitorInterval },
                        set: { value in
                            monitorInterval = value
                            agent.supervisionInterval = value
                        }
                    ),
                    in: 5...3600,
                    step: 5
                ) {
                    HStack {
                        Text(NSLocalizedString(
                            "MONITOR_INTERVAL",
                            comment: "Monitor Interval"
                        ))
                        Spacer()
                        Text(String(
                            format: NSLocalizedString("%d_SECOND", comment: "%ds"),
                            monitorInterval
                        ))
                        .foregroundColor(.secondary)
                    }
                }

                Toggle(
                    NSLocalizedString("MONITOR_ENABLE_RECORD", comment: "Enable Record"),
                    isOn: Binding(
                        get: { recordHistory },
                        set: { value in
                            recordHistory = value
                            agent.supervisionRecordEnabled = value
                            if !value {
                                askToPurgeHistory = true
                            }
                        }
                    )
                )
            } header: {
                Text(NSLocalizedString("SIDEBAR_DASHBOARD", comment: "Monitoring"))
            } footer: {
                Text(NSLocalizedString(
                    "MONITOR_INTERVAL_TINT",
                    comment: "Set the interval for each data gathering task"
                ))
            }

            Section {
                NavigationLink(destination: SettingAccountView()) {
                    Label(
                        NSLocalizedString("KEY", comment: "Key"),
                        systemImage: "key"
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

struct SettingView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            SettingView()
        }
    }
}
