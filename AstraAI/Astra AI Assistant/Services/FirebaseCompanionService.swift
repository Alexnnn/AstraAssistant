//
//  FirebaseCompanionService.swift
//  Astra AI Assistant
//
//  Created by Alex on 13/8/26.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import Combine

@MainActor
final class FirebaseCompanionService: ObservableObject {
    static let shared = FirebaseCompanionService()

    @Published var isReady = false
    @Published var uid: String?
    @Published var deviceId: String = DeviceIdentity.current
    @Published var lastError: String?

    private let db = Firestore.firestore()
    private var heartbeatTask: Task<Void, Never>?

    private init() {}

    func start() async {
        do {
            let user = try await ensureAuth()
            uid = user.uid

            try await registerDeviceOnline(uid: user.uid)
            startHeartbeat(uid: user.uid)

            isReady = true
            lastError = nil
        } catch {
            isReady = false
            lastError = error.localizedDescription
        }
    }

    func stop() {
        heartbeatTask?.cancel()
        heartbeatTask = nil

        Task {
            if let uid {
                try? await setOnline(uid: uid, online: false)
            }
        }
    }

    // MARK: - Private

    private func ensureAuth() async throws -> User {
        if let current = Auth.auth().currentUser {
            return current
        }

        return try await withCheckedThrowingContinuation { cont in
            Auth.auth().signInAnonymously { result, error in
                if let error {
                    cont.resume(throwing: error)
                } else if let user = result?.user {
                    cont.resume(returning: user)
                } else {
                    cont.resume(throwing: NSError(
                        domain: "FirebaseCompanionService",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Anonymous auth returned no user."]
                    ))
                }
            }
        }
    }

    private func registerDeviceOnline(uid: String) async throws {
        let ref = db.collection("users")
            .document(uid)
            .collection("devices")
            .document(deviceId)

        let payload: [String: Any] = [
            "platform": "macOS",
            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            "build": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown",
            "online": true,
            "lastSeen": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ]

        try await ref.setData(payload, merge: true)
    }

    private func startHeartbeat(uid: String) {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                try? await self.setOnline(uid: uid, online: true)
            }
        }
    }

    private func setOnline(uid: String, online: Bool) async throws {
        let ref = db.collection("users")
            .document(uid)
            .collection("devices")
            .document(deviceId)

        try await ref.setData([
            "online": online,
            "lastSeen": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
    }
}

enum DeviceIdentity {
    private static let key = "astra.device.id"

    static var current: String {
        if let existing = UserDefaults.standard.string(forKey: key), !existing.isEmpty {
            return existing
        }
        let new = UUID().uuidString
        UserDefaults.standard.set(new, forKey: key)
        return new
    }
}
