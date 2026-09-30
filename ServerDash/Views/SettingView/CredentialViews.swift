import PTFoundation
import Security
import SwiftUI
import UIKit

private struct CredentialEditorItem: Identifiable {
    let id = UUID()
    let credential: PTAccountManager.CredentialSummary?
}

struct CredentialListView: View {
    var showsDoneButton = false
    @Environment(\.dismiss) private var dismiss
    @State private var credentials: [PTAccountManager.CredentialSummary] = []
    @State private var editor: CredentialEditorItem?
    @State private var deletionBlocked = false

    var body: some View {
        List {
            ForEach(credentials) { credential in
                Button {
                    editor = CredentialEditorItem(credential: credential)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: credential.type == .secureShellWithKey ? "key.horizontal" : "person.crop.circle")
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(credential.displayName).foregroundColor(.primary)
                            Text(credential.username).font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            .onDelete { indexes in
                for index in indexes {
                    if !PTAccountManager.shared.deleteCredential(id: credentials[index].id) {
                        deletionBlocked = true
                    }
                }
                reload()
            }
        }
        .overlay {
            if credentials.isEmpty {
                ContentUnavailableCredentialView()
            }
        }
        .navigationTitle(NSLocalizedString("CREDENTIALS", comment: "Credentials"))
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if showsDoneButton {
                    Button(NSLocalizedString("DONE", comment: "Done")) { dismiss() }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    editor = CredentialEditorItem(credential: nil)
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(NSLocalizedString("NEW_CREDENTIAL", comment: "New Credential"))
            }
        }
        .sheet(item: $editor, onDismiss: reload) { item in
            NavigationView {
                CredentialEditorView(existing: item.credential)
            }
        }
        .alert(NSLocalizedString("CREDENTIAL_IN_USE", comment: "Credential is used by a server"), isPresented: $deletionBlocked) {
            Button(NSLocalizedString("DONE", comment: "Done"), role: .cancel) {}
        }
        .onAppear(perform: reload)
    }

    private func reload() {
        credentials = PTAccountManager.shared.listCredentials()
    }
}

private struct ContentUnavailableCredentialView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "key")
                .font(.system(size: 42))
            Text(NSLocalizedString("NO_CREDENTIALS", comment: "No credentials yet"))
                .font(.headline)
        }
        .foregroundColor(.secondary)
    }
}

private struct CredentialEditorView: View {
    let existing: PTAccountManager.CredentialSummary?

    @Environment(\.dismiss) private var dismiss
    @State private var label: String
    @State private var username: String
    @State private var isKey: Bool
    @State private var password = ""
    @State private var privateKey = ""
    @State private var passphrase = ""
    @State private var publicKey = ""
    @State private var generatedPrivateKey: String
    @State private var importingKey = false
    @State private var error = false

    init(existing: PTAccountManager.CredentialSummary?) {
        self.existing = existing
        let object = existing.flatMap { PTAccountManager.shared.retrieveAccountWith(key: $0.id)?.obtainDecryptedObject() }
        _label = State(initialValue: existing?.displayName ?? "")
        _username = State(initialValue: existing?.username ?? "")
        _isKey = State(initialValue: existing?.type == .secureShellWithKey)
        if existing?.type == .secureShellWithKey {
            _privateKey = State(initialValue: object?.representedObject.flatMap { String(data: $0, encoding: .utf8) } ?? "")
            _passphrase = State(initialValue: object?.key ?? "")
            _publicKey = State(initialValue: object?.publicKey ?? "")
            _generatedPrivateKey = State(initialValue: object?.representedObject.flatMap { String(data: $0, encoding: .utf8) } ?? "")
        } else {
            _password = State(initialValue: object?.key ?? "")
            _generatedPrivateKey = State(initialValue: "")
        }
    }

    private var canSave: Bool {
        !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            (isKey ? privateKey.contains("PRIVATE KEY-----") : !password.isEmpty)
    }

    var body: some View {
        Form {
            Section {
                TextField(NSLocalizedString("DISPLAY_NAME", comment: "Name"), text: $label)
                TextField(NSLocalizedString("USERNAME", comment: "Username"), text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if existing == nil {
                    Picker(NSLocalizedString("AUTHENTICATION", comment: "Authentication"), selection: $isKey) {
                        Text(NSLocalizedString("PASSWORD", comment: "Password")).tag(false)
                        Text(NSLocalizedString("SSH_KEY", comment: "SSH Key")).tag(true)
                    }
                }
            }

            if isKey {
                Section {
                    Button(NSLocalizedString("IMPORT_PRIVATE_KEY", comment: "Import Private Key")) {
                        importingKey = true
                    }
                    Button(NSLocalizedString("GENERATE_SSH_KEY", comment: "Generate SSH Key")) {
                        if let pair = SSHKeyGenerator.generate() {
                            generatedPrivateKey = pair.privateKey
                            privateKey = pair.privateKey
                            publicKey = pair.publicKey
                            passphrase = ""
                        } else {
                            error = true
                        }
                    }
                    SecureField(NSLocalizedString("PASSPHRASE_OPTIONAL", comment: "Passphrase (optional)"), text: $passphrase)
                    TextEditor(text: $privateKey)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 100)
                        .onChange(of: privateKey) { _ in
                            if privateKey != generatedPrivateKey { publicKey = "" }
                        }
                } header: {
                    Text(NSLocalizedString("PRIVATE_KEY", comment: "Private Key"))
                }

                if !publicKey.isEmpty {
                    Section {
                        Text(publicKey)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                        Button(NSLocalizedString("COPY_PUBLIC_KEY", comment: "Copy Public Key")) {
                            UIPasteboard.general.string = publicKey
                        }
                    } header: {
                        Text(NSLocalizedString("PUBLIC_KEY", comment: "Public Key"))
                    } footer: {
                        Text(NSLocalizedString("PUBLIC_KEY_HINT", comment: "Add this key to your server's authorized_keys file."))
                    }
                }
            } else {
                Section {
                    SecureField(NSLocalizedString("PASSWORD", comment: "Password"), text: $password)
                }
            }
        }
        .navigationTitle(existing == nil
            ? NSLocalizedString("NEW_CREDENTIAL", comment: "New Credential")
            : NSLocalizedString("EDIT_CREDENTIAL", comment: "Edit Credential"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(NSLocalizedString("CANCEL", comment: "Cancel")) { dismiss() }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(NSLocalizedString("SAVE", comment: "Save")) { save() }
                    .disabled(!canSave)
            }
        }
        .sheet(isPresented: $importingKey) {
            DocumentPicker(fileContent: $privateKey)
        }
        .alert(NSLocalizedString("CREDENTIAL_SAVE_FAILED", comment: "Could not save credential"), isPresented: $error) {
            Button(NSLocalizedString("DONE", comment: "Done"), role: .cancel) {}
        }
    }

    private func save() {
        let secret: PTAccountManager.CredentialSecret = isKey
            ? .privateKey(privateKey, passphrase: passphrase, publicKey: publicKey.isEmpty ? nil : publicKey)
            : .password(password)
        let success: Bool
        if let existing {
            success = PTAccountManager.shared.updateCredential(
                id: existing.id, label: label, username: username, secret: secret
            )
        } else {
            success = PTAccountManager.shared.createCredential(
                label: label, username: username, secret: secret
            ) != nil
        }
        if success { dismiss() } else { error = true }
    }
}
