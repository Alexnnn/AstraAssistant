//
//  CompanionPairingService.swift
//  Astra AI Assistant
//
//  Created by Alex on 13/8/26.
//

import Foundation
import FirebaseFirestore
import Combine

@MainActor
final class CompanionPairingService: ObservableObject {
    static let shared = CompanionPairingService()

    @Published var currentCode: String?
    @Published var expiresAt: Date?
    @Published var lastError: String?
    @Published var isGenerating = false

    private let db = Firestore.firestore()

    private init() {}

    func generateCode(uid: String, deviceId: String) async {
        isGenerating = true
        defer { isGenerating = false }

        let code = Self.random6Digits()
        let expiry = Date().addingTimeInterval(10 * 60) // 10 min

        do {
            try await db.collection("pairingCodes").document(code).setData([
                "macUID": uid,
                "macDeviceID": deviceId,
                "createdAt": FieldValue.serverTimestamp(),
                "expiresAt": Timestamp(date: expiry),
                "claimed": false,
                "claimedBy": NSNull()
            ], merge: true)

            currentCode = code
            expiresAt = expiry
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private static func random6Digits() -> String {
        String(format: "%06d", Int.random(in: 0...999_999))
    }
}
