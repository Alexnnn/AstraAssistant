//
//  MacConnectionStatusViewModel.swift
//  AstraCompanion
//
//  Created by Alex on 14/8/26.
//

import Foundation
import SwiftUI
import FirebaseFirestore
import Combine

@MainActor
final class MacConnectionStatusViewModel: ObservableObject {
    @Published var isListening = false
    @Published var rawOnline = false
    @Published var lastSeen: Date?
    @Published var appVersion: String?
    @Published var build: String?
    @Published var platform: String?
    @Published var statusText = "Mac status unknown"
    @Published var lastPingText: String?
    @Published var lastError: String?

    private var listener: ListenerRegistration?

    var isCommandAvailable: Bool {
        guard rawOnline else { return false }

        // Если heartbeat старше 60 секунд — считаем Mac подозрительно недоступным.
        if let lastSeen {
            return Date().timeIntervalSince(lastSeen) < 60
        }

        return true
    }

    var statusColor: Color {
        if isCommandAvailable {
            return .green
        }

        if rawOnline {
            return .orange
        }

        return .red
    }

    func start(profile: ConnectionProfile?) {
        stop()

        guard let profile else {
            rawOnline = false
            lastSeen = nil
            statusText = "Not connected"
            return
        }

        let ref = Firestore.firestore()
            .collection("users")
            .document(profile.macUID)
            .collection("devices")
            .document(profile.macDeviceID)

        isListening = true
        lastError = nil

        listener = ref.addSnapshotListener { [weak self] snapshot, error in
            guard let self else { return }

            Task { @MainActor in
                if let error {
                    self.lastError = error.localizedDescription
                    self.rawOnline = false
                    self.statusText = "Mac status error"
                    return
                }

                guard let data = snapshot?.data() else {
                    self.rawOnline = false
                    self.lastSeen = nil
                    self.statusText = "Mac device not found"
                    return
                }

                self.rawOnline = (data["online"] as? Bool) ?? false
                self.lastSeen = (data["lastSeen"] as? Timestamp)?.dateValue()
                self.appVersion = data["appVersion"] as? String
                self.build = data["build"] as? String
                self.platform = data["platform"] as? String

                self.rebuildStatusText()
            }
        }
    }

    func stop() {
        listener?.remove()
        listener = nil
        isListening = false
    }

    func ping(profile: ConnectionProfile?) async {
        guard let profile else {
            lastPingText = nil
            lastError = "Not connected to Mac."
            return
        }

        lastPingText = "Pinging..."
        lastError = nil

        do {
            try await CompanionCommandClient.shared.ensureAuth()

            let commandId = try await CompanionCommandClient.shared.sendCommand(
                macUID: profile.macUID,
                targetDevice: profile.macDeviceID,
                type: .systemPing,
                payload: [:]
            )

            let response = try await CompanionCommandClient.shared.waitForResponse(
                macUID: profile.macUID,
                commandId: commandId,
                timeoutSeconds: 20
            )

            let message = response.raw["message"] as? String ?? "pong"
            lastPingText = "Ping OK: \(message)"
        } catch {
            lastPingText = "Ping failed"
            lastError = error.localizedDescription
        }
    }

    private func rebuildStatusText() {
        guard rawOnline else {
            if let lastSeen {
                statusText = "Mac offline · last seen \(relativeDate(lastSeen))"
            } else {
                statusText = "Mac offline"
            }
            return
        }

        guard let lastSeen else {
            statusText = "Mac online"
            return
        }

        let age = Date().timeIntervalSince(lastSeen)

        if age < 60 {
            statusText = "Mac online"
        } else {
            statusText = "Mac maybe offline · last seen \(relativeDate(lastSeen))"
        }
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
