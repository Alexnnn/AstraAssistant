//
//  KeychainStore.swift
//  AstraAssistant
//
//  Created by Alex on 10/8/26.
//

import Foundation
import Security

final class KeychainStore {
    static let shared = KeychainStore()

    private init() {}

    private let service = "com.astra.assistant"

    func saveOpenAIKey(_ key: String) throws {
        try save(key, account: "openai_api_key")
    }

    func getOpenAIKey() -> String? {
        get(account: "openai_api_key")
    }

    func deleteOpenAIKey() {
        delete(account: "openai_api_key")
    }
    
    func saveWaveSpeedKey(_ key: String) throws {
        try save(key, account: "wavespeed_api_key")
    }

    func getWaveSpeedKey() -> String? {
        get(account: "wavespeed_api_key")
    }

    func deleteWaveSpeedKey() {
        delete(account: "wavespeed_api_key")
    }

    private func save(_ value: String, account: String) throws {
        let data = Data(value.utf8)

        delete(account: account)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw NSError(
                domain: "KeychainStore",
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "Failed to save item to Keychain."]
            )
        }
    }

    private func get(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?

        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }

        return string
    }

    private func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        SecItemDelete(query as CFDictionary)
    }
}
