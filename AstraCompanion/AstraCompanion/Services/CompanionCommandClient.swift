//
//  CompanionCommandClient.swift
//  AstraCompanion
//
//  Created by Alex on 13/8/26.
//


import Foundation
import UIKit
import FirebaseAuth
import FirebaseFirestore

final class CompanionCommandClient {
    static let shared = CompanionCommandClient()
    private init() {}

    private let db = Firestore.firestore()

    func ensureAuth() async throws {
        if Auth.auth().currentUser != nil { return }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            Auth.auth().signInAnonymously { _, error in
                if let error { cont.resume(throwing: error) }
                else { cont.resume(returning: ()) }
            }
        }
    }

    func sendCommand(
        macUID: String,
        targetDevice: String,
        type: CompanionCommandType,
        payload: [String: Any]
    ) async throws -> String {
        guard let sourceUID = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "Companion", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }

        let commandId = UUID().uuidString
        let ref = db.collection("users").document(macUID).collection("commands").document(commandId)

        try await ref.setData([
            "type": type.rawValue,
            "status": "queued",
            "sourceDevice": IOSDeviceIdentity.sourceDeviceName,
            "sourceClientUID": sourceUID,
            "targetDevice": targetDevice,
            "payload": payload,
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ])

        return commandId
    }

    func waitForResponse(
        macUID: String,
        commandId: String,
        timeoutSeconds: TimeInterval = 180
    ) async throws -> CompanionCommandResponse {
        let ref = db.collection("users")
            .document(macUID)
            .collection("responses")
            .document(commandId)

        let deadline = Date().addingTimeInterval(timeoutSeconds)
        let pollIntervalNs: UInt64 = 700_000_000

        while Date() < deadline {
            let snapshot = try await ref.getDocument()

            if let data = snapshot.data() {
                let status = (data["status"] as? String) ?? ""

                if status == "done" {
                    let d = (data["data"] as? [String: Any]) ?? [:]

                    return CompanionCommandResponse(
                        status: status,
                        assistantText: d["assistantText"] as? String,
                        conversationId: d["conversationId"] as? String,
                        attachmentURL: (d["attachmentURL"] as? String)
                            ?? (d["imageURL"] as? String)
                            ?? (d["audioURL"] as? String),
                        attachmentType: (d["attachmentType"] as? String)
                            ?? ((d["imageURL"] as? String) != nil ? "image" : nil)
                            ?? ((d["audioURL"] as? String) != nil ? "audio" : nil),
                        audioURL: d["audioURL"] as? String,
                        raw: d
                    )
                }

                if status == "error" {
                    let err = (data["error"] as? String)
                        ?? (data["errorMessage"] as? String)
                        ?? "Unknown error"

                    throw NSError(
                        domain: "Companion",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: err]
                    )
                }
            }

            try await Task.sleep(nanoseconds: pollIntervalNs)
        }

        throw NSError(
            domain: "Companion",
            code: -2,
            userInfo: [NSLocalizedDescriptionKey: "Response timeout"]
        )
    }
    
    // MARK: - Conversation Delete
    
    /// Удаляет чат на Mac
    func deleteConversation(
        macUID: String,
        targetDevice: String,
        conversationId: String
    ) async throws {
        guard let sourceUID = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "Companion", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        let commandId = UUID().uuidString
        let ref = db.collection("users").document(macUID).collection("commands").document(commandId)
        
        try await ref.setData([
            "type": CompanionCommandType.conversationDelete.rawValue,
            "status": "queued",
            "sourceDevice": IOSDeviceIdentity.sourceDeviceName,
            "sourceClientUID": sourceUID,
            "targetDevice": targetDevice,
            "payload": [
                "conversationId": conversationId
            ],
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ])
        
        // Ждем подтверждение
        _ = try await waitForResponse(
            macUID: macUID,
            commandId: commandId,
            timeoutSeconds: 30
        )
    }
}

struct CompanionCommandResponse {
    let status: String
    let assistantText: String?
    let conversationId: String?
    let attachmentURL: String?
    let attachmentType: String?
    let audioURL: String?
    let raw: [String: Any]
}
