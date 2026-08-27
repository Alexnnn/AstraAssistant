//
//  LocalQwenTTSClient.swift
//  Astra AI Assistant
//
//  Created by Alex on 22/8/26.
//

import Foundation

private final class LocalQwenProcessState {
    private let lock = NSLock()
    private var didResume = false
    private var didTimeout = false

    func markTimeout() {
        lock.lock()
        didTimeout = true
        lock.unlock()
    }

    func isTimedOut() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return didTimeout
    }

    func tryMarkResumed() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        if didResume {
            return false
        }

        didResume = true
        return true
    }
}

final class LocalQwenTTSClient {
    static let shared = LocalQwenTTSClient()
    private init() {}

    func synthesizeSpeech(
        text: String,
        settings: AssistantSettings
    ) async throws -> Data {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanText.isEmpty else {
            throw NSError(
                domain: "LocalQwenTTSClient",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Text is empty."]
            )
        }

        let projectPath = settings.localQwenProjectPath
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !projectPath.isEmpty else {
            throw NSError(
                domain: "LocalQwenTTSClient",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Local Qwen project path is empty."]
            )
        }

        let projectURL = URL(fileURLWithPath: projectPath, isDirectory: true)

        guard FileManager.default.fileExists(atPath: projectURL.path) else {
            throw NSError(
                domain: "LocalQwenTTSClient",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Local Qwen project folder does not exist: \(projectURL.path)"]
            )
        }

        // Сначала пробуем быстрый локальный HTTP-сервер.
        // Если сервер не запущен, fallback ниже пойдёт в старый CLI через Process().
        do {
            return try await synthesizeViaLocalServer(
                text: cleanText,
                projectURL: projectURL,
                settings: settings
            )
        } catch let error as URLError {
            // Сервер не запущен или недоступен — используем старый CLI fallback.
            print("Local Qwen TTS server unavailable, falling back to CLI:", error.localizedDescription)
        } catch {
            // Если сервер ответил ошибкой, не маскируем её CLI fallback'ом.
            throw error
        }

        let scriptURL = projectURL.appendingPathComponent("astra_tts_cli.py")

        guard FileManager.default.fileExists(atPath: scriptURL.path) else {
            throw NSError(
                domain: "LocalQwenTTSClient",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "astra_tts_cli.py not found in project folder."]
            )
        }

        let pythonPath = settings.localQwenPythonPath
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let pythonURL: URL

        if pythonPath.isEmpty {
            pythonURL = projectURL
                .appendingPathComponent(".venv")
                .appendingPathComponent("bin")
                .appendingPathComponent("python")
        } else {
            pythonURL = URL(fileURLWithPath: pythonPath)
        }

        guard FileManager.default.fileExists(atPath: pythonURL.path) else {
            throw NSError(
                domain: "LocalQwenTTSClient",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Python executable not found: \(pythonURL.path)"]
            )
        }

        let tempDir = FileManager.default.temporaryDirectory

        let textFileURL = tempDir.appendingPathComponent("astra-qwen-input-\(UUID().uuidString).txt")
        let outputURL = tempDir.appendingPathComponent("astra-qwen-output-\(UUID().uuidString).wav")

        try cleanText.write(to: textFileURL, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: textFileURL)
        }

        var arguments: [String] = [
            scriptURL.path,
            "--text-file", textFileURL.path,
            "--out", outputURL.path,
            "--model-folder", settings.localQwenModelFolder,
            "--mode", settings.localQwenMode.cliValue,
            "--speed", String(settings.localQwenSpeed)
        ]
        
        switch settings.localQwenMode {
        case .voiceCloning:
            let refAudio = settings.localQwenReferenceAudioPath
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !refAudio.isEmpty else {
                throw NSError(
                    domain: "LocalQwenTTSClient",
                    code: 6,
                    userInfo: [NSLocalizedDescriptionKey: "Voice Cloning mode requires reference audio path."]
                )
            }

            arguments.append(contentsOf: ["--ref-audio", refAudio])

            let refText = settings.localQwenReferenceText
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if !refText.isEmpty {
                arguments.append(contentsOf: ["--ref-text", refText])
            }

        case .customVoice:
            let speaker = settings.localQwenSpeaker
                .trimmingCharacters(in: .whitespacesAndNewlines)

            arguments.append(contentsOf: [
                "--voice", speaker.isEmpty ? "Vivian" : speaker
            ])

            let instruct = settings.localQwenInstruct
                .trimmingCharacters(in: .whitespacesAndNewlines)

            arguments.append(contentsOf: [
                "--instruct", instruct.isEmpty ? "Normal tone" : instruct
            ])

        case .voiceDesign:
            let instruct = settings.localQwenInstruct
                .trimmingCharacters(in: .whitespacesAndNewlines)

            arguments.append(contentsOf: [
                "--instruct", instruct.isEmpty ? "A natural friendly voice" : instruct
            ])
        }

        try await runPython(
            pythonURL: pythonURL,
            projectURL: projectURL,
            arguments: arguments,
            timeoutSeconds: settings.localQwenMaxWaitSeconds
        )

        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw NSError(
                domain: "LocalQwenTTSClient",
                code: 5,
                userInfo: [NSLocalizedDescriptionKey: "Local Qwen did not produce output WAV."]
            )
        }

        let data = try Data(contentsOf: outputURL)

        try? FileManager.default.removeItem(at: outputURL)

        return data
    }
    
    private func synthesizeViaLocalServer(
        text: String,
        projectURL: URL,
        settings: AssistantSettings
    ) async throws -> Data {
        guard let url = URL(string: "http://127.0.0.1:8765/speak") else {
            throw URLError(.badURL)
        }

        var payload: [String: Any] = [
            "text": text,
            "models_dir": projectURL.appendingPathComponent("models", isDirectory: true).path,
            "model_folder": settings.localQwenModelFolder,
            "mode": settings.localQwenMode.cliValue,
            "speed": settings.localQwenSpeed,
            "language": localQwenLanguageCode(from: settings.assistantLanguage)
        ]

        switch settings.localQwenMode {
        case .voiceCloning:
            let refAudio = settings.localQwenReferenceAudioPath
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !refAudio.isEmpty else {
                throw NSError(
                    domain: "LocalQwenTTSClient",
                    code: 6,
                    userInfo: [NSLocalizedDescriptionKey: "Voice Cloning mode requires reference audio path."]
                )
            }

            payload["ref_audio"] = refAudio

            let refText = settings.localQwenReferenceText
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if !refText.isEmpty {
                payload["ref_text"] = refText
            }

        case .customVoice:
            let speaker = settings.localQwenSpeaker
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let instruct = settings.localQwenInstruct
                .trimmingCharacters(in: .whitespacesAndNewlines)

            payload["voice"] = speaker.isEmpty ? "Vivian" : speaker
            payload["instruct"] = instruct.isEmpty ? "Normal tone" : instruct

        case .voiceDesign:
            let instruct = settings.localQwenInstruct
                .trimmingCharacters(in: .whitespacesAndNewlines)

            payload["instruct"] = instruct.isEmpty ? "A natural friendly voice" : instruct
        }

        let body = try JSONSerialization.data(withJSONObject: payload)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = TimeInterval(max(20, settings.localQwenMaxWaitSeconds))
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard 200..<300 ~= http.statusCode else {
            let bodyText = String(data: data, encoding: .utf8) ?? ""

            throw NSError(
                domain: "LocalQwenTTSServer",
                code: http.statusCode,
                userInfo: [
                    NSLocalizedDescriptionKey: """
                    Local Qwen TTS server returned HTTP \(http.statusCode).

                    Response:
                    \(bodyText)
                    """
                ]
            )
        }

        return data
    }
    
    private func localQwenLanguageCode(from value: String) -> String {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if normalized.hasPrefix("ru") {
            return "ru"
        }

        if normalized.hasPrefix("en") {
            return "en"
        }

        if normalized.hasPrefix("de") {
            return "de"
        }

        if normalized.hasPrefix("fr") {
            return "fr"
        }

        if normalized.hasPrefix("es") {
            return "es"
        }

        if normalized.hasPrefix("it") {
            return "it"
        }

        if normalized.hasPrefix("pt") {
            return "pt"
        }

        return "en"
    }
    
    

    private func runPython(
        pythonURL: URL,
        projectURL: URL,
        arguments: [String],
        timeoutSeconds: Int
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = pythonURL
            process.arguments = arguments
            process.currentDirectoryURL = projectURL

            var env = ProcessInfo.processInfo.environment
            env["TOKENIZERS_PARALLELISM"] = "false"
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
            process.environment = env

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()

            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            let state = LocalQwenProcessState()

            func finishSuccess() {
                guard state.tryMarkResumed() else { return }
                continuation.resume(returning: ())
            }

            func finishFailure(_ error: Error) {
                guard state.tryMarkResumed() else { return }
                continuation.resume(throwing: error)
            }

            process.terminationHandler = { proc in
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                let stderr = String(data: stderrData, encoding: .utf8) ?? ""

                if proc.terminationStatus == 0 {
                    finishSuccess()
                    return
                }

                let message: String

                if state.isTimedOut() {
                    message = """
                    Local Qwen TTS timeout after \(timeoutSeconds)s.

                    STDOUT:
                    \(stdout)

                    STDERR:
                    \(stderr)
                    """
                } else {
                    message = """
                    Local Qwen TTS failed with exit code \(proc.terminationStatus).

                    STDOUT:
                    \(stdout)

                    STDERR:
                    \(stderr)
                    """
                }

                let nsError = NSError(
                    domain: "LocalQwenTTSClient",
                    code: Int(proc.terminationStatus),
                    userInfo: [
                        NSLocalizedDescriptionKey: message
                    ]
                )

                finishFailure(nsError)
            }

            do {
                try process.run()
            } catch {
                finishFailure(error)
                return
            }

            Task.detached {
                let seconds = max(20, timeoutSeconds)
                try? await Task.sleep(
                    nanoseconds: UInt64(seconds) * 1_000_000_000
                )

                if process.isRunning {
                    state.markTimeout()
                    process.terminate()
                }
            }
        }
    }
}
