//
//  MemoryItem.swift
//  AstraAssistant
//
//  Created by Alex on 10/8/26.
//

import Foundation

struct MemoryItem: Identifiable, Codable, Hashable {
    let id: Int64
    var type: String
    var content: String
    var importance: Int
    var createdAt: Date
    var updatedAt: Date
}
