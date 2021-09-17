//
//  SettingView.swift
//  ServerDash
//
//  Created by Lakr Aream on 4/29/21.
//

import SwiftUI
import LocalAuthentication
import PTFoundation

struct SettingView: View {
    @StateObject var windowObserver = WindowObserver()
    
    @ObservedObject var appearance = AppearanceStore.shared
    

    @ObservedObject var agent = Agent.shared

    @State var supervisionTimeInterval: String = ""
    @State var supervisionMaxRecord: String = ""

    let ThemeMode = [
        NSLocalizedString("FOLLOW_SYSTEM", comment: "Follow System"),
        NSLocalizedString("LIGHT_MODE", comment: "Light Mode"),
        NSLocalizedString("DARK_MODE", comment: "Dark Mode"),
    ]

    func getLAContextTypeSystemImage() -> String {
        switch LAContext().biometricType {
        case .faceID:
            return "faceid"
        case .touchID:
            return "touchid"
        default:
            return "lock.shield"
        }
    }
    var body: some View {
        Group {
            ScrollView {
                VStack(spacing: 12) {
                    
                   
                    
                    
                    VStack {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "moon.fill")
                                Text(NSLocalizedString("THEME", comment: "theme"))
                                Spacer()
                            }
                            .font(.system(size: 18, weight: .semibold, design: .default))
                            Text(NSLocalizedString("THEME_TINT", comment: "Override app's color scheme here"))
                                .font(.system(size: 14, weight: .regular, design: .default))
                                .opacity(0.5)
                        }

                        Divider()

                        ForEach(0 ..< ThemeMode.count, id: \.self) { idx in
                            let mode = ThemeMode[idx]
                            Button(action: {
                                guard let current = InternalColorScheme(rawValue: idx) else {
                                    debugPrint("bad color scheme")
                                    return
                                }
                                appearance.storeColorScheme(withValue: current)
                            }) {
                                HStack {
                                    Text(mode)
                                        .foregroundColor(
                                            appearance.storedColorScheme == idx
                                                ? Color.overridableAccentColor
                                                : Color.primary
                                        )
                                    Spacer()
                                    if appearance.storedColorScheme == idx {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.overridableAccentColor)
                                    }
                                }
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                                .frame(height: 30)
                            }
                        }
                    }
                    .padding()
                    .background(Color.lightGray)
                    .cornerRadius(12)
                    
                    Section {
                        VStack(spacing: 4) {
                            Group {
                                SettingToggleView(icon: getLAContextTypeSystemImage(),
                                                  title: NSLocalizedString("APP_PROTECTION", comment: "App Protection"),
                                                  subTitle: NSLocalizedString("APP_PROTECTION_TINT", comment: "Protect us from unauthorized operations when app become active")) {
                                    Agent.shared.applicationProtected
                                } callback: { value in
                                    if Agent.shared.applicationProtected {
                                        let authResult = Agent
                                            .shared
                                            .authenticationWithBioIDSyncAndReturnIsSuccessOrError()
                                        if !authResult.0 { return }
                                    }
                                    Agent.shared.applicationProtected = value
                                }
                                Divider()
                                SettingToggleView(icon: "terminal",
                                                  title: NSLocalizedString("APP_PROTECTION_SCRIPT", comment: "Execution Protection"),
                                                  subTitle: NSLocalizedString("APP_PROTECTION_SCRIPT_TINT", comment: "Authenticate when execute script on server")) {
                                    Agent.shared.applicationProtectedScriptExecution
                                } callback: { value in
                                    if Agent.shared.applicationProtectedScriptExecution {
                                        let authResult = Agent
                                            .shared
                                            .authenticationWithBioIDSyncAndReturnIsSuccessOrError()
                                        if !authResult.0 { return }
                                    }
                                    Agent.shared.applicationProtectedScriptExecution = value
                                }
                            }
                            .padding(.horizontal, 8)
                        }
                        .background(Color.lightGray)
                        .cornerRadius(12)
                    }
                    
                    Section {
                        VStack(spacing: 4) {
                            Group {
                                SettingButtonView(icon: "stopwatch",
                                                  title: NSLocalizedString("MONITOR_INTERVAL", comment: "Monitor Interval"),
                                                  subTitle: NSLocalizedString("MONITOR_INTERVAL_TINT", comment: "Set the interval for each data gathering task"),
                                                  callback: { str in
                                                      let alert = UIAlertController(title: NSLocalizedString("MONITOR_INTERVAL", comment: "Monitor Interval"),
                                                                                    message: NSLocalizedString("MONITOR_INTERVAL_VALUE_TINT", comment: "A monitor interval that is too small may cost extra load to remote machine."),
                                                                                    preferredStyle: .alert)
                                                      alert.addTextField { textField in
                                                          textField.placeholder = "60"
                                                          textField.text = "\(Agent.shared.supervisionInterval)"
                                                      }
                                                      alert.addAction(UIAlertAction(title: NSLocalizedString("CANCEL", comment: "Cancel"),
                                                                                    style: .cancel,
                                                                                    handler: nil))
                                                      alert.addAction(UIAlertAction(title: NSLocalizedString("DONE", comment: "Done"),
                                                                                    style: .default,
                                                                                    handler: { _ in
                                                                                        if let str = alert.textFields?.first?.text,
                                                                                           let value = Int(str)
                                                                                        {
                                                                                            Agent.shared.supervisionInterval = value
                                                                                            supervisionTimeInterval = String(format: NSLocalizedString("%d_SECOND", comment: "%ds"), Agent.shared.supervisionInterval)
                                                                                        }
                                                                                    }))
                                                      windowObserver
                                                          .window?
                                                          .topMostViewController?
                                                          .present(alert,
                                                                   animated: true,
                                                                   completion: nil)
                                                  }, buttonStr: $supervisionTimeInterval)
                                    .onAppear {
                                        supervisionTimeInterval = String(format: NSLocalizedString("%d_SECOND", comment: "%ds"), Agent.shared.supervisionInterval)
                                    }
                            }
                            .padding(.horizontal, 8)
                        }
                        .background(Color.lightGray)
                        .cornerRadius(12)
                    }
                    Section {
                        VStack(spacing: 4) {
                            Group {
                                SettingToggleView(icon: "externaldrive.fill.badge.timemachine",
                                                  title: NSLocalizedString("MONITOR_ENABLE_RECORD", comment: "Enable Record"),
                                                  subTitle: NSLocalizedString("MONITOR_ENABLE_RECORD_TINT", comment: "Should we record server status")) {
                                    Agent.shared.supervisionRecordEnabled
                                } callback: { value in
                                    Agent.shared.supervisionRecordEnabled = value
                                    if !value {
                                        let alert = UIAlertController(title: "",
                                                                      message: NSLocalizedString("DELETE_EXIST_RECORD", comment: "Do you wish to delete exist records?"),
                                                                      preferredStyle: .alert)
                                        alert.addAction(UIAlertAction(title: NSLocalizedString("CONTINUE", comment: "Continue"),
                                                                      style: .destructive,
                                                                      handler: { _ in
                                                                          PTServerManager.shared.purgeDatabase()
                                                                      }))
                                        alert.addAction(UIAlertAction(title: NSLocalizedString("CANCEL", comment: "Cancel"),
                                                                      style: .default,
                                                                      handler: nil))
                                        windowObserver.window?.topMostViewController?.present(alert, animated: true, completion: nil)
                                    }
                                }
                            }
                            .padding(.horizontal, 8)
                        }
                        .background(Color.lightGray)
                        .cornerRadius(12)
                    }
                    
                    Section {
                        VStack(spacing: 4) {
                            Group {
                                NavigationLink(destination: SettingAccountView()) {
                                    SettingElementView(icon: "rectangle.stack.person.crop",
                                                       title: NSLocalizedString("KEY", comment: "Key"),
                                                       subTitle: NSLocalizedString("ACCOUNTS_SETTING_TINT", comment: "Manage accounts and keys associated with your server"))
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                            .padding(.horizontal, 8)
                        }
                        .background(Color.lightGray)
                        .cornerRadius(12)
                    }
//                    Section {
//                        VStack(spacing: 4) {
//                            Group {
//                                NavigationLink(destination: SettingDiagView()) {
//                                    SettingElementView(icon: "cross.case",
//                                                       title: NSLocalizedString("DIAGNOSTIC", comment: "Diagnostic"),
//                                                       subTitle: NSLocalizedString("DIAGNOSTIC_SETTING_TINT", comment: "Get here if something goes wrong"))
//                                }
//                                .buttonStyle(PlainButtonStyle())
//                                Divider()
//                                NavigationLink(destination: Text("Usage")) {
//                                    SettingElementView(icon: "loupe",
//                                                       title: NSLocalizedString("USAGE", comment: "Usage"),
//                                                       subTitle: NSLocalizedString("USAGE_SETTING_TINT", comment: "Show the usage of the app"))
//                                }
//                                .buttonStyle(PlainButtonStyle())
//                            }
//                            .padding(.horizontal, 8)
//                        }
//                        .background(Color.lightGray)
//                        .cornerRadius(12)
//                    }
//                    Section {
//                        VStack(spacing: 4) {
//                            Group {
//                                NavigationLink(destination: Text("Experimental")) {
//                                    SettingElementView(icon: "pyramid",
//                                                       title: NSLocalizedString("EXPERIMENTAL", comment: "Experimental"),
//                                                       subTitle: NSLocalizedString("EXPERIMENTAL_SETTING_TINT", comment: "Testing new features here"))
//                                }
//                                .buttonStyle(PlainButtonStyle())
//                            }
//                            .padding(.horizontal, 8)
//                        }
//                        .background(Color.lightGray)
//                        .cornerRadius(12)
//                    }
//                    Section {
//                        VStack(spacing: 4) {
//                            Group {
//                                NavigationLink(destination: Text("FAQ")) {
//                                    SettingElementView(icon: "questionmark.circle",
//                                                       title: "FAQ",
//                                                       subTitle: NSLocalizedString("FAQ_SETTING_TINT", comment: "Frequently asked questions"))
//                                }
//                                .buttonStyle(PlainButtonStyle())
//                                Divider()
//                                NavigationLink(destination: Text("Support")) {
//                                    SettingElementView(icon: "highlighter",
//                                                       title: NSLocalizedString("SUPPORT", comment: "Support"),
//                                                       subTitle: NSLocalizedString("SUPPORT_SETTING_TINT", comment: "Contact us if you still have questions"))
//                                }
//                                .buttonStyle(PlainButtonStyle())
//                            }
//                            .padding(.horizontal, 8)
//                        }
//                        .background(Color.lightGray)
//                        .cornerRadius(12)
//                    }

                }
                .padding()
            }
        }
        .navigationTitle(NSLocalizedString("SETTINGS", comment: "Settings"))
        .background(
            HostingWindowFinder { [weak windowObserver] window in
                windowObserver?.window = window
            }
        )
    }
}

struct SettingView_Previews: PreviewProvider {
    static var previews: some View {
        SettingView()
            .previewLayout(.fixed(width: 800, height: 500))
    }
}
