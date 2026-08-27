//
//  ModelManagerView.swift
//  AstraAssistant
//
//  Created by Alex on 10/8/26.
//

import SwiftUI
import AppKit

struct ModelManagerView: View {
    @EnvironmentObject private var appViewModel: AppViewModel

    @State private var search = ""

    var body: some View {
        ZStack {
            AstraUITheme.mainBackground

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    headerCard
                    installedModelsCard
                    recommendedCommandsCard
                }
                .padding(14)
                .frame(maxWidth: 980, alignment: .leading)
            }
        }
        .task {
            await appViewModel.refreshModels()
            await appViewModel.refreshDiagnostics()
        }
    }

    // MARK: Header

    private var headerCard: some View {
        HStack(spacing: 12) {
            AstraSectionHeader(
                "Models",
                subtitle: "Install models with Ollama, then assign them to Chat / Embedding / Vision.",
                icon: "cpu.fill"
            )

            Spacer()

            TextField("Search models...", text: $search)
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)

            Button {
                Task {
                    await appViewModel.refreshModels()
                    await appViewModel.refreshDiagnostics()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                    Text("Refresh")
                }
                .font(.callout.weight(.semibold))
            }
            .buttonStyle(AstraGhostButtonStyle())

            Button {
                if let url = URL(string: "https://ollama.com") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "safari")
                    Text("Open Ollama")
                }
                .font(.callout.weight(.semibold))
            }
            .buttonStyle(AstraGhostButtonStyle())
        }
        .padding(14)
        .premiumCard()
    }

    // MARK: Installed models

    private var installedModelsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Installed Ollama Models")
                    .font(.headline)
                    .foregroundStyle(.white)

                Spacer()

                AstraStatusChip(text: "\(filteredModels.count)", tint: AstraUITheme.accent)
            }

            if filteredModels.isEmpty {
                if appViewModel.installedModels.isEmpty {
                    ContentUnavailableView(
                        "No models found",
                        systemImage: "tray",
                        description: Text("Make sure Ollama is running, then refresh.")
                    )
                    .foregroundStyle(.white.opacity(0.85))
                } else {
                    ContentUnavailableView(
                        "No matches",
                        systemImage: "magnifyingglass",
                        description: Text("Try another search query.")
                    )
                    .foregroundStyle(.white.opacity(0.85))
                }
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(filteredModels) { model in
                        modelRow(model)
                    }
                }
            }
        }
        .padding(14)
        .premiumCard()
    }

    private func modelRow(_ model: OllamaModel) -> some View {
        let settings = appViewModel.settingsStore.settings

        let isChat = settings.selectedChatModel == model.name
        let isEmbed = settings.selectedEmbeddingModel == model.name
        let isVision = settings.selectedVisionModel == model.name

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.name)
                        .font(.headline)
                        .foregroundStyle(.white)

                    HStack(spacing: 8) {
                        if let size = model.size {
                            AstraStatusChip(text: formatBytes(size), tint: .blue)
                        }

                        if isChat { AstraStatusChip(text: "Chat", tint: .green) }
                        if isEmbed { AstraStatusChip(text: "Embedding", tint: .orange) }
                        if isVision { AstraStatusChip(text: "Vision", tint: .purple) }
                    }
                }

                Spacer()
            }

            HStack(spacing: 8) {
                Button {
                    appViewModel.selectChatModel(model.name)
                } label: {
                    Label(isChat ? "Selected Chat" : "Use as Chat", systemImage: "bubble.left.and.bubble.right.fill")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(AstraGhostButtonStyle())

                Button {
                    appViewModel.selectEmbeddingModel(model.name)
                } label: {
                    Label(isEmbed ? "Selected Embedding" : "Use as Embedding", systemImage: "brain.head.profile")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(AstraGhostButtonStyle())

                Button {
                    appViewModel.selectVisionModel(model.name)
                } label: {
                    Label(isVision ? "Selected Vision" : "Use as Vision", systemImage: "eye.fill")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(AstraGhostButtonStyle())

                Spacer()
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Commands

    private var recommendedCommandsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recommended Setup Commands")
                .font(.headline)
                .foregroundStyle(.white)

            commandBlock(
                title: "Install Ollama",
                command: """
                Download Ollama:
                https://ollama.com

                Or with Homebrew:
                brew install ollama
                """
            )

            commandBlock(
                title: "Start Ollama service",
                command: """
                ollama serve
                """
            )

            commandBlock(
                title: "Recommended chat model",
                command: """
                ollama pull qwen2.5:14b
                """
            )

            commandBlock(
                title: "Embedding model (memory)",
                command: """
                ollama pull nomic-embed-text
                """
            )

            commandBlock(
                title: "Vision model (image analysis)",
                command: """
                ollama pull llama3.2-vision
                """
            )
        }
        .padding(14)
        .premiumCard()
    }

    private func commandBlock(title: String, command: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.bold())
                .foregroundStyle(.white)

            Text(command)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.white.opacity(0.92))
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: Utils

    private var filteredModels: [OllamaModel] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return appViewModel.installedModels }
        return appViewModel.installedModels.filter { $0.name.lowercased().contains(q) }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
