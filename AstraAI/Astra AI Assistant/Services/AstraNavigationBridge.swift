//
//  AstraNavigationBridge.swift
//  AstraAssistant
//
//  Created by Alex on 11/8/26.
//

import Foundation
import AppKit

enum AstraNavTarget: String {
    case chat
    case memory
    case tasks
    case models
    case settings
}

extension Notification.Name {
    static let astraNavigateToSection = Notification.Name("astraNavigateToSection")
}

func astraNavigateTo(_ target: AstraNavTarget) {
    NSApp.activate(ignoringOtherApps: true)
    NotificationCenter.default.post(
        name: .astraNavigateToSection,
        object: nil,
        userInfo: ["target": target.rawValue]
    )
}

func openAstraSettingsWindow() {
    if #available(macOS 14.0, *) {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    } else {
        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
    }
}
