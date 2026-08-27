//
//  MainShellView.swift
//  AstraAssistant
//
//  Created by Alex on 10/8/26.
//


import SwiftUI

enum MainSection: String, CaseIterable, Identifiable {
    case chat
    case memory
    case tasks
    case models
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chat: return "Chat"
        case .memory: return "Memory"
        case .tasks: return "Tasks"
        case .models: return "Models"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .chat: return "bubble.left.and.bubble.right.fill"
        case .memory: return "brain.head.profile"
        case .tasks: return "checklist"
        case .models: return "cpu.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

struct MainShellView: View {
    @EnvironmentObject private var appViewModel: AppViewModel

    @StateObject private var chatViewModel = ChatViewModel()
    @State private var selectedSection: MainSection = .chat
    @State private var splitVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $splitVisibility) {
            sidebar
        } detail: {
            detailView
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        splitVisibility = (splitVisibility == .detailOnly) ? .all : .detailOnly
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .help("Show / Hide Sidebar")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .astraNavigateToSection)) { note in
            guard let raw = note.userInfo?["target"] as? String else { return }

            switch raw {
            case AstraNavTarget.chat.rawValue:
                selectedSection = .chat
            case AstraNavTarget.memory.rawValue:
                selectedSection = .memory
            case AstraNavTarget.tasks.rawValue:
                selectedSection = .tasks
            case AstraNavTarget.models.rawValue:
                selectedSection = .models
            case AstraNavTarget.settings.rawValue:
                selectedSection = .settings
            default:
                break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .conversationStoreDidChange)) { note in
            guard let raw = note.userInfo?["conversationId"] as? String,
                  let changedId = UUID(uuidString: raw) else {
                return
            }

            chatViewModel.refreshConversations()

            if changedId == chatViewModel.currentConversationId {
                chatViewModel.loadConversation(id: changedId)
            }
        }
        .task {
            chatViewModel.configure(appViewModel: appViewModel)
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        ZStack {
            AstraUITheme.mainBackground

            VStack(spacing: 12) {
                brandCard
                navigationCard
                toolsCard
                conversationsCard
                Spacer(minLength: 0)
                statusFooter
            }
            .padding(12)
        }
        .navigationTitle("")
        .toolbar(removing: .sidebarToggle)
    }

    private var brandCard: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [AstraUITheme.accent, AstraUITheme.accent2],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 34, height: 34)

                Image(systemName: "sparkles")
                    .foregroundStyle(.white)
                    .font(.system(size: 14, weight: .bold))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(appTitle)
                    .font(.headline)
                    .foregroundStyle(.white)

                Text("Private • Local-first")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
            }

            Spacer()
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.12), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var navigationCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Navigation")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.65))
                .padding(.horizontal, 6)

            ForEach(MainSection.allCases) { section in
                Button {
                    selectedSection = section
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: section.icon)
                            .frame(width: 18)
                        Text(section.title)
                            .font(.callout.weight(.semibold))
                        Spacer()
                    }
                    .foregroundStyle(selectedSection == section ? .white : .white.opacity(0.86))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .background(
                        selectedSection == section
                        ? AstraUITheme.accent.opacity(0.35)
                        : Color.clear
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(selectedSection == section ? Color.white.opacity(0.18) : .clear, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.12), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var toolsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick Tools")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.65))
                .padding(.horizontal, 6)

            toolButton("New Chat", "plus.bubble.fill") {
                chatViewModel.newConversation()
                selectedSection = .chat
            }

            toolButton("Daily Briefing", "sun.max.fill") {
                selectedSection = .chat
                Task { await chatViewModel.generateDailyBriefing() }
            }

            toolButton("Today Calendar", "calendar") {
                selectedSection = .chat
                Task { await chatViewModel.send("/calendar today") }
            }

            toolButton("Commands", "questionmark.circle.fill") {
                selectedSection = .chat
                chatViewModel.showCommandsHelp()
            }
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.12), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func toolButton(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .frame(width: 18)
                Text(title)
                    .font(.callout.weight(.semibold))
                Spacer()
            }
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private var conversationsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Conversations")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.65))
                .padding(.horizontal, 6)

            ConversationSidebarView(
                chatViewModel: chatViewModel,
                onSelectConversation: {
                    selectedSection = .chat
                }
            )
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.12), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: Detail

    @ViewBuilder
    private var detailView: some View {
        switch selectedSection {
        case .chat:
            ChatView(viewModel: chatViewModel)
        case .memory:
            MemoryView()
        case .tasks:
            TasksView()
        case .models:
            ModelManagerView()
        case .settings:
            SettingsView()
        }
    }

    // MARK: Footer

    private var statusFooter: some View {
        let settings = appViewModel.settingsStore.settings

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
                Text("System ready")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }

            Text(settings.selectedChatModel.isEmpty ? "No chat model selected" : settings.selectedChatModel)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)

            Text("Voice: \(settings.listeningMode.rawValue)")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)

            Text("TTS: \(settings.ttsProvider.rawValue)")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.12), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var appTitle: String {
        let name = appViewModel.settingsStore.settings.assistantDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Astra Assistant" : name
    }
}
