//
//  MemoryView.swift
//  AstraAssistant
//
//  Created by Alex on 10/8/26.
//

import SwiftUI

struct MemoryView: View {
    @EnvironmentObject private var appViewModel: AppViewModel

    @State private var memories: [MemoryItem] = []
    @State private var search = ""

    @State private var newMemoryText = ""
    @State private var newMemoryType = "user_fact"
    @State private var newMemoryImportance = 7

    @State private var isAdding = false
    @State private var errorMessage: String?

    private let memoryStore = VectorMemoryStore.shared
    private let ollama = OllamaClient.shared

    var body: some View {
        ZStack {
            AstraUITheme.mainBackground

            VStack(spacing: 12) {
                headerCard

                HStack(spacing: 12) {
                    memoryListCard
                    addMemoryCard
                        .frame(width: 360)
                }
            }
            .padding(14)
        }
        .onAppear { refresh() }
    }

    private var headerCard: some View {
        HStack {
            AstraSectionHeader(
                "Memory",
                subtitle: "Local long-term memory powered by embeddings",
                icon: "brain.head.profile"
            )

            Spacer()

            TextField("Search memory...", text: $search)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)

            Button("Refresh") { refresh() }
                .buttonStyle(AstraGhostButtonStyle())

            Button("Export") { exportMemory() }
                .buttonStyle(AstraGhostButtonStyle())
        }
        .padding(14)
        .premiumCard()
    }

    private var memoryListCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Saved memories")
                    .font(.headline)
                    .foregroundStyle(.white)

                Spacer()

                AstraStatusChip(text: "\(filteredMemories.count)", tint: AstraUITheme.accent)
            }

            if filteredMemories.isEmpty {
                ContentUnavailableView(
                    "No memories",
                    systemImage: "tray",
                    description: Text("Nothing matches your filter.")
                )
                .foregroundStyle(.white.opacity(0.8))
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredMemories) { memory in
                            memoryRow(memory)
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
        .padding(14)
        .premiumCard()
    }

    private func memoryRow(_ memory: MemoryItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                AstraStatusChip(text: memory.type, tint: AstraUITheme.accent2)
                AstraStatusChip(text: "Importance \(memory.importance)", tint: .orange)

                Spacer()

                Button(role: .destructive) {
                    delete(memory)
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red.opacity(0.9))
                }
                .buttonStyle(.plain)
            }

            Text(memory.content)
                .foregroundStyle(.white)
                .textSelection(.enabled)

            Text(memory.updatedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var addMemoryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            AstraSectionHeader("Add Memory", subtitle: "Manual entry", icon: "plus.circle.fill")

            TextField("Type (e.g. user_fact, preference)", text: $newMemoryType)
                .textFieldStyle(.roundedBorder)

            Stepper("Importance: \(newMemoryImportance)", value: $newMemoryImportance, in: 1...10)

            TextEditor(text: $newMemoryText)
                .frame(minHeight: 180)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(.white)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button {
                Task { await addMemory() }
            } label: {
                if isAdding {
                    ProgressView()
                        .progressViewStyle(.circular)
                } else {
                    Label("Save Memory", systemImage: "brain")
                }
            }
            .buttonStyle(AstraGhostButtonStyle())
            .disabled(newMemoryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAdding)

            Spacer()
        }
        .padding(14)
        .premiumCard()
    }

    private var filteredMemories: [MemoryItem] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return memories }

        return memories.filter {
            $0.content.lowercased().contains(q) || $0.type.lowercased().contains(q)
        }
    }

    private func refresh() {
        memories = memoryStore.listMemories()
    }

    private func addMemory() async {
        let text = newMemoryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        isAdding = true
        errorMessage = nil
        defer { isAdding = false }

        do {
            let settings = appViewModel.settingsStore.settings

            let embedding = try await ollama.embedding(
                model: settings.selectedEmbeddingModel,
                prompt: text
            )

            memoryStore.addMemory(
                type: newMemoryType,
                content: text,
                importance: newMemoryImportance,
                embedding: embedding
            )

            newMemoryText = ""
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ memory: MemoryItem) {
        memoryStore.deleteMemory(id: memory.id)
        refresh()
    }

    private func exportMemory() {
        let markdown = buildMemoryMarkdown()

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "astra-memory.md"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try markdown.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                print("Memory export error:", error.localizedDescription)
            }
        }
    }

    private func buildMemoryMarkdown() -> String {
        var result = "# Astra Assistant Memory\n\n"

        for memory in memories {
            result += "## \(memory.type)\n\n"
            result += "- Importance: \(memory.importance)\n"
            result += "- Created: \(memory.createdAt)\n"
            result += "- Updated: \(memory.updatedAt)\n\n"
            result += "\(memory.content)\n\n"
        }

        return result
    }
}
