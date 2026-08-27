//
//  DependencyChecker.swift
//  AstraAssistant
//
//  Created by Alex on 10/8/26.
//

import Foundation
import AVFoundation
import Speech

final class DependencyChecker {
    private let ollama = OllamaClient.shared
    private let keychain = KeychainStore.shared
    
    func quickCheckOllama() async -> Bool {
            return await ollama.isRunning()
        }
    
    

    func run(settings: AssistantSettings) async -> DependencyReport {
        var items: [DependencyCheckItem] = []

        // MARK: - Ollama

        let ollamaRunning = await ollama.isRunning()

        if ollamaRunning {
            items.append(
                DependencyCheckItem(
                    title: "Ollama",
                    status: .ok,
                    details: "Ollama is running on 127.0.0.1:11434.",
                    instruction: nil
                )
            )
        } else {
            items.append(
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
            )
            
            return DependencyReport(items: items)
        }

        // MARK: - Ollama Models

        do {
            let models = try await ollama.listModels()
            let modelNames = Set(models.map { $0.name })

            if models.isEmpty {
                items.append(
                    DependencyCheckItem(
                        title: "Ollama models",
                        status: .missing,
                        details: "No Ollama models are installed.",
                        instruction: """
                        Install recommended models:

                        Chat:
                        ollama pull qwen2.5:14b

                        Embeddings:
                        ollama pull nomic-embed-text

                        Vision:
                        ollama pull llama3.2-vision
                        """
                    )
                )
            } else {
                items.append(
                    DependencyCheckItem(
                        title: "Ollama models",
                        status: .ok,
                        details: "Found \(models.count) installed model(s).",
                        instruction: nil
                    )
                )
            }

            // Chat model
            if settings.selectedChatModel.isEmpty {
                items.append(
                    DependencyCheckItem(
                        title: "Selected chat model",
                        status: .warning,
                        details: "No chat model selected.",
                        instruction: "Open Settings → AI Model and select an installed Ollama model."
                    )
                )
            } else if modelNames.contains(settings.selectedChatModel) {
                items.append(
                    DependencyCheckItem(
                        title: "Selected chat model",
                        status: .ok,
                        details: settings.selectedChatModel,
                        instruction: nil
                    )
                )
            } else {
                items.append(
                    DependencyCheckItem(
                        title: "Selected chat model",
                        status: .missing,
                        details: "Selected model is not installed: \(settings.selectedChatModel)",
                        instruction: """
                        Install it with:

                        ollama pull \(settings.selectedChatModel)

                        Or choose another installed model in Settings.
                        """
                    )
                )
            }

            // Embedding model
            if settings.selectedEmbeddingModel.isEmpty {
                items.append(
                    DependencyCheckItem(
                        title: "Embedding model",
                        status: .missing,
                        details: "No embedding model selected.",
                        instruction: """
                        Install and select an embedding model:

                        ollama pull nomic-embed-text
                        """
                    )
                )
            } else if modelNames.contains(settings.selectedEmbeddingModel) {
                items.append(
                    DependencyCheckItem(
                        title: "Embedding model",
                        status: .ok,
                        details: settings.selectedEmbeddingModel,
                        instruction: nil
                    )
                )
            } else {
                items.append(
                    DependencyCheckItem(
                        title: "Embedding model",
                        status: .missing,
                        details: "Embedding model is not installed: \(settings.selectedEmbeddingModel)",
                        instruction: """
                        Install it with:

                        ollama pull \(settings.selectedEmbeddingModel)

                        Recommended:
                        ollama pull nomic-embed-text
                        """
                    )
                )
            }

            // Vision model
            if settings.selectedVisionModel.isEmpty {
                items.append(
                    DependencyCheckItem(
                        title: "Vision model",
                        status: .warning,
                        details: "No local vision model selected.",
                        instruction: """
                        Image analysis will be disabled until you choose a local Ollama vision model.

                        Recommended:
                        ollama pull llama3.2-vision

                        Alternative:
                        ollama pull llava
                        """
                    )
                )
            } else if modelNames.contains(settings.selectedVisionModel) {
                items.append(
                    DependencyCheckItem(
                        title: "Selected vision model",
                        status: .ok,
                        details: settings.selectedVisionModel,
                        instruction: nil
                    )
                )
            } else {
                items.append(
                    DependencyCheckItem(
                        title: "Selected vision model",
                        status: .missing,
                        details: "Selected vision model is not installed: \(settings.selectedVisionModel)",
                        instruction: """
                        Install it with:

                        ollama pull \(settings.selectedVisionModel)

                        Recommended:
                        ollama pull llama3.2-vision
                        """
                    )
                )
            }

        } catch {
            items.append(
                DependencyCheckItem(
                    title: "Ollama model check",
                    status: .missing,
                    details: error.localizedDescription,
                    instruction: "Restart Ollama and try again."
                )
            )
        }

        // MARK: - Microphone Permission

        let microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)

        switch microphoneStatus {
        case .authorized:
            items.append(
                DependencyCheckItem(
                    title: "Microphone permission",
                    status: .ok,
                    details: "Microphone access granted.",
                    instruction: nil
                )
            )

        case .notDetermined:
            items.append(
                DependencyCheckItem(
                    title: "Microphone permission",
                    status: .warning,
                    details: "Microphone permission has not been requested yet.",
                    instruction: "Astra Assistant will ask for microphone permission when voice mode starts."
                )
            )

        default:
            items.append(
                DependencyCheckItem(
                    title: "Microphone permission",
                    status: .missing,
                    details: "Microphone access is denied.",
                    instruction: """
                    Open:

                    System Settings → Privacy & Security → Microphone

                    Enable access for Astra Assistant.
                    """
                )
            )
        }

        // MARK: - Speech Recognition Permission

        let speechStatus = SFSpeechRecognizer.authorizationStatus()

        switch speechStatus {
        case .authorized:
            items.append(
                DependencyCheckItem(
                    title: "Speech Recognition",
                    status: .ok,
                    details: "Speech recognition access granted.",
                    instruction: nil
                )
            )

        case .notDetermined:
            items.append(
                DependencyCheckItem(
                    title: "Speech Recognition",
                    status: .warning,
                    details: "Speech recognition permission has not been requested yet.",
                    instruction: "Astra Assistant will ask for speech recognition permission when voice mode starts."
                )
            )

        default:
            items.append(
                DependencyCheckItem(
                    title: "Speech Recognition",
                    status: .missing,
                    details: "Speech recognition access is denied.",
                    instruction: """
                    Open:

                    System Settings → Privacy & Security → Speech Recognition

                    Enable access for Astra Assistant.
                    """
                )
            )
        }

        // MARK: - OpenAI Images

        if settings.enableOpenAIImages {
            if let key = keychain.getOpenAIKey(), !key.isEmpty {
                items.append(
                    DependencyCheckItem(
                        title: "OpenAI API key",
                        status: .ok,
                        details: "OpenAI API key is configured for image generation and editing.",
                        instruction: nil
                    )
                )
            } else {
                items.append(
                    DependencyCheckItem(
                        title: "OpenAI API key",
                        status: .missing,
                        details: "OpenAI image features are enabled but API key is missing.",
                        instruction: """
                        Open Settings → OpenAI Images and paste your API key.

                        Create a key here:
                        https://platform.openai.com/api-keys
                        """
                    )
                )
            }
        }

        // MARK: - TTS Provider

        switch settings.ttsProvider {
        case .macOS:
            items.append(
                DependencyCheckItem(
                    title: "macOS Text-to-Speech",
                    status: .ok,
                    details: "Native macOS speech engine is available.",
                    instruction: nil
                )
            )
            
        case .localQwen3:
            let projectPath = settings.localQwenProjectPath
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if projectPath.isEmpty {
                items.append(
                    DependencyCheckItem(
                        title: "Local Qwen3 TTS",
                        status: .missing,
                        details: "Local Qwen project path is empty.",
                        instruction: """
                        Open Settings → Voice → Local Qwen3 TTS.

                        Set project folder, for example:
                        /Users/alex/Downloads/qwen3-tts-apple-silicon

                        The folder must contain:
                        - .venv/bin/python
                        - astra_tts_cli.py
                        - models/
                        """
                    )
                )
            } else {
                let projectURL = URL(fileURLWithPath: projectPath, isDirectory: true)
                let pythonURL = settings.localQwenPythonPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? projectURL.appendingPathComponent(".venv/bin/python")
                    : URL(fileURLWithPath: settings.localQwenPythonPath)

                let scriptURL = projectURL.appendingPathComponent("astra_tts_cli.py")
                let modelURL = projectURL
                    .appendingPathComponent("models")
                    .appendingPathComponent(settings.localQwenModelFolder)

                let hasProject = FileManager.default.fileExists(atPath: projectURL.path)
                let hasPython = FileManager.default.fileExists(atPath: pythonURL.path)
                let hasScript = FileManager.default.fileExists(atPath: scriptURL.path)
                let hasModel = FileManager.default.fileExists(atPath: modelURL.path)

                if hasProject && hasPython && hasScript && hasModel {
                    items.append(
                        DependencyCheckItem(
                            title: "Local Qwen3 TTS",
                            status: .ok,
                            details: """
                            Local Qwen3 TTS files found.
                            Mode: \(settings.localQwenMode.title)
                            Model: \(settings.localQwenModelFolder)
                            """,
                            instruction: nil
                        )
                    )
                } else {
                    var details = ""

                    details += "Project: \(hasProject ? "OK" : "MISSING")\n"
                    details += "Python: \(hasPython ? "OK" : "MISSING") — \(pythonURL.path)\n"
                    details += "Script: \(hasScript ? "OK" : "MISSING") — \(scriptURL.path)\n"
                    details += "Model: \(hasModel ? "OK" : "MISSING") — \(modelURL.path)"

                    items.append(
                        DependencyCheckItem(
                            title: "Local Qwen3 TTS",
                            status: .missing,
                            details: details,
                            instruction: """
                            Make sure your Qwen3 TTS project folder is correct.

                            Required:
                            1. Project folder path points to qwen3-tts-apple-silicon.
                            2. Python exists at .venv/bin/python.
                            3. astra_tts_cli.py is copied into that folder.
                            4. Selected model folder exists in models/.
                            """
                        )
                    )
                }

                if settings.localQwenMode == .voiceCloning {
                    let refAudio = settings.localQwenReferenceAudioPath
                        .trimmingCharacters(in: .whitespacesAndNewlines)

                    if refAudio.isEmpty {
                        items.append(
                            DependencyCheckItem(
                                title: "Local Qwen3 reference audio",
                                status: .missing,
                                details: "Reference audio path is empty.",
                                instruction: "Set a local WAV reference audio file in Settings → Voice."
                            )
                        )
                    } else if FileManager.default.fileExists(atPath: refAudio) {
                        items.append(
                            DependencyCheckItem(
                                title: "Local Qwen3 reference audio",
                                status: .ok,
                                details: refAudio,
                                instruction: nil
                            )
                        )
                    } else {
                        items.append(
                            DependencyCheckItem(
                                title: "Local Qwen3 reference audio",
                                status: .missing,
                                details: "Reference audio does not exist: \(refAudio)",
                                instruction: "Choose an existing local WAV file."
                            )
                        )
                    }
                }

                if settings.localQwenMode == .customVoice {
                    items.append(
                        DependencyCheckItem(
                            title: "Local Qwen3 custom speaker",
                            status: .ok,
                            details: "Speaker: \(settings.localQwenSpeaker)",
                            instruction: nil
                        )
                    )
                }

                if settings.localQwenMode == .voiceDesign {
                    let instruct = settings.localQwenInstruct
                        .trimmingCharacters(in: .whitespacesAndNewlines)

                    items.append(
                        DependencyCheckItem(
                            title: "Local Qwen3 voice design prompt",
                            status: instruct.isEmpty ? .warning : .ok,
                            details: instruct.isEmpty ? "Voice design instruction is empty." : instruct,
                            instruction: instruct.isEmpty ? "Describe the voice in Settings → Voice." : nil
                        )
                    )
                }
            }
            let isRunning = await TTSProcessManager.shared.isServerReady()
                if isRunning {
                    items.append(
                        DependencyCheckItem(
                            title: "Local Qwen3 TTS Server",
                            status: .ok,
                            details: "TTS server is running on localhost:8765.",
                            instruction: nil
                        )
                    )
                } else {
                    items.append(
                        DependencyCheckItem(
                            title: "Local Qwen3 TTS Server",
                            status: .missing,
                            details: "TTS server is not running.",
                            instruction: """
                            The server will start automatically when needed.
                            If it doesn't start, try:
                            1. Check that the project path is correct in Settings.
                            2. Click 'Restart Server' in Settings → Voice.
                            3. Check logs in Console for more details.
                            """
                        )
                    )
                }

        case .waveSpeedQwen3:
            let referenceAudioURL = settings.waveSpeedReferenceAudioURL
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if let key = keychain.getWaveSpeedKey(), !key.isEmpty {
                items.append(
                    DependencyCheckItem(
                        title: "WaveSpeed API key",
                        status: .ok,
                        details: "WaveSpeed API key is configured in Keychain.",
                        instruction: nil
                    )
                )
            } else {
                items.append(
                    DependencyCheckItem(
                        title: "WaveSpeed API key",
                        status: .missing,
                        details: "WaveSpeed API key is missing.",
                        instruction: """
                        Open Settings → Voice and paste your WaveSpeed API key.

                        The key is stored locally in macOS Keychain.
                        """
                    )
                )
            }

            if referenceAudioURL.isEmpty {
                items.append(
                    DependencyCheckItem(
                        title: "WaveSpeed reference audio",
                        status: .missing,
                        details: "Reference audio URL is empty.",
                        instruction: """
                        WaveSpeed requires a public URL to the reference voice audio.

                        Upload your reference WAV/MP3 to:
                        - Cloudflare R2
                        - S3
                        - Supabase Storage
                        - Vercel Blob
                        - another public file host

                        Then paste the public audio URL in Settings.
                        """
                    )
                )
            } else if isProbablyHTTPURL(referenceAudioURL) {
                items.append(
                    DependencyCheckItem(
                        title: "WaveSpeed reference audio",
                        status: .ok,
                        details: referenceAudioURL,
                        instruction: nil
                    )
                )
            } else {
                items.append(
                    DependencyCheckItem(
                        title: "WaveSpeed reference audio",
                        status: .missing,
                        details: "Reference audio must be a public HTTP/HTTPS URL.",
                        instruction: """
                        Invalid value:
                        \(referenceAudioURL)

                        WaveSpeed cannot access local files like:
                        /Users/alex/voice.wav

                        Use a public URL:
                        https://example.com/voice.wav
                        """
                    )
                )
            }
        }

        return DependencyReport(items: items)
    }

    // MARK: - WaveSpeed Backend Check

    private enum BackendCheckResult {
        case ok(String)
        case warning(String, String)
        case missing(String, String)
    }

    private func checkWaveSpeedBackend(baseURL: String) async -> BackendCheckResult {
        let normalizedBase = baseURL.hasSuffix("/")
            ? String(baseURL.dropLast())
            : baseURL

        guard let url = URL(string: "\(normalizedBase)/api/health") else {
            return .missing(
                "Invalid backend URL.",
                """
                Check Settings → Voice → Backend URL.

                Example:
                https://astra-tts-api.vercel.app
                """
            )
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse else {
                return .missing(
                    "Invalid response from backend.",
                    "Make sure your Vercel backend is deployed correctly."
                )
            }

            guard 200..<300 ~= http.statusCode else {
                let body = String(data: data, encoding: .utf8) ?? ""

                return .missing(
                    "Backend returned HTTP \(http.statusCode).",
                    """
                    Check your backend deployment.

                    Response:
                    \(body)
                    """
                )
            }

            let decoded = try JSONDecoder().decode(WaveSpeedHealthResponse.self, from: data)

            guard decoded.ok else {
                return .missing(
                    "Backend health check returned ok=false.",
                    "Open your Vercel logs and check the Flask API."
                )
            }

            if decoded.wavespeed_key_configured == true {
                return .ok("Backend is reachable and WAVESPEED_API_KEY is configured.")
            } else {
                return .missing(
                    "Backend is reachable, but WAVESPEED_API_KEY is not configured.",
                    """
                    Add the environment variable in Vercel:

                    WAVESPEED_API_KEY=your-api-key

                    Then redeploy:

                    vercel --prod
                    """
                )
            }

        } catch {
            return .missing(
                "Cannot reach WaveSpeed backend.",
                """
                Error:
                \(error.localizedDescription)

                Make sure your backend URL is correct and deployed.

                Example:
                https://astra-tts-api.vercel.app/api/health
                """
            )
        }
    }

    private func isProbablyHTTPURL(_ value: String) -> Bool {
        guard let url = URL(string: value) else {
            return false
        }

        return url.scheme == "http" || url.scheme == "https"
    }
}

private struct WaveSpeedHealthResponse: Codable {
    let ok: Bool
    let service: String?
    let wavespeed_key_configured: Bool?
}
