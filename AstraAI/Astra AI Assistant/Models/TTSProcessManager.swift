//
//  TTSProcessManager.swift
//  Astra AI Assistant
//
//  Created by Alex on 23/8/26.
//


import Foundation
import AppKit

/// Управляет запуском и остановкой локального Python-сервера для Qwen3 TTS
final class TTSProcessManager {
    static let shared = TTSProcessManager()
    private init() {}
    
    private var process: Process?
    private var isRunning = false
    private var healthCheckTask: Task<Void, Never>?
    private var isHealthCheckActive = false
    
    // MARK: - Public API
    
    /// Запускает TTS сервер, если он ещё не запущен
    func startIfNeeded(projectPath: String) async throws {
        let trimmedPath = projectPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            throw TTSProcessError.emptyProjectPath
        }
        
        // Сначала проверяем, не запущен ли уже сервер
        if await isServerRunning() {
            isRunning = true
            return
        }
        
        // Проверяем наличие файлов
        let projectURL = URL(fileURLWithPath: trimmedPath, isDirectory: true)
        try validateProjectFiles(projectURL: projectURL)
        
        // Убиваем старые процессы, если есть
        killOldProcesses(projectPath: trimmedPath)
        
        // Запускаем сервер
        try await startServer(projectURL: projectURL)
        
        // Ждём, пока сервер поднимется
        try await waitForServer(maxAttempts: 30, delay: 0.5)
        
        isRunning = true
        startHealthCheck()
    }
    
    /// Останавливает TTS сервер
    func stop() {
        healthCheckTask?.cancel()
        healthCheckTask = nil
        isHealthCheckActive = false
        
        process?.terminate()
        process = nil
        isRunning = false
    }
    
    /// Проверяет, доступен ли сервер
    func isServerReady() async -> Bool {
        return await isServerRunning()
    }
    
    /// Проверяет, все ли файлы на месте
    func validateFiles(projectPath: String) -> Bool {
        let trimmedPath = projectPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return false }
        
        let projectURL = URL(fileURLWithPath: trimmedPath, isDirectory: true)
        
        do {
            try validateProjectFiles(projectURL: projectURL)
            return true
        } catch {
            return false
        }
    }
    
    // MARK: - Private Methods
    
    private func validateProjectFiles(projectURL: URL) throws {
        let fileManager = FileManager.default
        
        // Проверяем, что папка существует
        guard fileManager.fileExists(atPath: projectURL.path) else {
            throw TTSProcessError.projectNotFound(projectURL.path)
        }
        
        // Проверяем Python
        let pythonURL = projectURL.appendingPathComponent(".venv").appendingPathComponent("bin").appendingPathComponent("python")
        guard fileManager.fileExists(atPath: pythonURL.path) else {
            throw TTSProcessError.pythonNotFound(pythonURL.path)
        }
        
        // Проверяем скрипт сервера
        let serverScriptURL = projectURL.appendingPathComponent("astra_tts_server.py")
        guard fileManager.fileExists(atPath: serverScriptURL.path) else {
            throw TTSProcessError.serverScriptNotFound(serverScriptURL.path)
        }
        
        // Проверяем наличие моделей (хотя бы одной)
        let modelsDir = projectURL.appendingPathComponent("models", isDirectory: true)
        guard fileManager.fileExists(atPath: modelsDir.path) else {
            throw TTSProcessError.modelsNotFound
        }
        
        let modelFolders = try fileManager.contentsOfDirectory(atPath: modelsDir.path)
            .filter { !$0.hasPrefix(".") }
        
        guard !modelFolders.isEmpty else {
            throw TTSProcessError.noModelsFound
        }
    }
    
    private func startServer(projectURL: URL) async throws {
        let pythonURL = projectURL.appendingPathComponent(".venv").appendingPathComponent("bin").appendingPathComponent("python")
        let serverScriptURL = projectURL.appendingPathComponent("astra_tts_server.py")
        
        let process = Process()
        process.executableURL = pythonURL
        process.arguments = [serverScriptURL.path, "--port", "8765"]
        process.currentDirectoryURL = projectURL
        
        var env = ProcessInfo.processInfo.environment
        env["TOKENIZERS_PARALLELISM"] = "false"
        env["TQDM_DISABLE"] = "1"
        env["PYTHONUNBUFFERED"] = "1"
        process.environment = env
        
        // Настраиваем вывод для отладки
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        
        // Читаем вывод в фоне для отладки
        Task.detached {
            let handle = stdoutPipe.fileHandleForReading
            handle.readabilityHandler = { handle in
                let data = handle.availableData
                if let str = String(data: data, encoding: .utf8), !str.isEmpty {
                    print("[TTS Server stdout]", str.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
        }
        
        Task.detached {
            let handle = stderrPipe.fileHandleForReading
            handle.readabilityHandler = { handle in
                let data = handle.availableData
                if let str = String(data: data, encoding: .utf8), !str.isEmpty {
                    print("[TTS Server stderr]", str.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
        }
        
        self.process = process
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { [weak self] proc in
                Task { @MainActor in
                    self?.isRunning = false
                    self?.process = nil
                }
                print("TTS Server terminated with code:", proc.terminationStatus)
            }
            
            do {
                try process.run()
                continuation.resume(returning: ())
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    private func killOldProcesses(projectPath: String) {
        // Ищем и убиваем существующие процессы сервера
        let scriptPath = URL(fileURLWithPath: projectPath)
            .appendingPathComponent("astra_tts_server.py")
            .path
        
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        task.arguments = ["-f", scriptPath]
        
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            // Игнорируем ошибки - возможно, процесс уже завершён
        }
    }
    
    private func isServerRunning() async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:8765/health") else {
            return false
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 2
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                return true
            }
        } catch {
            // Сервер недоступен
        }
        
        return false
    }
    
    private func waitForServer(maxAttempts: Int, delay: TimeInterval) async throws {
        var attempts = 0
        
        while attempts < maxAttempts {
            if await isServerRunning() {
                return
            }
            
            attempts += 1
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        
        throw TTSProcessError.serverStartTimeout
    }
    
    private func startHealthCheck() {
        guard !isHealthCheckActive else { return }
        isHealthCheckActive = true
        
        healthCheckTask = Task { [weak self] in
            guard let self else { return }
            
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 секунд
                
                if Task.isCancelled { break }
                
                let available = await self.isServerRunning()
                if !available && self.isRunning {
                    print("TTS Server health check: server unavailable, restarting...")
                    await MainActor.run {
                        self.isRunning = false
                    }
                }
            }
        }
    }
}

// MARK: - Errors

enum TTSProcessError: LocalizedError {
    case emptyProjectPath
    case projectNotFound(String)
    case pythonNotFound(String)
    case serverScriptNotFound(String)
    case modelsNotFound
    case noModelsFound
    case serverStartTimeout
    
    var errorDescription: String? {
        switch self {
        case .emptyProjectPath:
            return "Project path is empty. Please set the path in Settings → Voice → Local Qwen3 TTS."
        case .projectNotFound(let path):
            return "Project folder not found: \(path)"
        case .pythonNotFound(let path):
            return "Python not found at: \(path). Make sure the virtual environment is set up."
        case .serverScriptNotFound(let path):
            return "Server script not found: \(path). Make sure astra_tts_server.py exists in the project folder."
        case .modelsNotFound:
            return "Models folder not found. Make sure the 'models' folder exists in the project."
        case .noModelsFound:
            return "No models found in the 'models' folder. Download and extract at least one model."
        case .serverStartTimeout:
            return "TTS server failed to start within the timeout period."
        }
    }
}
