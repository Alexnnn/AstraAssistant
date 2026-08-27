//
//  VoiceModeController.swift
//  AstraAssistant
//
//  Created by Alex on 10/8/26.
//

import Foundation
import Combine

@MainActor
final class VoiceModeController: ObservableObject {
    @Published var mode: ListeningMode = .manual
    @Published var isActive = false
    @Published var transcript = ""
    @Published var statusText = "Idle"
    

    let inputService = VoiceInputService()
    var onUserUtterance: ((String) -> Void)?
    
    private var suspendedByAssistantSpeech = false
    
    private var settings: AssistantSettings?
    private var localeValue: String = "en-US"

    // wake phrase state
    private var wakeArmedUntil: Date?
    private let wakeWindow: TimeInterval = 8

    // restart/session state
    private var restarting = false
    private var rollingRestartTask: Task<Void, Never>?
    private var silenceCommitTask: Task<Void, Never>?
    private var lastPartialSnapshot = ""

    // anti-duplicate output
    private var lastEmittedText: String = ""
    private var lastEmittedAt: Date = .distantPast
    private let dedupWindow: TimeInterval = 2.0

    private let silenceCommitDelayNs: UInt64 = 1_100_000_000 // 1.1 sec
    private let rollingRestartIntervalNs: UInt64 = 50_000_000_000 // 50 sec

    init() {
        inputService.onPartialResult = { [weak self] text in
            Task { @MainActor in
                self?.handlePartialText(text)
            }
        }

        inputService.onFinalResult = { [weak self] text in
            Task { @MainActor in
                self?.handleFinalText(text)
            }
        }

        inputService.onSessionEnded = { [weak self] _ in
            Task { @MainActor in
                self?.restartIfNeeded()
            }
        }
    }

    deinit {
        rollingRestartTask?.cancel()
        silenceCommitTask?.cancel()
    }
    
    func suspendForAssistantSpeech() {
        guard isActive else { return }
        guard mode == .continuous || mode == .wakePhrase else { return }
        guard !suspendedByAssistantSpeech else { return }

        suspendedByAssistantSpeech = true
        inputService.stopListening()
        statusText = "Assistant speaking..."
    }

    func resumeAfterAssistantSpeechIfNeeded() async {
        guard isActive else { return }
        guard mode == .continuous || mode == .wakePhrase else { return }
        guard suspendedByAssistantSpeech else { return }

        suspendedByAssistantSpeech = false
        let ok = await inputService.startListening(localeIdentifier: localeValue)
        if ok {
            statusText = (mode == .continuous) ? "Continuous listening" : "Waiting for wake phrase"
        } else {
            statusText = inputService.errorMessage ?? "Voice restart failed"
        }
    }

    func configure(settings: AssistantSettings) {
        self.settings = settings
        self.mode = settings.listeningMode
    }

    func start() async {
        guard let settings else { return }

        mode = settings.listeningMode
        localeValue = localeIdentifier(from: settings.assistantLanguage)

        transcript = ""
        lastPartialSnapshot = ""
        isActive = true

        switch mode {
        case .manual: statusText = "Manual voice input"
        case .pushToTalk: statusText = "Push-to-talk listening"
        case .holdToTalk: statusText = "Hold-to-talk listening"
        case .continuous: statusText = "Continuous listening"
        case .wakePhrase: statusText = "Waiting for wake phrase"
        }

        let ok = await inputService.startListening(localeIdentifier: localeValue)
        if !ok {
            isActive = false
            statusText = inputService.errorMessage ?? "Voice start failed"
            return
        }

        scheduleRollingRestartIfNeeded()
    }

    func stop() {
        rollingRestartTask?.cancel()
        rollingRestartTask = nil

        silenceCommitTask?.cancel()
        silenceCommitTask = nil

        inputService.stopListening()
        isActive = false
        wakeArmedUntil = nil
        statusText = "Idle"
    }

    func pushToTalkPressed() async {
        guard mode == .pushToTalk || mode == .manual else { return }
        await start()
    }

    func pushToTalkReleased() {
        guard mode == .pushToTalk || mode == .manual else { return }
        let final = finalTranscript()
        stop()

        guard !final.isEmpty else { return }
        emitUtteranceIfNeeded(final)
    }

    func holdToTalkBegan() async {
        guard mode == .holdToTalk else { return }
        await start()
    }

    func holdToTalkEnded() {
        guard mode == .holdToTalk else { return }
        let final = finalTranscript()
        stop()

        guard !final.isEmpty else { return }
        emitUtteranceIfNeeded(final)
    }

    private func handlePartialText(_ text: String) {
        
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        guard !suspendedByAssistantSpeech else { return }

        transcript = cleaned
        lastPartialSnapshot = cleaned

        if mode == .continuous || mode == .wakePhrase {
            scheduleSilenceCommit()
        }
    }

    private func handleFinalText(_ text: String) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !suspendedByAssistantSpeech else { return }
        guard !cleaned.isEmpty else {
            restartIfNeeded()
            return
        }

        transcript = cleaned
        lastPartialSnapshot = cleaned

        switch mode {
        case .manual, .pushToTalk, .holdToTalk:
            // отправка только on release / send button
            break

        case .continuous, .wakePhrase:
            silenceCommitTask?.cancel()
            processCommittedUtterance(cleaned)
            restartIfNeeded()
        }
    }

    private func scheduleSilenceCommit() {
        silenceCommitTask?.cancel()
        let snapshot = lastPartialSnapshot

        silenceCommitTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: silenceCommitDelayNs)
            guard let self else { return }
            guard self.isActive else { return }
            guard snapshot == self.lastPartialSnapshot else { return }

            let candidate = snapshot.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !candidate.isEmpty else { return }

            self.processCommittedUtterance(candidate)
            self.restartIfNeeded()
        }
    }

    private func processCommittedUtterance(_ utterance: String) {
        let cleaned = utterance.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        switch mode {
        case .manual, .pushToTalk, .holdToTalk:
            break

        case .continuous:
            statusText = "Continuous: command sent"
            emitUtteranceIfNeeded(cleaned)

        case .wakePhrase:
            handleWakePhraseUtterance(cleaned)
        }
    }

    private func handleWakePhraseUtterance(_ text: String) {
        guard let settings else { return }

        let normalizedText = normalizeForWake(text)

        if let wake = settings.wakePhrases.first(where: { normalizedText.contains(normalizeForWake($0)) }) {
            let wakeNorm = normalizeForWake(wake)
            let command = normalizedText
                .replacingOccurrences(of: wakeNorm, with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if !command.isEmpty {
                statusText = "Wake: command sent"
                emitUtteranceIfNeeded(command)
                wakeArmedUntil = nil
            } else {
                wakeArmedUntil = Date().addingTimeInterval(wakeWindow)
                statusText = "Wake detected. Speak command..."
            }
            return
        }

        if let armed = wakeArmedUntil, Date() <= armed {
            statusText = "Wake: command sent"
            emitUtteranceIfNeeded(normalizedText)
            wakeArmedUntil = nil
        } else {
            statusText = "Waiting for wake phrase"
        }
    }

    private func emitUtteranceIfNeeded(_ text: String) {
        let normalized = text
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else { return }

        let now = Date()
        if normalized == lastEmittedText,
           now.timeIntervalSince(lastEmittedAt) < dedupWindow {
            return
        }

        lastEmittedText = normalized
        lastEmittedAt = now

        onUserUtterance?(text)
    }

    private func restartIfNeeded() {
        guard !suspendedByAssistantSpeech else { return }
        guard isActive else { return }
        guard mode == .continuous || mode == .wakePhrase else { return }
        guard !restarting else { return }

        restarting = true

        Task { @MainActor in
            inputService.stopListening()
            try? await Task.sleep(nanoseconds: 250_000_000)

            if isActive {
                _ = await inputService.startListening(localeIdentifier: localeValue)
            }

            restarting = false
        }
    }

    private func scheduleRollingRestartIfNeeded() {
        rollingRestartTask?.cancel()
        guard mode == .continuous || mode == .wakePhrase else { return }

        rollingRestartTask = Task { @MainActor [weak self] in
            guard let self else { return }

            while !Task.isCancelled && self.isActive && (self.mode == .continuous || self.mode == .wakePhrase) {
                try? await Task.sleep(nanoseconds: rollingRestartIntervalNs)
                if Task.isCancelled { return }
                self.restartIfNeeded()
            }
        }
    }

    private func finalTranscript() -> String {
        let candidate = !inputService.lastFinalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? inputService.lastFinalText
            : transcript
        return candidate.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizeForWake(_ value: String) -> String {
        let lowered = value.lowercased()
        let cleaned = lowered.replacingOccurrences(
            of: #"[^a-zа-я0-9\s]"#,
            with: " ",
            options: .regularExpression
        )

        return cleaned
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func localeIdentifier(from value: String) -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)

        if normalized.contains("-") {
            return normalized
        }

        switch normalized.lowercased() {
        case "ru", "russian": return "ru-RU"
        case "en", "english": return "en-US"
        case "es", "spanish": return "es-ES"
        case "de", "german": return "de-DE"
        case "fr", "french": return "fr-FR"
        case "it", "italian": return "it-IT"
        case "pt", "portuguese": return "pt-BR"
        default: return "en-US"
        }
    }
}
