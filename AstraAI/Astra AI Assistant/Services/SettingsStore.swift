//
//  SettingsStore.swift
//  AstraAssistant
//
//  Created by Alex on 10/8/26.
//

import Foundation
import Combine

@MainActor
final class SettingsStore: ObservableObject {
    @Published private(set) var settings: AssistantSettings

    private let key = "astra.assistant.settings"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(AssistantSettings.self, from: data) {
            self.settings = decoded
        } else {
            self.settings = AssistantSettings()
        }
    }

    func update(_ transform: (inout AssistantSettings) -> Void) {
        transform(&settings)
        save()
    }

    func replace(with newSettings: AssistantSettings) {
        settings = newSettings
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(settings) else {
            return
        }

        UserDefaults.standard.set(data, forKey: key)
    }
}
