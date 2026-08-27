//
//  ConversationSidebarView.swift
//  AstraAssistant
//
//  Created by Alex on 10/8/26.
//

import SwiftUI

struct ConversationSidebarView: View {
    @ObservedObject var chatViewModel: ChatViewModel
    let onSelectConversation: () -> Void

    @State private var searchText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                chatViewModel.newConversation()
                onSelectConversation()
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("New Chat")
                    Spacer()
                }
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(AstraUITheme.accent.opacity(0.35))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.15), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)

            TextField("Search conversations...", text: $searchText)
                .textFieldStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .foregroundStyle(.white)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(filteredConversations) { conversation in
                        ConversationRow(
                            conversation: conversation,
                            isSelected: conversation.id == chatViewModel.currentConversationId,
                            onOpen: {
                                chatViewModel.loadConversation(id: conversation.id)
                                onSelectConversation()
                            },
                            onDelete: {
                                chatViewModel.deleteConversation(id: conversation.id)
                            }
                        )
                    }

                    if filteredConversations.isEmpty {
                        Text("No conversations found.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                            .padding(.top, 8)
                    }
                }
            }
            .frame(minHeight: 120, maxHeight: 260)
        }
    }

    private var filteredConversations: [ConversationSummary] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return chatViewModel.conversationsList }

        return chatViewModel.conversationsList.filter {
            $0.title.lowercased().contains(query)
        }
    }
}

private struct ConversationRow: View {
    let conversation: ConversationSummary
    let isSelected: Bool
    let onOpen: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(conversation.title)
                        .lineLimit(1)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.white)

                    Text(conversation.updatedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.65))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Menu {
                Button("Open") { onOpen() }
                Button("Delete", role: .destructive) { onDelete() }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(6)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            }
            .menuStyle(.borderlessButton)
            .opacity(isHovering || isSelected ? 1 : 0.3)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(backgroundStyle)
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(isSelected ? Color.white.opacity(0.18) : Color.clear, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var backgroundStyle: some ShapeStyle {
        if isSelected {
            return AnyShapeStyle(AstraUITheme.accent.opacity(0.25))
        }
        if isHovering {
            return AnyShapeStyle(Color.white.opacity(0.07))
        }
        return AnyShapeStyle(Color.clear)
    }
}
