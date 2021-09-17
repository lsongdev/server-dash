//
//  ServerDashApp.swift
//  ServerDash
//
//  Created by Lakr Aream on 4/17/21.
//

import PTFoundation
import SwiftUI

private let initializationLock = NSLock()

@main
struct ServerDashApp: App {
    @Environment(\.scenePhase) var scenePhase

    @State var foundationInitialized = false
    @StateObject var windowObserver = WindowObserver()

    @UserDefaultsWrapper(key: "wiki.qaq.FoundationBootSucceed", defaultValue: true)
    static var lastBootSucceed: Bool

    static func obtainApplicationDescription() -> String {
        let bundleIdentity = Bundle.main.infoDictionary?["CFBundleIdentifier"] as? String ?? ""
        let bundleVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let bundleBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        return "\(bundleIdentity) version:\(bundleVersion) build:\(bundleBuild)"
    }

    static func obtainApplicationStoragePath() -> URL? {
        FileManager
            .default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first
    }

    init() {
        print("Application Boot \(Date().timeIntervalSince1970)")
    }

    func setupApplication() {
        DispatchQueue.global().async {
            initializationLock.lock()
            defer { initializationLock.unlock() }
            if foundationInitialized {
                return
            }
            if !ServerDashApp.lastBootSucceed {
                print("Foundation setup canceled due a failed boot exists")
                DispatchQueue.main.async {
                    let view = AppRecoveryView()
                    let controller = UIHostingController(rootView: view)
                    (controller as UIViewController).modalPresentationStyle = .formSheet
                    (controller as UIViewController).preferredContentSize = CGSize(width: 800, height: 600)
                    windowObserver.window?.topMostViewController?.present(controller, animated: true, completion: {})
                }
                return
            }
            guard let documentLocation = ServerDashApp.obtainApplicationStoragePath()
            else {
                ServerDashApp.lastBootSucceed = false
                usleep(5000)
                fatalError("Application failed to obtain document path, system bugged!")
            }
            #if DEBUG
                let masterKey: String? = "C5B4CA6A-D94B-4FBC-BC55-BC8A6EFD5634"
            #else
                let masterKey: String? = nil
            #endif

            let requestingUserDefault = { key in
                UserDefaults.standard.value(forKey: key)
            }

            PTFoundation.initialization(baseDir: documentLocation,
                                        masterKey: masterKey, // iOS 上可以直接放行到 KeyChain 来处理主解密密钥
                                        requireRunLoop: true,
                                        requestingUserDefault: requestingUserDefault)
            { initializationError in
                ServerDashApp.lastBootSucceed = false
                usleep(5000)
                fatalError("Application failed to initialize with error \(initializationError)")
            } onRuntimeCriticalError: { runtimeError in
                ServerDashApp.lastBootSucceed = false
                usleep(5000)
                fatalError("Application crashed due to a runtime error \(runtimeError)")
            }

            for (_, checkpoints) in PTCheckpointManager.shared.obtainCheckpointList() {
                for (_, checkpoint) in checkpoints {
                    PTCheckpointManager.shared.deleteCheckpointWith(name: checkpoint.name, inSection: checkpoint.section)
                }
            }

            PTLog.shared.join("App",
                              "waiting for data to be filled",
                              level: .info)

            foundationInitialized = true

            DispatchQueue.global().asyncAfter(deadline: .now() + 8) {
                PTLog.shared.join("App",
                                  "sending successful boot signal",
                                  level: .info)
                ServerDashApp.lastBootSucceed = true
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            BootView(foundationInitialized: $foundationInitialized)
                .onOpenURL(perform: { url in
                    print("Application received url: \(url)")
                })
                .onAppear(perform: {
                    setupApplication()
                })
                .background(
                    HostingWindowFinder { [weak windowObserver] window in
                        windowObserver?.window = window
                    }
                )
        }
        .onChange(of: scenePhase) { newScenePhase in
            switch newScenePhase {
            case .active:
                PTLog.shared.join("App",
                                  "Application is active",
                                  level: .info)
                Agent.shared.applicationBecomeActive()
            case .inactive:
                PTLog.shared.join("App",
                                  "Application is inactive",
                                  level: .info)
                Agent.shared.applicationBecomeInactive()
            case .background:
                PTLog.shared.join("App",
                                  "Application is in background",
                                  level: .info)
                Agent.shared.applicationBecomeInactive()
            @unknown default:
                PTLog.shared.join("App",
                                  "Unknown Application Status \(newScenePhase)",
                                  level: .info)
            }
        }
    }
}

extension UIApplication {
    func endEditing() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
