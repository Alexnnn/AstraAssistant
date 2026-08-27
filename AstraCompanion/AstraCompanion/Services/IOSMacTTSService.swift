//
//  IOSMacTTSService.swift
//  AstraCompanion
//
//  Created by Alex on 23/8/26.
//

import Foundation
import AVFoundation
import Combine

/// Сервис для синтеза речи на Mac через Firebase
@MainActor
final class IOSMacTTSService: ObservableObject {
    static let shared = IOSMacTTSService()
    private init() {}
    
    @Published var isGenerating = false
    @Published var lastError: String?
    
    private let client = CompanionCommandClient.shared
    private var audioPlayer: AVPlayer?
    private var endObserver: NSObjectProtocol?
    
    /// Генерирует речь на Mac и возвращает URL аудио файла
    func synthesize(
        macUID: String,
        macDeviceID: String,
        text: String,
        timeoutSeconds: TimeInterval = 180
    ) async throws -> URL {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else {
            throw NSError(
                domain: "MacTTSService",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Text is empty."]
            )
        }
        
        guard !macUID.isEmpty, !macDeviceID.isEmpty else {
            throw NSError(
                domain: "MacTTSService",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "Not connected to Mac."]
            )
        }
        
        isGenerating = true
        defer { isGenerating = false }
        
        let commandId = try await client.sendCommand(
            macUID: macUID,
            targetDevice: macDeviceID,
            type: .ttsSynthesize,
            payload: ["text": clean]
        )
        
        let response = try await client.waitForResponse(
            macUID: macUID,
            commandId: commandId,
            timeoutSeconds: timeoutSeconds
        )
        
        let rawURL = response.audioURL ?? response.attachmentURL
        
        guard let rawURL,
              let url = URL(string: rawURL) else {
            throw NSError(
                domain: "MacTTSService",
                code: 500,
                userInfo: [NSLocalizedDescriptionKey: "Mac did not return audioURL."]
            )
        }
        
        return url
    }
    
    /// Синтезирует и сразу воспроизводит
    func speak(
        macUID: String,
        macDeviceID: String,
        text: String,
        timeoutSeconds: TimeInterval = 180
    ) async throws {
        let url = try await synthesize(
            macUID: macUID,
            macDeviceID: macDeviceID,
            text: text,
            timeoutSeconds: timeoutSeconds
        )
        
        await MainActor.run {
            playAudio(url: url)
        }
    }
    
    private func playAudio(url: URL) {
        stopAudio()
        
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            lastError = "Audio session error: \(error.localizedDescription)"
            return
        }
        
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.volume = 1.0
        
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.stopAudio()
        }
        
        audioPlayer = player
        player.play()
    }
    
    func stopAudio() {
        audioPlayer?.pause()
        audioPlayer = nil
        
        if let observer = endObserver {
            NotificationCenter.default.removeObserver(observer)
            endObserver = nil
        }
        
        try? AVAudioSession.sharedInstance().setActive(false)
    }
}
