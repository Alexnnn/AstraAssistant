//
//  ChatViewModel.swift
//  AstraAssistant
//
//  Created by Alex on 10/8/26.
//

import Foundation
import Combine
import AppKit
import EventKit

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var conversationsList: [ConversationSummary] = []
    @Published var isSending = false
    @Published var currentConversationId = UUID()

    @Published var pendingToolConfirmation: PendingToolConfirmation?
    @Published var pendingMemoryConfirmation: PendingMemoryConfirmation?
    @Published var toolStatus: String?
    @Published var isAssistantSpeaking = false

    private weak var appViewModel: AppViewModel?

    private let webSearch = WebSearchService.shared
    private let fileReader = FileReaderService.shared
    private let taskStore = TaskStore.shared
    private let calendarService = CalendarService.shared

    private let ollama = OllamaClient.shared
    private let memory = VectorMemoryStore.shared
    private let conversations = ConversationStore.shared

    private let openAI = OpenAIClient.shared
    private let waveSpeedImage = WaveSpeedImageClient.shared
    private let firebaseStorage = FirebaseStorageService.shared

    private let voiceOutput = VoiceOutputService()

    private var isConfigured = false
    private var cancellables = Set<AnyCancellable>()

    // Anti-duplicate input (important for continuous/wake)
    private var lastInputFingerprint: String = ""
    private var lastInputAt: Date = .distantPast
    private let inputDedupWindow: TimeInterval = 1.8

    init() {
        voiceOutput.$isSpeaking
            .receive(on: RunLoop.main)
            .sink { [weak self] speaking in
                self?.isAssistantSpeaking = speaking
            }
            .store(in: &cancellables)
    }

    // MARK: - Configure

    func configure(appViewModel: AppViewModel) {
        guard !isConfigured else { return }

        self.appViewModel = appViewModel
        isConfigured = true

        refreshConversations()
        if let latest = conversationsList.first {
            loadConversation(id: latest.id)
        } else {
            newConversation()
        }
    }

    // MARK: - Conversations

    func refreshConversations() {
        conversationsList = conversations.listConversations()
    }

    func newConversation() {
        currentConversationId = UUID()
        messages = []

        conversations.createConversation(
            id: currentConversationId,
            title: "New conversation"
        )

        refreshConversations()
    }

    func loadConversation(id: UUID) {
        currentConversationId = id
        messages = conversations.loadMessages(conversationId: id)
        refreshConversations()
    }

    func deleteConversation(id: UUID) {
        conversations.deleteConversation(id: id)

        if id == currentConversationId {
            refreshConversations()
            if let latest = conversationsList.first {
                loadConversation(id: latest.id)
            } else {
                newConversation()
            }
        } else {
            refreshConversations()
        }
    }

    func exportCurrentConversationMarkdown() -> String {
        conversations.exportConversationMarkdown(conversationId: currentConversationId)
    }

    // MARK: - Main Send

    func send(_ text: String, speakResponse: Bool = false) async {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else { return }

        if shouldDropDuplicateInput(cleanText) { return }
        guard !isSending else { return }

        // 1) instantly show user message
        let userMessage = ChatMessage(
            conversationId: currentConversationId,
            role: .user,
            content: cleanText
        )
        appendAndSave(userMessage)

        // 2) direct commands first
        if await handleDirectToolCommand(cleanText) {
            return
        }

        guard let appViewModel else {
            appendAssistant("Internal error: AppViewModel unavailable.")
            return
        }

        let settings = appViewModel.settingsStore.settings

        // 3) explicit memory intent
        if await handleExplicitMemoryIntent(cleanText) {
            return
        }

        // 4) model checks
        guard !settings.selectedChatModel.isEmpty else {
            appendAssistant("Please select an Ollama chat model in Settings.")
            return
        }

        guard !settings.selectedEmbeddingModel.isEmpty else {
            appendAssistant("Please select an embedding model in Settings.")
            return
        }

        // 5) tool routing by LLM
        if await routeWithLLMIfNeeded(cleanText) {
            return
        }

        // 6) ollama preflight
        let ollamaReady = await ollama.isRunning()
        guard ollamaReady else {
            appendAssistant("""
            I can't connect to Ollama.
            Check that the server is running:
            ollama serve
            """)
            return
        }

        // 7) normal LLM chat
        isSending = true
        defer { isSending = false }

        let assistantMessageId = UUID()
        let assistantCreatedAt = Date()

        messages.append(
            ChatMessage(
                id: assistantMessageId,
                conversationId: currentConversationId,
                role: .assistant,
                content: "",
                createdAt: assistantCreatedAt
            )
        )

        do {
            let queryEmbedding = try await ollama.embedding(
                model: settings.selectedEmbeddingModel,
                prompt: cleanText
            )

            let relevantMemories: [MemoryItem] = settings.memoryMode == .off
                ? []
                : memory.searchSimilar(
                    queryEmbedding: queryEmbedding,
                    limit: 5,
                    minSimilarity: 0.38
                )

            let promptMessages = buildPromptMessages(
                settings: settings,
                relevantMemories: relevantMemories,
                userText: cleanText
            )

            var accumulated = ""

            let finalResponse = try await ollama.chatStream(
                model: settings.selectedChatModel,
                messages: promptMessages,
                temperature: settings.temperature,
                contextSize: settings.contextSize
            ) { token in
                await MainActor.run {
                    accumulated += token
                    self.updateMessageContent(id: assistantMessageId, content: accumulated)
                }
            }

            let cleanResponse = cleanAssistantOutput(finalResponse)
            updateMessageContent(id: assistantMessageId, content: cleanResponse)

            conversations.appendMessage(
                ChatMessage(
                    id: assistantMessageId,
                    conversationId: currentConversationId,
                    role: .assistant,
                    content: cleanResponse,
                    createdAt: assistantCreatedAt
                )
            )
            refreshConversations()

            if speakResponse {
                voiceOutput.speak(cleanResponse, settings: settings)
            }

            await maybeStoreMemory(
                userText: cleanText,
                assistantText: cleanResponse,
                settings: settings
            )

        } catch {
            let readable = makeReadableError(error)
            updateMessageContent(id: assistantMessageId, content: readable)

            conversations.appendMessage(
                ChatMessage(
                    id: assistantMessageId,
                    conversationId: currentConversationId,
                    role: .assistant,
                    content: readable,
                    createdAt: assistantCreatedAt
                )
            )
            refreshConversations()
        }
    }

    // MARK: - Voice output control

    func stopSpeaking() {
        voiceOutput.stop()
    }

    // MARK: - Images / Files / Briefing

    func analyzeImage(imageURL: URL, prompt: String, storeAttachment: Bool = true) async {
        guard !isSending else { return }
        setToolStatus("Analyzing image...")
        defer { setToolStatus(nil) }

        guard let appViewModel else { return }
        let settings = appViewModel.settingsStore.settings

        guard !settings.selectedVisionModel.isEmpty else {
            appendAssistant("Please select a local Ollama vision model in Settings.")
            return
        }

        isSending = true
        defer { isSending = false }

        let userText = prompt.isEmpty ? "Analyze this image." : prompt

        appendAndSave(
                ChatMessage(
                    conversationId: currentConversationId,
                    role: .user,
                    content: userText,
                    attachmentPath: storeAttachment ? imageURL.path : nil
                )
            )

        do {
            let response = try await ollama.analyzeImage(
                model: settings.selectedVisionModel,
                imageURL: imageURL,
                prompt: userText,
                temperature: 0.3,
                contextSize: settings.contextSize
            )

            appendAndSave(
                ChatMessage(
                    conversationId: currentConversationId,
                    role: .assistant,
                    content: response
                )
            )
        } catch {
            appendAssistant("Image analysis error: \(makeReadableError(error))")
        }
    }

    func generateImage(prompt: String) async {
        guard !isSending else { return }
        setToolStatus("Generating image...")
        defer { setToolStatus(nil) }

        guard let appViewModel else { return }
        let settings = appViewModel.settingsStore.settings

        isSending = true
        defer { isSending = false }

        appendAndSave(
            ChatMessage(
                conversationId: currentConversationId,
                role: .user,
                content: "Generate image: \(prompt)"
            )
        )

        do {
            let imageURL: URL

            switch settings.imageProvider {
            case .openAI:
                guard settings.enableOpenAIImages else {
                    appendAssistant("OpenAI image generation is disabled in Settings.")
                    return
                }

                imageURL = try await openAI.generateImage(
                    prompt: prompt,
                    model: settings.openAIImageModel
                )

            case .waveSpeed:
                imageURL = try await waveSpeedImage.generateImage(
                    prompt: prompt,
                    settings: settings
                )
            }

            appendAndSave(
                ChatMessage(
                    conversationId: currentConversationId,
                    role: .assistant,
                    content: "Generated image.",
                    attachmentPath: imageURL.path
                )
            )

        } catch {
            appendAssistant("Image generation error: \(makeReadableError(error))")
        }
    }

    /// New unified edit method:
    /// - OpenAI: local image file
    /// - WaveSpeed: public URL (auto-upload from local file to Firebase if needed)
    func editImage(
        localImageURL: URL?,
        waveSpeedPublicImageURL: String?,
        prompt: String
    ) async {
        guard !isSending else { return }
        setToolStatus("Editing image...")
        defer { setToolStatus(nil) }

        guard let appViewModel else { return }
        let settings = appViewModel.settingsStore.settings

        isSending = true
        defer { isSending = false }

        appendAndSave(
            ChatMessage(
                conversationId: currentConversationId,
                role: .user,
                content: "Edit image: \(prompt)",
                attachmentPath: localImageURL?.path
            )
        )

        do {
            let editedURL: URL

            switch settings.imageProvider {
            case .openAI:
                guard settings.enableOpenAIImages else {
                    appendAssistant("OpenAI image editing is disabled in Settings.")
                    return
                }

                guard let localImageURL else {
                    appendAssistant("Select a local image for OpenAI edit.")
                    return
                }

                editedURL = try await openAI.editImage(
                    imageURL: localImageURL,
                    prompt: prompt,
                    model: settings.openAIImageModel
                )

            case .waveSpeed:
                var publicURL = waveSpeedPublicImageURL?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                // If user did not provide public URL, but selected local image -> auto-upload to Firebase
                if publicURL.isEmpty, let localImageURL {
                    setToolStatus("Uploading image to Firebase...")
                    publicURL = try await firebaseStorage.uploadFile(
                        localURL: localImageURL,
                        purpose: .image
                    )
                    setToolStatus("Editing image...")
                }

                guard !publicURL.isEmpty else {
                    appendAssistant("For Seedream Edit, provide a public image URL or choose a local file for auto-upload.")
                    return
                }

                editedURL = try await waveSpeedImage.editImage(
                    prompt: prompt,
                    imagePublicURLs: [publicURL],
                    settings: settings
                )
            }

            appendAndSave(
                ChatMessage(
                    conversationId: currentConversationId,
                    role: .assistant,
                    content: "Edited image.",
                    attachmentPath: editedURL.path
                )
            )

        } catch {
            appendAssistant("Image editing error: \(makeReadableError(error))")
        }
    }

    /// Backward compatibility overload (old calls)
    func editImage(imageURL: URL, prompt: String) async {
        await editImage(
            localImageURL: imageURL,
            waveSpeedPublicImageURL: nil,
            prompt: prompt
        )
    }

    func readAndSummarizeFile(url: URL) async {
        guard !isSending else { return }
        setToolStatus("Reading file...")
        defer { setToolStatus(nil) }

        guard let appViewModel else { return }
        let settings = appViewModel.settingsStore.settings

        guard !settings.selectedChatModel.isEmpty else {
            appendAssistant("Please select an Ollama chat model in Settings.")
            return
        }

        isSending = true
        defer { isSending = false }

        do {
            let shouldAccess = url.startAccessingSecurityScopedResource()
            defer {
                if shouldAccess { url.stopAccessingSecurityScopedResource() }
            }

            var text = try fileReader.readText(from: url)
            if text.count > 30_000 {
                text = String(text.prefix(30_000))
            }

            appendAndSave(
                ChatMessage(
                    conversationId: currentConversationId,
                    role: .user,
                    content: "Read and summarize file: \(url.lastPathComponent)",
                    attachmentPath: url.path
                )
            )

            let prompt = """
            Summarize this file for the user.

            File name:
            \(url.lastPathComponent)

            File content:
            \(text)

            Requirements:
            - Provide a concise summary.
            - List key points.
            - If it contains tasks or decisions, extract them.
            - Answer in \(settings.assistantLanguage).
            """

            await sendWithToolContext(
                userVisibleQuestion: "Summarize file \(url.lastPathComponent)",
                toolContextPrompt: prompt,
                settings: settings
            )

        } catch {
            appendAssistant("Failed to read file: \(error.localizedDescription)")
        }
    }

    func generateDailyBriefing() async {
        guard !isSending else { return }
        setToolStatus("Preparing daily briefing...")
        defer { setToolStatus(nil) }

        guard let appViewModel else { return }
        let settings = appViewModel.settingsStore.settings

        guard !settings.selectedChatModel.isEmpty else {
            appendAssistant("Please select an Ollama chat model in Settings.")
            return
        }

        appendAssistant("I prepare a daily briefing based on your open tasks and saved memory...")

        let tasks = taskStore.listOpenTasks()
        let memories = memory.listMemories().prefix(10)

        let taskText = tasks.isEmpty ? "No open tasks." : tasks.map { "- \($0.title)" }.joined(separator: "\n")
        let memoryText = memories.isEmpty ? "No important memories." : memories.map { "- \($0.content)" }.joined(separator: "\n")

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

        await sendWithToolContext(
            userVisibleQuestion: "Daily briefing",
            toolContextPrompt: prompt,
            settings: settings
        )
    }

    // MARK: - Direct commands

    private func handleDirectToolCommand(_ text: String) async -> Bool {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        if lower == "/now" || lower == "what time is it" || lower == "what is the time" || lower == "what is the hour" || lower == "what is the day" || lower == "который час" || lower == "какой час" || lower == "который час" || lower == "какое сегодня число" {
            let formatter = DateFormatter()
            formatter.locale = Locale.current
            formatter.dateStyle = .full
            formatter.timeStyle = .medium
            appendAssistant("It's: \(formatter.string(from: Date()))")
            return true
        }

        if lower == "/calendar today" || lower.contains("события на сегодня") {
            await listTodayCalendarEvents()
            return true
        }

        if lower.hasPrefix("/calendar add ") {
            let raw = String(text.dropFirst("/calendar add ".count))
            await addCalendarEventFromCommand(raw)
            return true
        }

        if lower == "/help" || lower == "help" || lower == "команды" || lower == "/commands" {
            appendAssistant(commandsHelpText())
            return true
        }

        if lower.hasPrefix("/search ") {
            let query = String(text.dropFirst("/search ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            await performWebSearch(query: query)
            return true
        }

        // Явный естественный запрос на поиск.
        // Важно: больше не ловим любое "найди ...", потому что это слишком агрессивно.
        if hasExplicitWebSearchIntent(text) {
            await performWebSearch(query: text)
            return true
        }

        if lower.hasPrefix("/open ") {
            let urlString = String(text.dropFirst("/open ".count)).trimmingCharacters(in: .whitespacesAndNewlines)

            pendingToolConfirmation = PendingToolConfirmation(
                kind: .openURL,
                title: "Open URL",
                details: "Astra wants to open this URL:\n\(urlString)",
                payload: urlString
            )
            return true
        }

        if lower.hasPrefix("/task ") {
            let title = String(text.dropFirst("/task ".count)).trimmingCharacters(in: .whitespacesAndNewlines)

            guard !title.isEmpty else {
                appendAssistant("Write the task after /task. Example: /task buy a microphone")
                return true
            }

            taskStore.addTask(title: title)
            appendAssistant("Done, I added the task: \(title)")
            return true
        }

        if lower == "/tasks" || lower.contains("мои задачи") {
            let tasks = taskStore.listOpenTasks()

            if tasks.isEmpty {
                appendAssistant("You don't have any open tasks yet.")
            } else {
                let list = tasks.map { "• \($0.title)" }.joined(separator: "\n")
                appendAssistant("Your open tasks:\n\(list)")
            }

            return true
        }

        return false
    }

    // MARK: - LLM router

    private func routeWithLLMIfNeeded(_ text: String) async -> Bool {
        guard let appViewModel else { return false }

        let settings = appViewModel.settingsStore.settings
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        if lower.count < 12 {
            return false
        }

        if lower.contains("запомни") || lower.contains("remember") {
            return false
        }

        let mayNeedWeb = shouldAllowWebSearchForText(text)

        let mayNeedTask =
            lower.contains("задач") ||
            lower.contains("todo") ||
            lower.contains("to-do") ||
            lower.contains("добавь задачу") ||
            lower.contains("создай задачу") ||
            lower.contains("напомни") ||
            lower.contains("remind me") ||
            lower.contains("add task")

        let mayNeedOpenURL =
            lower.contains("http://") ||
            lower.contains("https://") ||
            lower.hasPrefix("/open ") ||
            lower.hasPrefix("открой ") ||
            lower.hasPrefix("open ")

        guard mayNeedWeb || mayNeedTask || mayNeedOpenURL else {
            return false
        }

        do {
            let routerPrompt = """
            You are a conservative tool routing module for Astra Assistant.

            Decide whether the user's message requires a tool.

            Available actions:
            - none: normal chat, no tool needed
            - webSearch: ONLY when the user explicitly asks to search online OR asks for current/recent/live information
            - openURL: when user explicitly asks to open a website or URL
            - createTask: when user asks to create/save a todo/task/reminder
            - listTasks: when user asks for their tasks

            Important:
            - Do NOT use webSearch for general knowledge, explanations, programming help, opinions, planning, writing, or debugging.
            - If the assistant can answer locally, choose none.
            - Prefer none unless a tool is clearly required.

            Return strict JSON only:
            {
              "action": "none | webSearch | openURL | createTask | listTasks",
              "query": "search query if needed",
              "url": "url if needed",
              "title": "task title if needed",
              "reason": "short reason"
            }

            User message:
            \(text)
            """

            let response = try await ollama.chat(
                model: settings.selectedChatModel,
                messages: [
                    [
                        "role": "system",
                        "content": "You are a strict conservative JSON tool router. Return JSON only."
                    ],
                    [
                        "role": "user",
                        "content": routerPrompt
                    ]
                ],
                temperature: 0.0,
                contextSize: 2048
            )

            let json = extractJSONObject(from: response, fallback: #"{"action":"none"}"#)
            guard let data = json.data(using: .utf8) else { return false }

            let decision = try JSONDecoder().decode(ToolRoutingDecision.self, from: data)

            switch decision.action {
            case .none:
                return false

            case .webSearch:
                guard shouldAllowWebSearchForText(text) else {
                    return false
                }

                let query = (decision.query ?? text)
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                guard !query.isEmpty else {
                    return false
                }

                switch settings.webSearchMode ?? .askBeforeSearch {
                case .off:
                    appendAssistant("Web search is disabled in Settings.")
                    return true

                case .manualOnly:
                    return false

                case .askBeforeSearch:
                    pendingToolConfirmation = PendingToolConfirmation(
                        kind: .webSearch,
                        title: "Search the web?",
                        details: """
                        Astra thinks this request may require current or online information.

                        Query:
                        \(query)

                        Allow web search?
                        """,
                        payload: query
                    )
                    return true

                case .automatic:
                    await performWebSearch(query: query)
                    return true
                }

            case .openURL:
                guard let url = decision.url, !url.isEmpty else { return false }

                pendingToolConfirmation = PendingToolConfirmation(
                    kind: .openURL,
                    title: "Open URL",
                    details: "Astra wants to open this URL:\n\(url)",
                    payload: url
                )
                return true

            case .createTask:
                let title = (decision.title ?? decision.query ?? text)
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                guard !title.isEmpty else { return false }

                taskStore.addTask(title: title)
                appendAssistant("Done, I added the task: \(title)")
                return true

            case .listTasks:
                let tasks = taskStore.listOpenTasks()

                if tasks.isEmpty {
                    appendAssistant("You don't have any open tasks yet.")
                } else {
                    let list = tasks.map { "• \($0.title)" }.joined(separator: "\n")
                    appendAssistant("Your open tasks:\n\(list)")
                }

                return true
            }

        } catch {
            print("Tool routing failed:", error.localizedDescription)
            return false
        }
    }

    // MARK: - Web search

    private func performWebSearch(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            appendAssistant("Empty search query.")
            return
        }

        if effectiveWebSearchMode() == .off {
            appendAssistant("Web search is disabled in Settings.")
            return
        }

        guard !isSending else { return }

        setToolStatus("Searching web...")
        defer { setToolStatus(nil) }

        isSending = true
        defer { isSending = false }

        do {
            let results = try await webSearch.search(query: trimmed, limit: 5)

            guard !results.isEmpty else {
                appendAssistant("""
                Unable to retrieve results for your request.

                Try:
                1) Refine your query
                2) Try again in 5-10 seconds
                3) Check your internet connection
                """)
                return
            }

            guard let appViewModel else {
                let rawList = results.map { "• \($0.title)\n\($0.url)" }.joined(separator: "\n\n")
                appendAssistant("Search results:\n\n\(rawList)")
                return
            }

            let settings = appViewModel.settingsStore.settings
            let ollamaReady = await ollama.isRunning()

            // If no chat model/Ollama, still show raw results.
            if settings.selectedChatModel.isEmpty || !ollamaReady {
                let rawList = results.map { "• \($0.title)\n\($0.url)" }.joined(separator: "\n\n")
                appendAssistant("Search results:\n\n\(rawList)")
                return
            }

            let context = results.enumerated().map { idx, r in
                """
                [\(idx + 1)] \(r.title)
                URL: \(r.url)
                Snippet: \(r.snippet)
                """
            }.joined(separator: "\n\n")

            let prompt = """
            User asked:
            \(trimmed)

            Web search results:
            \(context)

            Answer the user using the search results.
            Include useful source links.
            If results are insufficient, say so.
            """

            await sendWithToolContext(
                userVisibleQuestion: trimmed,
                toolContextPrompt: prompt,
                settings: settings
            )

        } catch {
            appendAssistant("Web search error: \(error.localizedDescription)")
        }
    }

    private func sendWithToolContext(
        userVisibleQuestion: String,
        toolContextPrompt: String,
        settings: AssistantSettings
    ) async {
        let assistantMessageId = UUID()
        let assistantCreatedAt = Date()

        messages.append(
            ChatMessage(
                id: assistantMessageId,
                conversationId: currentConversationId,
                role: .assistant,
                content: "",
                createdAt: assistantCreatedAt
            )
        )

        do {
            let promptMessages: [[String: String]] = [
                [
                    "role": "system",
                    "content": settings.systemPrompt + """

                    You have access to tool results supplied by the system.
                    Do not claim you browsed live unless tool results are provided.
                    Always cite URLs when web search results are used.
                    """
                ],
                [
                    "role": "user",
                    "content": toolContextPrompt
                ]
            ]

            var accumulated = ""

            let finalResponse = try await ollama.chatStream(
                model: settings.selectedChatModel,
                messages: promptMessages,
                temperature: settings.temperature,
                contextSize: settings.contextSize
            ) { token in
                await MainActor.run {
                    accumulated += token
                    self.updateMessageContent(id: assistantMessageId, content: accumulated)
                }
            }

            let clean = cleanAssistantOutput(finalResponse)
            updateMessageContent(id: assistantMessageId, content: clean)

            conversations.appendMessage(
                ChatMessage(
                    id: assistantMessageId,
                    conversationId: currentConversationId,
                    role: .assistant,
                    content: clean,
                    createdAt: assistantCreatedAt
                )
            )
            refreshConversations()

        } catch {
            updateMessageContent(
                id: assistantMessageId,
                content: "Response error with tool context: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Memory

    private func handleExplicitMemoryIntent(_ text: String) async -> Bool {
        guard let appViewModel else { return false }

        let settings = appViewModel.settingsStore.settings
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        let isMemoryIntent =
            lower.hasPrefix("запомни") ||
            lower.hasPrefix("remember") ||
            lower.hasPrefix("/remember ")

        guard isMemoryIntent else { return false }

        guard settings.memoryMode != .off else {
            appendAssistant("Memory is disabled in Settings → Memory mode.")
            return true
        }

        guard !settings.selectedEmbeddingModel.isEmpty else {
            appendAssistant("Please select an embedding model in Settings.")
            return true
        }

        let candidate = extractMemoryCandidate(from: text)
        guard !candidate.isEmpty else {
            appendAssistant("What exactly should I remember? For example: «Remember that I have a meeting on Friday».")
            return true
        }

        do {
            let embedding = try await ollama.embedding(
                model: settings.selectedEmbeddingModel,
                prompt: candidate
            )

            memory.addMemory(
                type: "user_fact",
                content: candidate,
                importance: 8,
                embedding: embedding
            )

            appendAssistant("I remembered: \(candidate)")
        } catch {
            appendAssistant("Failed to save to memory: \(error.localizedDescription)")
        }

        return true
    }

    private func maybeStoreMemory(
        userText: String,
        assistantText: String,
        settings: AssistantSettings
    ) async {
        guard settings.memoryMode != .off else { return }

        let lower = userText.lowercased()
        let explicitRemember =
            lower.contains("remember that") ||
            lower.contains("remember") ||
            lower.contains("запомни") ||
            lower.contains("запомни что")

        if settings.memoryMode == .manual && !explicitRemember {
            return
        }

        do {
            let extractionPrompt = """
            You are a memory extraction module for a personal AI assistant.

            Analyze this short conversation and extract only stable, useful long-term facts about the user.
            Do not save temporary questions, jokes, random facts, or one-time requests.

            Return strict JSON only, without Markdown:
            {
              "memories": [
                {
                  "type": "user_fact | preference | project | instruction | task_context",
                  "content": "short memory text",
                  "importance": 1
                }
              ]
            }

            Rules:
            - If there is nothing worth remembering, return {"memories":[]}
            - Importance must be 1 to 10.
            - Use the same language as the fact.
            - Do not include private sensitive data unless user explicitly asked to remember it.

            User message:
            \(userText)

            Assistant response:
            \(assistantText)
            """

            let response = try await ollama.chat(
                model: settings.selectedChatModel,
                messages: [
                    ["role": "system", "content": "You extract assistant memory as strict JSON only."],
                    ["role": "user", "content": extractionPrompt]
                ],
                temperature: 0.1,
                contextSize: 2048
            )

            let jsonText = extractJSONObject(from: response, fallback: #"{"memories":[]}"#)
            guard let data = jsonText.data(using: .utf8) else { return }

            let decoded = try JSONDecoder().decode(MemoryExtractionResponse.self, from: data)

            if settings.memoryMode == .askBeforeSaving && !explicitRemember {
                if let first = decoded.memories.first {
                    let content = first.content.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !content.isEmpty else { return }

                    pendingMemoryConfirmation = PendingMemoryConfirmation(
                        type: first.type,
                        content: content,
                        importance: max(1, min(10, first.importance))
                    )
                }
                return
            }

            for item in decoded.memories {
                let content = item.content.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !content.isEmpty else { continue }

                let embedding = try await ollama.embedding(
                    model: settings.selectedEmbeddingModel,
                    prompt: content
                )

                memory.addMemory(
                    type: item.type,
                    content: content,
                    importance: max(1, min(10, item.importance)),
                    embedding: embedding
                )
            }

        } catch {
            print("Memory extraction failed:", error.localizedDescription)
        }
    }

    func confirmPendingMemory() async {
        guard let appViewModel, let pending = pendingMemoryConfirmation else { return }
        pendingMemoryConfirmation = nil

        let settings = appViewModel.settingsStore.settings

        do {
            let emb = try await ollama.embedding(
                model: settings.selectedEmbeddingModel,
                prompt: pending.content
            )

            memory.addMemory(
                type: pending.type,
                content: pending.content,
                importance: pending.importance,
                embedding: emb
            )

            appendAssistant("Saved in memory: \(pending.content)")
        } catch {
            appendAssistant("Failed to save to memory: \(error.localizedDescription)")
        }
    }

    func cancelPendingMemory() {
        pendingMemoryConfirmation = nil
        appendAssistant("Okay, I'm not saving this to memory..")
    }

    // MARK: - Calendar

    private func listTodayCalendarEvents() async {
        setToolStatus("Loading calendar events...")
        defer { setToolStatus(nil) }

        do {
            let events = try await calendarService.eventsForToday(limit: 12)

            if events.isEmpty {
                appendAssistant("There are no events on the calendar today.")
                return
            }

            let tf = DateFormatter()
            tf.timeStyle = .short
            tf.dateStyle = .none

            let lines = events.map { e in
                "• \(tf.string(from: e.startDate)) – \(e.title ?? "(untitled)")"
            }.joined(separator: "\n")

            appendAssistant("Events for today:\n\(lines)")
        } catch {
            appendAssistant("Unable to read the calendar: \(error.localizedDescription)")
        }
    }

    private func addCalendarEventFromCommand(_ raw: String) async {
        let parts = raw
            .components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        guard parts.count >= 2 else {
            appendAssistant("Format: /calendar add YYYY-MM-DD HH:mm | Event name")
            return
        }

        let datePart = parts[0]
        let title = parts[1]

        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd HH:mm"

        guard let start = df.date(from: datePart) else {
            appendAssistant("I can't parse the date. Use the format: YYYY-MM-DD HH:mm")
            return
        }

        let end = Calendar.current.date(byAdding: .minute, value: 60, to: start) ?? start.addingTimeInterval(3600)

        setToolStatus("Creating calendar event...")
        defer { setToolStatus(nil) }

        do {
            try await calendarService.addEvent(title: title, start: start, end: end)
            appendAssistant("Added an event to the calendar: \(title)")
        } catch {
            appendAssistant("Failed to add event: \(error.localizedDescription)")
        }
    }

    // MARK: - Pending tool actions

    func confirmPendingTool() {
        guard let pending = pendingToolConfirmation else { return }
        pendingToolConfirmation = nil

        switch pending.kind {
        case .openURL:
            openURL(pending.payload)

        case .webSearch:
            Task {
                await performWebSearch(query: pending.payload)
            }

        default:
            appendAssistant("Tool confirmation for \(pending.kind.title) is not implemented yet.")
        }
    }

    func cancelPendingTool() {
        pendingToolConfirmation = nil
        appendAssistant("Action canceled.")
    }

    func showCommandsHelp() {
        appendAssistant(commandsHelpText())
    }

    private func openURL(_ value: String) {
        var urlString = value.trimmingCharacters(in: .whitespacesAndNewlines)

        if !urlString.hasPrefix("http://") && !urlString.hasPrefix("https://") {
            urlString = "https://\(urlString)"
        }

        guard let url = URL(string: urlString) else {
            appendAssistant("Failed to open URL: \(value)")
            return
        }

        NSWorkspace.shared.open(url)
        appendAssistant("I'm opening it: \(url.absoluteString)")
    }

    // MARK: - Helpers
    
    private func effectiveWebSearchMode() -> WebSearchMode {
        appViewModel?.settingsStore.settings.webSearchMode ?? .askBeforeSearch
    }

    private func hasExplicitWebSearchIntent(_ text: String) -> Bool {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        let explicitWebPhrases = [
            "/search",
            "найди в интернете",
            "поищи в интернете",
            "поищи в сети",
            "найди в сети",
            "погугли",
            "загугли",
            "google",
            "search web",
            "web search",
            "find online",
            "look up online",
            "search online"
        ]

        return explicitWebPhrases.contains { lower.contains($0) }
    }

    private func shouldAllowWebSearchForText(_ text: String) -> Bool {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        if hasExplicitWebSearchIntent(lower) {
            return true
        }

        let freshnessPhrases = [
            "сегодня",
            "сейчас",
            "актуальн",
            "последн",
            "новости",
            "курс",
            "цена",
            "погода",
            "latest",
            "current",
            "today",
            "news",
            "price",
            "weather",
            "recent",
            "new version",
            "latest version"
        ]

        return freshnessPhrases.contains { lower.contains($0) }
    }
    
    

    private func setToolStatus(_ text: String?) {
        toolStatus = text
    }

    private func buildPromptMessages(
        settings: AssistantSettings,
        relevantMemories: [MemoryItem],
        userText: String
    ) -> [[String: String]] {
        var system = settings.systemPrompt

        if !settings.personalPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            system += "\n\nUser personal instructions:\n\(settings.personalPrompt)"
        }

        if !relevantMemories.isEmpty {
            let grouped = Dictionary(grouping: relevantMemories, by: { $0.type })

            system += "\n\nRelevant long-term memory. Use only if directly helpful:\n"

            for type in grouped.keys.sorted() {
                system += "\n\(type):\n"

                for item in grouped[type] ?? [] {
                    system += "- \(item.content)\n"
                }
            }
        }

        system += "\n\nAssistant language: \(settings.assistantLanguage)"

        let nowISO = ISO8601DateFormatter().string(from: Date())
        system += "\n\nCurrent local datetime: \(nowISO)"
        system += "\nUse this as the source of truth for local date/time-related answers."

        var result: [[String: String]] = [
            ["role": "system", "content": system]
        ]

        let cleanUserText = userText.trimmingCharacters(in: .whitespacesAndNewlines)

        let historyMessages: ArraySlice<ChatMessage>

        if let last = messages.last,
           last.role == .user,
           last.content.trimmingCharacters(in: .whitespacesAndNewlines) == cleanUserText {
            historyMessages = messages.dropLast()
        } else {
            historyMessages = messages[...]
        }

        for message in historyMessages.suffix(12) where message.role == .user || message.role == .assistant {
            let content = message.content.trimmingCharacters(in: .whitespacesAndNewlines)

            if !content.isEmpty {
                result.append([
                    "role": message.role.rawValue,
                    "content": content
                ])
            }
        }

        result.append([
            "role": "user",
            "content": cleanUserText
        ])

        return result
    }
    private func extractJSONObject(from text: String, fallback: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.hasPrefix("{"), trimmed.hasSuffix("}") {
            return trimmed
        }

        guard let start = trimmed.firstIndex(of: "{"),
              let end = trimmed.lastIndex(of: "}") else {
            return fallback
        }

        return String(trimmed[start...end])
    }

    private func extractMemoryCandidate(from text: String) -> String {
        var result = text

        let prefixes = [
            "remember that",
            "remember",
            "/remember",
            "запомни что",
            "запомни"
        ]

        for prefix in prefixes {
            result = result.replacingOccurrences(of: prefix, with: "", options: [.caseInsensitive])
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func appendAndSave(_ message: ChatMessage) {
        messages.append(message)
        conversations.appendMessage(message)

        if message.role == .user {
            let count = messages.filter { $0.role == .user }.count
            if count == 1 {
                let title = String(message.content.prefix(60))
                conversations.updateConversationTitle(
                    id: message.conversationId,
                    title: title.isEmpty ? "New conversation" : title
                )
            }
        }

        refreshConversations()
    }

    private func appendAssistant(_ text: String) {
        appendAndSave(
            ChatMessage(
                conversationId: currentConversationId,
                role: .assistant,
                content: text
            )
        )
    }

    private func updateMessageContent(id: UUID, content: String) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }

        let old = messages[index]
        messages[index] = ChatMessage(
            id: old.id,
            conversationId: old.conversationId,
            role: old.role,
            content: content,
            createdAt: old.createdAt,
            attachmentPath: old.attachmentPath
        )
    }

    private func makeReadableError(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return """
                Request timed out.

                Try:
                1. Use a smaller model.
                2. Reduce context size to 2048 or 4096.
                3. Warm up the model with ollama run.
                4. Make sure Ollama is running.
                """
            case .cannotConnectToHost, .notConnectedToInternet:
                return """
                Cannot connect to service.

                For local chat:
                ollama serve
                """
            default:
                return urlError.localizedDescription
            }
        }

        return error.localizedDescription
    }

    private func cleanAssistantOutput(_ text: String) -> String {
        var result = text

        result = result.replacingOccurrences(
            of: #"(?s)<think>.*?</think>"#,
            with: "",
            options: .regularExpression
        )

        if let range = result.range(of: "</think>", options: .backwards) {
            result = String(result[range.upperBound...])
        }

        let tokensToRemove = [
            "<think>", "</think>",
            "<|im_end|>", "<|im_start|>",
            "<|endoftext|>", "<|end|>",
            "<|assistant|>", "<|user|>", "<|system|>"
        ]

        for token in tokensToRemove {
            result = result.replacingOccurrences(of: token, with: "")
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func shouldDropDuplicateInput(_ text: String) -> Bool {
        let normalized = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return true }

        let now = Date()
        if normalized == lastInputFingerprint,
           now.timeIntervalSince(lastInputAt) < inputDedupWindow {
            return true
        }

        lastInputFingerprint = normalized
        lastInputAt = now
        return false
    }

    private func commandsHelpText() -> String {
        """
        Available commands:

        /help
        Show this message.

        /search <query>
        Search the internet.
        Example: /search ai news today

        /open <url>
        Open a website (with confirmation).
        Example: /open https://ollama.com

        /task <text>
        Add a task.
        Example: /task buy a microphone

        /tasks
        Show open tasks.

        /now
        Current date and time.

        /calendar today
        Events for today.

        /calendar add YYYY-MM-DD HH:mm | Title
        Add an event for 1 hour.
        Example:
        /calendar add 2026-08-10 15:30 | Call with a client
        """
    }

    private struct MemoryExtractionResponse: Codable {
        struct Item: Codable {
            let type: String
            let content: String
            let importance: Int
        }

        let memories: [Item]
    }
}

// MARK: - Supporting model

struct PendingMemoryConfirmation: Identifiable, Hashable {
    let id = UUID()
    let type: String
    let content: String
    let importance: Int
}
