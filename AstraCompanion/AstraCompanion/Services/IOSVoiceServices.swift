//
//  IOSVoiceServices.swift
//  AstraCompanion
//
//  Created by Alex on 13/8/26.
//

import Foundation
import AVFoundation
import Speech
import Combine

enum IOSVoiceOutputMode: String {
    case local
    case mac
}

struct RemoteTTSConfig {
    let baseURL: String
    let referenceAudioURL: String
    let referenceText: String
    let language: String
    let maxWaitSeconds: Int
}

@MainActor
final class IOSSpeechToTextService: ObservableObject {
    @Published var isListening = false
    @Published var transcript = ""
    @Published var errorText: String?

    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?
    private var userStopped = false

    func requestPermissions() async -> Bool {
        let micGranted = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }

        let speechGranted = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }

        return micGranted && speechGranted
    }

    func start(locale: String = "ru-RU") async {
        let granted = await requestPermissions()
        guard granted else {
            errorText = "Microphone or Speech permission denied."
            return
        }

        stopInternal()

        recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale))
        guard let recognizer, recognizer.isAvailable else {
            errorText = "Speech recognizer unavailable."
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorText = "Audio session error: \(error.localizedDescription)"
            return
        }

        userStopped = false
        transcript = ""
        errorText = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()

        do {
            try audioEngine.start()
            isListening = true
        } catch {
            errorText = "Audio engine start failed: \(error.localizedDescription)"
            stopInternal()
            return
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }

                if let result {
                    self.transcript = result.bestTranscription.formattedString
                }

                if let error {
                    if !self.userStopped {
                        self.errorText = "Recognition error: \(error.localizedDescription)"
                    }
                    self.stopInternal()
                }
            }
        }
    }

    func stopAndGetTranscript() -> String {
        userStopped = true
        let final = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        stopInternal()
        return final
    }

    func stop() {
        userStopped = true
        stopInternal()
    }

    private func stopInternal() {
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)

        recognitionRequest?.endAudio()
        recognitionRequest = nil

        recognitionTask?.cancel()
        recognitionTask = nil

        isListening = false

        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }
}

@MainActor
final class IOSVoiceOutputService: NSObject, ObservableObject {
    @Published var isSpeaking = false
    @Published var lastError: String?
    
    private var endObserver: NSObjectProtocol?

    private let synthesizer = AVSpeechSynthesizer()
    private var player: AVPlayer?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(
        _ text: String,
        mode: IOSVoiceOutputMode,
        localLanguage: String = "ru-RU",
        remoteConfig: RemoteTTSConfig? = nil
    ) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }

        stop()
        lastError = nil

        do {
            try preparePlaybackSession()
        } catch {
            lastError = "Audio session error: \(error.localizedDescription)"
            return
        }

        switch mode {
        case .local:
            let utterance = AVSpeechUtterance(string: clean)
            utterance.voice = AVSpeechSynthesisVoice(language: localLanguage)
            utterance.volume = 1.0
            utterance.pitchMultiplier = 1.0
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate

            synthesizer.speak(utterance)

        case .mac:
            // Используем Mac TTS через Firebase
            lastError = "Use synthesizeSpeechOnMac() from CompanionChatViewModel"
            isSpeaking = false
        }
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)

        player?.pause()
        player = nil

        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }

        isSpeaking = false
    }
    
    func playAudioURL(_ url: URL) {
        stop()
        lastError = nil

        do {
            try preparePlaybackSession()
        } catch {
            lastError = "Audio session error: \(error.localizedDescription)"
            return
        }

        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        p.volume = 1.0

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isSpeaking = false
                self?.player = nil

                if let observer = self?.endObserver {
                    NotificationCenter.default.removeObserver(observer)
                    self?.endObserver = nil
                }
            }
        }

        player = p
        isSpeaking = true
        p.play()
    }

    private func preparePlaybackSession() throws {
        let session = AVAudioSession.sharedInstance()

        try session.setCategory(
            .playback,
            mode: .spokenAudio,
            options: [.duckOthers]
        )

        try session.setActive(true, options: [])
    }
}

extension IOSVoiceOutputService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = true }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
}
