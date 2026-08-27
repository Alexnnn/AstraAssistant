//
//  Astra_AI_AssistantApp.swift
//  Astra AI Assistant
//
//  Created by Alex on 13/8/26.
//

import SwiftUI
import FirebaseCore


@main
struct Astra_AI_AssistantApp: App {
    @StateObject private var appViewModel = AppViewModel()

    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appViewModel)
                .task {
                    await appViewModel.start()
                }
        }

        // можно оставить стандартные Settings для меню app
        Settings {
            SettingsView()
                .environmentObject(appViewModel)
        }

        // ДОБАВИТЬ: явное окно settings с id
        Window("App Settings", id: "app-settings") {
            SettingsView()
                .environmentObject(appViewModel)
                .frame(minWidth: 920, minHeight: 720)
        }

        Window("Setup Wizard", id: "setup-wizard") {
            SetupLauncherView()
                .environmentObject(appViewModel)
                .frame(minWidth: 980, minHeight: 700)
        }

        Window("Help & Setup", id: "help-center") {
            HelpCenterView()
                .environmentObject(appViewModel)
                .frame(minWidth: 900, minHeight: 700)
        }
    }
}
