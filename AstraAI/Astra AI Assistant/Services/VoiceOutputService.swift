//
//  VoiceOutputService.swift
//  AstraAssistant
//
//  Created by Alex on 10/8/26.
//



import Foundation
import AVFoundation
import Combine


@MainActor
final class VoiceOutputService: NSObject, ObservableObject {
    @Published var isSpeaking = false
    @Published var lastError: String?
    
    private let synthesizer = AVSpeechSynthesizer()
    private var audioPlayer: AVAudioPlayer?
    
    override init() {
        super.init()
        synthesizer.delegate = self
    }
    
    func speak(
        _ text: String,
        settings: AssistantSettings
    ) {
        let cleaned = cleanTextForSpeech(text)
        guard !cleaned.isEmpty else { return }
        
        stop()
        
        switch settings.ttsProvider {
        case .macOS:
            speakWithMacOS(cleaned, settings: settings)
            
        case .waveSpeedQwen3:
            speakWithWaveSpeed(cleaned, settings: settings)
            
        case .localQwen3:
            // Проверяем, что сервер готов
            Task { @MainActor in
                let ready = await TTSProcessManager.shared.isServerReady()
                if ready {
                    speakWithLocalQwen(cleaned, settings: settings)
                } else {
                    lastError = "Local Qwen TTS server is not ready. Check Settings → Voice → Local Qwen3 TTS."
                    isSpeaking = false
                }
            }
        }
    }
    
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        audioPlayer?.stop()
        audioPlayer = nil
        isSpeaking = false
    }
    
    private func speakWithLocalQwen(
        _ text: String,
        settings: AssistantSettings
    ) {
        let projectPath = settings.localQwenProjectPath
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !projectPath.isEmpty else {
            lastError = "Local Qwen project path is empty."
            return
        }
        
        isSpeaking = true
        lastError = nil
        
        Task.detached(priority: .userInitiated) {
            do {
                let audioData = try await LocalQwenTTSClient.shared.synthesizeSpeech(
                    text: text,
                    settings: settings
                )
                
                await MainActor.run {
                    self.playAudioData(audioData)
                }
                
            } catch {
                await MainActor.run {
                    self.lastError = error.localizedDescription
                    self.isSpeaking = false
                }
            }
        }
    }
    
    private func speakWithMacOS(
        _ text: String,
        settings: AssistantSettings
    ) {
        let utterance = AVSpeechUtterance(string: text)
        
        if !settings.macOSVoiceIdentifier.isEmpty,
           let voice = AVSpeechSynthesisVoice(identifier: settings.macOSVoiceIdentifier) {
            utterance.voice = voice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: settings.assistantLanguage)
        }
        
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.volume = 1.0
        utterance.pitchMultiplier = 1.0
        
        synthesizer.speak(utterance)
    }
    
    private func speakWithWaveSpeed(
        _ text: String,
        settings: AssistantSettings
    ) {
        guard !settings.waveSpeedReferenceAudioURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            lastError = "Reference audio URL is empty."
            return
        }
        
        isSpeaking = true
        lastError = nil
        
        Task.detached(priority: .userInitiated) {
            do {
                let audioData = try await WaveSpeedTTSClient.shared.synthesizeSpeech(
                    text: text,
                    settings: settings
                )
                
                await MainActor.run {
                    self.playAudioData(audioData)
                }
                
            } catch {
                await MainActor.run {
                    self.lastError = error.localizedDescription
                    self.isSpeaking = false
                }
            }
        }
    }
    
    private func playAudioData(_ data: Data) {
        do {
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            isSpeaking = true
        } catch {
            lastError = error.localizedDescription
            isSpeaking = false
        }
    }
    
    private func cleanTextForSpeech(_ text: String) -> String {
        var result = text
        
        // Удаляем think-блоки
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
            "<|im_end|>", "<|im_start|>", "<|endoftext|>", "<|end|>",
            "<|assistant|>", "<|user|>", "<|system|>",
            "```", "**", "`", "#", "*"
        ]
        
        for token in tokensToRemove {
            result = result.replacingOccurrences(of: token, with: "")
        }
        
        // ✅ Удаляем эмодзи
        result = removeEmojis(from: result)
        
        // Нормализуем пробелы
        result = result.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func removeEmojis(from text: String) -> String {
        String(text.filter { character in
            !character.unicodeScalars.contains { scalar in
                scalar.properties.isEmojiPresentation
            }
        })
    }
}

private struct WaveSpeedTTSResponse: Codable {
    let ok: Bool
    let prediction_id: String?
    let status: String?
    let audio_url: String?
    let outputs: [String]?
    let error: String?
}

extension VoiceOutputService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didStart utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            self.isSpeaking = true
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            self.isSpeaking = false
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            self.isSpeaking = false
        }
    }
}

extension VoiceOutputService: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(
        _ player: AVAudioPlayer,
        successfully flag: Bool
    ) {
        Task { @MainActor in
            self.isSpeaking = false
            self.audioPlayer = nil
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(
        _ player: AVAudioPlayer,
        error: Error?
    ) {
        Task { @MainActor in
            self.lastError = error?.localizedDescription
            self.isSpeaking = false
            self.audioPlayer = nil
        }
    }
}
