//
//  CompanionConversationsView.swift
//  AstraCompanion
//
//  Created by Alex on 13/8/26.
//


import SwiftUI
import FirebaseFirestore
import Combine

struct RemoteConversationItem: Identifiable, Hashable {
    let id: String
    let title: String
    let lastMessage: String
}

@MainActor
final class CompanionConversationsViewModel: ObservableObject {
    @Published var items: [RemoteConversationItem] = []
    @Published var errorText: String?
    @Published var isDeleting = false
    
    private var listener: ListenerRegistration?
    private var macUID: String = ""
    private var macDeviceID: String = ""

    deinit {
        listener?.remove()
    }

    func start(macUID: String, macDeviceID: String) {
        stop()
        guard !macUID.isEmpty, !macDeviceID.isEmpty else { return }
        
        self.macUID = macUID
        self.macDeviceID = macDeviceID

        let db = Firestore.firestore()
        listener = db.collection("users")
            .document(macUID)
            .collection("remoteConversations")
            .order(by: "updatedAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }

                if let error {
                    self.errorText = error.localizedDescription
                    return
                }

                guard let docs = snapshot?.documents else { return }

                self.items = docs.map { doc in
                    let data = doc.data()
                    return RemoteConversationItem(
                        id: doc.documentID,
                        title: (data["title"] as? String) ?? "Conversation",
                        lastMessage: (data["lastMessage"] as? String) ?? ""
                    )
                }
            }
    }

    func stop() {
        listener?.remove()
        listener = nil
    }
    
    // MARK: - Delete Conversation
    
    func deleteConversation(_ conversationId: String) async -> Bool {
        guard !macUID.isEmpty, !macDeviceID.isEmpty else {
            errorText = "Not connected to Mac"
            return false
        }
        
        isDeleting = true
        defer { isDeleting = false }
        
        do {
            try await CompanionCommandClient.shared.deleteConversation(
                macUID: macUID,
                targetDevice: macDeviceID,
                conversationId: conversationId
            )
            
            // Удаляем из локального списка
            items.removeAll { $0.id == conversationId }
            return true
            
        } catch {
            errorText = "Failed to delete: \(error.localizedDescription)"
            return false
        }
    }
}

struct CompanionConversationsView: View {
    let macUID: String
    let macDeviceID: String
    let onSelectConversation: (String) -> Void
    let onNewChat: () -> Void

    @StateObject private var vm = CompanionConversationsViewModel()
    @State private var conversationToDelete: RemoteConversationItem?
    @State private var showDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        onNewChat()
                    } label: {
                        Label("New Chat", systemImage: "plus.bubble.fill")
                    }
                }

                if let err = vm.errorText {
                    Section {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                if vm.isDeleting {
                    Section {
                        HStack {
                            ProgressView()
                            Text("Deleting...")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if vm.items.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "No Conversations Yet",
                            systemImage: "tray",
                            description: Text("Send first message from Chat tab.")
                        )
                    }
                } else {
                    Section("Open conversations") {
                        ForEach(vm.items) { item in
                            ConversationRow(
                                item: item,
                                onSelect: { onSelectConversation(item.id) },
                                onDelete: {
                                    conversationToDelete = item
                                    showDeleteConfirmation = true
                                }
                            )
                        }
                    }
                }
            }
            .navigationTitle("Conversations")
            .onAppear {
                vm.start(macUID: macUID, macDeviceID: macDeviceID)
            }
            .onDisappear { vm.stop() }
            .alert("Delete Conversation?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) {
                    conversationToDelete = nil
                }
                Button("Delete", role: .destructive) {
                    if let item = conversationToDelete {
                        Task {
                            _ = await vm.deleteConversation(item.id)
                        }
                        conversationToDelete = nil
                    }
                }
            } message: {
                if let item = conversationToDelete {
                    Text("Are you sure you want to delete \"\(item.title)\"? This cannot be undone.")
                } else {
                    Text("Are you sure you want to delete this conversation?")
                }
            }
        }
    }
}

// MARK: - Conversation Row

struct ConversationRow: View {
    let item: RemoteConversationItem
    let onSelect: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        Button {
            onSelect()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                Text(item.lastMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Open") {
                onSelect()
            }
            
            Divider()
            
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
