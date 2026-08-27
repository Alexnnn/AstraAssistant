//
//  DefaultMacCommandExecutor.swift
//  Astra AI Assistant
//
//  Created by Alex on 13/8/26.
//


import Foundation
import FirebaseFirestore
import EventKit

@MainActor
protocol MacCommandExecuting: AnyObject {
    func execute(_ request: CompanionCommandRequest) async throws -> CompanionCommandResult
}

@MainActor
final class DefaultMacCommandExecutor: MacCommandExecuting {
    private let ollama = OllamaClient.shared
    private let settingsStore: SettingsStore
    private let conversations = ConversationStore.shared
    private let tasks = TaskStore.shared
    private let memory = VectorMemoryStore.shared
    private let fileReader = FileReaderService.shared
    private let db = Firestore.firestore()
    
    private let webSearch = WebSearchService.shared
    private let calendarService = CalendarService.shared
    private let ttsProcessManager = TTSProcessManager.shared

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
    }

    func execute(_ request: CompanionCommandRequest) async throws -> CompanionCommandResult {
        switch request.type {
        case .systemPing:
            return CompanionCommandResult(data: [
                "ok": true,
                "message": "pong",
                "timestamp": ISO8601DateFormatter().string(from: Date())
            ])

        case .chatSend:
            return try await executeChatSend(request)

        case .tasksList:
            return executeTasksList()

        case .tasksAdd:
            return try executeTasksAdd(request)
            
        case .tasksSetDone:
            return try executeTasksSetDone(request)

        case .tasksDelete:
            return try executeTasksDelete(request)
            
        case .webSearch:
            return try await executeWebSearch(request)

        case .dailyBriefing:
            return try await executeDailyBriefing(request)

        case .calendarToday:
            return try await executeCalendarToday(request)

        case .imageGenerate:
            return try await executeImageGenerate(request)

        case .imageAnalyze:
            return try await executeImageAnalyze(request)

        case .imageEdit:
            return try await executeImageEdit(request)

        case .fileSummarize:
            return try await executeFileSummarize(request)
            
        case .ttsSynthesize:
            return try await executeTTSSynthesize(request)
            
        case .conversationDelete:
                return try await executeConversationDelete(request)
        }
    }
    
    // MARK: - TTS Synthesize (Updated: supports all TTS providers)
    
    private func executeTTSSynthesize(_ request: CompanionCommandRequest) async throws -> CompanionCommandResult {
        guard let text = request.payload["text"] as? String,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NSError(
                domain: "Companion",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "tts.synthesize requires payload.text"]
            )
        }

        let settings = settingsStore.settings
        let audioData: Data
        
        // Определяем какой TTS провайдер использовать
        switch settings.ttsProvider {
        case .macOS:
            // Используем macOS TTS
            audioData = try await synthesizeWithMacOS(text: text, settings: settings)
            
        case .waveSpeedQwen3:
            // Используем WaveSpeed
            audioData = try await WaveSpeedTTSClient.shared.synthesizeSpeech(
                text: text,
                settings: settings
            )
            
        case .localQwen3:
            // Используем локальный Qwen3
            // Проверяем, что сервер запущен
            let isServerReady = await ttsProcessManager.isServerReady()
            if !isServerReady {
                // Пытаемся запустить сервер
                let projectPath = settings.localQwenProjectPath
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                
                if !projectPath.isEmpty {
                    try await ttsProcessManager.startIfNeeded(projectPath: projectPath)
                } else {
                    throw NSError(
                        domain: "Companion",
                        code: 422,
                        userInfo: [NSLocalizedDescriptionKey: "Local Qwen3 TTS path is not configured on Mac."]
                    )
                }
            }
            
            audioData = try await LocalQwenTTSClient.shared.synthesizeSpeech(
                text: text,
                settings: settings
            )
        }

        // Сохраняем аудио во временный файл
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("astra-ios-tts-\(UUID().uuidString).mp3")

        try audioData.write(to: tempURL, options: .atomic)

        // Загружаем в Firebase Storage
        let publicURL = try await FirebaseStorageService.shared.uploadFile(
            localURL: tempURL,
            purpose: .audio
        )

        // Очищаем временный файл
        try? FileManager.default.removeItem(at: tempURL)

        return CompanionCommandResult(data: [
            "ok": true,
            "assistantText": "",
            "audioURL": publicURL,
            "attachmentURL": publicURL,
            "attachmentType": "audio"
        ])
    }
    
    // MARK: - Conversation Delete

    private func executeConversationDelete(_ request: CompanionCommandRequest) async throws -> CompanionCommandResult {
        guard let conversationId = request.payload["conversationId"] as? String,
              !conversationId.isEmpty else {
            throw NSError(
                domain: "Companion",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "conversation.delete requires payload.conversationId"]
            )
        }
        
        guard let conversationUUID = UUID(uuidString: conversationId) else {
            throw NSError(
                domain: "Companion",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Invalid conversationId format"]
            )
        }
        
        // Удаляем чат
        conversations.deleteConversation(id: conversationUUID)
        
        // Также удаляем удаленный чат из Firestore
        let convRef = db.collection("users")
            .document(request.uid)
            .collection("remoteConversations")
            .document(conversationId)
        
        try await convRef.delete()
        
        return CompanionCommandResult(data: [
            "ok": true,
            "conversationId": conversationId,
            "message": "Conversation deleted"
        ])
    }
    
    
    // MARK: - macOS TTS Helper

    private func synthesizeWithMacOS(text: String, settings: AssistantSettings) async throws -> Data {
        // Создаем временный файл для аудио
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("astra-tts-\(UUID().uuidString).caf")
        
        // Используем NSSpeechSynthesizer для генерации аудио
        let synthesizer = NSSpeechSynthesizer()
        
        // Настраиваем голос
        if !settings.macOSVoiceIdentifier.isEmpty {
            // NSSpeechSynthesizer.VoiceName - это typealias для String
            let voiceName = NSSpeechSynthesizer.VoiceName(rawValue: settings.macOSVoiceIdentifier)
            synthesizer.setVoice(voiceName)
        } else {
            // Используем голос по умолчанию для языка
            let voices = NSSpeechSynthesizer.availableVoices
            for voice in voices {
                // voice имеет тип NSSpeechSynthesizer.VoiceName, который является String
                let voiceString = voice.rawValue
                if voiceString.contains(settings.assistantLanguage) {
                    synthesizer.setVoice(voice)
                    break
                }
            }
        }
        
        // Настраиваем параметры
        synthesizer.rate = 175 // Средняя скорость
        synthesizer.volume = 1.0
        
        // Создаем аудио файл
        let url = tempURL
        let success = synthesizer.startSpeaking(text, to: url)
        
        guard success else {
            throw NSError(
                domain: "Companion",
                code: 500,
                userInfo: [NSLocalizedDescriptionKey: "Failed to start macOS speech synthesis."]
            )
        }
        
        // Ждем завершения синтеза
        var isSpeaking = true
        var waitCount = 0
        let maxWait = 120 // 120 секунд максимум
        
        while isSpeaking && waitCount < maxWait {
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 секунды
            isSpeaking = synthesizer.isSpeaking
            waitCount += 1
        }
        
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw NSError(
                domain: "Companion",
                code: 500,
                userInfo: [NSLocalizedDescriptionKey: "macOS TTS did not produce audio file."]
            )
        }
        
        let audioData = try Data(contentsOf: url)
        try? FileManager.default.removeItem(at: url)
        
        return audioData
    }

    // MARK: - Web Search
    
    private func executeWebSearch(_ request: CompanionCommandRequest) async throws -> CompanionCommandResult {
        guard let query = request.payload["query"] as? String,
              !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NSError(
                domain: "Companion",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "web.search requires payload.query"]
            )
        }

        let settings = settingsStore.settings
        let cid = parseConversationId(request.payload) ?? UUID()

        guard !settings.selectedChatModel.isEmpty else {
            throw NSError(
                domain: "Companion",
                code: 422,
                userInfo: [NSLocalizedDescriptionKey: "No chat model selected on Mac"]
            )
        }

        let results = try await webSearch.search(query: query, limit: 5)

        let context = results.enumerated().map { index, result in
            """
            [\(index + 1)] \(result.title)
            URL: \(result.url)
            Snippet: \(result.snippet)
            """
        }.joined(separator: "\n\n")

        let prompt = """
        User asked:
        \(query)

        Web search results:
        \(context)

        Answer the user using the search results.
        Include useful source links.
        If results are insufficient, say so.
        """

        let answer = try await ollama.chat(
            model: settings.selectedChatModel,
            messages: [
                [
                    "role": "system",
                    "content": settings.systemPrompt + "\nAlways cite URLs when web search results are used."
                ],
                [
                    "role": "user",
                    "content": prompt
                ]
            ],
            temperature: settings.temperature,
            contextSize: settings.contextSize
        )

        try await appendRemoteMessage(
            uid: request.uid,
            conversationId: cid.uuidString,
            role: "user",
            text: "Search web: \(query)",
            attachmentURL: nil,
            attachmentType: nil
        )

        try await appendRemoteMessage(
            uid: request.uid,
            conversationId: cid.uuidString,
            role: "assistant",
            text: answer,
            attachmentURL: nil,
            attachmentType: nil
        )

        return CompanionCommandResult(data: [
            "conversationId": cid.uuidString,
            "assistantText": answer
        ])
    }
    
    // MARK: - Daily Briefing
    
    private func executeDailyBriefing(_ request: CompanionCommandRequest) async throws -> CompanionCommandResult {
        let settings = settingsStore.settings
        let cid = parseConversationId(request.payload) ?? UUID()

        guard !settings.selectedChatModel.isEmpty else {
            throw NSError(
                domain: "Companion",
                code: 422,
                userInfo: [NSLocalizedDescriptionKey: "No chat model selected on Mac"]
            )
        }

        let openTasks = tasks.listOpenTasks()
        let memories = memory.listMemories().prefix(10)

        let taskText = openTasks.isEmpty
            ? "No open tasks."
            : openTasks.map { "- \($0.title)" }.joined(separator: "\n")

        let memoryText = memories.isEmpty
            ? "No important memories."
            : memories.map { "- \($0.content)" }.joined(separator: "\n")

        let prompt = """
        Create a concise daily briefing for the user.

        Open tasks:
        \(taskText)

        Relevant user memory:
        \(memoryText)

        Requirements:
        - Friendly greeting.
        - Mention top priorities.
        - Suggest 2-3 next actions.
        - Answer in \(settings.assistantLanguage).
        """

        let answer = try await ollama.chat(
            model: settings.selectedChatModel,
            messages: [
                [
                    "role": "system",
                    "content": settings.systemPrompt
                ],
                [
                    "role": "user",
                    "content": prompt
                ]
            ],
            temperature: settings.temperature,
            contextSize: settings.contextSize
        )

        try await appendRemoteMessage(
            uid: request.uid,
            conversationId: cid.uuidString,
            role: "user",
            text: "Daily briefing",
            attachmentURL: nil,
            attachmentType: nil
        )

        try await appendRemoteMessage(
            uid: request.uid,
            conversationId: cid.uuidString,
            role: "assistant",
            text: answer,
            attachmentURL: nil,
            attachmentType: nil
        )

        return CompanionCommandResult(data: [
            "conversationId": cid.uuidString,
            "assistantText": answer
        ])
    }
    
    // MARK: - Calendar Today
    
    private func executeCalendarToday(_ request: CompanionCommandRequest) async throws -> CompanionCommandResult {
        let cid = parseConversationId(request.payload) ?? UUID()

        let events = try await calendarService.eventsForToday(limit: 12)

        let answer: String

        if events.isEmpty {
            answer = "There are no events on the calendar today."
        } else {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            formatter.dateStyle = .none

            let lines = events.map { event in
                "• \(formatter.string(from: event.startDate)) – \(event.title ?? "(untitled)")"
            }.joined(separator: "\n")

            answer = "Events for today:\n\(lines)"
        }

        try await appendRemoteMessage(
            uid: request.uid,
            conversationId: cid.uuidString,
            role: "user",
            text: "Today calendar",
            attachmentURL: nil,
            attachmentType: nil
        )

        try await appendRemoteMessage(
            uid: request.uid,
            conversationId: cid.uuidString,
            role: "assistant",
            text: answer,
            attachmentURL: nil,
            attachmentType: nil
        )

        return CompanionCommandResult(data: [
            "conversationId": cid.uuidString,
            "assistantText": answer
        ])
    }
    
    // MARK: - Tasks
    
    private func executeTasksSetDone(_ request: CompanionCommandRequest) throws -> CompanionCommandResult {
        guard let rawId = request.payload["id"] as? String,
              let id = UUID(uuidString: rawId) else {
            throw NSError(
                domain: "Companion",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "tasks.setDone requires payload.id"]
            )
        }

        guard let isDone = request.payload["isDone"] as? Bool else {
            throw NSError(
                domain: "Companion",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "tasks.setDone requires payload.isDone"]
            )
        }

        tasks.setTaskDone(id: id, isDone: isDone)

        return CompanionCommandResult(data: [
            "ok": true,
            "id": rawId,
            "isDone": isDone
        ])
    }

    private func executeTasksDelete(_ request: CompanionCommandRequest) throws -> CompanionCommandResult {
        guard let rawId = request.payload["id"] as? String,
              let id = UUID(uuidString: rawId) else {
            throw NSError(
                domain: "Companion",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "tasks.delete requires payload.id"]
            )
        }

        tasks.deleteTask(id: id)

        return CompanionCommandResult(data: [
            "ok": true,
            "id": rawId
        ])
    }

    // MARK: - Chat

    private func executeChatSend(_ request: CompanionCommandRequest) async throws -> CompanionCommandResult {
        guard let text = request.payload["text"] as? String,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NSError(domain: "Companion", code: 400, userInfo: [NSLocalizedDescriptionKey: "chat.send requires payload.text"])
        }

        let settings = settingsStore.settings
        guard !settings.selectedChatModel.isEmpty else {
            throw NSError(domain: "Companion", code: 422, userInfo: [NSLocalizedDescriptionKey: "No chat model selected on Mac"])
        }

        let cid = parseConversationId(request.payload) ?? UUID()
        conversations.createConversation(id: cid, title: "Remote chat")

        conversations.appendMessage(ChatMessage(conversationId: cid, role: .user, content: text))

        var systemPrompt = settings.systemPrompt
        if !settings.personalPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            systemPrompt += "\n\nUser personal instructions:\n\(settings.personalPrompt)"
        }

        if settings.memoryMode != .off && !settings.selectedEmbeddingModel.isEmpty {
            if let emb = try? await ollama.embedding(model: settings.selectedEmbeddingModel, prompt: text) {
                let relevant = memory.searchSimilar(
                    queryEmbedding: emb,
                    limit: 5,
                    minSimilarity: 0.38
                )
                if !relevant.isEmpty {
                    systemPrompt += "\n\nRelevant long-term memory:\n"
                    relevant.forEach { systemPrompt += "- \($0.content)\n" }
                }
            }
        }

        let answer = try await ollama.chat(
            model: settings.selectedChatModel,
            messages: [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text]
            ],
            temperature: settings.temperature,
            contextSize: settings.contextSize
        )

        conversations.appendMessage(ChatMessage(conversationId: cid, role: .assistant, content: answer))

        return CompanionCommandResult(data: [
            "conversationId": cid.uuidString,
            "assistantText": answer
        ])
    }

    // MARK: - Tasks List/Add

    private func executeTasksList() -> CompanionCommandResult {
        let open = tasks.listOpenTasks()
        let items: [[String: Any]] = open.map {
            [
                "id": $0.id.uuidString,
                "title": $0.title,
                "notes": $0.notes,
                "isDone": $0.isDone,
                "createdAt": $0.createdAt.timeIntervalSince1970
            ]
        }
        return CompanionCommandResult(data: ["count": items.count, "items": items])
    }

    private func executeTasksAdd(_ request: CompanionCommandRequest) throws -> CompanionCommandResult {
        guard let title = request.payload["title"] as? String,
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NSError(domain: "Companion", code: 400, userInfo: [NSLocalizedDescriptionKey: "tasks.add requires payload.title"])
        }

        let notes = (request.payload["notes"] as? String) ?? ""
        tasks.addTask(title: title, notes: notes)

        return CompanionCommandResult(data: ["ok": true, "message": "Task added", "title": title])
    }

    // MARK: - Image generate

    private func executeImageGenerate(_ request: CompanionCommandRequest) async throws -> CompanionCommandResult {
        guard let prompt = request.payload["prompt"] as? String,
              !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NSError(domain: "Companion", code: 400, userInfo: [NSLocalizedDescriptionKey: "image.generate requires payload.prompt"])
        }

        let settings = settingsStore.settings
        let cid = parseConversationId(request.payload) ?? UUID()

        let localURL: URL
        switch settings.imageProvider {
        case .openAI:
            guard settings.enableOpenAIImages else {
                throw NSError(domain: "Companion", code: 422, userInfo: [NSLocalizedDescriptionKey: "OpenAI image features are disabled"])
            }
            localURL = try await OpenAIClient.shared.generateImage(prompt: prompt, model: settings.openAIImageModel)

        case .waveSpeed:
            localURL = try await WaveSpeedImageClient.shared.generateImage(prompt: prompt, settings: settings)
        }

        let publicURL = try await FirebaseStorageService.shared.uploadFile(localURL: localURL, purpose: .image)

        try await appendRemoteMessage(uid: request.uid, conversationId: cid.uuidString, role: "user", text: "Generate image: \(prompt)", attachmentURL: nil, attachmentType: nil)
        try await appendRemoteMessage(uid: request.uid, conversationId: cid.uuidString, role: "assistant", text: "Image generated.", attachmentURL: publicURL, attachmentType: "image")

        return CompanionCommandResult(data: [
            "conversationId": cid.uuidString,
            "assistantText": "Image generated.",
            "attachmentURL": publicURL,
            "attachmentType": "image"
        ])
    }

    // MARK: - Image analyze

    private func executeImageAnalyze(_ request: CompanionCommandRequest) async throws -> CompanionCommandResult {
        guard let imageURLString = request.payload["imageURL"] as? String,
              let imageURL = URL(string: imageURLString) else {
            throw NSError(domain: "Companion", code: 400, userInfo: [NSLocalizedDescriptionKey: "image.analyze requires payload.imageURL"])
        }

        let prompt = (request.payload["prompt"] as? String) ?? "Analyze this image."
        let settings = settingsStore.settings
        let cid = parseConversationId(request.payload) ?? UUID()

        guard !settings.selectedVisionModel.isEmpty else {
            throw NSError(domain: "Companion", code: 422, userInfo: [NSLocalizedDescriptionKey: "No vision model selected on Mac"])
        }

        let (data, response) = try await URLSession.shared.data(from: imageURL)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw NSError(domain: "Companion", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to download image"])
        }

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("ios-image-\(UUID().uuidString).jpg")
        try data.write(to: tempURL)

        let answer = try await ollama.analyzeImage(
            model: settings.selectedVisionModel,
            imageURL: tempURL,
            prompt: prompt,
            temperature: 0.3,
            contextSize: settings.contextSize
        )

        try await appendRemoteMessage(uid: request.uid, conversationId: cid.uuidString, role: "user", text: prompt, attachmentURL: imageURLString, attachmentType: "image")
        try await appendRemoteMessage(uid: request.uid, conversationId: cid.uuidString, role: "assistant", text: answer, attachmentURL: nil, attachmentType: nil)

        return CompanionCommandResult(data: [
            "conversationId": cid.uuidString,
            "assistantText": answer
        ])
    }

    // MARK: - Image edit

    private func executeImageEdit(_ request: CompanionCommandRequest) async throws -> CompanionCommandResult {
        guard let imageURLString = request.payload["imageURL"] as? String,
              !imageURLString.isEmpty,
              let sourceURL = URL(string: imageURLString) else {
            throw NSError(domain: "Companion", code: 400, userInfo: [NSLocalizedDescriptionKey: "image.edit requires payload.imageURL"])
        }

        guard let prompt = request.payload["prompt"] as? String,
              !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NSError(domain: "Companion", code: 400, userInfo: [NSLocalizedDescriptionKey: "image.edit requires payload.prompt"])
        }

        let settings = settingsStore.settings
        let cid = parseConversationId(request.payload) ?? UUID()

        let editedLocalURL: URL

        switch settings.imageProvider {
        case .openAI:
            guard settings.enableOpenAIImages else {
                throw NSError(domain: "Companion", code: 422, userInfo: [NSLocalizedDescriptionKey: "OpenAI image features are disabled"])
            }

            let (data, response) = try await URLSession.shared.data(from: sourceURL)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
                throw NSError(domain: "Companion", code: -3, userInfo: [NSLocalizedDescriptionKey: "Failed to download source image"])
            }

            let temp = FileManager.default.temporaryDirectory.appendingPathComponent("edit-source-\(UUID().uuidString).png")
            try data.write(to: temp)

            editedLocalURL = try await OpenAIClient.shared.editImage(
                imageURL: temp,
                prompt: prompt,
                model: settings.openAIImageModel
            )

        case .waveSpeed:
            editedLocalURL = try await WaveSpeedImageClient.shared.editImage(
                prompt: prompt,
                imagePublicURLs: [imageURLString],
                settings: settings
            )
        }

        let editedPublicURL = try await FirebaseStorageService.shared.uploadFile(localURL: editedLocalURL, purpose: .image)

        try await appendRemoteMessage(uid: request.uid, conversationId: cid.uuidString, role: "user", text: "Edit image: \(prompt)", attachmentURL: imageURLString, attachmentType: "image")
        try await appendRemoteMessage(uid: request.uid, conversationId: cid.uuidString, role: "assistant", text: "Edited image.", attachmentURL: editedPublicURL, attachmentType: "image")

        return CompanionCommandResult(data: [
            "conversationId": cid.uuidString,
            "assistantText": "Edited image.",
            "attachmentURL": editedPublicURL,
            "attachmentType": "image"
        ])
    }

    // MARK: - File summarize

    private func executeFileSummarize(_ request: CompanionCommandRequest) async throws -> CompanionCommandResult {
        guard let fileURLString = request.payload["fileURL"] as? String,
              let fileURL = URL(string: fileURLString) else {
            throw NSError(domain: "Companion", code: 400, userInfo: [NSLocalizedDescriptionKey: "file.summarize requires payload.fileURL"])
        }

        let fileName = (request.payload["fileName"] as? String) ?? "file"
        let cid = parseConversationId(request.payload) ?? UUID()
        let settings = settingsStore.settings

        guard !settings.selectedChatModel.isEmpty else {
            throw NSError(domain: "Companion", code: 422, userInfo: [NSLocalizedDescriptionKey: "No chat model selected"])
        }

        let (data, response) = try await URLSession.shared.data(from: fileURL)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw NSError(domain: "Companion", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to download file"])
        }

        let ext = URL(string: fileURLString)?.pathExtension.isEmpty == false
            ? (URL(string: fileURLString)?.pathExtension ?? "txt")
            : "txt"

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("ios-file-\(UUID().uuidString).\(ext)")
        try data.write(to: tempURL)

        var text = try fileReader.readText(from: tempURL)
        if text.count > 30_000 { text = String(text.prefix(30_000)) }

        let prompt = """
        Summarize this file for the user.

        File name:
        \(fileName)

        File content:
        \(text)

        Requirements:
        - concise summary
        - key points
        - extract tasks/decisions if present
        """

        let answer = try await ollama.chat(
            model: settings.selectedChatModel,
            messages: [
                ["role": "system", "content": settings.systemPrompt],
                ["role": "user", "content": prompt]
            ],
            temperature: settings.temperature,
            contextSize: settings.contextSize
        )

        try await appendRemoteMessage(uid: request.uid, conversationId: cid.uuidString, role: "user", text: "Summarize file: \(fileName)", attachmentURL: fileURLString, attachmentType: "file")
        try await appendRemoteMessage(uid: request.uid, conversationId: cid.uuidString, role: "assistant", text: answer, attachmentURL: nil, attachmentType: nil)

        return CompanionCommandResult(data: [
            "conversationId": cid.uuidString,
            "assistantText": answer
        ])
    }

    // MARK: Helpers

    private func parseConversationId(_ payload: [String: Any]) -> UUID? {
        guard let raw = payload["conversationId"] as? String, !raw.isEmpty else { return nil }
        return UUID(uuidString: raw)
    }

    private func appendRemoteMessage(
        uid: String,
        conversationId: String,
        role: String,
        text: String,
        attachmentURL: String?,
        attachmentType: String?
    ) async throws {
        let convRef = db.collection("users").document(uid).collection("remoteConversations").document(conversationId)
        let msgRef = convRef.collection("messages").document()

        var msg: [String: Any] = [
            "role": role,
            "text": text,
            "createdAt": FieldValue.serverTimestamp()
        ]

        if let attachmentURL { msg["attachmentURL"] = attachmentURL }
        if let attachmentType { msg["attachmentType"] = attachmentType }

        try await msgRef.setData(msg)

        var convUpdate: [String: Any] = [
            "conversationId": conversationId,
            "lastMessage": text,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if role == "user" {
            convUpdate["title"] = String(text.prefix(60))
        }

        try await convRef.setData(convUpdate, merge: true)
    }
}
