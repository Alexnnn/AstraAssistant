//
//  ConnectionProfileStore.swift
//  AstraCompanion
//
//  Created by Alex on 13/8/26.
//

import Foundation

final class ConnectionProfileStore {
    static let shared = ConnectionProfileStore()
    private init() {}

    private let key = "astra.companion.connection.profile"

    func save(_ profile: ConnectionProfile) {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    func load() -> ConnectionProfile? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(ConnectionProfile.self, from: data)
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
