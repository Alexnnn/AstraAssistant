//
//  CompanionChatViewModel.swift
//  AstraCompanion
//
//  Created by Alex on 13/8/26.
//


import Foundation
import SwiftUI
import FirebaseFirestore
import Combine

struct CompanionUIMessage: Identifiable, Hashable {
    let id: String
    let role: String
    let text: String
    let imageURL: String?
    let attachmentURL: String?
    let attachmentType: String?
    let createdAt: Date
    let isLocalPending: Bool
}

@MainActor
final class CompanionChatViewModel: ObservableObject {
    @Published var messages: [CompanionUIMessage] = []
    @Published var inputText: String = ""

    @Published var isSending = false
    @Published var isAwaitingAssistant = false
    @Published var statusText = "Idle"
    @Published var lastError: String?
    @Published var autoSpeak = false

    @Published private(set) var macUID: String = ""
    @Published private(set) var macDeviceID: String = ""
    @Published private(set) var conversationId: String?

    private let client = CompanionCommandClient.shared
    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    private var pendingLocal: [CompanionUIMessage] = []
    
    // TTS состояние
    private var lastSpokenMessageId: String?
    let tts = IOSVoiceOutputService()
    
    

    deinit {
        listener?.remove()
    }

    // MARK: Connection

    func applyConnection(_ profile: ConnectionProfile) {
        macUID = profile.macUID
        macDeviceID = profile.macDeviceID
        conversationId = profile.conversationId
        subscribe()
    }

    func clearConnection() {
        listener?.remove()
        listener = nil

        macUID = ""
        macDeviceID = ""
        conversationId = nil

        pendingLocal = []
        messages = []
        inputText = ""

        isSending = false
        isAwaitingAssistant = false
        statusText = "Idle"
        lastError = nil
    }

    func setConversation(_ id: String) {
        conversationId = id
        persist()
        subscribe()
    }

    func startNewConversation() {
        conversationId = nil
        pendingLocal = []
        messages = []
        persist()
        statusText = "New conversation"
    }

    // MARK: Chat send

    func send() async {
        let text = inputText
        inputText = ""
        await sendText(text)
    }

    func sendText(_ text: String) async {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }

        guard !macUID.isEmpty, !macDeviceID.isEmpty else {
            lastError = "Not connected to Mac."
            return
        }

        guard !isSending else { return }

        ensureConversationIfNeeded()

        isSending = true
        isAwaitingAssistant = true
        statusText = "Sending..."
        lastError = nil

        appendPendingUserMessage(text: clean, attachmentURL: nil, attachmentType: nil)

        defer { isSending = false }

        do {
            let commandId = try await client.sendCommand(
                macUID: macUID,
                targetDevice: macDeviceID,
                type: .chatSend,
                payload: [
                    "text": clean,
                    "conversationId": conversationId ?? ""
                ]
            )

            let response = try await client.waitForResponse(
                macUID: macUID,
                commandId: commandId,
                timeoutSeconds: 120
            )

            if let cid = response.conversationId, !cid.isEmpty, cid != conversationId {
                conversationId = cid
                persist()
                subscribe()
            }

            statusText = "Done"
            isAwaitingAssistant = false

        } catch {
            statusText = "Failed"
            isAwaitingAssistant = false
            lastError = error.localizedDescription
        }
    }

    // MARK: Commands

    func generateImage(prompt: String) async {
        let clean = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        guard !macUID.isEmpty, !macDeviceID.isEmpty else { return }

        ensureConversationIfNeeded()

        isSending = true
        isAwaitingAssistant = true
        statusText = "Generating image..."
        lastError = nil

        appendPendingUserMessage(text: "Generate image: \(clean)", attachmentURL: nil, attachmentType: nil)

        defer { isSending = false }

        do {
            let cmd = try await client.sendCommand(
                macUID: macUID,
                targetDevice: macDeviceID,
                type: .imageGenerate,
                payload: [
                    "prompt": clean,
                    "conversationId": conversationId ?? ""
                ]
            )

            _ = try await client.waitForResponse(macUID: macUID, commandId: cmd, timeoutSeconds: 240)

            statusText = "Done"
            isAwaitingAssistant = false
        } catch {
            statusText = "Failed"
            isAwaitingAssistant = false
            lastError = error.localizedDescription
        }
    }
    
    func runRemoteAction(
        type: CompanionCommandType,
        payload: [String: Any],
        userVisibleText: String,
        status: String,
        timeoutSeconds: TimeInterval = 180
    ) async {
        guard !macUID.isEmpty, !macDeviceID.isEmpty else {
            lastError = "Not connected to Mac."
            return
        }

        guard !isSending else { return }

        ensureConversationIfNeeded()

        isSending = true
        isAwaitingAssistant = true
        statusText = status
        lastError = nil

        appendPendingUserMessage(
            text: userVisibleText,
            attachmentURL: nil,
            attachmentType: nil
        )

        defer {
            isSending = false
        }

        var finalPayload = payload
        finalPayload["conversationId"] = conversationId ?? ""

        do {
            let commandId = try await client.sendCommand(
                macUID: macUID,
                targetDevice: macDeviceID,
                type: type,
                payload: finalPayload
            )

            let response = try await client.waitForResponse(
                macUID: macUID,
                commandId: commandId,
                timeoutSeconds: timeoutSeconds
            )

            if let cid = response.conversationId,
               !cid.isEmpty,
               cid != conversationId {
                conversationId = cid
                persist()
                subscribe()
            }

            statusText = "Done"
            isAwaitingAssistant = false

        } catch {
            statusText = "Failed"
            isAwaitingAssistant = false
            lastError = error.localizedDescription
        }
    }

    func analyzeImage(publicURL: String, prompt: String) async {
        let imageURL = publicURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !imageURL.isEmpty else { return }
        guard !macUID.isEmpty, !macDeviceID.isEmpty else { return }

        ensureConversationIfNeeded()

        isSending = true
        isAwaitingAssistant = true
        statusText = "Analyzing image..."
        lastError = nil

        appendPendingUserMessage(
            text: cleanPrompt.isEmpty ? "Analyze image" : cleanPrompt,
            attachmentURL: imageURL,
            attachmentType: "image"
        )

        defer { isSending = false }

        do {
            let cmd = try await client.sendCommand(
                macUID: macUID,
                targetDevice: macDeviceID,
                type: .imageAnalyze,
                payload: [
                    "imageURL": imageURL,
                    "prompt": cleanPrompt.isEmpty ? "Analyze this image." : cleanPrompt,
                    "conversationId": conversationId ?? ""
                ]
            )

            _ = try await client.waitForResponse(macUID: macUID, commandId: cmd, timeoutSeconds: 240)

            statusText = "Done"
            isAwaitingAssistant = false
        } catch {
            statusText = "Failed"
            isAwaitingAssistant = false
            lastError = error.localizedDescription
        }
    }

    func editImage(publicURL: String, prompt: String) async {
        let imageURL = publicURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !imageURL.isEmpty else { return }
        guard !cleanPrompt.isEmpty else { return }
        guard !macUID.isEmpty, !macDeviceID.isEmpty else { return }

        ensureConversationIfNeeded()

        isSending = true
        isAwaitingAssistant = true
        statusText = "Editing image..."
        lastError = nil

        appendPendingUserMessage(
            text: "Edit image: \(cleanPrompt)",
            attachmentURL: imageURL,
            attachmentType: "image"
        )

        defer { isSending = false }

        do {
            let cmd = try await client.sendCommand(
                macUID: macUID,
                targetDevice: macDeviceID,
                type: .imageEdit,
                payload: [
                    "imageURL": imageURL,
                    "prompt": cleanPrompt,
                    "conversationId": conversationId ?? ""
                ]
            )

            _ = try await client.waitForResponse(macUID: macUID, commandId: cmd, timeoutSeconds: 300)

            statusText = "Done"
            isAwaitingAssistant = false
        } catch {
            statusText = "Failed"
            isAwaitingAssistant = false
            lastError = error.localizedDescription
        }
    }
    
    func summarizeFile(publicURL: String, fileName: String) async {
        let fileURL = publicURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fileURL.isEmpty else { return }
        guard !macUID.isEmpty, !macDeviceID.isEmpty else { return }

        ensureConversationIfNeeded()

        isSending = true
        isAwaitingAssistant = true
        statusText = "Summarizing file..."
        lastError = nil

        appendPendingUserMessage(
            text: "Summarize file: \(fileName)",
            attachmentURL: fileURL,
            attachmentType: "file"
        )

        defer { isSending = false }

        do {
            let cmd = try await client.sendCommand(
                macUID: macUID,
                targetDevice: macDeviceID,
                type: .fileSummarize,
                payload: [
                    "fileURL": fileURL,
                    "fileName": fileName,
                    "conversationId": conversationId ?? ""
                ]
            )

            _ = try await client.waitForResponse(macUID: macUID, commandId: cmd, timeoutSeconds: 300)

            statusText = "Done"
            isAwaitingAssistant = false
        } catch {
            statusText = "Failed"
            isAwaitingAssistant = false
            lastError = error.localizedDescription
        }
    }
    
    // MARK: - Mac TTS
    
    /// Запросить синтез речи на Mac и получить URL аудио
    func synthesizeSpeechOnMac(text: String) async throws -> URL {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !clean.isEmpty else {
            throw NSError(
                domain: "CompanionTTS",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Text is empty."]
            )
        }

        guard !macUID.isEmpty, !macDeviceID.isEmpty else {
            throw NSError(
                domain: "CompanionTTS",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "Not connected to Mac."]
            )
        }

        statusText = "Synthesizing voice on Mac..."
        lastError = nil

        let commandId = try await client.sendCommand(
            macUID: macUID,
            targetDevice: macDeviceID,
            type: .ttsSynthesize,
            payload: [
                "text": clean
            ]
        )

        let response = try await client.waitForResponse(
            macUID: macUID,
            commandId: commandId,
            timeoutSeconds: 180
        )

        let rawURL = response.audioURL ?? response.attachmentURL

        guard let rawURL,
              let url = URL(string: rawURL) else {
            throw NSError(
                domain: "CompanionTTS",
                code: 500,
                userInfo: [NSLocalizedDescriptionKey: "Mac did not return audioURL."]
            )
        }

        statusText = "Voice ready"
        return url
    }
    
    /// Воспроизвести текст через Mac TTS (автоматически синтезирует и проигрывает)
    func speakOnMac(_ text: String, ttsService: IOSVoiceOutputService) async {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        
        do {
            let audioURL = try await synthesizeSpeechOnMac(text: clean)
            ttsService.playAudioURL(audioURL)
        } catch {
            lastError = "Mac TTS failed: \(error.localizedDescription)"
        }
    }

    // MARK: Subscribe

    private func subscribe() {
        listener?.remove()
        listener = nil

        guard !macUID.isEmpty,
              let cid = conversationId,
              !cid.isEmpty else {
            messages = pendingLocal
            return
        }

        listener = db.collection("users")
            .document(macUID)
            .collection("remoteConversations")
            .document(cid)
            .collection("messages")
            .order(by: "createdAt", descending: false)
            .addSnapshotListener { [weak self] snap, err in
                guard let self else { return }

                if let err {
                    self.lastError = err.localizedDescription
                    return
                }

                guard let docs = snap?.documents else { return }

                let remote: [CompanionUIMessage] = docs.map { d in
                    let m = d.data()
                    let text = (m["text"] as? String) ?? ""

                    let explicitAttachmentURL = m["attachmentURL"] as? String
                    let legacyImageURL = m["imageURL"] as? String
                    let inferredURLFromText = Self.extractFirstURL(from: text)

                    let attachmentURL = explicitAttachmentURL ?? legacyImageURL ?? inferredURLFromText
                    let explicitType = m["attachmentType"] as? String
                    let inferredType = Self.inferAttachmentType(urlString: attachmentURL, text: text)

                    return CompanionUIMessage(
                        id: d.documentID,
                        role: (m["role"] as? String) ?? "system",
                        text: text,
                        imageURL: legacyImageURL,
                        attachmentURL: attachmentURL,
                        attachmentType: explicitType ?? inferredType,
                        createdAt: (m["createdAt"] as? Timestamp)?.dateValue() ?? Date.distantPast,
                        isLocalPending: false
                    )
                }

                self.pendingLocal.removeAll { pending in
                    remote.contains(where: { $0.role == "user" && $0.text == pending.text })
                }

                self.rebuildDisplayedMessages(remote: remote)
            }
    }

    // MARK: Helpers

    private func ensureConversationIfNeeded() {
        if conversationId == nil || conversationId?.isEmpty == true {
            conversationId = UUID().uuidString
            persist()
            subscribe()
        }
    }

    private func appendPendingUserMessage(text: String, attachmentURL: String?, attachmentType: String?) {
        let pending = CompanionUIMessage(
            id: "local-\(UUID().uuidString)",
            role: "user",
            text: text,
            imageURL: nil,
            attachmentURL: attachmentURL,
            attachmentType: attachmentType,
            createdAt: Date(),
            isLocalPending: true
        )
        pendingLocal.append(pending)
        rebuildDisplayedMessages(remote: messages.filter { !$0.isLocalPending })
    }

    private func rebuildDisplayedMessages(remote: [CompanionUIMessage]) {
        let merged = (remote + pendingLocal).sorted { $0.createdAt < $1.createdAt }

        var seen = Set<String>()
        let unique = merged.filter { m in
            let key = "\(m.role)|\(m.text)|\(Int(m.createdAt.timeIntervalSince1970))|\(m.attachmentURL ?? "")|\(m.attachmentType ?? "")"
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }

        messages = unique
    }

    private func persist() {
        guard !macUID.isEmpty, !macDeviceID.isEmpty else { return }

        ConnectionProfileStore.shared.save(
            ConnectionProfile(
                macUID: macUID,
                macDeviceID: macDeviceID,
                conversationId: conversationId
            )
        )
    }

    private static func extractFirstURL(from text: String) -> String? {
        let pattern = #"https?://[^\s]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let r = Range(match.range, in: text) else { return nil }
        return String(text[r])
    }

    private static func inferAttachmentType(urlString: String?, text: String) -> String? {
        guard let urlString, let url = URL(string: urlString) else { return nil }

        let ext = url.pathExtension.lowercased()
        if ["png", "jpg", "jpeg", "webp", "heic"].contains(ext) { return "image" }
        if ["pdf", "txt", "md", "json", "csv", "doc", "docx"].contains(ext) { return "file" }

        let lower = text.lowercased()
        if lower.contains("summarize file") || lower.contains("документ") || lower.contains("file:") {
            return "file"
        }
        return "image"
    }
}

extension CompanionChatViewModel {
    static func inferPublicAttachmentTypeForUI(urlString: String?) -> String? {
        guard let urlString,
              let url = URL(string: urlString) else {
            return nil
        }

        let ext = url.pathExtension.lowercased()

        if ["png", "jpg", "jpeg", "webp", "heic"].contains(ext) {
            return "image"
        }

        if ["pdf", "txt", "md", "json", "csv", "doc", "docx"].contains(ext) {
            return "file"
        }

        if ["mp3", "wav", "m4a", "aac"].contains(ext) {
            return "audio"
        }

        return nil
    }
}
