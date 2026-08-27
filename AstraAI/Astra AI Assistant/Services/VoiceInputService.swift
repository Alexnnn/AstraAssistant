//
//  VoiceInputService.swift
//  AstraAssistant
//
//  Created by Alex on 10/8/26.
//


import Foundation
import AVFoundation
import Speech
import Combine

@MainActor
final class VoiceInputService: ObservableObject {
    @Published var isListening = false
    @Published var partialText = ""
    @Published var lastFinalText = ""
    @Published var errorMessage: String?

    var onPartialResult: ((String) -> Void)?
    var onFinalResult: ((String) -> Void)?
    var onSessionEnded: ((Error?) -> Void)?

    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var speechRecognizer: SFSpeechRecognizer?

    func requestPermissions() async -> Bool {
        let micGranted = await requestMicrophonePermission()
        let speechGranted = await requestSpeechPermission()
        return micGranted && speechGranted
    }

    @discardableResult
    func startListening(localeIdentifier: String = "en-US") async -> Bool {
        let granted = await requestPermissions()
        guard granted else {
            errorMessage = "Microphone or Speech Recognition permission denied."
            return false
        }

        stopListening()

        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier))
        guard let speechRecognizer else {
            errorMessage = "Speech recognizer is not available for locale \(localeIdentifier)."
            return false
        }

        guard speechRecognizer.isAvailable else {
            errorMessage = "Speech recognizer is currently unavailable for \(localeIdentifier)."
            return false
        }

        partialText = ""
        lastFinalText = ""
        errorMessage = nil

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else {
            errorMessage = "Unable to create speech recognition request."
            return false
        }

        recognitionRequest.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()

        do {
            try audioEngine.start()
            isListening = true
        } catch {
            errorMessage = error.localizedDescription
            isListening = false
            return false
        }

        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }

            Task { @MainActor in
                if let result {
                    let text = result.bestTranscription.formattedString
                    self.partialText = text
                    self.onPartialResult?(text)

                    if result.isFinal {
                        self.lastFinalText = text
                        self.onFinalResult?(text)
                    }
                }

                if let error {
                    self.cleanupAfterSessionEnd()
                    self.onSessionEnded?(error)
                }
            }
        }

        return true
    }

    func stopListening() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)

        recognitionRequest?.endAudio()
        recognitionRequest = nil

        recognitionTask?.cancel()
        recognitionTask = nil

        isListening = false
    }

    private func cleanupAfterSessionEnd() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)

        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask = nil
        isListening = false
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func requestSpeechPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
}
