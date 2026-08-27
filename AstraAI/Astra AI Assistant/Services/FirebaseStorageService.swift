//
//  FirebaseStorageService.swift
//  AstraAssistant
//
//  Created by Alex on 11/8/26.
//

import Foundation
import FirebaseCore
import FirebaseAuth
import FirebaseStorage

enum UploadPurpose {
    case image
    case audio

    var folder: String {
        switch self {
        case .image: return "public/images"
        case .audio: return "public/audio"
        }
    }
}

final class FirebaseStorageService {
    static let shared = FirebaseStorageService()

    private let storage: Storage

    private init() {
        // Явно берём bucket из Firebase options
        if let app = FirebaseApp.app(),
           let bucket = app.options.storageBucket,
           !bucket.isEmpty {
            self.storage = Storage.storage(url: "gs://\(bucket)")
        } else {
            // fallback (может сработать, но лучше всегда иметь bucket)
            self.storage = Storage.storage()
        }
    }

    func uploadFile(localURL: URL, purpose: UploadPurpose) async throws -> String {
        guard FirebaseApp.app() != nil else {
            throw NSError(
                domain: "FirebaseStorageService",
                code: -100,
                userInfo: [NSLocalizedDescriptionKey: "FirebaseApp is not configured. Call FirebaseApp.configure() on app start."]
            )
        }

        try await ensureAnonymousAuth()

        let ext = localURL.pathExtension.isEmpty ? "bin" : localURL.pathExtension.lowercased()
        let fileName = "\(UUID().uuidString).\(ext)"
        let path = "\(purpose.folder)/\(fileName)"

        let ref = storage.reference().child(path)

        let metadata = StorageMetadata()
        metadata.contentType = mimeType(for: ext)

        _ = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<StorageMetadata, Error>) in
            ref.putFile(from: localURL, metadata: metadata) { meta, error in
                if let error {
                    cont.resume(throwing: self.decorateFirebaseError(error))
                } else if let meta {
                    cont.resume(returning: meta)
                } else {
                    cont.resume(throwing: NSError(
                        domain: "FirebaseStorageService",
                        code: -101,
                        userInfo: [NSLocalizedDescriptionKey: "Upload failed: empty metadata and no error."]
                    ))
                }
            }
        }

        let downloadURL = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
            ref.downloadURL { url, error in
                if let error {
                    cont.resume(throwing: self.decorateFirebaseError(error))
                } else if let url {
                    cont.resume(returning: url)
                } else {
                    cont.resume(throwing: NSError(
                        domain: "FirebaseStorageService",
                        code: -102,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to get download URL."]
                    ))
                }
            }
        }

        return downloadURL.absoluteString
    }

    private func ensureAnonymousAuth() async throws {
        if Auth.auth().currentUser != nil { return }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            Auth.auth().signInAnonymously { _, error in
                if let error {
                    cont.resume(throwing: self.decorateFirebaseError(error))
                } else {
                    cont.resume(returning: ())
                }
            }
        }
    }

    private func decorateFirebaseError(_ error: Error) -> Error {
        let ns = error as NSError
        let details = """
        Firebase error:
        domain=\(ns.domain)
        code=\(ns.code)
        description=\(ns.localizedDescription)
        userInfo=\(ns.userInfo)
        """
        return NSError(
            domain: ns.domain,
            code: ns.code,
            userInfo: [NSLocalizedDescriptionKey: details]
        )
    }

    private func mimeType(for ext: String) -> String {
        switch ext {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "webp": return "image/webp"
        case "heic": return "image/heic"
        case "wav": return "audio/wav"
        case "mp3": return "audio/mpeg"
        case "m4a": return "audio/mp4"
        default: return "application/octet-stream"
        }
    }
}
