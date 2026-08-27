//
//  CompanionAppState.swift
//  AstraCompanion
//
//  Created by Alex on 13/8/26.
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class CompanionAppState: ObservableObject {
    @Published var profile: ConnectionProfile?
    @Published var statusText: String = "Initializing..."
    @Published var errorText: String?
    @Published var selectedTab: AppTab = .conversations

    let chatVM = CompanionChatViewModel()

    func bootstrap() async {
        do {
            try await CompanionPairingClient.shared.ensureAuth()
            statusText = "Firebase ready"

            if let saved = ConnectionProfileStore.shared.load() {
                applyProfile(saved)
            }
        } catch {
            statusText = "Auth failed"
            errorText = error.localizedDescription
        }
    }

    func connectWithCode(_ code: String) async {
        errorText = nil
        do {
            let prof = try await CompanionPairingClient.shared.redeemCode(code)
            ConnectionProfileStore.shared.save(prof)
            applyProfile(prof)
            selectedTab = .chat
        } catch {
            errorText = error.localizedDescription
        }
    }

    func openConversation(_ id: String) {
        chatVM.setConversation(id)
        selectedTab = .chat
    }

    func createNewConversation() {
        chatVM.startNewConversation()
        selectedTab = .chat
    }

    func disconnect() {
        profile = nil
        ConnectionProfileStore.shared.clear()
        chatVM.clearConnection()
        selectedTab = .conversations
    }

    private func applyProfile(_ profile: ConnectionProfile) {
        self.profile = profile
        chatVM.applyConnection(profile)
    }
}
