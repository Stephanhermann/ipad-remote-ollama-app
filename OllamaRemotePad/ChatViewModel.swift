import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ChatViewModel: ObservableObject {
    enum BannerStyle {
        case error
        case success
        case info
    }

    struct BannerData: Identifiable, Equatable {
        let id: UUID
        let message: String
        let style: BannerStyle

        init(id: UUID = UUID(), message: String, style: BannerStyle) {
            self.id = id
            self.message = message
            self.style = style
        }
    }

    private let placeholderMessage = ChatMessage(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID(),
        role: .assistant,
        content: "Verbinde dich mit deinem Ollama-Server und starte dann einen Chat."
    )

    @AppStorage("selectedModel") var selectedModel: String = ""
    @AppStorage("systemPrompt") var systemPrompt: String = "Du bist ein hilfreicher Assistent."
    @AppStorage("useStreaming") var useStreaming: Bool = true
    @AppStorage("savedSessions") private var savedSessionsData: String = ""
    @AppStorage("selectedSessionID") private var selectedSessionIDString: String = ""
    @AppStorage("savedServerProfiles") private var savedServerProfilesData: String = ""
    @AppStorage("selectedServerProfileID") private var selectedServerProfileIDString: String = ""
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding: Bool = false

    @Published var availableModels: [OllamaModel] = []
    @Published var sessions: [ChatSession] = []
    @Published var selectedSessionID: UUID?
    @Published var serverProfiles: [ServerProfile] = []
    @Published var selectedServerProfileID: UUID?
    @Published var draft: String = ""
    @Published var draftAttachments: [ImageAttachment] = []
    @Published var chatSearchText: String = ""
    @Published var isLoading = false
    @Published var isRefreshingModels = false
    @Published var errorMessage: String?
    @Published var banner: BannerData?
    @Published var isTestingConnection = false

    private let client = OllamaClient()
    private var bannerDismissTask: Task<Void, Never>?

    var currentMessages: [ChatMessage] {
        currentSession?.messages ?? [placeholderMessage]
    }

    var currentSessionTitle: String {
        currentSession?.title ?? "Neuer Chat"
    }

    var currentServerProfileName: String {
        currentServerProfile?.name ?? "Kein Server"
    }

    var canSend: Bool {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return (!text.isEmpty || !draftAttachments.isEmpty) && !selectedModel.isEmpty && !isLoading
    }

    var filteredSessions: [ChatSession] {
        let query = chatSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return sessions }
        return sessions.filter { session in
            session.title.localizedCaseInsensitiveContains(query) ||
            session.messages.contains { $0.content.localizedCaseInsensitiveContains(query) }
        }
    }

    var draftCharacterCount: Int {
        draft.count
    }

    var draftEstimatedTokenCount: Int {
        let textTokens = max(1, draftCharacterCount / 4)
        let imageTokens = draftAttachments.count * 256
        return textTokens + imageTokens
    }

    var currentConversationEstimatedTokenCount: Int {
        currentMessages.reduce(into: 0) { partialResult, message in
            partialResult += max(1, message.content.count / 4)
            partialResult += message.attachments.count * 256
        }
    }

    var currentServerURL: String {
        currentServerProfile?.serverURL ?? ""
    }

    var currentAuthenticationMode: AuthenticationMode {
        get { currentServerProfile?.authenticationMode ?? .none }
        set { updateCurrentServerProfile { $0.authenticationMode = newValue } }
    }

    var currentAuthToken: String {
        get { currentServerProfile?.authToken ?? "" }
        set { updateCurrentServerProfile { $0.authToken = newValue } }
    }

    var currentAuthUsername: String {
        get { currentServerProfile?.authUsername ?? "" }
        set { updateCurrentServerProfile { $0.authUsername = newValue } }
    }

    var currentAuthPassword: String {
        get { currentServerProfile?.authPassword ?? "" }
        set { updateCurrentServerProfile { $0.authPassword = newValue } }
    }

    private var currentSession: ChatSession? {
        guard let selectedSessionID else { return nil }
        return sessions.first(where: { $0.id == selectedSessionID })
    }

    private var currentServerProfile: ServerProfile? {
        guard let selectedServerProfileID else { return nil }
        return serverProfiles.first(where: { $0.id == selectedServerProfileID })
    }

    private var currentServerURLObject: URL? {
        URL(string: currentServerURL.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func bootstrap() async {
        loadServerProfiles()
        if serverProfiles.isEmpty {
            createServerProfile()
        }
        loadSessions()
        if sessions.isEmpty {
            createNewSession()
        }
        guard availableModels.isEmpty else { return }
        await refreshModels()
    }

    func refreshModels() async {
        guard let serverURL = currentServerURLObject else {
            presentError(OllamaError.invalidURL.errorDescription ?? "Unbekannter Fehler")
            return
        }

        isRefreshingModels = true
        defer { isRefreshingModels = false }

        do {
            let models = try await client.fetchModels(baseURL: serverURL, auth: authentication)
            availableModels = models

            if selectedModel.isEmpty || !models.contains(where: { $0.name == selectedModel }) {
                selectedModel = models.first?.name ?? ""
            }
            clearError()
        } catch {
            presentError(error.localizedDescription)
        }
    }

    func testCurrentConnection() async {
        guard let serverURL = currentServerURLObject else {
            presentError(OllamaError.invalidURL.errorDescription ?? "Unbekannter Fehler")
            return
        }

        isTestingConnection = true
        defer { isTestingConnection = false }

        do {
            try await client.testConnection(baseURL: serverURL, auth: authentication)
            presentBanner("Verbindung erfolgreich getestet.", style: .success)
            clearError()
        } catch {
            presentError(error.localizedDescription)
        }
    }

    func sendMessage() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !draftAttachments.isEmpty else { return }
        guard let serverURL = currentServerURLObject else {
            presentError(OllamaError.invalidURL.errorDescription ?? "Unbekannter Fehler")
            return
        }
        guard !selectedModel.isEmpty else {
            presentError("Bitte zuerst ein Modell auswaehlen.")
            return
        }

        ensureSessionExists()
        guard let sessionID = selectedSessionID else { return }

        let outgoingAttachments = draftAttachments
        draft = ""
        draftAttachments = []
        clearError()
        isLoading = true

        appendMessage(ChatMessage(role: .user, content: text, attachments: outgoingAttachments), to: sessionID)
        let assistantID = UUID()
        appendMessage(ChatMessage(id: assistantID, role: .assistant, content: ""), to: sessionID)

        let requestMessages = buildRequestMessages(for: sessionID)

        do {
            if useStreaming {
                try await client.streamChat(
                    baseURL: serverURL,
                    auth: authentication,
                    model: selectedModel,
                    messages: requestMessages
                ) { [weak self] chunk in
                    guard let self else { return }
                    await MainActor.run {
                        self.appendStreamChunk(chunk, assistantID: assistantID, sessionID: sessionID)
                    }
                }
            } else {
                let reply = try await client.sendChat(
                    baseURL: serverURL,
                    auth: authentication,
                    model: selectedModel,
                    messages: requestMessages
                )
                replaceAssistantMessage(id: assistantID, sessionID: sessionID, content: reply)
            }

            trimEmptyAssistantMessage(id: assistantID, sessionID: sessionID)
            updateSessionMetadata(sessionID: sessionID, preferredTitle: text.isEmpty ? "Bildanfrage" : text)
            persistSessions()
        } catch {
            removeMessage(id: assistantID, from: sessionID)
            presentError(error.localizedDescription)
            persistSessions()
        }

        isLoading = false
    }

    func createNewSession() {
        let session = ChatSession(
            title: "Neuer Chat",
            messages: [ChatMessage(role: .assistant, content: initialAssistantText)]
        )
        sessions.insert(session, at: 0)
        selectedSessionID = session.id
        selectedSessionIDString = session.id.uuidString
        persistSessions()
    }

    func selectSession(_ sessionID: UUID) {
        selectedSessionID = sessionID
        selectedSessionIDString = sessionID.uuidString
        persistSessions()
    }

    func deleteSessions(at offsets: IndexSet) {
        let idsToDelete = offsets.map { sessions[$0].id }
        sessions.remove(atOffsets: offsets)

        if let selectedSessionID, idsToDelete.contains(selectedSessionID) {
            selectedSessionID = sessions.first?.id
            selectedSessionIDString = selectedSessionID?.uuidString ?? ""
        }

        if sessions.isEmpty {
            createNewSession()
        } else {
            persistSessions()
        }
    }

    func deleteSession(_ sessionID: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        deleteSessions(at: IndexSet(integer: index))
    }

    func clearConversation() {
        guard let sessionID = selectedSessionID else { return }
        replaceSessionMessages(
            sessionID: sessionID,
            messages: [ChatMessage(role: .assistant, content: initialAssistantText)]
        )
        if let index = sessions.firstIndex(where: { $0.id == sessionID }) {
            sessions[index].title = "Neuer Chat"
        }
        errorMessage = nil
        persistSessions()
    }

    func createServerProfile() {
        let nextNumber = serverProfiles.count + 1
        let profile = ServerProfile(name: "Server \(nextNumber)")
        serverProfiles.append(profile)
        selectedServerProfileID = profile.id
        selectedServerProfileIDString = profile.id.uuidString
        persistServerProfiles()
        presentBanner("Neues Serverprofil erstellt.", style: .info)
    }

    func duplicateServerProfile(_ profileID: UUID) {
        guard let profile = serverProfiles.first(where: { $0.id == profileID }) else { return }
        var duplicate = profile
        duplicate = ServerProfile(
            name: "\(profile.name) Kopie",
            serverURL: profile.serverURL,
            authenticationMode: profile.authenticationMode,
            authToken: profile.authToken,
            authUsername: profile.authUsername,
            authPassword: profile.authPassword
        )
        serverProfiles.append(duplicate)
        selectedServerProfileID = duplicate.id
        selectedServerProfileIDString = duplicate.id.uuidString
        persistServerProfiles()
        presentBanner("Serverprofil dupliziert.", style: .success)
    }

    func selectServerProfile(_ profileID: UUID) {
        selectedServerProfileID = profileID
        selectedServerProfileIDString = profileID.uuidString
        availableModels = []
        persistServerProfiles()
    }

    func deleteServerProfile(_ profileID: UUID) {
        guard serverProfiles.count > 1 else {
            presentError("Mindestens ein Serverprofil muss erhalten bleiben.")
            return
        }
        serverProfiles.removeAll { $0.id == profileID }
        if selectedServerProfileID == profileID {
            selectedServerProfileID = serverProfiles.first?.id
            selectedServerProfileIDString = selectedServerProfileID?.uuidString ?? ""
            availableModels = []
        }
        persistServerProfiles()
    }

    func updateCurrentServerName(_ name: String) {
        updateCurrentServerProfile { $0.name = name }
    }

    func updateCurrentServerURL(_ url: String) {
        updateCurrentServerProfile { $0.serverURL = url }
    }

    func addAttachment(data: Data, suggestedName: String) throws {
        guard let mimeType = inferMimeType(from: suggestedName) else {
            throw OllamaError.imageEncodingFailed
        }

        let attachment = ImageAttachment(
            filename: suggestedName,
            mimeType: mimeType,
            base64Data: data.base64EncodedString()
        )
        draftAttachments.append(attachment)
    }

    func removeAttachment(_ attachmentID: UUID) {
        draftAttachments.removeAll { $0.id == attachmentID }
    }

    func makeArchive() -> ChatArchiveDocument {
        ChatArchiveDocument(
            archive: ChatArchive(
                exportedAt: .now,
                selectedSessionID: selectedSessionID,
                sessions: sessions
            )
        )
    }

    func importArchive(_ document: ChatArchiveDocument) {
        let importedSessions = document.archive.sessions.sorted { $0.updatedAt > $1.updatedAt }
        guard !importedSessions.isEmpty else {
            presentError("Die importierte Datei enthaelt keine Chats.")
            return
        }

        sessions = importedSessions
        if let selected = document.archive.selectedSessionID,
           sessions.contains(where: { $0.id == selected }) {
            selectedSessionID = selected
        } else {
            selectedSessionID = sessions.first?.id
        }
        selectedSessionIDString = selectedSessionID?.uuidString ?? ""
        clearError()
        persistSessions()
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
    }

    func dismissBanner() {
        bannerDismissTask?.cancel()
        banner = nil
    }

    private func ensureSessionExists() {
        if selectedSessionID == nil || currentSession == nil {
            createNewSession()
        }
    }

    private func buildRequestMessages(for sessionID: UUID) -> [ChatMessage] {
        guard let session = sessions.first(where: { $0.id == sessionID }) else { return [] }

        var requestMessages = session.messages
        if let firstMessage = requestMessages.first,
           firstMessage.role == .assistant,
           firstMessage.content == initialAssistantText {
            requestMessages.removeFirst()
        }

        requestMessages.removeAll {
            $0.role == .assistant && $0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        let prompt = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !prompt.isEmpty {
            requestMessages.insert(ChatMessage(role: .system, content: prompt), at: 0)
        }

        return requestMessages
    }

    private func appendMessage(_ message: ChatMessage, to sessionID: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        sessions[index].messages.append(message)
        sessions[index].updatedAt = .now
    }

    private func removeMessage(id: UUID, from sessionID: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        sessions[index].messages.removeAll { $0.id == id }
        sessions[index].updatedAt = .now
    }

    private func replaceAssistantMessage(id: UUID, sessionID: UUID, content: String) {
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }),
              let messageIndex = sessions[sessionIndex].messages.firstIndex(where: { $0.id == id }) else { return }
        sessions[sessionIndex].messages[messageIndex].content = content
        sessions[sessionIndex].updatedAt = .now
    }

    private func appendStreamChunk(_ chunk: String, assistantID: UUID, sessionID: UUID) {
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }),
              let messageIndex = sessions[sessionIndex].messages.firstIndex(where: { $0.id == assistantID }) else { return }
        sessions[sessionIndex].messages[messageIndex].content += chunk
        sessions[sessionIndex].updatedAt = .now
    }

    private func trimEmptyAssistantMessage(id: UUID, sessionID: UUID) {
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }),
              let messageIndex = sessions[sessionIndex].messages.firstIndex(where: { $0.id == id }) else { return }

        let trimmed = sessions[sessionIndex].messages[messageIndex].content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            sessions[sessionIndex].messages.remove(at: messageIndex)
        } else {
            sessions[sessionIndex].messages[messageIndex].content = trimmed
        }
        sessions[sessionIndex].updatedAt = .now
    }

    private func replaceSessionMessages(sessionID: UUID, messages: [ChatMessage]) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        sessions[index].messages = messages
        sessions[index].updatedAt = .now
    }

    private func updateSessionMetadata(sessionID: UUID, preferredTitle: String) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        if sessions[index].title == "Neuer Chat" {
            sessions[index].title = String(preferredTitle.prefix(40))
        }
        sessions[index].updatedAt = .now
        sessions.sort { $0.updatedAt > $1.updatedAt }
        selectedSessionID = sessionID
        selectedSessionIDString = sessionID.uuidString
    }

    private func updateCurrentServerProfile(_ mutate: (inout ServerProfile) -> Void) {
        guard let selectedServerProfileID,
              let index = serverProfiles.firstIndex(where: { $0.id == selectedServerProfileID }) else { return }
        mutate(&serverProfiles[index])
        persistServerProfiles()
    }

    private func loadServerProfiles() {
        guard !savedServerProfilesData.isEmpty,
              let data = savedServerProfilesData.data(using: .utf8),
              let decoded = decodeServerProfiles(from: data) else {
            serverProfiles = []
            selectedServerProfileID = nil
            return
        }

        serverProfiles = decoded
        if let restoredID = UUID(uuidString: selectedServerProfileIDString),
           serverProfiles.contains(where: { $0.id == restoredID }) {
            selectedServerProfileID = restoredID
        } else {
            selectedServerProfileID = serverProfiles.first?.id
            selectedServerProfileIDString = selectedServerProfileID?.uuidString ?? ""
        }
    }

    private func persistServerProfiles() {
        if let data = encodeServerProfiles(serverProfiles) {
            savedServerProfilesData = String(decoding: data, as: UTF8.self)
        }
        selectedServerProfileIDString = selectedServerProfileID?.uuidString ?? ""
    }

    private func loadSessions() {
        guard !savedSessionsData.isEmpty,
              let data = savedSessionsData.data(using: .utf8),
              let decoded = decodeSessions(from: data) else {
            sessions = []
            selectedSessionID = nil
            return
        }

        sessions = decoded.sorted { $0.updatedAt > $1.updatedAt }
        if let restoredID = UUID(uuidString: selectedSessionIDString),
           sessions.contains(where: { $0.id == restoredID }) {
            selectedSessionID = restoredID
        } else {
            selectedSessionID = sessions.first?.id
            selectedSessionIDString = selectedSessionID?.uuidString ?? ""
        }
    }

    private func persistSessions() {
        if let data = encodeSessions(sessions) {
            savedSessionsData = String(decoding: data, as: UTF8.self)
        }
        selectedSessionIDString = selectedSessionID?.uuidString ?? ""
    }

    private var initialAssistantText: String {
        "Verbinde dich mit deinem Ollama-Server und starte dann einen Chat."
    }

    private var authentication: AuthenticationConfiguration {
        AuthenticationConfiguration(
            mode: currentAuthenticationMode,
            bearerToken: normalizedToken,
            username: normalizedUsername,
            password: normalizedPassword
        )
    }

    private var normalizedToken: String? {
        let token = currentAuthToken.trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }

    private var normalizedUsername: String? {
        let username = currentAuthUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        return username.isEmpty ? nil : username
    }

    private var normalizedPassword: String? {
        let password = currentAuthPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        return password.isEmpty ? nil : password
    }

    private func encodeSessions(_ sessions: [ChatSession]) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(sessions)
    }

    private func decodeSessions(from data: Data) -> [ChatSession]? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode([ChatSession].self, from: data)
    }

    private func encodeServerProfiles(_ profiles: [ServerProfile]) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(profiles)
    }

    private func decodeServerProfiles(from data: Data) -> [ServerProfile]? {
        try? JSONDecoder().decode([ServerProfile].self, from: data)
    }

    private func inferMimeType(from filename: String) -> String? {
        let ext = URL(fileURLWithPath: filename).pathExtension
        guard let type = UTType(filenameExtension: ext),
              let mimeType = type.preferredMIMEType,
              mimeType.hasPrefix("image/") else {
            return nil
        }
        return mimeType
    }

    private func presentError(_ message: String) {
        errorMessage = message
        presentBanner(message, style: .error)
    }

    private func clearError() {
        errorMessage = nil
    }

    private func presentBanner(_ message: String, style: BannerStyle) {
        bannerDismissTask?.cancel()
        banner = BannerData(message: message, style: style)
        bannerDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            await MainActor.run {
                guard self?.banner?.message == message else { return }
                self?.banner = nil
            }
        }
    }
}
