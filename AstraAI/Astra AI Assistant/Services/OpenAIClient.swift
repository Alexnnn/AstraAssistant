//
//  OpenAIClient.swift
//  AstraAssistant
//
//  Created by Alex on 10/8/26.
//

import Foundation
import AppKit

final class OpenAIClient {
    static let shared = OpenAIClient()

    private init() {}

    private let baseURL = URL(string: "https://api.openai.com")!

    func generateImage(
        prompt: String,
        model: String = "gpt-image-2",
        size: String = "1024x1024"
    ) async throws -> URL {
        let apiKey = try getAPIKey()

        let url = baseURL.appendingPathComponent("/v1/images/generations")

        let body: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "size": size
        ]

        let data = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = data
        request.timeoutInterval = 180
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (responseData, response) = try await URLSession.shared.data(for: request)

        try validateHTTP(response, responseData: responseData)

        return try await saveImageFromOpenAIResponse(responseData, prefix: "generated")
    }

    func editImage(
        imageURL: URL,
        prompt: String,
        model: String = "gpt-image-2",
        size: String = "1024x1024"
    ) async throws -> URL {
        let apiKey = try getAPIKey()

        let url = baseURL.appendingPathComponent("/v1/images/edits")
        let boundary = "Boundary-\(UUID().uuidString)"

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 240
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )

        var body = Data()

        body.appendMultipartField(name: "model", value: model, boundary: boundary)
        body.appendMultipartField(name: "prompt", value: prompt, boundary: boundary)
        body.appendMultipartField(name: "size", value: size, boundary: boundary)

        let preparedImageURL = try prepareImageForOpenAIEdit(imageURL)
        let imageData = try Data(contentsOf: preparedImageURL)

        body.appendMultipartFile(
            name: "image",
            filename: "image.png",
            mimeType: "image/png",
            fileData: imageData,
            boundary: boundary
        )

        body.appendString("--\(boundary)--\r\n")

        request.httpBody = body

        let (responseData, response) = try await URLSession.shared.data(for: request)

        try validateHTTP(response, responseData: responseData)

        return try await saveImageFromOpenAIResponse(responseData, prefix: "edited")
    }

    private func getAPIKey() throws -> String {
        guard let apiKey = KeychainStore.shared.getOpenAIKey(),
              !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NSError(
                domain: "OpenAIClient",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "OpenAI API key is missing."]
            )
        }

        return apiKey
    }

    private func validateHTTP(_ response: URLResponse, responseData: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard 200..<300 ~= http.statusCode else {
            let body = String(data: responseData, encoding: .utf8) ?? ""

            throw NSError(
                domain: "OpenAIClient",
                code: http.statusCode,
                userInfo: [
                    NSLocalizedDescriptionKey: """
                    OpenAI HTTP error \(http.statusCode):

                    \(body)
                    """
                ]
            )
        }
    }

    private func saveImageFromOpenAIResponse(
        _ data: Data,
        prefix: String
    ) async throws -> URL {
        let decoded = try JSONDecoder().decode(OpenAIImageResponse.self, from: data)

        guard let first = decoded.data.first else {
            throw NSError(
                domain: "OpenAIClient",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "OpenAI image response is empty."]
            )
        }

        if let base64 = first.b64_json,
           let imageData = Data(base64Encoded: base64) {
            return try saveImageData(imageData, prefix: prefix)
        }

        if let urlString = first.url,
           let imageURL = URL(string: urlString) {
            let (imageData, response) = try await URLSession.shared.data(from: imageURL)

            guard let http = response as? HTTPURLResponse,
                  200..<300 ~= http.statusCode else {
                throw NSError(
                    domain: "OpenAIClient",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to download OpenAI image URL."]
                )
            }

            return try saveImageData(imageData, prefix: prefix)
        }

        throw NSError(
            domain: "OpenAIClient",
            code: -3,
            userInfo: [NSLocalizedDescriptionKey: "OpenAI response does not contain b64_json or url."]
        )
    }

    private func saveImageData(_ data: Data, prefix: String) throws -> URL {
        let folder = generatedImagesFolder()

        try FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true
        )

        let fileURL = folder.appendingPathComponent("\(prefix)-\(UUID().uuidString).png")
        try data.write(to: fileURL)

        return fileURL
    }

    private func generatedImagesFolder() -> URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        return base
            .appendingPathComponent("Astra Assistant", isDirectory: true)
            .appendingPathComponent("Generated Images", isDirectory: true)
    }

    private func prepareImageForOpenAIEdit(_ imageURL: URL) throws -> URL {
        guard let image = NSImage(contentsOf: imageURL) else {
            throw NSError(
                domain: "OpenAIClient",
                code: -10,
                userInfo: [NSLocalizedDescriptionKey: "Failed to load image for editing."]
            )
        }

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(
                domain: "OpenAIClient",
                code: -11,
                userInfo: [NSLocalizedDescriptionKey: "Failed to convert image to PNG."]
            )
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("astra-openai-edit-\(UUID().uuidString).png")

        try pngData.write(to: tempURL)

        return tempURL
    }
}

private struct OpenAIImageResponse: Codable {
    struct Item: Codable {
        let b64_json: String?
        let url: String?
    }

    let data: [Item]
}

private extension Data {
    mutating func appendString(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }

    mutating func appendMultipartField(
        name: String,
        value: String,
        boundary: String
    ) {
        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        appendString("\(value)\r\n")
    }

    mutating func appendMultipartFile(
        name: String,
        filename: String,
        mimeType: String,
        fileData: Data,
        boundary: String
    ) {
        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        appendString("Content-Type: \(mimeType)\r\n\r\n")
        append(fileData)
        appendString("\r\n")
    }
}
