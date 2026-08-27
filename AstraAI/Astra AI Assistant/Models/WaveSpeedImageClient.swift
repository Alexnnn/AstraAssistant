//
//  WaveSpeedImageClient.swift
//  AstraAssistant
//
//  Created by Alex on 11/8/26.
//

import Foundation

final class WaveSpeedImageClient {
    static let shared = WaveSpeedImageClient()
    private init() {}

    func generateImage(prompt: String, settings: AssistantSettings) async throws -> URL {
        guard let apiKey = KeychainStore.shared.getWaveSpeedKey(),
              !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NSError(domain: "WaveSpeedImageClient", code: 401, userInfo: [
                NSLocalizedDescriptionKey: "WaveSpeed API key is missing."
            ])
        }

        let endpoint = settings.waveSpeedGenerateModel.rawValue
        let submitURL = URL(string: "https://api.wavespeed.ai/api/v3/\(endpoint)")!

        var payload: [String: Any] = [
            "prompt": prompt
        ]

        switch settings.waveSpeedGenerateModel {
        case .seedreamV45:
            payload["size"] = settings.waveSpeedV45Size
        case .seedreamV50Pro:
            payload["aspect_ratio"] = settings.waveSpeedAspectRatio
            payload["resolution"] = settings.waveSpeedResolution
            payload["output_format"] = settings.waveSpeedOutputFormat
        }

        let prediction = try await submit(apiKey: apiKey, submitURL: submitURL, payload: payload)
        let outputURL = try await pollForOutputURL(
            apiKey: apiKey,
            predictionId: prediction.id,
            resultURL: prediction.resultURL,
            maxWaitSeconds: settings.waveSpeedImageMaxWaitSeconds
        )

        return try await downloadAndSaveImage(from: outputURL, prefix: "seedream-generated")
    }

    func editImage(
        prompt: String,
        imagePublicURLs: [String],
        settings: AssistantSettings
    ) async throws -> URL {
        guard let apiKey = KeychainStore.shared.getWaveSpeedKey(),
              !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NSError(domain: "WaveSpeedImageClient", code: 401, userInfo: [
                NSLocalizedDescriptionKey: "WaveSpeed API key is missing."
            ])
        }

        let cleaned = imagePublicURLs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !cleaned.isEmpty else {
            throw NSError(domain: "WaveSpeedImageClient", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Seedream Edit requires at least one public image URL."
            ])
        }

        let endpoint = settings.waveSpeedEditModel.rawValue
        let submitURL = URL(string: "https://api.wavespeed.ai/api/v3/\(endpoint)")!

        var payload: [String: Any] = [
            "prompt": prompt,
            "images": cleaned
        ]

        // Для V5 Edit добавляем параметры, если есть
        if settings.waveSpeedEditModel == .seedreamV50ProEdit {
            payload["aspect_ratio"] = settings.waveSpeedAspectRatio
            payload["resolution"] = settings.waveSpeedResolution
            payload["output_format"] = settings.waveSpeedOutputFormat
        }

        let prediction = try await submit(apiKey: apiKey, submitURL: submitURL, payload: payload)
        let outputURL = try await pollForOutputURL(
            apiKey: apiKey,
            predictionId: prediction.id,
            resultURL: prediction.resultURL,
            maxWaitSeconds: settings.waveSpeedImageMaxWaitSeconds
        )

        return try await downloadAndSaveImage(from: outputURL, prefix: "seedream-edited")
    }

    // MARK: - Core API

    private func submit(
        apiKey: String,
        submitURL: URL,
        payload: [String: Any]
    ) async throws -> PredictionRef {
        let body = try JSONSerialization.data(withJSONObject: payload)

        var req = URLRequest(url: submitURL)
        req.httpMethod = "POST"
        req.timeoutInterval = 90
        req.httpBody = body
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: req)
        try validateHTTP(response: response, data: data)

        let envelope = try JSONDecoder().decode(WSEnvelope<WSDataPrediction>.self, from: data)

        guard envelope.code == 200 else {
            throw NSError(domain: "WaveSpeedImageClient", code: envelope.code, userInfo: [
                NSLocalizedDescriptionKey: envelope.message
            ])
        }

        guard let id = envelope.data.id, !id.isEmpty else {
            throw NSError(domain: "WaveSpeedImageClient", code: -2, userInfo: [
                NSLocalizedDescriptionKey: "Prediction id missing in WaveSpeed response."
            ])
        }

        let resultURLString = envelope.data.urls?.get ?? "https://api.wavespeed.ai/api/v3/predictions/\(id)/result"
        guard let resultURL = URL(string: resultURLString) else {
            throw NSError(domain: "WaveSpeedImageClient", code: -3, userInfo: [
                NSLocalizedDescriptionKey: "Invalid result URL."
            ])
        }

        return PredictionRef(id: id, resultURL: resultURL)
    }

    private func pollForOutputURL(
        apiKey: String,
        predictionId: String,
        resultURL: URL,
        maxWaitSeconds: Int
    ) async throws -> URL {
        let started = Date()
        var delay: UInt64 = 2

        while true {
            if Date().timeIntervalSince(started) > TimeInterval(maxWaitSeconds) {
                throw NSError(domain: "WaveSpeedImageClient", code: -4, userInfo: [
                    NSLocalizedDescriptionKey: "Seedream polling timeout after \(maxWaitSeconds)s."
                ])
            }

            var req = URLRequest(url: resultURL)
            req.httpMethod = "GET"
            req.timeoutInterval = 60
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await URLSession.shared.data(for: req)
            try validateHTTP(response: response, data: data)

            let envelope = try JSONDecoder().decode(WSEnvelope<WSDataPrediction>.self, from: data)
            guard envelope.code == 200 else {
                throw NSError(domain: "WaveSpeedImageClient", code: envelope.code, userInfo: [
                    NSLocalizedDescriptionKey: envelope.message
                ])
            }

            let p = envelope.data
            let status = p.status ?? ""

            switch status {
            case "completed":
                if let first = p.outputs?.first,
                   let outputURL = URL(string: first) {
                    return outputURL
                }
                throw NSError(domain: "WaveSpeedImageClient", code: -5, userInfo: [
                    NSLocalizedDescriptionKey: "Completed but outputs are empty."
                ])

            case "failed", "cancelled", "timeout":
                throw NSError(domain: "WaveSpeedImageClient", code: -6, userInfo: [
                    NSLocalizedDescriptionKey: p.error ?? "Seedream task failed."
                ])

            case "created", "processing":
                try await Task.sleep(nanoseconds: delay * 1_000_000_000)
                delay = min(delay + 1, 10)

            default:
                throw NSError(domain: "WaveSpeedImageClient", code: -7, userInfo: [
                    NSLocalizedDescriptionKey: "Unexpected status: \(status)"
                ])
            }
        }
    }

    private func downloadAndSaveImage(from url: URL, prefix: String) async throws -> URL {
        let (data, response) = try await URLSession.shared.data(from: url)
        try validateHTTP(response: response, data: data)

        let folder = generatedImagesFolder()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let fileURL = folder.appendingPathComponent("\(prefix)-\(UUID().uuidString).png")
        try data.write(to: fileURL)
        return fileURL
    }

    private func generatedImagesFolder() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base
            .appendingPathComponent("Astra Assistant", isDirectory: true)
            .appendingPathComponent("Generated Images", isDirectory: true)
    }

    private func validateHTTP(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard 200..<300 ~= http.statusCode else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "WaveSpeedImageClient", code: http.statusCode, userInfo: [
                NSLocalizedDescriptionKey: "HTTP \(http.statusCode)\n\n\(body)"
            ])
        }
    }
}

// MARK: - DTOs

private struct PredictionRef {
    let id: String
    let resultURL: URL
}

private struct WSEnvelope<T: Codable>: Codable {
    let code: Int
    let message: String
    let data: T
}

private struct WSDataPrediction: Codable {
    struct URLs: Codable {
        let get: String?
    }

    let id: String?
    let status: String?
    let outputs: [String]?
    let error: String?
    let urls: URLs?
}
