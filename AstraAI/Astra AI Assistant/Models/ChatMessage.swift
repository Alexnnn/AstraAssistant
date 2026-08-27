//
//  ChatMessage.swift
//  AstraAssistant
//
//  Created by Alex on 10/8/26.
//

import Foundation

enum ChatRole: String, Codable {
    case system
    case user
    case assistant
    case tool
}

struct ChatMessage: Identifiable, Codable, Hashable {
    let id: UUID
    let conversationId: UUID
    let role: ChatRole
    let content: String
    let createdAt: Date
    let attachmentPath: String?

    init(
        id: UUID = UUID(),
        conversationId: UUID,
        role: ChatRole,
        content: String,
        createdAt: Date = Date(),
        attachmentPath: String? = nil
    ) {
        self.id = id
        self.conversationId = conversationId
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.attachmentPath = attachmentPath
    }
}
