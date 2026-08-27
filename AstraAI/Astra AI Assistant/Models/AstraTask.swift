//
//  AstraTask.swift
//  AstraAssistant
//
//  Created by Alex on 10/8/26.
//

import Foundation

struct AstraTask: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var notes: String
    var isDone: Bool
    var createdAt: Date
    var dueAt: Date?

    init(
        id: UUID = UUID(),
        title: String,
        notes: String = "",
        isDone: Bool = false,
        createdAt: Date = Date(),
        dueAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.isDone = isDone
        self.createdAt = createdAt
        self.dueAt = dueAt
    }
}
