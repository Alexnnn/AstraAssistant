//
//  WaveSpeedTTSClient.swift
//  AstraAssistant
//
//  Created by Alex on 10/8/26.
//

import Foundation

final class WaveSpeedTTSClient {
    static let shared = WaveSpeedTTSClient()

    private init() {}

    private let submitURL = URL(
        string: "https://api.wavespeed.ai/api/v3/wavespeed-ai/qwen3-tts/voice-clone"
    )!

    func synthesizeSpeech(
        text: String,
        settings: AssistantSettings
    ) async throws -> Data {
        guard let apiKey = KeychainStore.shared.getWaveSpeedKey(),
              !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NSError(
                domain: "WaveSpeedTTSClient",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "WaveSpeed API key is missing."]
            )
        }

        guard !settings.waveSpeedReferenceAudioURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NSError(
                domain: "WaveSpeedTTSClient",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "WaveSpeed reference audio URL is empty."]
            )
        }

        let prediction = try await submit(
            apiKey: apiKey,
            text: text,
            settings: settings
        )

        let audioURL = try await pollUntilCompleted(
            apiKey: apiKey,
            predictionId: prediction.predictionId,
            resultURL: prediction.resultURL,
            maxWaitSeconds: settings.waveSpeedMaxWaitSeconds
        )

        return try await downloadAudio(from: audioURL)
    }

    private func submit(
        apiKey: String,
        text: String,
        settings: AssistantSettings
    ) async throws -> WaveSpeedSubmitResult {
        var payload: [String: Any] = [
            "audio": settings.waveSpeedReferenceAudioURL,
            "text": text,
            "language": settings.waveSpeedLanguage
        ]

        if !settings.waveSpeedReferenceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["reference_text"] = settings.waveSpeedReferenceText
        }

        let body = try JSONSerialization.data(withJSONObject: payload)

        var request = URLRequest(url: submitURL)
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = 60
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)

        try validateHTTP(response, data: data)

        let envelope = try JSONDecoder().decode(WaveSpeedEnvelope<WaveSpeedPrediction>.self, from: data)

        guard envelope.code == 200 else {
            throw NSError(
                domain: "WaveSpeedTTSClient",
                code: envelope.code,
                userInfo: [NSLocalizedDescriptionKey: envelope.message]
            )
        }

        guard let predictionId = envelope.data.id, !predictionId.isEmpty else {
            throw NSError(
                domain: "WaveSpeedTTSClient",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "WaveSpeed response did not contain prediction id."]
            )
        }

        let resultURLString = envelope.data.urls?.get
            ?? "https://api.wavespeed.ai/api/v3/predictions/\(predictionId)/result"

        guard let resultURL = URL(string: resultURLString) else {
            throw NSError(
                domain: "WaveSpeedTTSClient",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "Invalid WaveSpeed result URL."]
            )
        }

        return WaveSpeedSubmitResult(
            predictionId: predictionId,
            resultURL: resultURL
        )
    }

    private func pollUntilCompleted(
        apiKey: String,
        predictionId: String,
        resultURL: URL,
        maxWaitSeconds: Int
    ) async throws -> URL {
        let startedAt = Date()
        var delaySeconds: UInt64 = 2

        while true {
            if Date().timeIntervalSince(startedAt) > TimeInterval(maxWaitSeconds) {
                throw NSError(
                    domain: "WaveSpeedTTSClient",
                    code: -4,
                    userInfo: [NSLocalizedDescriptionKey: "WaveSpeed polling timeout after \(maxWaitSeconds) seconds."]
                )
            }

            let result = try await pollOnce(apiKey: apiKey, resultURL: resultURL)

            switch result.status {
            case "completed":
                guard let output = result.outputs?.first else {
                    throw NSError(
                        domain: "WaveSpeedTTSClient",
                        code: -5,
                        userInfo: [NSLocalizedDescriptionKey: "WaveSpeed completed but returned no outputs."]
                    )
                }

                guard let audioURL = URL(string: output) else {
                    throw NSError(
                        domain: "WaveSpeedTTSClient",
                        code: -6,
                        userInfo: [NSLocalizedDescriptionKey: "Invalid WaveSpeed audio URL."]
                    )
                }

                return audioURL

            case "failed", "cancelled", "timeout":
                throw NSError(
                    domain: "WaveSpeedTTSClient",
                    code: -7,
                    userInfo: [NSLocalizedDescriptionKey: result.error ?? "WaveSpeed task failed."]
                )

            case "created", "processing":
                try await Task.sleep(nanoseconds: delaySeconds * 1_000_000_000)
                delaySeconds = min(delaySeconds + 1, 10)

            default:
                throw NSError(
                    domain: "WaveSpeedTTSClient",
                    code: -8,
                    userInfo: [NSLocalizedDescriptionKey: "Unexpected WaveSpeed status: \(result.status ?? "nil")"]
                )
            }
        }
    }

    private func pollOnce(
        apiKey: String,
        resultURL: URL
    ) async throws -> WaveSpeedPrediction {
        var request = URLRequest(url: resultURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 60
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        try validateHTTP(response, data: data)

        let envelope = try JSONDecoder().decode(WaveSpeedEnvelope<WaveSpeedPrediction>.self, from: data)

        guard envelope.code == 200 else {
            throw NSError(
                domain: "WaveSpeedTTSClient",
                code: envelope.code,
                userInfo: [NSLocalizedDescriptionKey: envelope.message]
            )
        }

        return envelope.data
    }

    private func downloadAudio(from url: URL) async throws -> Data {
        let request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 120
        )

        let (data, response) = try await URLSession.shared.data(for: request)

        try validateHTTP(response, data: data)

        return data
    }

    private func validateHTTP(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard 200..<300 ~= http.statusCode else {
            let body = String(data: data, encoding: .utf8) ?? ""

            throw NSError(
                domain: "WaveSpeedTTSClient",
                code: http.statusCode,
                userInfo: [
                    NSLocalizedDescriptionKey: """
                    HTTP \(http.statusCode)

                    \(body)
                    """
                ]
            )
        }
    }
}

private struct WaveSpeedSubmitResult {
    let predictionId: String
    let resultURL: URL
}

private struct WaveSpeedEnvelope<T: Codable>: Codable {
    let code: Int
    let message: String
    let data: T
}

private struct WaveSpeedPrediction: Codable {
    struct URLs: Codable {
        let get: String?
    }

    let id: String?
    let model: String?
    let status: String?
    let outputs: [String]?
    let error: String?
    let urls: URLs?
}
