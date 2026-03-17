import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var viewModel = ChatViewModel()
    @StateObject private var speechRecognizer = SpeechRecognizer()
    @State private var showSettings = false
    @State private var showImporter = false
    @State private var exportDocument = ChatArchiveDocument(
        archive: ChatArchive(exportedAt: .now, selectedSessionID: nil, sessions: [])
    )
    @State private var showExporter = false
    @State private var isPushToTalkPressed = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var showOnboarding = false

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            chatPane
        }
        .task {
            await viewModel.bootstrap()
            showOnboarding = !viewModel.hasCompletedOnboarding
        }
        .onChange(of: selectedPhotoItems) { _, items in
            Task {
                await importSelectedPhotos(items)
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView(viewModel: viewModel)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Fertig") {
                                showSettings = false
                            }
                        }
                    }
            }
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView {
                viewModel.completeOnboarding()
                showOnboarding = false
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .fileExporter(
            isPresented: $showExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "ollama-remote-chat-export"
        ) { _ in
        }
        .overlay(alignment: .top) {
            if let banner = viewModel.banner {
                BannerView(banner: banner) {
                    viewModel.dismissBanner()
                }
                .padding(.top, 10)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private var sidebar: some View {
        List {
            Section {
                Button {
                    viewModel.createNewSession()
                } label: {
                    Label("Neuer Chat", systemImage: "square.and.pencil")
                }
            }

            Section("Verlauf") {
                ForEach(viewModel.filteredSessions) { session in
                    Button {
                        viewModel.selectSession(session.id)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(session.title)
                                    .font(.headline)
                                    .lineLimit(1)
                                Text(session.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if viewModel.selectedSessionID == session.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            viewModel.deleteSession(session.id)
                        } label: {
                            Label("Loeschen", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .searchable(text: $viewModel.chatSearchText, prompt: "Chats durchsuchen")
        .navigationTitle("Chats")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showImporter = true
                } label: {
                    Label("Importieren", systemImage: "square.and.arrow.down")
                }

                Button {
                    exportDocument = viewModel.makeArchive()
                    showExporter = true
                } label: {
                    Label("Exportieren", systemImage: "square.and.arrow.up")
                }

                Button {
                    showSettings = true
                } label: {
                    Label("Einstellungen", systemImage: "slider.horizontal.3")
                }
            }
        }
    }

    private var chatPane: some View {
        VStack(spacing: 0) {
            header

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(viewModel.currentMessages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }

                        if viewModel.isLoading {
                            HStack {
                                ProgressView()
                                Text(viewModel.useStreaming ? "Ollama streamt gerade..." : "Ollama antwortet...")
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                    .padding(.vertical, 20)
                }
                .background(
                    LinearGradient(
                        colors: [
                            Color(red: 0.10, green: 0.12, blue: 0.16),
                            Color(red: 0.16, green: 0.19, blue: 0.24)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .onChange(of: viewModel.currentMessages) { _, messages in
                    guard let lastID = messages.last?.id else { return }
                    withAnimation {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }

            Divider()
            composer
        }
        .navigationTitle(viewModel.selectedModel.isEmpty ? "Chat" : viewModel.selectedModel)
    }

    private var header: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.currentSessionTitle)
                    .font(.title3.weight(.semibold))

                Text("\(viewModel.currentServerProfileName) · \(viewModel.currentServerURL)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(viewModel.selectedModel.isEmpty ? "Kein Modell ausgewaehlt" : "Aktiv: \(viewModel.selectedModel)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text("Kontext grob: ~\(viewModel.currentConversationEstimatedTokenCount) Tokens")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Einstellungen") {
                showSettings = true
            }
            .buttonStyle(.bordered)

            Button("Leeren") {
                viewModel.clearConversation()
            }
            .buttonStyle(.bordered)
        }
        .padding(20)
        .background(.thinMaterial)
    }

    private var composer: some View {
        VStack(spacing: 12) {
            if !viewModel.draftAttachments.isEmpty {
                attachmentStrip
            }

            TextEditor(text: $viewModel.draft)
                .frame(minHeight: 90, maxHeight: 180)
                .padding(12)
                .scrollContentBackground(.hidden)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(red: 0.18, green: 0.20, blue: 0.25))
                )

            HStack(spacing: 12) {
                statusText

                Spacer()

                Text("\(viewModel.draftCharacterCount) Zeichen · ~\(viewModel.draftEstimatedTokenCount) Tokens")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                PhotosPicker(selection: $selectedPhotoItems, maxSelectionCount: 4, matching: .images) {
                    Label("Bild", systemImage: "photo")
                }
                .buttonStyle(.bordered)

                PushToTalkButton(
                    isRecording: speechRecognizer.isRecording,
                    isPressed: isPushToTalkPressed,
                    start: startPushToTalk,
                    stop: stopPushToTalk
                )

                Button {
                    Task {
                        await viewModel.sendMessage()
                    }
                } label: {
                    Label("Senden", systemImage: "paperplane.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canSend)
            }
        }
        .padding(20)
        .background(Color(red: 0.11, green: 0.13, blue: 0.17))
    }

    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(viewModel.draftAttachments) { attachment in
                    AttachmentChip(attachment: attachment) {
                        viewModel.removeAttachment(attachment.id)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var statusText: some View {
        if let errorMessage = viewModel.errorMessage {
            Text(errorMessage)
                .font(.footnote)
                .foregroundStyle(.red)
                .lineLimit(2)
        } else if let speechError = speechRecognizer.errorMessage {
            Text(speechError)
                .font(.footnote)
                .foregroundStyle(.red)
                .lineLimit(2)
        } else if speechRecognizer.isRecording {
            Text("Push-to-talk aktiv...")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func startPushToTalk() {
        guard !isPushToTalkPressed else { return }
        isPushToTalkPressed = true
        Task {
            await speechRecognizer.startRecording(into: $viewModel.draft)
        }
    }

    private func stopPushToTalk() {
        guard isPushToTalkPressed else { return }
        isPushToTalkPressed = false
        speechRecognizer.stopRecording()
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                let granted = url.startAccessingSecurityScopedResource()
                defer {
                    if granted {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                let data = try Data(contentsOf: url)
                let document = try ChatArchiveDocument(data: data)
                viewModel.importArchive(document)
            } catch {
                viewModel.errorMessage = "Import fehlgeschlagen: \(error.localizedDescription)"
            }
        case .failure(let error):
            viewModel.errorMessage = "Import fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    private func importSelectedPhotos(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        for item in items {
            do {
                if let data = try await item.loadTransferable(type: Data.self) {
                    let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
                    let filename = "bild-\(UUID().uuidString).\(ext)"
                    try viewModel.addAttachment(data: data, suggestedName: filename)
                }
            } catch {
                viewModel.errorMessage = "Bildimport fehlgeschlagen: \(error.localizedDescription)"
            }
        }
        selectedPhotoItems = []
    }
}

private struct BannerView: View {
    let banner: ChatViewModel.BannerData
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
            Text(banner.message)
                .lineLimit(2)
            Spacer()
            Button(action: dismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(backgroundColor)
        .foregroundStyle(.white)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        .padding(.horizontal, 20)
    }

    private var iconName: String {
        switch banner.style {
        case .error:
            return "exclamationmark.triangle.fill"
        case .success:
            return "checkmark.circle.fill"
        case .info:
            return "info.circle.fill"
        }
    }

    private var backgroundColor: Color {
        switch banner.style {
        case .error:
            return Color.red.opacity(0.9)
        case .success:
            return Color.green.opacity(0.85)
        case .info:
            return Color.blue.opacity(0.85)
        }
    }
}

private struct PushToTalkButton: View {
    let isRecording: Bool
    let isPressed: Bool
    let start: () -> Void
    let stop: () -> Void

    var body: some View {
        Label(isRecording ? "Aufnahme..." : "Push-to-talk", systemImage: isRecording ? "waveform.circle.fill" : "mic.circle.fill")
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minWidth: 160)
            .background(backgroundColor)
            .foregroundStyle(foregroundColor)
            .clipShape(Capsule())
            .scaleEffect(isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: isPressed)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        start()
                    }
                    .onEnded { _ in
                        stop()
                    }
            )
    }

    private var backgroundColor: Color {
        isRecording ? Color.red.opacity(0.16) : Color.blue.opacity(0.14)
    }

    private var foregroundColor: Color {
        isRecording ? .red : .blue
    }
}

private struct AttachmentChip: View {
    let attachment: ImageAttachment
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if let data = Data(base64Encoded: attachment.base64Data),
               let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.filename)
                    .font(.subheadline)
                    .lineLimit(1)
                Text("Bildanhaengung")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button(role: .destructive, action: remove) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(Color(red: 0.19, green: 0.22, blue: 0.27))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .assistant {
                bubble
                Spacer(minLength: 60)
            } else {
                Spacer(minLength: 60)
                bubble
            }
        }
        .padding(.horizontal, 20)
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if !message.attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(message.attachments) { attachment in
                            if let data = Data(base64Encoded: attachment.base64Data),
                               let uiImage = UIImage(data: data) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 120, height: 120)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                        }
                    }
                }
            }

            MarkdownMessageText(content: message.content)
                .textSelection(.enabled)
        }
        .padding(16)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.16), radius: 10, y: 4)
    }

    private var title: String {
        switch message.role {
        case .system:
            return "System"
        case .user:
            return "Du"
        case .assistant:
            return "Ollama"
        }
    }

    private var backgroundColor: Color {
        switch message.role {
        case .system:
            return Color.orange.opacity(0.16)
        case .user:
            return Color(red: 0.17, green: 0.34, blue: 0.56)
        case .assistant:
            return Color(red: 0.14, green: 0.16, blue: 0.21)
        }
    }
}
