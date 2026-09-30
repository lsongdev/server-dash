//
//  AboutView.swift
//  ServerDash
//

import SwiftUI

struct AboutView: View {
    private let projectURL = URL(string: "https://github.com/lsongdev/server-dash")!

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? "Server Dash"
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "—"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            ?? "—"
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 12) {
                    Image("AboutIcon")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 96, height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.08))
                        }
                        .shadow(color: .black.opacity(0.1), radius: 10, y: 4)

                    Text(appName)
                        .font(.title2.weight(.semibold))

                    Text(String(
                        format: NSLocalizedString(
                            "ABOUT_VERSION_FORMAT",
                            comment: "Version %@ (Build %@)"
                        ),
                        appVersion,
                        buildNumber
                    ))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .listRowBackground(Color.clear)
            }

            Section {
                Link(destination: projectURL) {
                    HStack {
                        Label(
                            NSLocalizedString("PROJECT_LINK", comment: "Project on GitHub"),
                            systemImage: "chevron.left.forwardslash.chevron.right"
                        )
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .foregroundColor(.secondary)
                    }
                }
            } footer: {
                Text(NSLocalizedString(
                    "COPY_RIGHT_FULL",
                    comment: "Copyright information"
                ))
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
            }
        }
        .navigationTitle(NSLocalizedString("ABOUT", comment: "About"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AboutView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            AboutView()
        }
    }
}
