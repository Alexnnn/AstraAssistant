//
//  AppViewModel.swift
//  AstraAssistant
//
//  Created by Alex on 10/8/26.
//

import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import FirebaseCore



@MainActor
final class AppViewModel: ObservableObject {
    @Published var dependencyReport: DependencyReport?
    @Published var installedModels: [OllamaModel] = []

    // For regular UI refreshes
    @Published var isLoading = false

    // Startup-only loading
    @Published var isStartupLoading = false

    @Published var startupError: String?
    
    @Published var isTTSServerReady = false
    @Published var ttsServerError: String?
        
    private let ttsProcessManager = TTSProcessManager.shared

    let settingsStore = SettingsStore()

    private var diagnosticsTask: Task<Void, Never>?
    private var hasStarted = false

    private let dependencyChecker = DependencyChecker()
    private let ollama = OllamaClient.shared

    // Companion
    private let firebaseCompanion = FirebaseCompanionService.shared
    private var commandExecutor: DefaultMacCommandExecutor?

    private var cancellables = Set<AnyCancellable>()

    init() {
        settingsStore.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    
        NotificationCenter.default.addObserver(
                forName: UserDefaults.didChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                // Проверяем, изменился ли TTS провайдер
                Task { [weak self] in
                    await self?.handleTTSSettingsChange()
                }
            }
        }
    
    @MainActor
    private func handleTTSSettingsChange() async {
        let settings = settingsStore.settings
        
        if settings.ttsProvider == .localQwen3 {
            await startTTSServerIfNeeded()
        } else {
            stopTTSServer()
        }
    }

    func refreshDiagnosticsDebounced() {
        diagnosticsTask?.cancel()
        diagnosticsTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            await self?.refreshDiagnostics()
        }
    }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true

        isStartupLoading = true
        defer { isStartupLoading = false }

        // Start Firebase companion first (non-fatal)
        await firebaseCompanion.start()
        if let uid = firebaseCompanion.uid {
            let executor = DefaultMacCommandExecutor(settingsStore: settingsStore)
            commandExecutor = executor

            await MacCommandBusService.shared.start(
                uid: uid,
                deviceId: firebaseCompanion.deviceId,
                executor: executor
            )
        } else if let err = firebaseCompanion.lastError {
            print("FirebaseCompanion start warning:", err)
        }
        
        if let uid = firebaseCompanion.uid {
            // one-time backfill at startup
            await ConversationCloudMirrorService.shared.fullBackfill(uid: uid)

            // incremental sync on conversation changes
            NotificationCenter.default.publisher(for: .conversationStoreDidChange)
                .sink { note in
                    guard let raw = note.userInfo?["conversationId"] as? String,
                          let id = UUID(uuidString: raw),
                          let uid = self.firebaseCompanion.uid else { return }

                    Task {
                        await ConversationCloudMirrorService.shared.syncConversation(uid: uid, conversationId: id)
                    }
                }
                .store(in: &cancellables)
        }
        
        
        

        // Ollama preflight
        let ollamaRunning = await withTimeout(seconds: 6) { [ollama] in
            await ollama.isRunning()
        } ?? false

        if !ollamaRunning {
            dependencyReport = DependencyReport(items: [
                DependencyCheckItem(
                    title: "Ollama",
                    status: .missing,
                    details: "Ollama is not running or not installed.",
                    instruction: """
                    Install Ollama from:
                    https://ollama.com

                    Then run:
                    ollama serve

                    Recommended chat model:
                    ollama pull qwen2.5:14b

                    Recommended embedding model:
                    ollama pull nomic-embed-text

                    Recommended vision model:
                    ollama pull llama3.2-vision
                    """
                )
            ])

            installedModels = []
            startupError = "Ollama unavailable. App started in limited mode."
            return
        }

        await startTTSServerIfNeeded()
        
        await refreshDiagnostics()
        await refreshModels()
    }
    
    

    func forceFinishLoadingIfNeeded() {
        if isStartupLoading {
            isStartupLoading = false
        }

        if dependencyReport == nil {
            dependencyReport = DependencyReport(items: [
                DependencyCheckItem(
                    title: "Startup fallback",
                    status: .warning,
                    details: "Startup checks took too long. App started in limited mode.",
                    instruction: "Open Diagnostics and run checks again."
                )
            ])
        }
    }

    func refreshDiagnostics() async {
        isLoading = true
        defer { isLoading = false }

        let report = await withTimeout(seconds: 12) { [self] in
            await self.dependencyChecker.run(settings: self.settingsStore.settings)
        } ?? DependencyReport(items: [
            DependencyCheckItem(
                title: "Diagnostics timeout",
                status: .missing,
                details: "Diagnostics check timed out.",
                instruction: "Check your network connection and try again."
            )
        ])

        dependencyReport = report
    }

    private func withTimeout<T>(
        seconds: Double,
        operation: @escaping () async -> T
    ) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await operation() }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return nil
            }

            for await result in group {
                if let result = result {
                    group.cancelAll()
                    return result
                }
            }
            return nil
        }
    }

    func refreshModels() async {
        let models: [OllamaModel]? = (await withTimeout(seconds: 10) { [ollama] in
            try? await ollama.listModels()
        }) ?? nil

        if let models {
            installedModels = models
            startupError = nil
        } else {
            installedModels = []
            startupError = "Unable to load models. Make sure Ollama is running."
        }
    }

    func selectChatModel(_ model: String) {
        settingsStore.update { $0.selectedChatModel = model }
        refreshDiagnosticsDebounced()
    }

    func selectEmbeddingModel(_ model: String) {
        settingsStore.update { $0.selectedEmbeddingModel = model }
        refreshDiagnosticsDebounced()
    }

    func selectVisionModel(_ model: String) {
        settingsStore.update { $0.selectedVisionModel = model }
        refreshDiagnosticsDebounced()
    }
    
    func startTTSServerIfNeeded() async {
            let settings = settingsStore.settings
            
            guard settings.ttsProvider == .localQwen3 else {
                isTTSServerReady = true // Другие провайдеры не требуют сервера
                return
            }
            
            let projectPath = settings.localQwenProjectPath
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            guard !projectPath.isEmpty else {
                ttsServerError = "Local Qwen project path is not set. Please configure it in Settings."
                isTTSServerReady = false
                return
            }
            
            do {
                try await ttsProcessManager.startIfNeeded(projectPath: projectPath)
                isTTSServerReady = true
                ttsServerError = nil
                print("✅ TTS Server started successfully")
            } catch {
                ttsServerError = error.localizedDescription
                isTTSServerReady = false
                print("❌ TTS Server failed to start:", error.localizedDescription)
            }
        }
        
        func stopTTSServer() {
            ttsProcessManager.stop()
            isTTSServerReady = false
        }
        
        func restartTTSServer() async {
            stopTTSServer()
            try? await Task.sleep(nanoseconds: 500_000_000)
            await startTTSServerIfNeeded()
        }
    
}
