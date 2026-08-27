//
//  AstraCompanionApp.swift
//  AstraCompanion
//
//  Created by Alex on 13/8/26.
//

import SwiftUI
import FirebaseCore

@main
struct AstraCompanionApp: App {
    @StateObject private var appState = CompanionAppState()
    @StateObject private var avatarStore = IOSAvatarStore()

    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            CompanionRootView()
                .environmentObject(appState)
                .environmentObject(avatarStore)
                .task {
                    await appState.bootstrap()
                }
        }
    }
}
