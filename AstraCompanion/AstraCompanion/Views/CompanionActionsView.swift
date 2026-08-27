//
//  CompanionActionsView.swift
//  AstraCompanion
//
//  Created by Alex on 14/8/26.
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

private enum CompanionActionImportPurpose {
    case summarizeDocument
}

struct CompanionActionsView: View {
    @EnvironmentObject private var appState: CompanionAppState
    @EnvironmentObject private var macStatus: MacConnectionStatusViewModel

    @State private var selectedPhotoItem: PhotosPickerItem?

    @State private var showGenerateSheet = false
    @State private var showAnalyzeSheet = false
    @State private var showEditSheet = false
    @State private var showSearchSheet = false

    @State private var generatePrompt = "Create a high quality image of ..."
    @State private var analyzePrompt = "Describe this image."
    @State private var editPrompt = "Edit this image..."
    @State private var searchQuery = ""

    @State private var showImporter = false
    @State private var importerPurpose: CompanionActionImportPurpose?

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    statusCard

                    LazyVGrid(columns: columns, spacing: 12) {
                        actionCard(
                            title: "New Chat",
                            subtitle: "Start fresh",
                            icon: "plus.bubble.fill",
                            tint: .blue
                        ) {
                            appState.createNewConversation()
                        }

                        actionCard(
                            title: "Generate Image",
                            subtitle: "Create from prompt",
                            icon: "photo.fill.on.rectangle.fill",
                            tint: .purple
                        ) {
                            showGenerateSheet = true
                        }

                        actionCard(
                            title: "Analyze Image",
                            subtitle: "Upload and inspect",
                            icon: "eye.fill",
                            tint: .cyan
                        ) {
                            showAnalyzeSheet = true
                        }

                        actionCard(
                            title: "Edit Image",
                            subtitle: "Upload and transform",
                            icon: "slider.horizontal.3",
                            tint: .orange
                        ) {
                            showEditSheet = true
                        }

                        actionCard(
                            title: "Summarize File",
                            subtitle: "PDF, text, JSON, CSV",
                            icon: "doc.text.fill",
                            tint: .indigo
                        ) {
                            importerPurpose = .summarizeDocument
                            showImporter = true
                        }

                        actionCard(
                            title: "Daily Briefing",
                            subtitle: "Tasks + memory",
                            icon: "sun.max.fill",
                            tint: .yellow
                        ) {
                            Task {
                                await appState.chatVM.runRemoteAction(
                                    type: .dailyBriefing,
                                    payload: [:],
                                    userVisibleText: "Daily briefing",
                                    status: "Preparing briefing...",
                                    timeoutSeconds: 180
                                )
                                appState.selectedTab = .chat
                            }
                        }

                        actionCard(
                            title: "Web Search",
                            subtitle: "Fresh information",
                            icon: "globe",
                            tint: .green
                        ) {
                            showSearchSheet = true
                        }

                        actionCard(
                            title: "Calendar Today",
                            subtitle: "Today's events",
                            icon: "calendar",
                            tint: .red
                        ) {
                            Task {
                                await appState.chatVM.runRemoteAction(
                                    type: .calendarToday,
                                    payload: [:],
                                    userVisibleText: "Today calendar",
                                    status: "Loading calendar...",
                                    timeoutSeconds: 90
                                )
                                appState.selectedTab = .chat
                            }
                        }

                        actionCard(
                            title: "Tasks",
                            subtitle: "Open task manager",
                            icon: "checklist",
                            tint: .mint
                        ) {
                            appState.selectedTab = .tasks
                        }
                        
                        actionCard(
                            title: "Test Mac TTS",
                            subtitle: "Speak on Mac",
                            icon: "desktopcomputer",
                            tint: .purple
                        ) {
                            Task {
                                await appState.chatVM.speakOnMac(
                                    "Hello, this is a test from your iPhone. If you hear this, Mac TTS is working correctly.",
                                    ttsService: appState.chatVM.tts
                                )
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Actions")
            .background(Color(.systemGroupedBackground))
            .sheet(isPresented: $showGenerateSheet) {
                generateSheet
            }
            .sheet(isPresented: $showAnalyzeSheet) {
                analyzeSheet
            }
            .sheet(isPresented: $showEditSheet) {
                editSheet
            }
            .sheet(isPresented: $showSearchSheet) {
                searchSheet
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: importerAllowedTypes,
                allowsMultipleSelection: false,
                onCompletion: handleImporterResult
            )
        }
    }

    private var statusCard: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(macStatus.statusColor)
                .frame(width: 11, height: 11)

            VStack(alignment: .leading, spacing: 2) {
                Text(macStatus.statusText)
                    .font(.headline)

                Text(macStatus.isCommandAvailable ? "Ready for remote actions" : "Open Astra on your Mac")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task {
                    await macStatus.ping(profile: appState.profile)
                }
            } label: {
                Image(systemName: "dot.radiowaves.left.and.right")
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func actionCard(
        title: String,
        subtitle: String,
        icon: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            guard macStatus.isCommandAvailable || title == "New Chat" || title == "Tasks" else {
                appState.chatVM.lastError = "Mac is offline. Open Astra on your Mac."
                return
            }

            action()
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.18))
                        .frame(width: 44, height: 44)

                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(tint)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, minHeight: 145, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .opacity((macStatus.isCommandAvailable || title == "New Chat" || title == "Tasks") ? 1.0 : 0.45)
    }

    private var generateSheet: some View {
        NavigationStack {
            Form {
                Section("Prompt") {
                    TextField("Image prompt", text: $generatePrompt, axis: .vertical)
                        .lineLimit(4...8)
                }

                Section {
                    Button {
                        let prompt = generatePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !prompt.isEmpty else { return }

                        showGenerateSheet = false

                        Task {
                            await appState.chatVM.generateImage(prompt: prompt)
                            appState.selectedTab = .chat
                        }
                    } label: {
                        Label("Generate", systemImage: "sparkles")
                    }
                }
            }
            .navigationTitle("Generate Image")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        showGenerateSheet = false
                    }
                }
            }
        }
    }

    private var analyzeSheet: some View {
        NavigationStack {
            Form {
                Section("Prompt") {
                    TextField("Analyze prompt", text: $analyzePrompt, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Image") {
                    PhotosPicker("Pick image", selection: $selectedPhotoItem, matching: .images)
                }

                Section {
                    Button {
                        Task {
                            await uploadAndAnalyze()
                        }
                    } label: {
                        Label("Upload & Analyze", systemImage: "eye.fill")
                    }
                    .disabled(selectedPhotoItem == nil)
                }
            }
            .navigationTitle("Analyze Image")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        showAnalyzeSheet = false
                    }
                }
            }
        }
    }

    private var editSheet: some View {
        NavigationStack {
            Form {
                Section("Prompt") {
                    TextField("Edit prompt", text: $editPrompt, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Source Image") {
                    PhotosPicker("Pick image", selection: $selectedPhotoItem, matching: .images)
                }

                Section {
                    Button {
                        Task {
                            await uploadAndEdit()
                        }
                    } label: {
                        Label("Upload & Edit", systemImage: "slider.horizontal.3")
                    }
                    .disabled(selectedPhotoItem == nil)
                }
            }
            .navigationTitle("Edit Image")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        showEditSheet = false
                    }
                }
            }
        }
    }

    private var searchSheet: some View {
        NavigationStack {
            Form {
                Section("Search query") {
                    TextField("What do you want to search?", text: $searchQuery, axis: .vertical)
                        .lineLimit(2...5)
                }

                Section {
                    Button {
                        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !query.isEmpty else { return }

                        showSearchSheet = false

                        Task {
                            await appState.chatVM.runRemoteAction(
                                type: .webSearch,
                                payload: [
                                    "query": query
                                ],
                                userVisibleText: "Search web: \(query)",
                                status: "Searching web...",
                                timeoutSeconds: 180
                            )

                            appState.selectedTab = .chat
                        }
                    } label: {
                        Label("Search", systemImage: "globe")
                    }
                }
            }
            .navigationTitle("Web Search")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        showSearchSheet = false
                    }
                }
            }
        }
    }

    private func uploadAndAnalyze() async {
        do {
            guard let item = selectedPhotoItem else { return }

            guard let data = try await item.loadTransferable(type: Data.self) else {
                appState.chatVM.lastError = "Failed to read selected image."
                return
            }

            let publicURL = try await IOSMediaUploadService.shared.uploadImageData(data)

            showAnalyzeSheet = false
            selectedPhotoItem = nil

            await appState.chatVM.analyzeImage(
                publicURL: publicURL,
                prompt: analyzePrompt
            )

            appState.selectedTab = .chat
        } catch {
            appState.chatVM.lastError = error.localizedDescription
        }
    }

    private func uploadAndEdit() async {
        do {
            guard let item = selectedPhotoItem else { return }

            guard let data = try await item.loadTransferable(type: Data.self) else {
                appState.chatVM.lastError = "Failed to read selected image."
                return
            }

            let publicURL = try await IOSMediaUploadService.shared.uploadImageData(data)

            showEditSheet = false
            selectedPhotoItem = nil

            await appState.chatVM.editImage(
                publicURL: publicURL,
                prompt: editPrompt
            )

            appState.selectedTab = .chat
        } catch {
            appState.chatVM.lastError = error.localizedDescription
        }
    }

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

                        await appState.chatVM.summarizeFile(
                            publicURL: publicURL,
                            fileName: url.lastPathComponent
                        )

                        appState.selectedTab = .chat
                    } catch {
                        appState.chatVM.lastError = error.localizedDescription
                    }
                }

            case .none:
                break
            }

        case .failure(let error):
            appState.chatVM.lastError = error.localizedDescription
        }

        importerPurpose = nil
    }
}
