//
//  AppRecovery.swift
//  ServerDash
//
//  Created by Lakr Aream on 4/17/21.
//

import SwiftUI
import UIKit

private struct AppRecoveryItemView: View {
    var iconSystemName: String
    var title: String
    var description: String
    var action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom) {
                Image(systemName: iconSystemName)
                Text(title)
                Spacer()
            }
            .font(.system(size: 22, weight: .semibold))
            Divider()
            Text(description)
                .multilineTextAlignment(.leading)
                .font(.system(size: 12, weight: .regular))
            Spacer()
            Button(action: {
                action()
            }, label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.right.circle.fill")
                            .scaleEffect(0.95)
                        Text("Continue")
                    }
                    .foregroundColor(.white)
                    .font(.system(size: 17, weight: .regular))
                    .padding(6)
                }
            })
                .frame(height: 36)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .foregroundColor(.lightGray)
        )
    }
}

struct AppRecoveryView: View {
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading) {
                    Text("An error occurred during the previous app launch.")
                        .multilineTextAlignment(.leading)
                        .font(.system(size: 15, weight: .regular))
                    Divider()
                    NavigationLink(
                        destination: AppLogView(showCurrentLog: false),
                        label: {
                            Text(ServerDashApp.obtainApplicationDescription())
                                .font(.system(size: 12, weight: .regular, design: .monospaced))
                        }
                    )
                    Divider()
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300))]) {
                        AppRecoveryItemView(iconSystemName: "trash",
                                            title: "Reset Application",
                                            description: "Delete all app data and start fresh.") {
                            if let documentLocation = ServerDashApp.obtainApplicationStoragePath()
                            {
                                try? FileManager.default.removeItem(atPath: documentLocation.path)
                            }
                            ServerDashApp.lastBootSucceed = true
                            usleep(5000)
                            UIControl().sendAction(#selector(NSXPCConnection.suspend),
                                                   to: UIApplication.shared, for: nil)
                            sleep(1)
                            exit(0)
                        }
                        AppRecoveryItemView(iconSystemName: "exclamationmark.arrow.circlepath",
                                            title: "Try Again",
                                            description: "Close the app and try launching it again.") {
                            ServerDashApp.lastBootSucceed = true
                            usleep(5000)
                            UIControl().sendAction(#selector(NSXPCConnection.suspend),
                                                   to: UIApplication.shared, for: nil)
                            sleep(1)
                            exit(0)
                        }
                    }
                    Divider()
                    Text(Date().description(with: .current))
                        .font(.system(size: 12, weight: .regular, design: .default))
                }
                .padding()
            }
            .navigationTitle("App Recovery")
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

#if DEBUG
    struct AppRecoveryView_Previews: PreviewProvider {
        static var previews: some View {
            AppRecoveryView()
                .previewLayout(.fixed(width: 666, height: 444))
        }
    }
#endif
