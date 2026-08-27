//
//  CompanionPairingClient.swift
//  AstraCompanion
//
//  Created by Alex on 13/8/26.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import UIKit


final class CompanionPairingClient {
    static let shared = CompanionPairingClient()
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

    /// Redeem 6-digit code and register this iOS user as paired client.
    func redeemCode(_ code: String) async throws -> ConnectionProfile {
        guard let iosUID = Auth.auth().currentUser?.uid else {
            throw NSError(
                domain: "Pairing",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "Not authenticated"]
            )
        }

        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines)

        guard normalized.count == 6 else {
            throw NSError(
                domain: "Pairing",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Code must be 6 digits"]
            )
        }

        let codeRef = db.collection("pairingCodes").document(normalized)

        let result: (macUID: String, macDeviceID: String) = try await withCheckedThrowingContinuation { cont in
            db.runTransaction({ tx, errPtr in
                do {
                    let snap = try tx.getDocument(codeRef)

                    guard let data = snap.data() else {
                        throw NSError(
                            domain: "Pairing",
                            code: 404,
                            userInfo: [NSLocalizedDescriptionKey: "Code not found"]
                        )
                    }

                    let claimed = (data["claimed"] as? Bool) ?? false

                    if claimed {
                        throw NSError(
                            domain: "Pairing",
                            code: 409,
                            userInfo: [NSLocalizedDescriptionKey: "Code already used"]
                        )
                    }

                    guard let expiry = data["expiresAt"] as? Timestamp else {
                        throw NSError(
                            domain: "Pairing",
                            code: 410,
                            userInfo: [NSLocalizedDescriptionKey: "Code expiry missing"]
                        )
                    }

                    if expiry.dateValue() < Date() {
                        throw NSError(
                            domain: "Pairing",
                            code: 411,
                            userInfo: [NSLocalizedDescriptionKey: "Code expired"]
                        )
                    }

                    guard let macUID = data["macUID"] as? String,
                          let macDeviceID = data["macDeviceID"] as? String else {
                        throw NSError(
                            domain: "Pairing",
                            code: 412,
                            userInfo: [NSLocalizedDescriptionKey: "Invalid pairing payload"]
                        )
                    }

                    let pairedRef = self.db.collection("users")
                        .document(macUID)
                        .collection("pairedClients")
                        .document(iosUID)

                    // 1. Claim code.
                    tx.updateData([
                        "claimed": true,
                        "claimedBy": iosUID,
                        "claimedAt": FieldValue.serverTimestamp()
                    ], forDocument: codeRef)

                    // 2. Register paired client in the SAME transaction.
                    // If this fails by rules, code claim is also rolled back.
                    tx.setData([
                        "active": true,
                        "macUID": macUID,
                        "updatedAt": FieldValue.serverTimestamp(),
                        "platform": "iOS",
                        "deviceName": UIDevice.current.name,
                        "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
                    ], forDocument: pairedRef, merge: true)

                    return [
                        "macUID": macUID,
                        "macDeviceID": macDeviceID
                    ] as NSDictionary

                } catch let error {
                    errPtr?.pointee = error as NSError
                    return nil
                }

            }) { rawResult, error in
                if let error {
                    cont.resume(throwing: error)
                    return
                }

                guard let dict = rawResult as? NSDictionary,
                      let macUID = dict["macUID"] as? String,
                      let macDeviceID = dict["macDeviceID"] as? String else {
                    cont.resume(throwing: NSError(
                        domain: "Pairing",
                        code: 500,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to parse pairing result"]
                    ))
                    return
                }

                cont.resume(returning: (macUID, macDeviceID))
            }
        }

        return ConnectionProfile(
            macUID: result.macUID,
            macDeviceID: result.macDeviceID,
            conversationId: nil
        )
    }
}
