//
//  IOSMediaUploadService.swift
//  AstraCompanion
//
//  Created by Alex on 13/8/26.
//

import Foundation
import FirebaseStorage
import UIKit

final class IOSMediaUploadService {
    static let shared = IOSMediaUploadService()
    private init() {}

    private let storage = Storage.storage()

    func uploadImageData(_ data: Data) async throws -> String {
        guard let image = UIImage(data: data),
              let jpegData = image.jpegData(compressionQuality: 0.9) else {
            throw NSError(
                domain: "Upload",
                code: -10,
                userInfo: [
                    NSLocalizedDescriptionKey: "Failed to convert selected image to JPEG."
                ]
            )
        }

        let path = "public/images/ios-\(UUID().uuidString).jpg"

        return try await uploadData(
            jpegData,
            path: path,
            contentType: "image/jpeg"
        )
    }

    func uploadFile(localURL: URL) async throws -> String {
        let ext = localURL.pathExtension.isEmpty ? "bin" : localURL.pathExtension.lowercased()
        let path = "public/files/ios-\(UUID().uuidString).\(ext)"
        let data = try Data(contentsOf: localURL)
        let mime = mimeType(for: ext)
        return try await uploadData(data, path: path, contentType: mime)
    }

    private func uploadData(_ data: Data, path: String, contentType: String) async throws -> String {
        let ref = storage.reference().child(path)
        let meta = StorageMetadata()
        meta.contentType = contentType

        _ = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<StorageMetadata, Error>) in
            ref.putData(data, metadata: meta) { md, err in
                if let err { cont.resume(throwing: err) }
                else if let md { cont.resume(returning: md) }
                else { cont.resume(throwing: NSError(domain: "Upload", code: -1)) }
            }
        }

        let url = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
            ref.downloadURL { url, err in
                if let err { cont.resume(throwing: err) }
                else if let url { cont.resume(returning: url) }
                else { cont.resume(throwing: NSError(domain: "Upload", code: -2)) }
            }
        }

        return url.absoluteString
    }

    private func mimeType(for ext: String) -> String {
        switch ext {
        case "pdf": return "application/pdf"
        case "txt": return "text/plain"
        case "md": return "text/markdown"
        case "json": return "application/json"
        case "csv": return "text/csv"
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        default: return "application/octet-stream"
        }
    }
}
