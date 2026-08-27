//
//  CompanionChatView.swift
//  AstraCompanion
//
//  Created by Alex on 13/8/26.
//


import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit
import Combine

private enum ImportPurpose {
    case summarizeDocument
    case voiceSample
}

struct CompanionChatView: View {
    @ObservedObject var vm: CompanionChatViewModel
    @EnvironmentObject private var macStatus: MacConnectionStatusViewModel

    @StateObject private var stt = IOSSpeechToTextService()
    @StateObject private var tts = IOSVoiceOutputService()

    @FocusState private var focused: Bool

    @AppStorage("ios.tts.mode") private var ttsModeRaw: String = IOSVoiceOutputMode.local.rawValue
    @AppStorage("ios.voice.locale") private var voiceLocale: String = "ru-RU"
    
 
    @State private var selectedPhotoItem: PhotosPickerItem?

    @State private var showGeneratePrompt = false
    @State private var showAnalyzePrompt = false
    @State private var showEditPrompt = false
    @State private var showTTSSettings = false

    @State private var genPrompt = "Create a high quality image of ..."
    @State private var imagePrompt = "Describe this image."
    @State private var editPrompt = "Edit this image..."

    @State private var fullScreenImageURL: URL?

    @State private var showImporter = false
    @State private var importerPurpose: ImportPurpose?

    @State private var lastSpokenMessageId: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                topBar
                Divider()

                messagesArea

                if stt.isListening {
                    voiceRecordingPill
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                errorArea

                Divider()
                composer
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Astra")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        focused = false
                    }
                }
            }
            .sheet(isPresented: $showGeneratePrompt) {
                generateSheet
            }
            .sheet(isPresented: $showAnalyzePrompt) {
                analyzeSheet
            }
            .sheet(isPresented: $showEditPrompt) {
                editSheet
            }
            .sheet(isPresented: $showTTSSettings) {
                ttsSheet
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: importerAllowedTypes,
                allowsMultipleSelection: false,
                onCompletion: handleImporterResult
            )
            .fullScreenCover(item: Binding(
                get: { fullScreenImageURL.map(IdentifiableURL.init) },
                set: { _ in fullScreenImageURL = nil }
            )) { item in
                ZoomableImageSheet(url: item.url)
            }
            .onDisappear {
                stt.stop()
                tts.stop()
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 10) {
            statusChip

            Spacer()

            // Mac TTS кнопка
            Button {
                Task {
                    let lastAssistantMessage = vm.messages.last(where: { $0.role == "assistant" && !$0.text.isEmpty })
                    if let msg = lastAssistantMessage {
                        await vm.speakOnMac(msg.text, ttsService: tts)
                    }
                }
            } label: {
                Image(systemName: "desktopcomputer")
                    .font(.title3)
            }
            .help("Speak on Mac")

            Toggle(isOn: $vm.autoSpeak) {
                Image(systemName: vm.autoSpeak ? "speaker.wave.2.fill" : "speaker.slash.fill")
            }
            .labelsHidden()
            .tint(.blue)

            Button {
                showTTSSettings = true
            } label: {
                Image(systemName: "waveform.circle")
                    .font(.title3)
            }

            Menu {
                Button {
                    showGeneratePrompt = true
                } label: {
                    Label("Generate image", systemImage: "photo.fill.on.rectangle.fill")
                }

                Button {
                    showAnalyzePrompt = true
                } label: {
                    Label("Analyze image", systemImage: "photo")
                }

                Button {
                    showEditPrompt = true
                } label: {
                    Label("Edit image", systemImage: "slider.horizontal.3")
                }

                Button {
                    importerPurpose = .summarizeDocument
                    showImporter = true
                } label: {
                    Label("Summarize document", systemImage: "doc.text.fill")
                }

                Divider()

                Button {
                    Task {
                        await vm.sendText("/tasks")
                    }
                } label: {
                    Label("My tasks", systemImage: "checklist")
                }

                Button {
                    Task {
                        await vm.runRemoteAction(
                            type: .calendarToday,
                            payload: [:],
                            userVisibleText: "Today calendar",
                            status: "Loading calendar...",
                            timeoutSeconds: 90
                        )
                    }
                } label: {
                    Label("Today calendar", systemImage: "calendar")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color(.secondarySystemBackground))
    }

    private var statusChip: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(vm.isSending ? Color.orange : macStatus.statusColor)
                .frame(width: 8, height: 8)

            Text(vm.isSending ? vm.statusText : macStatus.statusText)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Color(.tertiarySystemBackground))
        .clipShape(Capsule())
    }

    // MARK: - Messages

    private var messagesArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(vm.messages) { msg in
                        bubble(msg)
                            .id(msg.id)
                    }

                    if vm.isAwaitingAssistant {
                        typingBubble
                            .id("typing")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture {
                focused = false
            }
            .onChange(of: vm.messages.count) { _, _ in
                scrollToBottom(proxy)
                autoSpeakLastAssistantIfNeeded()
            }
            .onChange(of: vm.isAwaitingAssistant) { _, _ in
                scrollToBottom(proxy)
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.easeInOut(duration: 0.2)) {
                if vm.isAwaitingAssistant {
                    proxy.scrollTo("typing", anchor: .bottom)
                } else if let id = vm.messages.last?.id {
                    proxy.scrollTo(id, anchor: .bottom)
                }
            }
        }
    }

    @ViewBuilder
    private func bubble(_ msg: CompanionUIMessage) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if msg.role == "assistant" {
                assistantAvatarView

                VStack(alignment: .leading, spacing: 6) {
                    Text("Astra")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)

                    if !msg.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(msg.text)
                            .textSelection(.enabled)
                            .padding(11)
                            .foregroundStyle(.primary)
                            .background(Color.blue.opacity(0.11))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }

                    attachmentView(msg)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contextMenu {
                    Button("Copy text") {
                        UIPasteboard.general.string = msg.text
                    }

                    if !msg.text.isEmpty {
                        Button("Speak") {
                            speakText(msg.text)
                        }
                    }
                }

                Spacer(minLength: 38)

            } else if msg.role == "user" {
                Spacer(minLength: 38)

                VStack(alignment: .trailing, spacing: 6) {
                    Text("You")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)

                    if !msg.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(msg.text)
                            .textSelection(.enabled)
                            .padding(11)
                            .foregroundStyle(.primary)
                            .background(msg.isLocalPending ? Color.orange.opacity(0.13) : Color.green.opacity(0.13))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }

                    attachmentView(msg)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .contextMenu {
                    Button("Copy text") {
                        UIPasteboard.general.string = msg.text
                    }
                }

                userAvatarView
                    .frame(width: 30, height: 30)

            } else {
                Text(msg.text)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(Color.orange.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    
    // MARK: - Avatar Views

    private var assistantAvatarView: some View {
        IOSAvatarView(kind: .assistant, size: 30)
    }

    private var userAvatarView: some View {
        IOSAvatarView(kind: .user, size: 30)
    }

    private var typingBubble: some View {
        HStack(alignment: .top, spacing: 8) {
            assistantAvatarView

            HStack(spacing: 8) {
                IOSAnimatedTypingDots()

                Text("Astra is thinking")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))

            Spacer(minLength: 40)
        }
    }

    // MARK: - Attachments

    @ViewBuilder
    private func attachmentView(_ msg: CompanionUIMessage) -> some View {
        let rawURL = msg.attachmentURL ?? msg.imageURL

        if let rawURL,
           let url = URL(string: rawURL) {
            let type = msg.attachmentType
                ?? CompanionChatViewModel.inferPublicAttachmentTypeForUI(urlString: rawURL)

            switch type {
            case "image":
                imageAttachment(url: url)

            case "file":
                fileAttachment(url: url)

            case "audio":
                audioAttachment(url: url)

            default:
                genericAttachment(url: url)
            }
        }
    }

    private func imageAttachment(url: URL) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    ZStack {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.gray.opacity(0.12))
                            .frame(width: 230, height: 150)

                        ProgressView()
                    }

                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 245, maxHeight: 280)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .onTapGesture {
                            fullScreenImageURL = url
                        }

                case .failure:
                    attachmentFailureCard(
                        title: "Image preview failed",
                        icon: "photo",
                        url: url
                    )

                @unknown default:
                    EmptyView()
                }
            }

            attachmentActions(url: url, canSaveImage: true)
        }
    }

    private func fileAttachment(url: URL) -> some View {
        let fileName = url.lastPathComponent.isEmpty ? "Document" : url.lastPathComponent

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "doc.text.fill")
                    .font(.title3)
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text(fileName)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)

                    Text("Document")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            HStack(spacing: 12) {
                Link("Open", destination: url)

                Button("Copy URL") {
                    UIPasteboard.general.string = url.absoluteString
                }
            }
            .font(.caption)
        }
        .padding(10)
        .frame(maxWidth: 270, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func audioAttachment(url: URL) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "waveform.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.purple)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Audio")
                        .font(.caption.weight(.semibold))

                    Text("Generated voice")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            HStack(spacing: 12) {
                Button("Play") {
                    tts.playAudioURL(url)
                }

                Button("Open") {
                    UIApplication.shared.open(url)
                }

                Button("Copy URL") {
                    UIPasteboard.general.string = url.absoluteString
                }
            }
            .font(.caption)
        }
        .padding(10)
        .frame(maxWidth: 270, alignment: .leading)
        .background(Color.purple.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func genericAttachment(url: URL) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Attachment", systemImage: "paperclip")
                .font(.caption.weight(.semibold))

            Text(url.absoluteString)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: 12) {
                Button("Open") {
                    UIApplication.shared.open(url)
                }

                Button("Copy URL") {
                    UIPasteboard.general.string = url.absoluteString
                }
            }
            .font(.caption)
        }
        .padding(10)
        .frame(maxWidth: 270, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func attachmentFailureCard(title: String, icon: String, url: URL) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(url.absoluteString)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(10)
        .frame(maxWidth: 270, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func attachmentActions(url: URL, canSaveImage: Bool) -> some View {
        HStack(spacing: 12) {
            Button("Open") {
                UIApplication.shared.open(url)
            }

            Button("Copy URL") {
                UIPasteboard.general.string = url.absoluteString
            }

            if canSaveImage {
                Button("Save") {
                    saveImageFromURL(url)
                }
            }
        }
        .font(.caption)
    }

    // MARK: - Voice Recording UI

    private var voiceRecordingPill: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform")
                .foregroundStyle(.red)

            VStack(alignment: .leading, spacing: 2) {
                Text("Listening...")
                    .font(.caption.weight(.semibold))

                Text(stt.transcript.isEmpty ? "Speak now" : stt.transcript)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button("Cancel") {
                stt.stop()
            }
            .font(.caption)

            Button("Send") {
                let final = stt.stopAndGetTranscript()
                if !final.isEmpty {
                    Task {
                        await vm.sendText(final)
                    }
                }
            }
            .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.red.opacity(0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }

    // MARK: - Errors

    @ViewBuilder
    private var errorArea: some View {
        VStack(spacing: 0) {
            if let err = stt.errorText, !err.isEmpty {
                errorRow("Voice: \(err)")
            }

            if let err = tts.lastError, !err.isEmpty {
                errorRow("TTS: \(err)")
            }

            if let err = vm.lastError, !err.isEmpty {
                errorRow("Chat: \(err)")
            }
        }
    }

    private func errorRow(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Color.red.opacity(0.06))
    }

    // MARK: - Composer

    private var composer: some View {
        HStack(spacing: 8) {
            Menu {
                Button {
                    showGeneratePrompt = true
                } label: {
                    Label("Generate image", systemImage: "photo.fill.on.rectangle.fill")
                }

                Button {
                    showAnalyzePrompt = true
                } label: {
                    Label("Analyze image", systemImage: "photo")
                }

                Button {
                    showEditPrompt = true
                } label: {
                    Label("Edit image", systemImage: "slider.horizontal.3")
                }

                Button {
                    importerPurpose = .summarizeDocument
                    showImporter = true
                } label: {
                    Label("Summarize document", systemImage: "doc.text.fill")
                }
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(.blue)
            }

            Button {
                handleMicButton()
            } label: {
                Image(systemName: stt.isListening ? "stop.circle.fill" : "mic.circle.fill")
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(stt.isListening ? .red : .blue)
            }
            .buttonStyle(.plain)

            TextField(composerPlaceholder, text: $vm.inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .focused($focused)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))

            Button {
                focused = false
                Task {
                    await vm.send()
                }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 29, weight: .semibold))
                    .foregroundStyle(canSendText ? .blue : .gray.opacity(0.5))
            }
            .disabled(!canSendText || vm.isSending)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(Color(.secondarySystemBackground))
    }
    
    private var composerPlaceholder: String {
        macStatus.isCommandAvailable ? "Message..." : "Mac is offline..."
    }

    private var canSendText: Bool {
        macStatus.isCommandAvailable &&
        !vm.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func handleMicButton() {
        if stt.isListening {
            let final = stt.stopAndGetTranscript()

            if !final.isEmpty {
                guard macStatus.isCommandAvailable else {
                    vm.lastError = "Mac is offline. Open Astra on your Mac."
                    return
                }

                Task {
                    await vm.sendText(final)
                }
            }
        } else {
            focused = false

            Task {
                await stt.start(locale: voiceLocale)
            }
        }
    }

    // MARK: - Sheets

    private var generateSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("Generate image")
                    .font(.headline)

                TextField("Prompt", text: $genPrompt, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(4...8)

                Spacer()

                Button {
                    let p = genPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !p.isEmpty else { return }

                    showGeneratePrompt = false
                    Task {
                        await vm.generateImage(prompt: p)
                    }
                } label: {
                    Label("Generate", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .navigationTitle("Image")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        showGeneratePrompt = false
                    }
                }
            }
        }
    }

    private var analyzeSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("Analyze image")
                    .font(.headline)

                TextField("Prompt", text: $imagePrompt, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...6)

                PhotosPicker("Pick image", selection: $selectedPhotoItem, matching: .images)
                    .buttonStyle(.bordered)

                Spacer()

                Button {
                    Task {
                        await uploadAndAnalyzeSelectedImage()
                    }
                } label: {
                    Label("Upload & Analyze", systemImage: "eye.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedPhotoItem == nil)
            }
            .padding()
            .navigationTitle("Analyze")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        showAnalyzePrompt = false
                    }
                }
            }
        }
    }

    private var editSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("Edit image")
                    .font(.headline)

                TextField("Prompt", text: $editPrompt, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...6)

                PhotosPicker("Pick source image", selection: $selectedPhotoItem, matching: .images)
                    .buttonStyle(.bordered)

                Spacer()

                Button {
                    Task {
                        await uploadAndEditSelectedImage()
                    }
                } label: {
                    Label("Upload & Edit", systemImage: "slider.horizontal.3")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedPhotoItem == nil)
            }
            .padding()
            .navigationTitle("Edit")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        showEditPrompt = false
                    }
                }
            }
        }
    }

    private var ttsSheet: some View {
        NavigationStack {
            Form {
                Section("Voice output") {
                    Picker("Mode", selection: $ttsModeRaw) {
                        Text("iPhone Local").tag(IOSVoiceOutputMode.local.rawValue)
                        Text("Mac TTS").tag(IOSVoiceOutputMode.mac.rawValue)
                    }
                    .pickerStyle(.segmented)
                }

                Section("Speech recognition") {
                    Picker("Voice input language", selection: $voiceLocale) {
                        Text("Russian").tag("ru-RU")
                        Text("English US").tag("en-US")
                        Text("English UK").tag("en-GB")
                        Text("Spanish").tag("es-ES")
                        Text("German").tag("de-DE")
                        Text("French").tag("fr-FR")
                    }
                }

                Section("About") {
                    if ttsModeRaw == IOSVoiceOutputMode.local.rawValue {
                        Text("Uses built-in iPhone speech synthesis. Fast and works without Mac voice generation.")
                    } else {
                        Text("iPhone sends text to your Mac. Mac uses configured WaveSpeed voice settings, uploads generated audio to Firebase Storage, then iPhone plays it.")
                    }
                }
            }
            .navigationTitle("Voice")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        showTTSSettings = false
                    }
                }
            }
        }
    }

    // MARK: - Upload Actions

    private func uploadAndAnalyzeSelectedImage() async {
        do {
            guard let item = selectedPhotoItem else { return }

            guard let data = try await item.loadTransferable(type: Data.self) else {
                vm.lastError = "Failed to read selected image."
                return
            }

            let publicURL = try await IOSMediaUploadService.shared.uploadImageData(data)

            showAnalyzePrompt = false
            selectedPhotoItem = nil

            await vm.analyzeImage(
                publicURL: publicURL,
                prompt: imagePrompt
            )
        } catch {
            vm.lastError = error.localizedDescription
        }
    }

    private func uploadAndEditSelectedImage() async {
        do {
            guard let item = selectedPhotoItem else { return }

            guard let data = try await item.loadTransferable(type: Data.self) else {
                vm.lastError = "Failed to read selected image."
                return
            }

            let publicURL = try await IOSMediaUploadService.shared.uploadImageData(data)

            showEditPrompt = false
            selectedPhotoItem = nil

            await vm.editImage(
                publicURL: publicURL,
                prompt: editPrompt
            )
        } catch {
            vm.lastError = error.localizedDescription
        }
    }

    // MARK: - Importer

    private var importerAllowedTypes: [UTType] {
        switch importerPurpose {
        case .summarizeDocument:
            return [
                .pdf,
                .plainText,
                .utf8PlainText,
                .text,
                .json,
                .commaSeparatedText,
                .html,
                .sourceCode
            ]

        case .voiceSample:
            return [.audio]

        case .none:
            return [.data]
        }
    }

    private func handleImporterResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }

            switch importerPurpose {
            case .summarizeDocument:
                Task {
                    do {
                        let didAccess = url.startAccessingSecurityScopedResource()
                        defer {
                            if didAccess {
                                url.stopAccessingSecurityScopedResource()
                            }
                        }

                        let publicURL = try await IOSMediaUploadService.shared.uploadFile(localURL: url)

                        await vm.summarizeFile(
                            publicURL: publicURL,
                            fileName: url.lastPathComponent
                        )
                    } catch {
                        vm.lastError = error.localizedDescription
                    }
                }

            case .voiceSample:
                Task {
                    do {
                        let didAccess = url.startAccessingSecurityScopedResource()
                        defer {
                            if didAccess {
                                url.stopAccessingSecurityScopedResource()
                            }
                        }

                        let publicURL = try await IOSMediaUploadService.shared.uploadFile(localURL: url)
                        UIPasteboard.general.string = publicURL
                        vm.statusText = "Voice sample URL copied"
                    } catch {
                        vm.lastError = error.localizedDescription
                    }
                }

            case .none:
                break
            }

        case .failure(let error):
            vm.lastError = error.localizedDescription
        }

        importerPurpose = nil
    }

    // MARK: - TTS

    private func autoSpeakLastAssistantIfNeeded() {
        guard vm.autoSpeak else { return }

        guard let last = vm.messages.last,
              last.role == "assistant",
              !last.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        guard lastSpokenMessageId != last.id else { return }

        lastSpokenMessageId = last.id
        speakText(last.text)
    }

    private func speakText(_ text: String) {
        let mode = IOSVoiceOutputMode(rawValue: ttsModeRaw) ?? .local

        switch mode {
        case .local:
            tts.speak(
                text,
                mode: .local,
                localLanguage: voiceLocale,
                remoteConfig: nil
            )

        case .mac:
            Task {
                do {
                    let audioURL = try await vm.synthesizeSpeechOnMac(text: text)
                    tts.playAudioURL(audioURL)
                } catch {
                    vm.lastError = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Save Image

    private func saveImageFromURL(_ url: URL) {
        Task {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)

                guard let http = response as? HTTPURLResponse,
                      200..<300 ~= http.statusCode else {
                    return
                }

                guard let image = UIImage(data: data) else {
                    return
                }

                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
            } catch {
                vm.lastError = error.localizedDescription
            }
        }
    }
}

// MARK: - Animated Typing Dots

private struct IOSAnimatedTypingDots: View {
    @State private var phase = 0

    private let timer = Timer.publish(
        every: 0.32,
        on: .main,
        in: .common
    ).autoconnect()

    var body: some View {
        HStack(spacing: 5) {
            dot(0)
            dot(1)
            dot(2)
        }
        .onReceive(timer) { _ in
            phase = (phase + 1) % 3
        }
    }

    private func dot(_ index: Int) -> some View {
        Circle()
            .fill(Color.secondary.opacity(phase == index ? 1.0 : 0.35))
            .frame(width: 7, height: 7)
            .scaleEffect(phase == index ? 1.25 : 0.85)
            .animation(.easeInOut(duration: 0.2), value: phase)
    }
}

// MARK: - Helpers

private struct IdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ZoomableImageSheet: View {
    let url: URL

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .tint(.white)

                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .padding()

                    case .failure:
                        Text("Failed to load image")
                            .foregroundStyle(.white)

                    @unknown default:
                        EmptyView()
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: url) {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(.white)
                    }
                }
            }
        }
    }
}
