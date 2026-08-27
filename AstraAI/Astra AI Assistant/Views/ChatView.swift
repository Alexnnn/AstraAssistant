//
//  ChatView.swift
//  AstraAssistant
//
//  Created by Alex on 10/8/26.
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit
import Combine

struct ChatView: View {
    @EnvironmentObject private var appViewModel: AppViewModel

    @ObservedObject var viewModel: ChatViewModel
    @StateObject private var voiceController = VoiceModeController()

    @State private var showingDiagnosticsSheet = false
    @State private var showingGeneratePromptSheet = false
    @State private var showingImagePromptSheet = false
    @State private var showingEditPromptSheet = false
    @State private var showingSearchSheet = false
    @State private var showingCustomizeSheet = false

    @State private var inputText = ""
    @State private var generatePrompt = "Create a high quality image of ..."
    @State private var imagePrompt = "Analyze this image in detail."
    @State private var editPrompt = "Edit this image..."
    @State private var waveSpeedEditImageURL = ""
    @State private var searchQuery = ""

    @State private var selectedImageURL: URL?
    @State private var speakResponses = true
    @State private var isHoldingToTalk = false
    @State private var quickActionsAnimated = false

    private let bottomAnchorId = "CHAT_BOTTOM_ANCHOR"

    private enum QuickAction: String, CaseIterable, Identifiable {
        case dailyBriefing
        case analyzeImage
        case generateImage
        case editImage
        case readFile
        case analyzeScreen
        case findWeb
        case tasks
        case calendar

        var id: String { rawValue }

        var title: String {
            switch self {
            case .dailyBriefing: return "Daily Briefing"
            case .analyzeImage: return "Analyze Image"
            case .generateImage: return "Generate Image"
            case .editImage: return "Edit Image"
            case .readFile: return "Read File"
            case .analyzeScreen: return "Analyze Screen"
            case .findWeb: return "Find on Web"
            case .tasks: return "My Tasks"
            case .calendar: return "Today Calendar"
            }
        }

        var icon: String {
            switch self {
            case .dailyBriefing: return "sun.max.fill"
            case .analyzeImage: return "photo"
            case .generateImage: return "photo.fill.on.rectangle.fill"
            case .editImage: return "slider.horizontal.3"
            case .readFile: return "doc.text.fill"
            case .analyzeScreen: return "display"
            case .findWeb: return "globe"
            case .tasks: return "checklist"
            case .calendar: return "calendar"
            }
        }
    }

    var body: some View {
        ZStack {
            AstraUITheme.mainBackground

            VStack(spacing: 12) {
                topHeaderCard
                quickActionsRow
                chatAreaCard
                voiceControlsCard
                composerCard
            }
            .padding(14)
        }
        .onAppear {
            configureVoice()

            quickActionsAnimated = false
            withAnimation(.easeOut(duration: 0.25)) {
                quickActionsAnimated = true
            }
        }
        .onDisappear {
            voiceController.stop()
        }
        .onChange(of: appViewModel.settingsStore.settings.listeningMode) { _, _ in
            configureVoice()
        }
        .onChange(of: appViewModel.settingsStore.settings.assistantLanguage) { _, _ in
            configureVoice()
        }
        .onChange(of: viewModel.isAssistantSpeaking) { _, speaking in
            guard voiceController.mode == .continuous || voiceController.mode == .wakePhrase else { return }

            if speaking {
                voiceController.suspendForAssistantSpeech()
            } else {
                Task {
                    await voiceController.resumeAfterAssistantSpeechIfNeeded()
                }
            }
        }
        .sheet(item: $viewModel.pendingMemoryConfirmation) { pending in
            VStack(alignment: .leading, spacing: 16) {
                Text("Save to memory?")
                    .font(.title2.bold())

                Text("Type: \(pending.type)\nImportance: \(pending.importance)")
                    .foregroundStyle(.secondary)

                Text(pending.content)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                HStack {
                    Button("Skip") {
                        viewModel.cancelPendingMemory()
                    }

                    Spacer()

                    Button("Save") {
                        Task { await viewModel.confirmPendingMemory() }
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding()
            .frame(width: 520)
        }
        .sheet(item: $viewModel.pendingToolConfirmation) { pending in
            ToolConfirmationView(
                pending: pending,
                onConfirm: { viewModel.confirmPendingTool() },
                onCancel: { viewModel.cancelPendingTool() }
            )
        }
        .sheet(isPresented: $showingGeneratePromptSheet) {
            generateImageSheet
        }
        .sheet(isPresented: $showingDiagnosticsSheet) {
            DiagnosticsReportSheetView(report: appViewModel.dependencyReport)
        }
        .sheet(isPresented: $showingImagePromptSheet) {
            analyzeImageSheet
        }
        .sheet(isPresented: $showingEditPromptSheet) {
            editImageSheet
        }
        .sheet(isPresented: $showingSearchSheet) {
            searchSheet
        }
        .sheet(isPresented: $showingCustomizeSheet) {
            customizeSheet
        }
    }

    private var assistantName: String {
        let name = appViewModel.settingsStore.settings.assistantDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Astra Assistant" : name
    }

    private var displayedMessages: [ChatMessage] {
        if isAwaitingAssistantFirstToken, !viewModel.messages.isEmpty {
            return Array(viewModel.messages.dropLast())
        }
        return viewModel.messages
    }

    private var isAwaitingAssistantFirstToken: Bool {
        guard viewModel.isSending,
              let last = viewModel.messages.last,
              last.role == .assistant else { return false }

        return last.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var topHeaderCard: some View {
        HStack(spacing: 14) {
            HStack(spacing: 10) {
                assistantAvatarView(size: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text(assistantName)
                        .font(.headline)
                        .foregroundStyle(.white)

                    Text(modelStatusText)
                        .font(.caption)
                        .foregroundStyle(AstraUITheme.subtle)
                        .lineLimit(1)
                }
            }

            Spacer()

            Toggle("Speak", isOn: $speakResponses)
                .toggleStyle(.switch)
                .tint(AstraUITheme.accent)

            headerIconButton("paintbrush.fill", "Customize") {
                showingCustomizeSheet = true
            }

            headerIconButton("stop.circle", "Stop Voice") {
                viewModel.stopSpeaking()
            }

            headerIconButton("wrench.and.screwdriver.fill", "Diagnostics") {
                Task {
                    await appViewModel.refreshDiagnostics()
                    showingDiagnosticsSheet = true
                }
            }

            headerIconButton("questionmark.circle.fill", "Commands") {
                viewModel.showCommandsHelp()
            }

            headerIconButton("square.and.arrow.up", "Export") {
                exportCurrentChat()
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AstraUITheme.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var quickActionsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(QuickAction.allCases.enumerated()), id: \.element.id) { index, action in
                    actionChip(action.title, action.icon) {
                        performQuickAction(action)
                    }
                    .opacity(quickActionsAnimated ? 1 : 0)
                    .offset(y: quickActionsAnimated ? 0 : 8)
                    .animation(
                        .spring(response: 0.36, dampingFraction: 0.84).delay(Double(index) * 0.045),
                        value: quickActionsAnimated
                    )
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func performQuickAction(_ action: QuickAction) {
        switch action {
        case .dailyBriefing:
            Task { await viewModel.generateDailyBriefing() }

        case .analyzeImage:
            chooseImageForAnalysis()

        case .generateImage:
            let prefill = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
            generatePrompt = prefill.isEmpty ? "Create a high quality image of ..." : prefill
            showingGeneratePromptSheet = true

        case .editImage:
            selectedImageURL = nil
            waveSpeedEditImageURL = ""
            showingEditPromptSheet = true

        case .readFile:
            chooseFileForReading()

        case .analyzeScreen:
            analyzeScreen()

        case .findWeb:
            searchQuery = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
            showingSearchSheet = true

        case .tasks:
            Task { await viewModel.send("/tasks") }

        case .calendar:
            Task { await viewModel.send("/calendar today") }
        }
    }

    private var chatAreaCard: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(displayedMessages) { message in
                            messageBubble(message)
                                .id(message.id)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .bottom).combined(with: .opacity),
                                    removal: .opacity
                                ))
                        }
                        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: displayedMessages.map(\.id))

                        if isAwaitingAssistantFirstToken {
                            typingBubble
                        }

                        if let status = viewModel.toolStatus,
                           status.lowercased() != "astra is thinking..." {
                            statusRow(status)
                        }

                        Color.clear
                            .frame(height: 1)
                            .id(bottomAnchorId)
                    }
                    .padding(12)
                }
                .onAppear {
                    scrollToBottom(proxy: proxy, animated: false)
                }
                .onChange(of: viewModel.messages.count) { _, _ in
                    scrollToBottom(proxy: proxy, animated: true)
                }
                .onChange(of: viewModel.messages.last?.content) { _, _ in
                    scrollToBottom(proxy: proxy, animated: false)
                }
                .onChange(of: isAwaitingAssistantFirstToken) { _, _ in
                    scrollToBottom(proxy: proxy, animated: false)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(AstraUITheme.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var typingBubble: some View {
        HStack(alignment: .bottom, spacing: 10) {
            assistantAvatarView(size: 28)

            HStack(spacing: 8) {
                TypingDotsView()
                Text("typing")
                    .font(.caption2)
                    .foregroundStyle(AstraUITheme.subtle)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(AstraUITheme.assistantBubble)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(AstraUITheme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))

            Spacer(minLength: 80)
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool) {
        if animated {
            withAnimation(.easeInOut(duration: 0.18)) {
                proxy.scrollTo(bottomAnchorId, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(bottomAnchorId, anchor: .bottom)
        }
    }

    private func statusRow(_ text: String) -> some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(text)
                .font(.caption)
                .foregroundStyle(AstraUITheme.subtle)
        }
        .padding(8)
        .background(Color.white.opacity(0.05))
        .clipShape(Capsule())
        .shimmer(true)
    }

    private var voiceControlsCard: some View {
        let settings = appViewModel.settingsStore.settings

        return HStack(spacing: 10) {
            VoicePulseIndicator(isActive: voiceController.isActive)

            Text(voiceController.statusText)
                .font(.caption)
                .foregroundStyle(AstraUITheme.subtle)

            if !voiceController.transcript.isEmpty {
                Text("“\(voiceController.transcript)”")
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(.white.opacity(0.8))
            }

            Spacer()

            voiceButtons(for: settings.listeningMode)
        }
        .padding(10)
        .background(.ultraThinMaterial)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AstraUITheme.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private func voiceButtons(for mode: ListeningMode) -> some View {
        switch mode {
        case .manual:
            HStack {
                minimalButton("mic.fill", "Dictate") {
                    Task {
                        configureVoice()
                        await voiceController.start()
                    }
                }
                minimalButton("paperplane.fill", "Send") {
                    voiceController.pushToTalkReleased()
                }
                minimalButton("stop.circle", "Stop") {
                    voiceController.stop()
                }
            }

        case .pushToTalk:
            HStack {
                minimalButton("waveform.circle.fill", "Start PTT") {
                    Task {
                        configureVoice()
                        await voiceController.pushToTalkPressed()
                    }
                }
                minimalButton("paperplane.fill", "Send") {
                    voiceController.pushToTalkReleased()
                }
                minimalButton("stop.circle", "Stop") {
                    voiceController.stop()
                }
            }

        case .holdToTalk:
            holdToTalkButton

        case .continuous:
            HStack {
                minimalButton("waveform", "Start") {
                    Task {
                        configureVoice()
                        await voiceController.start()
                    }
                }
                minimalButton("stop.circle", "Stop") {
                    voiceController.stop()
                }
            }

        case .wakePhrase:
            HStack {
                minimalButton("ear.fill", "Start") {
                    Task {
                        configureVoice()
                        await voiceController.start()
                    }
                }
                minimalButton("stop.circle", "Stop") {
                    voiceController.stop()
                }
            }
        }
    }

    private var holdToTalkButton: some View {
        Text(isHoldingToTalk ? "Release to send..." : "Hold to Talk")
            .font(.caption.bold())
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isHoldingToTalk ? AstraUITheme.accent.opacity(0.4) : Color.white.opacity(0.08))
            .clipShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !isHoldingToTalk else { return }
                        isHoldingToTalk = true
                        Task {
                            configureVoice()
                            await voiceController.holdToTalkBegan()
                        }
                    }
                    .onEnded { _ in
                        isHoldingToTalk = false
                        voiceController.holdToTalkEnded()
                    }
            )
    }

    private var composerCard: some View {
        HStack(spacing: 10) {
            TextField("Message Astra...", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.white)
                .onSubmit { send() }

            Button {
                send()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [AstraUITheme.accent2, AstraUITheme.accent],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isSending || inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(10)
        .background(.ultraThinMaterial)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AstraUITheme.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func messageBubble(_ message: ChatMessage) -> some View {
        HStack(alignment: .bottom, spacing: 10) {
            if message.role == .assistant {
                assistantAvatarView(size: 28)

                VStack(alignment: .leading, spacing: 8) {
                    Text(assistantName)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AstraUITheme.subtle)

                    Text(message.content)
                        .textSelection(.enabled)
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(AstraUITheme.assistantBubble)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(AstraUITheme.border, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14))

                    attachmentView(message.attachmentPath)
                }

                Spacer(minLength: 80)
            } else {
                Spacer(minLength: 80)

                VStack(alignment: .trailing, spacing: 8) {
                    Text("You")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AstraUITheme.subtle)

                    Text(message.content)
                        .textSelection(.enabled)
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(AstraUITheme.userBubble)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(AstraUITheme.border, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14))

                    attachmentView(message.attachmentPath)
                }

                userAvatarView(size: 28)
            }
        }
    }

    @ViewBuilder
    private func attachmentView(_ path: String?) -> some View {
        if let path, let image = NSImage(contentsOfFile: path) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 360, maxHeight: 280)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(AstraUITheme.border, lineWidth: 1))

            Button("Open Image") {
                NSWorkspace.shared.open(URL(fileURLWithPath: path))
            }
            .font(.caption)
        }
    }

    @ViewBuilder
    private func assistantAvatarView(size: CGFloat) -> some View {
        let path = appViewModel.settingsStore.settings.assistantAvatarPath
        if !path.isEmpty, let ns = NSImage(contentsOfFile: path) {
            Image(nsImage: ns)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            Image("assistant_default_avatar")
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
        }
    }

    @ViewBuilder
    private func userAvatarView(size: CGFloat) -> some View {
        let path = appViewModel.settingsStore.settings.userAvatarPath
        if !path.isEmpty, let ns = NSImage(contentsOfFile: path) {
            Image(nsImage: ns)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: size, height: size)
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
    }

    private var searchSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Find on Web")
                .font(.title2.bold())

            TextField("What do you want to search?", text: $searchQuery)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel") {
                    showingSearchSheet = false
                }

                Spacer()

                Button("Search") {
                    let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !q.isEmpty else { return }
                    showingSearchSheet = false
                    Task {
                        await viewModel.send("/search \(q)")
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 520)
    }

    private var generateImageSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Generate Image")
                .font(.title2.bold())

            Text(providerGenerateDescription)
                .foregroundStyle(.secondary)

            TextEditor(text: $generatePrompt)
                .frame(height: 120)
                .border(Color.gray.opacity(0.3))

            HStack {
                Button("Cancel") { showingGeneratePromptSheet = false }
                Spacer()
                Button("Generate") {
                    let prompt = generatePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !prompt.isEmpty else { return }
                    showingGeneratePromptSheet = false
                    Task { await viewModel.generateImage(prompt: prompt) }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 560)
    }

    private var analyzeImageSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Analyze Image")
                .font(.title2.bold())

            Text("Uses your local Ollama vision model.")
                .foregroundStyle(.secondary)

            TextEditor(text: $imagePrompt)
                .frame(height: 120)
                .border(Color.gray.opacity(0.3))

            HStack {
                Button("Cancel") { showingImagePromptSheet = false }
                Spacer()
                Button("Analyze") {
                    guard let selectedImageURL else { return }
                    showingImagePromptSheet = false
                    Task {
                        await viewModel.analyzeImage(imageURL: selectedImageURL, prompt: imagePrompt)
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 560)
    }

    private var editImageSheet: some View {
        let provider = appViewModel.settingsStore.settings.imageProvider

        return VStack(alignment: .leading, spacing: 16) {
            Text("Edit Image")
                .font(.title2.bold())

            if provider == .openAI {
                Text("OpenAI edit uses a selected local image.")
                    .foregroundStyle(.secondary)

                Button("Choose local image") {
                    chooseImageForEditing(autoShowSheet: false)
                }

                if let selectedImageURL {
                    Text("Selected: \(selectedImageURL.lastPathComponent)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Seedream Edit: use public URL or choose local image for auto-upload to Firebase.")
                    .foregroundStyle(.secondary)

                TextField("Public image URL (optional)", text: $waveSpeedEditImageURL)
                    .textFieldStyle(.roundedBorder)

                Button("Choose local image (auto-upload)") {
                    chooseImageForEditing(autoShowSheet: false)
                }

                if let selectedImageURL {
                    Text("Selected local image: \(selectedImageURL.lastPathComponent)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            TextEditor(text: $editPrompt)
                .frame(height: 120)
                .border(Color.gray.opacity(0.3))

            HStack {
                Button("Cancel") { showingEditPromptSheet = false }
                Spacer()
                Button("Edit Image") {
                    showingEditPromptSheet = false
                    Task {
                        await viewModel.editImage(
                            localImageURL: selectedImageURL,
                            waveSpeedPublicImageURL: waveSpeedEditImageURL,
                            prompt: editPrompt
                        )
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 640)
    }

    private var customizeSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Customize Assistant")
                .font(.title2.bold())

            TextField("Assistant name", text: Binding(
                get: { appViewModel.settingsStore.settings.assistantDisplayName },
                set: { newValue in
                    appViewModel.settingsStore.update { $0.assistantDisplayName = newValue }
                }
            ))
            .textFieldStyle(.roundedBorder)

            HStack {
                Button("Choose Assistant Avatar") {
                    chooseAvatarForAssistant()
                }

                Button("Reset Assistant Avatar") {
                    appViewModel.settingsStore.update { $0.assistantAvatarPath = "" }
                }
            }

            HStack {
                Button("Choose User Avatar") {
                    chooseAvatarForUser()
                }

                Button("Reset User Avatar") {
                    appViewModel.settingsStore.update { $0.userAvatarPath = "" }
                }
            }

            HStack(spacing: 20) {
                VStack {
                    Text("Assistant")
                        .font(.caption)
                    assistantAvatarView(size: 52)
                }
                VStack {
                    Text("User")
                        .font(.caption)
                    userAvatarView(size: 52)
                }
            }

            HStack {
                Spacer()
                Button("Done") { showingCustomizeSheet = false }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 520)
    }

    private func send() {
        guard !viewModel.isSending else { return }

        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        inputText = ""
        Task {
            await viewModel.send(text, speakResponse: speakResponses)
        }
    }

    private func configureVoice() {
        let settings = appViewModel.settingsStore.settings
        voiceController.configure(settings: settings)

        voiceController.onUserUtterance = { text in
            Task {
                guard !viewModel.isSending else { return }
                await viewModel.send(text, speakResponse: speakResponses)
            }
        }
    }

    private func chooseImageForAnalysis() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                selectedImageURL = try makeAccessibleTempCopy(from: url)
                imagePrompt = "Analyze this image in detail."
                showingImagePromptSheet = true
            } catch {
                print("Image open/copy error:", error.localizedDescription)
            }
        }
    }

    private func chooseImageForEditing(autoShowSheet: Bool = true) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                selectedImageURL = try makeAccessibleTempCopy(from: url)
                if autoShowSheet {
                    showingEditPromptSheet = true
                }
            } catch {
                print("Image open/copy error:", error.localizedDescription)
            }
        }
    }

    private func chooseFileForReading() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            .pdf, .plainText, .utf8PlainText, .text,
            .json, .commaSeparatedText, .xml, .html, .sourceCode
        ]
        panel.allowsOtherFileTypes = true

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task {
                do {
                    let safeURL = try makeAccessibleTempCopy(from: url)
                    await viewModel.readAndSummarizeFile(url: safeURL)
                } catch {
                    print("File open/copy error:", error.localizedDescription)
                }
            }
        }
    }

    private func chooseAvatarForAssistant() {
        chooseAvatarAndSave { copiedPath in
            appViewModel.settingsStore.update { $0.assistantAvatarPath = copiedPath }
        }
    }

    private func chooseAvatarForUser() {
        chooseAvatarAndSave { copiedPath in
            appViewModel.settingsStore.update { $0.userAvatarPath = copiedPath }
        }
    }

    private func chooseAvatarAndSave(onSaved: @escaping (String) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            do {
                let copiedURL = try copyAvatarToAppSupport(from: url)
                onSaved(copiedURL.path)
            } catch {
                print("Avatar copy error:", error.localizedDescription)
            }
        }
    }

    private func copyAvatarToAppSupport(from originalURL: URL) throws -> URL {
        let didStart = originalURL.startAccessingSecurityScopedResource()
        defer {
            if didStart { originalURL.stopAccessingSecurityScopedResource() }
        }

        let data = try Data(contentsOf: originalURL)

        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = base
            .appendingPathComponent("Astra Assistant", isDirectory: true)
            .appendingPathComponent("Avatars", isDirectory: true)

        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let ext = originalURL.pathExtension.isEmpty ? "png" : originalURL.pathExtension
        let dst = folder.appendingPathComponent("avatar-\(UUID().uuidString).\(ext)")
        try data.write(to: dst, options: .atomic)
        return dst
    }

    private func makeAccessibleTempCopy(from originalURL: URL) throws -> URL {
        let didStart = originalURL.startAccessingSecurityScopedResource()
        defer {
            if didStart { originalURL.stopAccessingSecurityScopedResource() }
        }

        let data = try Data(contentsOf: originalURL)
        let ext = originalURL.pathExtension.isEmpty ? "tmp" : originalURL.pathExtension
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("astra-import-\(UUID().uuidString).\(ext)")
        try data.write(to: tempURL, options: .atomic)
        return tempURL
    }

    private func exportCurrentChat() {
        let markdown = viewModel.exportCurrentConversationMarkdown()
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "astra-conversation.md"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try markdown.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                print("Export error:", error.localizedDescription)
            }
        }
    }

    // ✅ FIXED: screenshot now persists and is shown as attachment in chat
    private func analyzeScreen() {
        Task {
            do {
                let tempScreenshotURL = try await ScreenContextService.shared.captureMainScreenToTemporaryPNG()
                let persistedURL = try persistScreenshotForChat(from: tempScreenshotURL)

                // cleanup temp
                try? FileManager.default.removeItem(at: tempScreenshotURL)

                await viewModel.analyzeImage(
                    imageURL: persistedURL,
                    prompt: "Analyze this screenshot. Describe what is visible and suggest helpful next actions.",
                    storeAttachment: true
                )
            } catch {
                print("Screen analysis error:", error.localizedDescription)
            }
        }
    }

    private func persistScreenshotForChat(from temporaryURL: URL) throws -> URL {
        let data = try Data(contentsOf: temporaryURL)

        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = base
            .appendingPathComponent("Astra Assistant", isDirectory: true)
            .appendingPathComponent("Captured Screens", isDirectory: true)

        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let dst = folder.appendingPathComponent("screen-\(UUID().uuidString).png")
        try data.write(to: dst, options: .atomic)
        return dst
    }

    private func headerIconButton(_ icon: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .padding(9)
                .background(Color.white.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .help(title)
    }

    private func actionChip(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.10))
            .overlay(Capsule().stroke(AstraUITheme.border, lineWidth: 1))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func minimalButton(_ icon: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.10))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var providerGenerateDescription: String {
        let provider = appViewModel.settingsStore.settings.imageProvider
        switch provider {
        case .openAI:
            return "Uses OpenAI image generation API."
        case .waveSpeed:
            return "Uses WaveSpeed Seedream generation model selected in Settings."
        }
    }

    private var modelStatusText: String {
        let settings = appViewModel.settingsStore.settings
        let chat = settings.selectedChatModel.isEmpty ? "No chat model" : settings.selectedChatModel
        let vision = settings.selectedVisionModel.isEmpty ? "No vision model" : settings.selectedVisionModel
        return "Chat: \(chat) · Vision: \(vision) · Voice: \(settings.listeningMode.rawValue) · Language: \(settings.assistantLanguage)"
    }
}

private struct TypingDotsView: View {
    @State private var phase: Int = 0
    private let timer = Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 4) {
            dot(0)
            dot(1)
            dot(2)
        }
        .onReceive(timer) { _ in
            phase = (phase + 1) % 3
        }
    }

    private func dot(_ idx: Int) -> some View {
        Circle()
            .fill(Color.white.opacity(phase == idx ? 0.95 : 0.35))
            .frame(width: 6, height: 6)
            .scaleEffect(phase == idx ? 1.1 : 0.85)
            .animation(.easeInOut(duration: 0.2), value: phase)
    }
}

private struct VoicePulseIndicator: View {
    let isActive: Bool
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(isActive ? Color.green.opacity(0.32) : Color.gray.opacity(0.35))
                .frame(width: 20, height: 20)
                .scaleEffect(isActive && pulse ? 1.45 : 1.0)
                .opacity(isActive ? 0.9 : 0.0)

            Circle()
                .fill(isActive ? Color.green : Color.gray)
                .frame(width: 10, height: 10)
        }
        .onAppear {
            guard isActive else { return }
            pulse = false
            withAnimation(.easeInOut(duration: 1.15).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .onChange(of: isActive) { _, active in
            if active {
                pulse = false
                withAnimation(.easeInOut(duration: 1.15).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            } else {
                pulse = false
            }
        }
    }
}
