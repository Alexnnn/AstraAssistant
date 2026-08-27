//
//  TasksView.swift
//  AstraAssistant
//
//  Created by Alex on 11/8/26.
//


import SwiftUI
import AppKit

struct TasksView: View {
    @State private var tasks: [AstraTask] = []
    @State private var search = ""

    @State private var newTaskTitle = ""
    @State private var newTaskNotes = ""
    @State private var includeDone = true

    @State private var errorMessage: String?

    private let taskStore = TaskStore.shared

    var body: some View {
        ZStack {
            AstraUITheme.mainBackground

            VStack(spacing: 12) {
                headerCard

                HStack(spacing: 12) {
                    tasksListCard
                    addTaskCard
                        .frame(width: 360)
                }
            }
            .padding(14)
        }
        .onAppear { refresh() }
    }

    // MARK: Header

    private var headerCard: some View {
        HStack {
            AstraSectionHeader(
                "Tasks",
                subtitle: "Local task manager for quick planning",
                icon: "checklist"
            )

            Spacer()

            Toggle("Include done", isOn: $includeDone)
                .toggleStyle(.switch)
                .tint(AstraUITheme.accent)

            TextField("Search tasks...", text: $search)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)

            Button("Refresh") {
                refresh()
            }
            .buttonStyle(AstraGhostButtonStyle())

            Button("Export") {
                exportTasks()
            }
            .buttonStyle(AstraGhostButtonStyle())
        }
        .padding(14)
        .premiumCard()
    }

    // MARK: Tasks list

    private var tasksListCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Your tasks")
                    .font(.headline)
                    .foregroundStyle(.white)

                Spacer()

                AstraStatusChip(text: "\(filteredTasks.count)", tint: AstraUITheme.accent)
            }

            if filteredTasks.isEmpty {
                ContentUnavailableView(
                    "No tasks",
                    systemImage: "tray",
                    description: Text("Add a task or change filters.")
                )
                .foregroundStyle(.white.opacity(0.85))
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredTasks) { task in
                            taskRow(task)
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
        .padding(14)
        .premiumCard()
    }

    private func taskRow(_ task: AstraTask) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    taskStore.setTaskDone(id: task.id, isDone: !task.isDone)
                    refresh()
                } label: {
                    Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(task.isDone ? .green : .white.opacity(0.7))
                }
                .buttonStyle(.plain)

                Text(task.title)
                    .font(.headline)
                    .foregroundStyle(task.isDone ? .white.opacity(0.55) : .white)
                    .strikethrough(task.isDone)

                Spacer()

                AstraStatusChip(
                    text: task.isDone ? "Done" : "Open",
                    tint: task.isDone ? .green : .orange
                )

                Button(role: .destructive) {
                    taskStore.deleteTask(id: task.id)
                    refresh()
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red.opacity(0.9))
                }
                .buttonStyle(.plain)
            }

            if !task.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(task.notes)
                    .foregroundStyle(.white.opacity(0.8))
                    .font(.subheadline)
            }

            HStack(spacing: 8) {
                Text(task.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.6))

                if let due = task.dueAt {
                    Text("•")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                    Text("Due: \(due.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Add task panel

    private var addTaskCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            AstraSectionHeader(
                "Add Task",
                subtitle: "Quickly save a new item",
                icon: "plus.circle.fill"
            )

            TextField("Task title", text: $newTaskTitle)
                .textFieldStyle(.roundedBorder)

            TextEditor(text: $newTaskNotes)
                .frame(minHeight: 140)
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
                addTask()
            } label: {
                Label("Save Task", systemImage: "checkmark.circle.fill")
            }
            .buttonStyle(AstraGhostButtonStyle())
            .disabled(newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Spacer()
        }
        .padding(14)
        .premiumCard()
    }

    // MARK: Data

    private var filteredTasks: [AstraTask] {
        var result = taskStore.listAllTasks()

        if !includeDone {
            result = result.filter { !$0.isDone }
        }

        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            result = result.filter {
                $0.title.lowercased().contains(q) || $0.notes.lowercased().contains(q)
            }
        }

        return result.sorted { $0.createdAt > $1.createdAt }
    }

    private func refresh() {
        tasks = taskStore.listAllTasks()
    }

    private func addTask() {
        let title = newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = newTaskNotes.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !title.isEmpty else {
            errorMessage = "Title cannot be empty."
            return
        }

        taskStore.addTask(title: title, notes: notes)
        newTaskTitle = ""
        newTaskNotes = ""
        errorMessage = nil
        refresh()
    }

    private func exportTasks() {
        let markdown = buildTasksMarkdown()

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "astra-tasks.md"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            do {
                try markdown.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                print("Task export error:", error.localizedDescription)
            }
        }
    }

    private func buildTasksMarkdown() -> String {
        let all = taskStore.listAllTasks()
        var out = "# Astra Tasks\n\n"

        for task in all {
            out += "## \(task.title)\n"
            out += "- Status: \(task.isDone ? "Done" : "Open")\n"
            out += "- Created: \(task.createdAt)\n"
            if let due = task.dueAt {
                out += "- Due: \(due)\n"
            }
            if !task.notes.isEmpty {
                out += "- Notes: \(task.notes)\n"
            }
            out += "\n"
        }

        return out
    }
}
