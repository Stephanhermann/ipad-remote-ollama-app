import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: ChatViewModel

    var body: some View {
        Form {
            Section("Serverprofile") {
                Button {
                    viewModel.createServerProfile()
                } label: {
                    Label("Neues Serverprofil", systemImage: "plus")
                }

                ForEach(viewModel.serverProfiles) { profile in
                    HStack {
                        Button {
                            viewModel.selectServerProfile(profile.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(profile.name)
                                    .foregroundStyle(.primary)
                                Text(profile.serverURL)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        if viewModel.selectedServerProfileID == profile.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.tint)
                        }

                        if viewModel.serverProfiles.count > 1 {
                            Button {
                                viewModel.duplicateServerProfile(profile.id)
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }

                            Button(role: .destructive) {
                                viewModel.deleteServerProfile(profile.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                    }
                }
            }

            Section("Verbindung") {
                TextField("Profilname", text: Binding(
                    get: { viewModel.currentServerProfileName },
                    set: { viewModel.updateCurrentServerName($0) }
                ))

                TextField("Server-URL", text: Binding(
                    get: { viewModel.currentServerURL },
                    set: { viewModel.updateCurrentServerURL($0) }
                ))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)

                Picker("Authentifizierung", selection: authModeBinding) {
                    ForEach(AuthenticationMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }

                if viewModel.currentAuthenticationMode == .bearer {
                    SecureField("Bearer-Token", text: Binding(
                        get: { viewModel.currentAuthToken },
                        set: { viewModel.currentAuthToken = $0 }
                    ))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                }

                if viewModel.currentAuthenticationMode == .basic {
                    TextField("Benutzername", text: Binding(
                        get: { viewModel.currentAuthUsername },
                        set: { viewModel.currentAuthUsername = $0 }
                    ))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                    SecureField("Passwort", text: Binding(
                        get: { viewModel.currentAuthPassword },
                        set: { viewModel.currentAuthPassword = $0 }
                    ))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                }

                Toggle("Streaming aktivieren", isOn: $viewModel.useStreaming)

                Button {
                    Task {
                        await viewModel.testCurrentConnection()
                    }
                } label: {
                    if viewModel.isTestingConnection {
                        ProgressView()
                    } else {
                        Label("Verbindung testen", systemImage: "network")
                    }
                }

                Button {
                    Task {
                        await viewModel.refreshModels()
                    }
                } label: {
                    if viewModel.isRefreshingModels {
                        ProgressView()
                    } else {
                        Label("Modelle laden", systemImage: "arrow.clockwise")
                    }
                }
            }

            Section("Modell") {
                if viewModel.availableModels.isEmpty {
                    Text("Noch keine Modelle geladen.")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Aktives Modell", selection: $viewModel.selectedModel) {
                        ForEach(viewModel.availableModels) { model in
                            Text(model.name).tag(model.name)
                        }
                    }
                }
            }

            Section("System Prompt") {
                TextEditor(text: $viewModel.systemPrompt)
                    .frame(minHeight: 160)
            }
        }
        .navigationTitle("Ollama Remote")
    }

    private var authModeBinding: Binding<AuthenticationMode> {
        Binding(
            get: { viewModel.currentAuthenticationMode },
            set: { viewModel.currentAuthenticationMode = $0 }
        )
    }
}
