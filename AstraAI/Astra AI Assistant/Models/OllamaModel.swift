//
//  OllamaModel.swift
//  AstraAssistant
//
//  Created by Alex on 10/8/26.
//

import Foundation

struct OllamaTagsResponse: Codable {
    let models: [OllamaModel]
}

struct OllamaModel: Codable, Identifiable, Hashable {
    var id: String { name }

    let name: String
    let modified_at: String?
    let size: Int64?
    let digest: String?
}
