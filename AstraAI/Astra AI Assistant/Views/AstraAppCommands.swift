//
//  AstraAppCommands.swift
//  AstraAssistant
//
//  Created by Alex on 11/8/26.
//

import SwiftUI

struct AstraAppCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        // Оставляем системное меню View -> Show/Hide Sidebar
        SidebarCommands()

        CommandMenu("Astra") {
            Button("Open Help & Setup") {
                openWindow(id: "help-center")
            }
            .keyboardShortcut("/", modifiers: [.command, .shift])
        }

        CommandGroup(after: .help) {
            Divider()
            Button("Astra Help & Setup") {
                openWindow(id: "help-center")
            }
            Divider()
            Button("Open Setup Wizard") {
                openWindow(id: "setup-wizard")
            }
            .keyboardShortcut("0", modifiers: [.command, .shift])
        }
    }
}
