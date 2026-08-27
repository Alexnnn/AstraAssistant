//
//  CompanionTasksView.swift
//  AstraCompanion
//
//  Created by Alex on 14/8/26.
//

import SwiftUI
import Combine

struct CompanionRemoteTask: Identifiable, Hashable {
    let id: String
    let title: String
    let notes: String
    let isDone: Bool
    let createdAt: Date?
}
private enum TaskInputField: Hashable {
    case title
    case notes
}

@MainActor
final class CompanionTasksViewModel: ObservableObject {
    @Published var tasks: [CompanionRemoteTask] = []
    @Published var newTaskTitle = ""
    @Published var newTaskNotes = ""
    @Published var isLoading = false
    @Published var isAdding = false
    @Published var lastError: String?
    @Published var statusText = "Idle"
    
    @FocusState private var focusedField: TaskInputField?

    private var macUID = ""
    private var macDeviceID = ""

    func applyConnection(_ profile: ConnectionProfile?) {
        macUID = profile?.macUID ?? ""
        macDeviceID = profile?.macDeviceID ?? ""
    }

    func loadTasks() async {
        guard !macUID.isEmpty, !macDeviceID.isEmpty else {
            lastError = "Not connected to Mac."
            return
        }

        isLoading = true
        statusText = "Loading tasks..."
        lastError = nil

        defer {
            isLoading = false
        }

        do {
            let commandId = try await CompanionCommandClient.shared.sendCommand(
                macUID: macUID,
                targetDevice: macDeviceID,
                type: .tasksList,
                payload: [:]
            )

            let response = try await CompanionCommandClient.shared.waitForResponse(
                macUID: macUID,
                commandId: commandId,
                timeoutSeconds: 60
            )

            let rawItems = response.raw["items"] as? [[String: Any]] ?? []

            tasks = rawItems.compactMap { item in
                guard let id = item["id"] as? String,
                      let title = item["title"] as? String else {
                    return nil
                }

                let notes = item["notes"] as? String ?? ""
                let isDone = item["isDone"] as? Bool ?? false

                let createdAt: Date?
                if let ts = item["createdAt"] as? TimeInterval {
                    createdAt = Date(timeIntervalSince1970: ts)
                } else {
                    createdAt = nil
                }

                return CompanionRemoteTask(
                    id: id,
                    title: title,
                    notes: notes,
                    isDone: isDone,
                    createdAt: createdAt
                )
            }

            statusText = "Loaded \(tasks.count) tasks"
        } catch {
            statusText = "Failed"
            lastError = error.localizedDescription
        }
    }

    func setDone(task: CompanionRemoteTask, isDone: Bool) async {
        guard !macUID.isEmpty, !macDeviceID.isEmpty else {
            lastError = "Not connected to Mac."
            return
        }

        statusText = "Updating task..."
        lastError = nil

        do {
            let commandId = try await CompanionCommandClient.shared.sendCommand(
                macUID: macUID,
                targetDevice: macDeviceID,
                type: .tasksSetDone,
                payload: [
                    "id": task.id,
                    "isDone": isDone
                ]
            )

            _ = try await CompanionCommandClient.shared.waitForResponse(
                macUID: macUID,
                commandId: commandId,
                timeoutSeconds: 60
            )

            statusText = "Task updated"
            await loadTasks()
        } catch {
            statusText = "Failed"
            lastError = error.localizedDescription
        }
    }

    func delete(task: CompanionRemoteTask) async {
        guard !macUID.isEmpty, !macDeviceID.isEmpty else {
            lastError = "Not connected to Mac."
            return
        }

        statusText = "Deleting task..."
        lastError = nil

        do {
            let commandId = try await CompanionCommandClient.shared.sendCommand(
                macUID: macUID,
                targetDevice: macDeviceID,
                type: .tasksDelete,
                payload: [
                    "id": task.id
                ]
            )

            _ = try await CompanionCommandClient.shared.waitForResponse(
                macUID: macUID,
                commandId: commandId,
                timeoutSeconds: 60
            )

            statusText = "Task deleted"
            await loadTasks()
        } catch {
            statusText = "Failed"
            lastError = error.localizedDescription
        }
    }
    
    
    func addTask() async {
        let title = newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = newTaskNotes.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !title.isEmpty else { return }

        guard !macUID.isEmpty, !macDeviceID.isEmpty else {
            lastError = "Not connected to Mac."
            return
        }

        isAdding = true
        statusText = "Adding task..."
        lastError = nil

        defer {
            isAdding = false
        }

        do {
            let commandId = try await CompanionCommandClient.shared.sendCommand(
                macUID: macUID,
                targetDevice: macDeviceID,
                type: .tasksAdd,
                payload: [
                    "title": title,
                    "notes": notes
                ]
            )

            _ = try await CompanionCommandClient.shared.waitForResponse(
                macUID: macUID,
                commandId: commandId,
                timeoutSeconds: 60
            )

            newTaskTitle = ""
            newTaskNotes = ""
            statusText = "Task added"

            await loadTasks()
        } catch {
            statusText = "Failed"
            lastError = error.localizedDescription
        }
    }
}

struct CompanionTasksView: View {
    @EnvironmentObject private var appState: CompanionAppState
    @EnvironmentObject private var macStatus: MacConnectionStatusViewModel

    @StateObject private var vm = CompanionTasksViewModel()
    @FocusState private var focusedField: TaskInputField?

    private var profileKey: String {
        guard let profile = appState.profile else {
            return "none"
        }

        return "\(profile.macUID)|\(profile.macDeviceID)"
    }

    var body: some View {
        NavigationStack {
            List {
                macStatusSection
                addTaskSection
                tasksSection

                if let error = vm.lastError {
                    Section {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Tasks")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            await vm.loadTasks()
                        }
                    } label: {
                        if vm.isLoading {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(!macStatus.isCommandAvailable || vm.isLoading)
                }
            }
            .task(id: profileKey) {
                vm.applyConnection(appState.profile)
                if macStatus.isCommandAvailable {
                    await vm.loadTasks()
                }
            }
            .refreshable {
                await vm.loadTasks()
            }
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        focusedField = nil
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            await vm.loadTasks()
                        }
                    } label: {
                        if vm.isLoading {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(!macStatus.isCommandAvailable || vm.isLoading)
                }
            }
        }
    }

    private var macStatusSection: some View {
        Section {
            HStack(spacing: 8) {
                Circle()
                    .fill(macStatus.statusColor)
                    .frame(width: 10, height: 10)

                VStack(alignment: .leading, spacing: 2) {
                    Text(macStatus.statusText)
                        .font(.subheadline.weight(.medium))

                    Text(vm.statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
        }
    }

    private var addTaskSection: some View {
        Section("Add Task") {
            TextField("Task title", text: $vm.newTaskTitle)
                .focused($focusedField, equals: .title)
                .submitLabel(.next)
                .onSubmit {
                    focusedField = .notes
                }

            TextField("Notes", text: $vm.newTaskNotes, axis: .vertical)
                .lineLimit(2...5)
                .focused($focusedField, equals: .notes)
                .submitLabel(.done)
                .onSubmit {
                    focusedField = nil
                }

            Button {
                Task {
                    await vm.addTask()
                    focusedField = nil
                }
            } label: {
                if vm.isAdding {
                    ProgressView()
                } else {
                    Label("Add to Mac", systemImage: "plus.circle.fill")
                }
            }
            .disabled(
                !macStatus.isCommandAvailable ||
                vm.isAdding ||
                vm.newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
        }
    }

    private var tasksSection: some View {
        Section("Open Tasks") {
            if !macStatus.isCommandAvailable {
                ContentUnavailableView(
                    "Mac is offline",
                    systemImage: "desktopcomputer.trianglebadge.exclamationmark",
                    description: Text("Open Astra on your Mac to load tasks.")
                )
            } else if vm.isLoading && vm.tasks.isEmpty {
                HStack {
                    ProgressView()
                    Text("Loading...")
                        .foregroundStyle(.secondary)
                }
            } else if vm.tasks.isEmpty {
                ContentUnavailableView(
                    "No Tasks",
                    systemImage: "checklist",
                    description: Text("Add your first task from iPhone or Mac.")
                )
            } else {
                ForEach(vm.tasks) { task in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Button {
                                Task {
                                    await vm.setDone(task: task, isDone: !task.isDone)
                                }
                            } label: {
                                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(task.isDone ? .green : .secondary)
                            }
                            .buttonStyle(.plain)
                            .disabled(!macStatus.isCommandAvailable)

                            Text(task.title)
                                .font(.headline)
                                .strikethrough(task.isDone)

                            Spacer()

                            Menu {
                                Button(task.isDone ? "Mark as Open" : "Mark as Done") {
                                    Task {
                                        await vm.setDone(task: task, isDone: !task.isDone)
                                    }
                                }

                                Button("Delete", role: .destructive) {
                                    Task {
                                        await vm.delete(task: task)
                                    }
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if !task.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(task.notes)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        if let createdAt = task.createdAt {
                            Text(createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
}
