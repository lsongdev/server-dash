//
//  AddServerView.swift
//  ServerDash
//

import PTFoundation
import SwiftUI

struct AddServerView: View {
    struct PassedData {
        init(underSection: String? = nil,
             modifyServer: PTServerManager.ServerDescriptor? = nil) {
            self.underSection = underSection
            self.modifyServer = modifyServer
        }

        let underSection: String?
        let modifyServer: PTServerManager.ServerDescriptor?
    }

    let passedData: PassedData?

    @Environment(\.dismiss) private var dismiss

    @State private var address = ""
    @State private var port = "22"
    @State private var username = "root"
    @State private var password = ""
    @State private var passphrase = ""
    @State private var privateKeyStr = ""
    @State private var nickname = ""
    @State private var sectionName = "Default"
    @State private var mountpoint = ""
    @State private var networkInterface = ""
    @State private var openFileSheet = false
    @State private var credentials: [PTAccountManager.CredentialSummary] = []
    @State private var selectedCredentialID = ""
    @State private var selectedAccountIndex = 0
    @State private var didLoadServer = false
    @State private var saveFailed = false

    init(passedData: PassedData? = nil) {
        self.passedData = passedData
    }

    var body: some View {
        Form {
            Section {
                ServerFormField(title: "Address") {
                    TextField("Hostname or IP address", text: $address)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }
                ServerFormField(title: "Port") {
                    TextField("22", text: $port)
                        .keyboardType(.numberPad)
                }
            } header: {
                Text("Server")
            } footer: {
                Text("Use a hostname or IP address and a port from 1 to 65535.")
            }

            Section {
                Picker("Method", selection: accountTypeSelection) {
                    Text("Password").tag(0)
                    Text("SSH Key").tag(1)
                    Text("Credentials").tag(2)
                }
                .pickerStyle(.segmented)

                switch selectedAccountIndex {
                case 0:
                    usernameField
                    ServerFormField(title: "Password") {
                        SecureField("Enter password", text: $password)
                            .textContentType(.password)
                    }
                case 1:
                    usernameField
                    ServerFormField(title: "Passphrase (optional)") {
                        SecureField("Enter passphrase", text: $passphrase)
                    }
                    ServerFormField(title: "Private Key") {
                        TextEditor(text: $privateKeyStr)
                            .font(.system(.caption, design: .monospaced))
                            .frame(minHeight: 110)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    Button {
                        openFileSheet = true
                    } label: {
                        Label("Import Private Key", systemImage: "square.and.arrow.down")
                    }
                default:
                    Picker("Credential", selection: $selectedCredentialID) {
                        Text("Select Credential").tag("")
                        ForEach(credentials) { credential in
                            Text(credential.displayName).tag(credential.id)
                        }
                    }
                    .disabled(credentials.isEmpty)
                    NavigationLink {
                        CredentialListView()
                            .onDisappear(perform: reloadCredentials)
                    } label: {
                        Label("Manage Credentials", systemImage: "key")
                    }
                }
            } header: {
                Text("Authentication")
            } footer: {
                if selectedAccountIndex == 2 {
                    Text("Saved credentials stay linked to this server and reflect later changes.")
                } else {
                    Text("These details are saved for this server only.")
                }
            }

            Section {
                ServerFormField(title: "Display Name") {
                    TextField("Optional", text: $nickname)
                }
                ServerFormField(title: "Group") {
                    TextField("Default", text: $sectionName)
                }
                ServerFormField(title: "Mount Point") {
                    TextField("Optional, e.g. /data", text: $mountpoint)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                ServerFormField(title: "Network Interface") {
                    TextField("Optional, e.g. enp0s1", text: $networkInterface)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            } header: {
                Text("Details")
            }
        }
        .navigationTitle(passedData?.modifyServer == nil ? "Add Server" : "Edit Server")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Save") { addServer() }
                    .disabled(!canSave)
            }
        }
        .onAppear {
            reloadCredentials()
            guard !didLoadServer else { return }
            didLoadServer = true
            loadServerIfEditing()
        }
        .sheet(isPresented: $openFileSheet) {
            DocumentPicker(fileContent: $privateKeyStr)
        }
        .alert("Could Not Save Server", isPresented: $saveFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Check the server details and authentication, then try again.")
        }
    }

    private var usernameField: some View {
        ServerFormField(title: "Username") {
            TextField("e.g. root", text: $username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.username)
        }
    }

    private var canSave: Bool {
        guard isServerAddrValid(addr: address),
              let serverPort = Int32(port),
              serverPort > 0 else { return false }

        switch selectedAccountIndex {
        case 0:
            return !username.isEmpty && !password.isEmpty
        case 1:
            return !username.isEmpty && !privateKeyStr.isEmpty
        default:
            return credentials.contains { $0.id == selectedCredentialID }
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
                    passphrase = ""
                    privateKeyStr = ""
                    selectedCredentialID = ""
                }
                selectedAccountIndex = index
            }
        )
    }

    private func reloadCredentials() {
        credentials = PTAccountManager.shared.listCredentials()
        if !selectedCredentialID.isEmpty,
           !credentials.contains(where: { $0.id == selectedCredentialID }) {
            selectedCredentialID = ""
        }
    }

    private func loadServerIfEditing() {
        guard let serverDescriptor = passedData?.modifyServer,
              let server = PTServerManager.shared.obtainServer(withKey: serverDescriptor)
        else {
            if let section = passedData?.underSection { sectionName = section }
            return
        }

        address = server.host
        port = String(server.port)
        if credentials.contains(where: { $0.id == server.accountDescriptor }) {
            // Keep the reference. Never copy a reusable credential into form state.
            selectedCredentialID = server.accountDescriptor
            selectedAccountIndex = 2
        } else if let account = PTAccountManager.shared.retrieveAccountWith(key: server.accountDescriptor),
                  let details = account.obtainDecryptedObject() {
            username = details.account
            if account.type == .secureShellWithKey {
                selectedAccountIndex = 1
                passphrase = details.key
                privateKeyStr = details.representedObject.flatMap {
                    String(data: $0, encoding: .utf8)
                } ?? ""
            } else {
                password = details.key
            }
        }
        nickname = server.tags[.nickName, default: ""]
        if let group = server.tags[.sectionName],
           group != PTServerManager.Server.defaultSectionName {
            sectionName = group
        }
        mountpoint = server.tags[.preferredMountPoint, default: ""]
        networkInterface = server.tags[.preferredNetworkInterface, default: ""]
    }

    private func addServer() {
        guard canSave, let serverPort = Int32(port) else {
            saveFailed = true
            return
        }

        let accountDescriptor: String
        var createdServerCredential = false
        if selectedAccountIndex == 2 {
            guard PTAccountManager.shared.retrieveAccountWith(key: selectedCredentialID) != nil else {
                saveFailed = true
                return
            }
            accountDescriptor = selectedCredentialID
        } else {
            let secret: PTAccountManager.CredentialSecret = selectedAccountIndex == 0
                ? .password(password)
                : .privateKey(privateKeyStr, passphrase: passphrase, publicKey: nil)
            guard let created = PTAccountManager.shared.createServerCredential(
                label: nickname.isEmpty ? address : nickname,
                username: username,
                secret: secret
            ) else {
                saveFailed = true
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
            saveFailed = true
            return
        }

        if let oldDescriptor = passedData?.modifyServer {
            PTServerManager.shared.removeServerFromRegisteredList(withKey: oldDescriptor)
        }
        PTServerManager.shared.superviseOnServer(
            withKey: descriptor,
            interval: Agent.shared.supervisionInterval
        )
        dismiss()
    }
}

private struct ServerFormField<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
            content
        }
        .padding(.vertical, 3)
    }
}

struct AddServerView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView { AddServerView() }
    }
}
