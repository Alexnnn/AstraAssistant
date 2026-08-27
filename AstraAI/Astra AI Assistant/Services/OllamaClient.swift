//
//  OllamaClient.swift
//  AstraAssistant
//
//  Created by Alex on 10/8/26.
//

import Foundation

final class OllamaClient {
    static let shared = OllamaClient()

    private let baseURL = URL(string: "http://127.0.0.1:11434")!
    private let session: URLSession
    private let fastSession: URLSession

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 120
        configuration.waitsForConnectivity = false
        self.session = URLSession(configuration: configuration)

        let fast = URLSessionConfiguration.ephemeral
        fast.timeoutIntervalForRequest = 4
        fast.timeoutIntervalForResource = 8
        fast.waitsForConnectivity = false
        self.fastSession = URLSession(configuration: fast)
    }

    func isRunning() async -> Bool {
        if await ping(path: "api/version") { return true }
        if await ping(path: "api/tags") { return true }
        return false
    }

    private func ping(path: String) async -> Bool {
        let url = baseURL.appendingPathComponent(path)

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 6

        do {
            let (_, response) = try await fastSession.data(for: req)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200..<300).contains(http.statusCode)
        } catch {
            return false
        }
    }

    func listModels() async throws -> [OllamaModel] {
        let url = baseURL.appendingPathComponent("api/tags")

        let (data, response) = try await session.data(from: url)
        try validateHTTP(response, data: data)

        let decoded = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
        return decoded.models
    }

    func embedding(model: String, prompt: String) async throws -> [Float] {
        let url = baseURL.appendingPathComponent("api/embeddings")

        let body: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "keep_alive": "30m"
        ]

        let data = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = data
        request.timeoutInterval = 600
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (responseData, response) = try await session.data(for: request)
        try validateHTTP(response, data: responseData)

        struct EmbeddingResponse: Codable {
            let embedding: [Double]
        }

        let decoded = try JSONDecoder().decode(EmbeddingResponse.self, from: responseData)
        return decoded.embedding.map { Float($0) }
    }

    func chat(
        model: String,
        messages: [[String: String]],
        temperature: Double,
        contextSize: Int
    ) async throws -> String {
        let url = baseURL.appendingPathComponent("api/chat")

        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "stream": false,
            "keep_alive": "30m",
            "options": [
                "temperature": temperature,
                "num_ctx": contextSize
            ]
        ]

        let data = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = data
        request.timeoutInterval = 900
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (responseData, response) = try await session.data(for: request)
        try validateHTTP(response, data: responseData)

        struct ChatResponse: Codable {
            struct Message: Codable {
                let role: String
                let content: String
            }
            let message: Message
        }

        let decoded = try JSONDecoder().decode(ChatResponse.self, from: responseData)
        return decoded.message.content
    }

    func chatStream(
        model: String,
        messages: [[String: String]],
        temperature: Double,
        contextSize: Int,
        onToken: @escaping @Sendable (String) async -> Void
    ) async throws -> String {
        let url = baseURL.appendingPathComponent("api/chat")

        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "stream": true,
            "keep_alive": "30m",
            "options": [
                "temperature": temperature,
                "num_ctx": contextSize
            ]
        ]

        let data = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = data
        request.timeoutInterval = 900
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (bytes, response) = try await session.bytes(for: request)
        try validateHTTP(response, data: Data())

        var fullText = ""

        for try await line in bytes.lines {
            guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            guard let lineData = line.data(using: .utf8) else { continue }

            do {
                let chunk = try JSONDecoder().decode(OllamaChatStreamChunk.self, from: lineData)

                if let content = chunk.message?.content, !content.isEmpty {
                    fullText += content
                    await onToken(content)
                }

                if chunk.done == true {
                    break
                }
            } catch {
                if let errorResponse = try? JSONDecoder().decode(OllamaErrorResponse.self, from: lineData) {
                    throw NSError(
                        domain: "OllamaClient",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: errorResponse.error]
                    )
                }
                throw error
            }
        }

        return fullText
    }

    func analyzeImage(
        model: String,
        imageURL: URL,
        prompt: String,
        temperature: Double = 0.3,
        contextSize: Int = 4096
    ) async throws -> String {
        let imageData = try Data(contentsOf: imageURL)
        let base64Image = imageData.base64EncodedString()

        let url = baseURL.appendingPathComponent("api/chat")

        let userMessage: [String: Any] = [
            "role": "user",
            "content": prompt,
            "images": [base64Image]
        ]

        let body: [String: Any] = [
            "model": model,
            "messages": [userMessage],
            "stream": false,
            "keep_alive": "30m",
            "options": [
                "temperature": temperature,
                "num_ctx": contextSize
            ]
        ]

        let data = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = data
        request.timeoutInterval = 900
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (responseData, response) = try await session.data(for: request)
        try validateHTTP(response, data: responseData)

        struct ChatResponse: Codable {
            struct Message: Codable {
                let role: String
                let content: String
            }
            let message: Message
        }

        let decoded = try JSONDecoder().decode(ChatResponse.self, from: responseData)
        return decoded.message.content
    }

    private func validateHTTP(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard 200..<300 ~= http.statusCode else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(
                domain: "OllamaClient",
                code: http.statusCode,
                userInfo: [
                    NSLocalizedDescriptionKey: """
                    Ollama HTTP error: \(http.statusCode)

                    \(body)
                    """
                ]
            )
        }
    }
}

private struct OllamaChatStreamChunk: Codable {
    struct Message: Codable {
        let role: String?
        let content: String?
    }

    let model: String?
    let created_at: String?
    let message: Message?
    let done: Bool?
    let total_duration: Int64?
    let load_duration: Int64?
    let prompt_eval_count: Int?
    let eval_count: Int?
}

private struct OllamaErrorResponse: Codable {
    let error: String
}
