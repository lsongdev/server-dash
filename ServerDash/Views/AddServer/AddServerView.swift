//
//  AddServerView.swift
//  ServerDash
//
//  Created by Lakr Aream on 4/19/21.
//

import PTFoundation
import SwiftUI

struct AddServerView: View {
    init(passedData: PassedData? = nil) {
        self.passedData = passedData
    }

    struct PassedData {
        init(underSection: String? = nil,
             modifyServer: PTServerManager.ServerDescriptor? = nil)
        {
            self.underSection = underSection
            self.modifyServer = modifyServer
        }

        let underSection: String?
        let modifyServer: PTServerManager.ServerDescriptor?
    }

    let passedData: PassedData?

    @State var address: String = ""
    @State var port: String = "22"
    @State var username: String = "root"
    @State var password: String = ""
    @State var privateKeyStr: String = ""
    @State var nickname: String = ""
    @State var sectionName: String = "Default"
    @State var mountpoint: String = ""
    @State var networkInterface: String = ""
    @State var openFileSheet = false

    @State private var credentials: [PTAccountManager.CredentialSummary] = []
    @State private var selectedCredentialID: String = ""
    @State private var selectedAccountIndex = 0
    @State private var showingCredentials = false

    @StateObject var windowObserver = WindowObserver()
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        Group {
            ScrollView {
                VStack(spacing: 12) {
                    serverAddr
                    accountTypeSelector
                    customization
                    HStack {
                        Button(action: {
                            windowObserver.window?.topMostViewController?.dismiss(animated: true, completion: nil)
                            presentationMode.wrappedValue.dismiss()
                        }, label: {
                            HStack {
                                Spacer()
                                Image(systemName: "xmark")
                                Spacer()
                            }
                            .padding(10)
                            .foregroundColor(.overridableAccentColor)
                            .font(.system(size: 20, weight: .regular, design: .default))
                            .background(
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .foregroundColor(.white)
                                        .opacity(0.05)
                                    RoundedRectangle(cornerRadius: 8)
                                        .foregroundColor(.white)
                                        .shadow(radius: 6)
                                        .opacity(0.2)
                                }
                            )
                            .frame(maxWidth: 500)
                        })
                        Button(action: {
                            addServer()
                        }, label: {
                            HStack {
                                Spacer()
                                Image(systemName: "arrow.right")
                                Spacer()
                            }
                            .padding(10)
                            .foregroundColor(.overridableAccentColor)
                            .font(.system(size: 20, weight: .regular, design: .default))
                            .background(
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .foregroundColor(.white)
                                        .opacity(0.05)
                                    RoundedRectangle(cornerRadius: 8)
                                        .foregroundColor(.white)
                                        .shadow(radius: 6)
                                        .opacity(0.2)
                                }
                            )
                        })
                    }
                }
                .padding()
            }
            .navigationTitle(passedData?.modifyServer == nil ? "Add Server" : "Modify Server")
            .navigationBarItems(trailing:
                Button(action: {
                    addServer()
                }, label: {
                    Image(systemName: "arrow.right.circle.fill")
                })
            )
            .background(
                HostingWindowFinder { [weak windowObserver] window in
                    windowObserver?.window = window
                }
            )
            .background(
                NavigationLink(
                    destination: CredentialListView(),
                    isActive: Binding(
                        get: { showingCredentials },
                        set: { isActive in
                            showingCredentials = isActive
                            if !isActive { reloadCredentials() }
                        }
                    ),
                    label: { EmptyView() }
                )
                .hidden()
            )
        }
        .onAppear {
            reloadCredentials()
            if let serverDescriptor = passedData?.modifyServer,
               let server = PTServerManager.shared.obtainServer(withKey: serverDescriptor)
            {
                address = server.host
                port = String(server.port)
                if let account = PTAccountManager.shared.retrieveAccountWith(key: server.accountDescriptor),
                   let details = account.obtainDecryptedObject()
                {
                    username = details.account
                    password = details.key
                    if account.type == .secureShellWithKey {
                        selectedAccountIndex = 1
                        privateKeyStr = details.representedObject.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                    }
                    if credentials.contains(where: { $0.id == server.accountDescriptor }) {
                        selectedCredentialID = server.accountDescriptor
                        selectedAccountIndex = 2
                    }
                }
                nickname = server.tags[.nickName, default: ""]
                if let sectionName = server.tags[.sectionName],
                   sectionName != PTServerManager.Server.defaultSectionName
                {
                    self.sectionName = sectionName
                }
                mountpoint = server.tags[.preferredMountPoint, default: ""]
                networkInterface = server.tags[.preferredNetworkInterface, default: ""]
            }
        }
        .sheet(isPresented: $openFileSheet) {
            DocumentPicker(fileContent: $privateKeyStr)
        }
    }

    var serverAddr: some View {
        AddServerStepView(title: "Server Basics",
                          icon: "externaldrive.connected.to.line.below.fill") {
            VStack {
                InputElementView(title: "Address",
                                 placeholder: "Example: 192.168.1.1",
                                 required: true,
                                 validator: {
                                     isServerAddrValid(addr: address)
                                 },
                                 type: .URL,
                                 useInlineTextField: true,
                                 binder: $address)
                InputElementView(title: "Port",
                                 placeholder: "Example: 22",
                                 required: true,
                                 validator: {
                                     if let port = Int(port), port >= 0, port <= 65535 {
                                         return true
                                     }
                                     return false
                                 },
                                 type: nil,
                                 useInlineTextField: true,
                                 binder: $port)
            }
        }
    }

    var accountTypeSelector: some View {
        AddServerStepView(title: "Account",
                          icon: "key.fill") {
            VStack(spacing: 12) {
                Picker(selection: accountTypeSelection, label: Text("")) {
                    Text("Password").tag(0)
                    Text("SSH Key").tag(1)
                    Text("Credentials").tag(2)
                }
                .pickerStyle(.segmented)

                switch selectedAccountIndex {
                case 0:
                    usePassword
                case 1:
                    useKey
                default:
                    savedCredentialPanel
                }
            }
        }
        .animation(.interactiveSpring(response: 0.25, dampingFraction: 1, blendDuration: 0), value: selectedAccountIndex)
    }

    private var savedCredentialPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("CREDENTIAL")
                .font(.system(size: 12, weight: .semibold))
                .opacity(0.5)

            HStack(spacing: 8) {
                Menu {
                    ForEach(credentials) { credential in
                        Button {
                            selectedCredentialID = credential.id
                        } label: {
                            Label(
                                "\(credential.displayName) · \(credential.type == .secureShellWithKey ? "SSH Key" : "Password")",
                                systemImage: credential.type == .secureShellWithKey
                                    ? "key.horizontal" : "person.crop.circle"
                            )
                        }
                    }
                } label: {
                    HStack {
                        Text(credentials.first(where: { $0.id == selectedCredentialID })?.displayName
                            ?? (credentials.isEmpty ? "No saved credentials" : "Select Credential"))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundColor(selectedCredentialID.isEmpty ? .secondary : .primary)
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(Color.lightGray)
                    .cornerRadius(6)
                }
                .disabled(credentials.isEmpty)

                Button {
                    showingCredentials = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .medium))
                        .frame(width: 36, height: 36)
                        .background(Color.lightGray)
                        .cornerRadius(6)
                }
                .accessibilityLabel("Manage Credentials")
            }

            if !selectedCredentialID.isEmpty {
                Text("Uses the latest saved credential when connecting.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if credentials.isEmpty {
                Text("Tap + to create a reusable credential.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    var usePassword: some View {
        VStack {
            InputElementView(title: "Username",
                             placeholder: "Example: root",
                             required: true,
                             validator: { !username.isEmpty },
                             type: .username,
                             useInlineTextField: true,
                             binder: $username)
            InputElementView(title: "Password",
                             placeholder: "",
                             required: true,
                             validator: { !password.isEmpty },
                             type: .password,
                             useInlineTextField: true,
                             binder: $password)
        }
    }

    var useKey: some View {
        VStack {
            InputElementView(title: "Username",
                             placeholder: "Example: root",
                             required: true,
                             validator: { !username.isEmpty },
                             type: .username,
                             useInlineTextField: true,
                             binder: $username)
            InputElementView(title: "Passphrase",
                             placeholder: "",
                             required: false,
                             validator: { true },
                             type: .password,
                             useInlineTextField: true,
                             binder: $password)
            InputElementView(title: "Private Key",
                             placeholder: "OPENSSH PRIVATE KEY",
                             required: true,
                             validator: { !privateKeyStr.isEmpty },
                             type: nil,
                             useInlineTextField: false,
                             binder: $privateKeyStr)
            TextEditor(text: $privateKeyStr)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .frame(height: 50)
                .padding()
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .foregroundColor(.lightGray)
                            .opacity(0.5)
                        if privateKeyStr.isEmpty {
                            Text("OPENSSH PRIVATE KEY")
                                .font(.system(size: 12))
                        }
                    }
                )
            HStack {
                Spacer()
                Button {
                    openFileSheet = true
                } label: {
                    Image(systemName: "folder")
                        .frame(width: 20, height: 16)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                }
            }
        }
    }

    var customization: some View {
        AddServerStepView(title: "Customization",
                          icon: "lasso.sparkles") {
            VStack(spacing: 12) {
                InputElementView(title: "Display Name",
                                 placeholder: "Example: My Server",
                                 required: false,
                                 validator: { true },
                                 type: .nickname,
                                 useInlineTextField: true,
                                 binder: $nickname)
                InputElementView(title: "Mount Point",
                                 placeholder: "Example: /data",
                                 required: false,
                                 validator: { true },
                                 type: nil,
                                 useInlineTextField: true,
                                 binder: $mountpoint)
                InputElementView(title: "Network Interface",
                                 placeholder: "Example: enp0s1",
                                 required: false,
                                 validator: { true },
                                 type: nil,
                                 useInlineTextField: true,
                                 binder: $networkInterface)
            }
        }
    }

    private func reloadCredentials() {
        credentials = PTAccountManager.shared.listCredentials()
        if !selectedCredentialID.isEmpty,
           !credentials.contains(where: { $0.id == selectedCredentialID }) {
            selectedCredentialID = ""
        }
    }

    private var accountTypeSelection: Binding<Int> {
        Binding(
            get: { selectedAccountIndex },
            set: { index in
                if selectedAccountIndex == 2 && index != 2 {
                    // A saved credential is referenced, never copied into manual fields.
                    username = "root"
                    password = ""
                    privateKeyStr = ""
                    selectedCredentialID = ""
                }
                selectedAccountIndex = index
            }
        )
    }

    func addServer() {
        func failed() {
            let alert = UIAlertController(
                title: "Error",
                message: "Check server details and credential",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "Done", style: .default))
            windowObserver.window?.topMostViewController?.present(alert, animated: true)
        }

        guard isServerAddrValid(addr: address),
              let serverPort = Int32(port), serverPort > 0
        else {
            failed()
            return
        }

        let accountDescriptor: String
        var createdServerCredential = false
        if selectedAccountIndex == 2 {
            guard PTAccountManager.shared.retrieveAccountWith(key: selectedCredentialID) != nil else {
                failed()
                return
            }
            accountDescriptor = selectedCredentialID
        } else {
            let secret: PTAccountManager.CredentialSecret
            if selectedAccountIndex == 0 {
                guard !username.isEmpty, !password.isEmpty else {
                    failed()
                    return
                }
                secret = .password(password)
            } else {
                guard !username.isEmpty, !privateKeyStr.isEmpty else {
                    failed()
                    return
                }
                secret = .privateKey(privateKeyStr, passphrase: password, publicKey: nil)
            }
            guard let created = PTAccountManager.shared.createServerCredential(
                label: nickname.isEmpty ? address : nickname,
                username: username,
                secret: secret
            ) else {
                failed()
                return
            }
            accountDescriptor = created
            createdServerCredential = true
        }

        var tags: [PTServerManager.Server.ServerTag: String] = [:]
        if !nickname.isEmpty { tags[.nickName] = nickname }
        if !mountpoint.isEmpty { tags[.preferredMountPoint] = mountpoint }
        if !networkInterface.isEmpty { tags[.preferredNetworkInterface] = networkInterface }
        if !sectionName.isEmpty { tags[.sectionName] = sectionName }

        let server = PTServerManager.Server(
            host: address,
            port: serverPort,
            accountDescriptor: accountDescriptor,
            supervisionTimeInterval: 0,
            tags: tags
        )
        guard let descriptor = PTServerManager.shared.createServer(
            withObject: server,
            onRecoverableError: { _, _ in .continueRegistration }
        ) else {
            if createdServerCredential {
                PTAccountManager.shared.removeServerCredentialIfUnused(id: accountDescriptor)
            }
            failed()
            return
        }

        if let oldDescriptor = passedData?.modifyServer {
            PTServerManager.shared.removeServerFromRegisteredList(withKey: oldDescriptor)
        }
        PTServerManager.shared.superviseOnServer(
            withKey: descriptor,
            interval: Agent.shared.supervisionInterval
        )
        windowObserver.window?.topMostViewController?.dismiss(animated: true)
        presentationMode.wrappedValue.dismiss()
    }

}

struct AddServerView_Previews: PreviewProvider {
    static var previews: some View {
        AddServerView()
            .preferredColorScheme(.light)
            .previewLayout(.fixed(width: 300, height: 900))
        AddServerView()
            .preferredColorScheme(.light)
            .previewLayout(.fixed(width: 600, height: 900))
        AddServerView()
            .preferredColorScheme(.dark)
            .previewLayout(.fixed(width: 600, height: 900))
    }
}
