//
//  HelpCenterView.swift
//  AstraAssistant
//
//  Created by Alex on 11/8/26.
//

import SwiftUI

struct HelpCenterView: View {
    @EnvironmentObject private var appViewModel: AppViewModel
    @Environment(\.openWindow) private var openWindow

    private struct CheckItem: Identifiable {
        let id = UUID()
        let title: String
        let details: String
        let status: DependencyStatus
    }

    var body: some View {
        ZStack {
            AstraUITheme.mainBackground

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    headerCard
                    actionsCard
                    checklistCard
                    quickGuideCard
                    commandsCard
                }
                .padding(14)
                .frame(maxWidth: 980, alignment: .leading)
            }
        }
        .task {
            if appViewModel.dependencyReport == nil {
                await appViewModel.refreshDiagnostics()
            }
        }
    }

    // MARK: Header

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Astra Help & Setup")
                .font(.largeTitle.bold())
                .foregroundStyle(.white)

            Text("Step-by-step setup and system status check.")
                .foregroundStyle(.white.opacity(0.75))
        }
        .padding(14)
        .premiumCard()
    }

    // MARK: Actions

    private var actionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Quick Actions", "bolt.fill")

            HStack(spacing: 10) {
                Button {
                    Task {
                        await appViewModel.refreshDiagnostics()
                        await appViewModel.refreshModels()
                    }
                } label: {
                    actionButton("Run Diagnostics", "stethoscope")
                }
                .buttonStyle(.plain)

                Button {
                    astraNavigateTo(.models)
                } label: {
                    actionButton("Open Models", "cpu.fill")
                }
                .buttonStyle(.plain)

                Button {
                    openAstraSettingsWindow()
                } label: {
                    actionButton("Open Settings", "gearshape.fill")
                }
                .buttonStyle(.plain)
                
            }

            HStack(spacing: 10) {
                Button {
                    astraNavigateTo(.chat)
                } label: {
                    actionButton("Open Chat", "bubble.left.and.bubble.right.fill")
                }
                .buttonStyle(.plain)

                Button {
                    astraNavigateTo(.tasks)
                } label: {
                    actionButton("Open Tasks", "checklist")
                }
                .buttonStyle(.plain)

                Button {
                    astraNavigateTo(.memory)
                } label: {
                    actionButton("Open Memory", "brain.head.profile")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .premiumCard()
    }

    // MARK: Checklist

    private var checklistCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Setup Checklist", "checkmark.seal.fill")

            ForEach(checklistItems) { item in
                HStack(alignment: .top, spacing: 10) {
                    Text(icon(for: item.status))
                        .font(.system(size: 16, weight: .bold))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.headline)
                            .foregroundStyle(.white)

                        Text(item.details)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.75))
                    }

                    Spacer()

                    Text(item.status.rawValue.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(color(for: item.status))
                }
                .padding(10)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(14)
        .premiumCard()
    }

    // MARK: Guides

    private var quickGuideCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("How to setup quickly", "list.bullet.rectangle")

            guide("1) Install and run Ollama", """
            - Install from https://ollama.com
            - Start: ollama serve
            """)

            guide("2) Pull recommended models", """
            ollama pull qwen2.5:14b
            ollama pull nomic-embed-text
            ollama pull llama3.2-vision
            """)

            guide("3) Open Models section", "Choose Chat / Embedding / Vision models.")
            guide("4) Open Settings", "Configure Voice, Images provider, and API keys.")
            guide("5) Run Diagnostics", "Fix all RED items first, then optional ORANGE items.")
        }
        .padding(14)
        .premiumCard()
    }

    private var commandsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Useful commands", "terminal.fill")

            mono("""
            /help
            /search <query>
            /open <url>
            /task <text>
            /tasks
            /now
            /calendar today
            /calendar add YYYY-MM-DD HH:mm | Title
            """)
        }
        .padding(14)
        .premiumCard()
    }

    // MARK: Derived checklist

    private var checklistItems: [CheckItem] {
        let settings = appViewModel.settingsStore.settings
        let report = appViewModel.dependencyReport

        func reportStatus(_ titleContains: String) -> (DependencyStatus, String) {
            guard let report else {
                return (.warning, "Diagnostics not run yet.")
            }

            if let item = report.items.first(where: {
                $0.title.lowercased().contains(titleContains.lowercased())
            }) {
                return (item.status, item.details)
            } else {
                return (.warning, "No data")
            }
        }

        let ollama = reportStatus("ollama")
        let mic = reportStatus("microphone")
        let speech = reportStatus("speech")
        let chatModelStatus: DependencyStatus = settings.selectedChatModel.isEmpty ? .warning : .ok
        let embModelStatus: DependencyStatus = settings.selectedEmbeddingModel.isEmpty ? .warning : .ok
        let visionStatus: DependencyStatus = settings.selectedVisionModel.isEmpty ? .warning : .ok

        let imageProviderStatus: (DependencyStatus, String) = {
            switch settings.imageProvider {
            case .openAI:
                if settings.enableOpenAIImages {
                    let hasKey = !(KeychainStore.shared.getOpenAIKey() ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    return hasKey
                    ? (.ok, "OpenAI key configured.")
                    : (.missing, "OpenAI images enabled but API key is missing.")
                } else {
                    return (.warning, "OpenAI image features are disabled.")
                }
            case .waveSpeed:
                let hasKey = !(KeychainStore.shared.getWaveSpeedKey() ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                return hasKey
                ? (.ok, "WaveSpeed key configured.")
                : (.missing, "WaveSpeed API key is missing.")
            }
        }()

        return [
            CheckItem(title: "Ollama service", details: ollama.1, status: ollama.0),
            CheckItem(title: "Chat model selected", details: settings.selectedChatModel.isEmpty ? "Select model in Models section." : settings.selectedChatModel, status: chatModelStatus),
            CheckItem(title: "Embedding model selected", details: settings.selectedEmbeddingModel.isEmpty ? "Select embedding model in Models section." : settings.selectedEmbeddingModel, status: embModelStatus),
            CheckItem(title: "Vision model selected", details: settings.selectedVisionModel.isEmpty ? "Optional, but required for image analysis." : settings.selectedVisionModel, status: visionStatus),
            CheckItem(title: "Microphone permission", details: mic.1, status: mic.0),
            CheckItem(title: "Speech recognition permission", details: speech.1, status: speech.0),
            CheckItem(title: "Image provider setup", details: imageProviderStatus.1, status: imageProviderStatus.0)
        ]
    }

    // MARK: Small UI helpers

    private func icon(for status: DependencyStatus) -> String {
        switch status {
        case .ok: return "✅"
        case .warning: return "⚠️"
        case .missing: return "❌"
        }
    }

    private func color(for status: DependencyStatus) -> Color {
        switch status {
        case .ok: return .green
        case .warning: return .orange
        case .missing: return .red
        }
    }

    private func sectionTitle(_ title: String, _ icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(AstraUITheme.accent2)
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
        }
    }

    private func actionButton(_ title: String, _ icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(title)
        }
        .font(.callout.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func guide(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)

            Text(text)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.75))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func mono(_ text: String) -> some View {
        Text(text)
            .font(.system(.body, design: .monospaced))
            .foregroundStyle(.white.opacity(0.9))
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
