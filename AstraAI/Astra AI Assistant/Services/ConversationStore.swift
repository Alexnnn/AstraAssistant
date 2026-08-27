//
//  ConversationStore.swift
//  AstraAssistant
//
//  Created by Alex on 10/8/26.
//

import Foundation
import SQLite3

struct ConversationSummary: Identifiable, Hashable {
    let id: UUID
    let title: String
    let createdAt: Date
    let updatedAt: Date
}

extension Notification.Name {
    static let conversationStoreDidChange = Notification.Name("conversationStoreDidChange")
}

final class ConversationStore {
    static let shared = ConversationStore()

    private var db: OpaquePointer?

    private init() {
        openDatabase()
        createTables()
    }

    deinit {
        sqlite3_close(db)
    }

    private var databaseURL: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        let folder = base.appendingPathComponent("Astra Assistant", isDirectory: true)

        try? FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true
        )

        return folder.appendingPathComponent("astra.sqlite")
    }

    private func openDatabase() {
        if sqlite3_open(databaseURL.path, &db) != SQLITE_OK {
            print("Failed to open ConversationStore database.")
        }
    }

    private func createTables() {
        let sql = """
        CREATE TABLE IF NOT EXISTS conversations (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        );

        CREATE TABLE IF NOT EXISTS messages (
            id TEXT PRIMARY KEY,
            conversation_id TEXT NOT NULL,
            role TEXT NOT NULL,
            content TEXT NOT NULL,
            attachment_path TEXT,
            created_at REAL NOT NULL,
            FOREIGN KEY(conversation_id) REFERENCES conversations(id)
        );
        """

        execute(sql)
    }

    private func execute(_ sql: String) {
        var error: UnsafeMutablePointer<Int8>?

        if sqlite3_exec(db, sql, nil, nil, &error) != SQLITE_OK {
            if let error {
                print("SQLite error:", String(cString: error))
                sqlite3_free(error)
            }
        }
    }

    func createConversation(id: UUID, title: String) {
        let sql = """
        INSERT OR IGNORE INTO conversations
        (id, title, created_at, updated_at)
        VALUES (?, ?, ?, ?);
        """

        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return
        }

        defer {
            sqlite3_finalize(statement)
        }

        let now = Date().timeIntervalSince1970

        sqlite3_bind_text(statement, 1, id.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, title, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(statement, 3, now)
        sqlite3_bind_double(statement, 4, now)

        sqlite3_step(statement)
        postChange(conversationId: id)
    }

    func updateConversationTitle(id: UUID, title: String) {
        let sql = """
        UPDATE conversations
        SET title = ?, updated_at = ?
        WHERE id = ?;
        """

        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return
        }

        defer {
            sqlite3_finalize(statement)
        }

        sqlite3_bind_text(statement, 1, title, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(statement, 2, Date().timeIntervalSince1970)
        sqlite3_bind_text(statement, 3, id.uuidString, -1, SQLITE_TRANSIENT)

        sqlite3_step(statement)
        postChange(conversationId: id)
    }

    func appendMessage(_ message: ChatMessage) {
        let sql = """
        INSERT INTO messages
        (id, conversation_id, role, content, attachment_path, created_at)
        VALUES (?, ?, ?, ?, ?, ?);
        """

        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return
        }

        defer {
            sqlite3_finalize(statement)
        }

        sqlite3_bind_text(statement, 1, message.id.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, message.conversationId.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 3, message.role.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 4, message.content, -1, SQLITE_TRANSIENT)

        if let attachmentPath = message.attachmentPath {
            sqlite3_bind_text(statement, 5, attachmentPath, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(statement, 5)
        }

        sqlite3_bind_double(statement, 6, message.createdAt.timeIntervalSince1970)

        sqlite3_step(statement)

        touchConversation(id: message.conversationId)
        postChange(conversationId: message.conversationId)
    }

    func listConversations() -> [ConversationSummary] {
        let sql = """
        SELECT id, title, created_at, updated_at
        FROM conversations
        ORDER BY updated_at DESC;
        """

        var statement: OpaquePointer?
        var result: [ConversationSummary] = []

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return []
        }

        defer {
            sqlite3_finalize(statement)
        }

        while sqlite3_step(statement) == SQLITE_ROW {
            let idString = String(cString: sqlite3_column_text(statement, 0))
            let title = String(cString: sqlite3_column_text(statement, 1))
            let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 2))
            let updatedAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 3))

            guard let id = UUID(uuidString: idString) else {
                continue
            }

            result.append(
                ConversationSummary(
                    id: id,
                    title: title,
                    createdAt: createdAt,
                    updatedAt: updatedAt
                )
            )
        }

        return result
    }

    func loadMessages(conversationId: UUID) -> [ChatMessage] {
        let sql = """
        SELECT id, role, content, attachment_path, created_at
        FROM messages
        WHERE conversation_id = ?
        ORDER BY created_at ASC;
        """

        var statement: OpaquePointer?
        var result: [ChatMessage] = []

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return []
        }

        defer {
            sqlite3_finalize(statement)
        }

        sqlite3_bind_text(statement, 1, conversationId.uuidString, -1, SQLITE_TRANSIENT)

        while sqlite3_step(statement) == SQLITE_ROW {
            let idString = String(cString: sqlite3_column_text(statement, 0))
            let roleString = String(cString: sqlite3_column_text(statement, 1))
            let content = String(cString: sqlite3_column_text(statement, 2))

            let attachmentPath: String?
            if let cString = sqlite3_column_text(statement, 3) {
                attachmentPath = String(cString: cString)
            } else {
                attachmentPath = nil
            }

            let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 4))

            guard let id = UUID(uuidString: idString),
                  let role = ChatRole(rawValue: roleString) else {
                continue
            }

            result.append(
                ChatMessage(
                    id: id,
                    conversationId: conversationId,
                    role: role,
                    content: content,
                    createdAt: createdAt,
                    attachmentPath: attachmentPath
                )
            )
        }

        return result
    }

    func exportConversationMarkdown(conversationId: UUID) -> String {
        let messages = loadMessages(conversationId: conversationId)

        var markdown = "# Astra Assistant Conversation\n\n"

        for message in messages {
            let roleTitle: String

            switch message.role {
            case .system:
                roleTitle = "System"
            case .user:
                roleTitle = "User"
            case .assistant:
                roleTitle = "Astra"
            case .tool:
                roleTitle = "Tool"
            }

            markdown += "## \(roleTitle)\n\n"
            markdown += message.content
            markdown += "\n\n"

            if let attachmentPath = message.attachmentPath {
                markdown += "_Attachment: \(attachmentPath)_\n\n"
            }
        }

        return markdown
    }

    func deleteConversation(id: UUID) {
        let deleteMessagesSQL = "DELETE FROM messages WHERE conversation_id = ?;"
        let deleteConversationSQL = "DELETE FROM conversations WHERE id = ?;"

        executeDelete(sql: deleteMessagesSQL, id: id.uuidString)
        executeDelete(sql: deleteConversationSQL, id: id.uuidString)
        postChange(conversationId: id)
    }

    private func touchConversation(id: UUID) {
        let sql = """
        UPDATE conversations
        SET updated_at = ?
        WHERE id = ?;
        """

        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return
        }

        defer {
            sqlite3_finalize(statement)
        }

        sqlite3_bind_double(statement, 1, Date().timeIntervalSince1970)
        sqlite3_bind_text(statement, 2, id.uuidString, -1, SQLITE_TRANSIENT)

        sqlite3_step(statement)
    }

    private func executeDelete(sql: String, id: String) {
        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return
        }

        defer {
            sqlite3_finalize(statement)
        }

        sqlite3_bind_text(statement, 1, id, -1, SQLITE_TRANSIENT)

        sqlite3_step(statement)
    }

    private func postChange(conversationId: UUID) {
        NotificationCenter.default.post(
            name: .conversationStoreDidChange,
            object: nil,
            userInfo: ["conversationId": conversationId.uuidString]
        )
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(
    -1,
    to: sqlite3_destructor_type.self
)
