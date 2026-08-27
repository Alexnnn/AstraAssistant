//
//  TaskStore.swift
//  AstraAssistant
//
//  Created by Alex on 10/8/26.
//

import Foundation
import SQLite3

final class TaskStore {
    static let shared = TaskStore()

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
        sqlite3_open(databaseURL.path, &db)
    }

    private func createTables() {
        let sql = """
        CREATE TABLE IF NOT EXISTS tasks (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            notes TEXT NOT NULL,
            is_done INTEGER NOT NULL,
            created_at REAL NOT NULL,
            due_at REAL
        );
        """

        sqlite3_exec(db, sql, nil, nil, nil)
    }
    
    func listAllTasks() -> [AstraTask] {
        let sql = """
        SELECT id, title, notes, is_done, created_at, due_at
        FROM tasks
        ORDER BY created_at DESC;
        """

        var statement: OpaquePointer?
        var result: [AstraTask] = []

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return []
        }

        defer { sqlite3_finalize(statement) }

        while sqlite3_step(statement) == SQLITE_ROW {
            guard let idString = sqlite3_column_text(statement, 0),
                  let titleString = sqlite3_column_text(statement, 1),
                  let notesString = sqlite3_column_text(statement, 2),
                  let id = UUID(uuidString: String(cString: idString)) else {
                continue
            }

            let isDone = sqlite3_column_int(statement, 3) == 1
            let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 4))

            let dueAt: Date?
            if sqlite3_column_type(statement, 5) == SQLITE_NULL {
                dueAt = nil
            } else {
                dueAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 5))
            }

            result.append(
                AstraTask(
                    id: id,
                    title: String(cString: titleString),
                    notes: String(cString: notesString),
                    isDone: isDone,
                    createdAt: createdAt,
                    dueAt: dueAt
                )
            )
        }

        return result
    }

    func setTaskDone(id: UUID, isDone: Bool) {
        let sql = "UPDATE tasks SET is_done = ? WHERE id = ?;"
        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int(statement, 1, isDone ? 1 : 0)
        sqlite3_bind_text(statement, 2, id.uuidString, -1, SQLITE_TRANSIENT)

        sqlite3_step(statement)
    }

    func deleteTask(id: UUID) {
        let sql = "DELETE FROM tasks WHERE id = ?;"
        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, id.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_step(statement)
    }

    func addTask(title: String, notes: String = "", dueAt: Date? = nil) {
        let task = AstraTask(title: title, notes: notes, dueAt: dueAt)

        let sql = """
        INSERT INTO tasks
        (id, title, notes, is_done, created_at, due_at)
        VALUES (?, ?, ?, ?, ?, ?);
        """

        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return
        }

        defer {
            sqlite3_finalize(statement)
        }

        sqlite3_bind_text(statement, 1, task.id.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, task.title, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 3, task.notes, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(statement, 4, task.isDone ? 1 : 0)
        sqlite3_bind_double(statement, 5, task.createdAt.timeIntervalSince1970)

        if let dueAt = task.dueAt {
            sqlite3_bind_double(statement, 6, dueAt.timeIntervalSince1970)
        } else {
            sqlite3_bind_null(statement, 6)
        }

        sqlite3_step(statement)
    }

    func listOpenTasks() -> [AstraTask] {
        let sql = """
        SELECT id, title, notes, is_done, created_at, due_at
        FROM tasks
        WHERE is_done = 0
        ORDER BY created_at DESC;
        """

        var statement: OpaquePointer?
        var result: [AstraTask] = []

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return []
        }

        defer {
            sqlite3_finalize(statement)
        }

        while sqlite3_step(statement) == SQLITE_ROW {
            guard let idString = sqlite3_column_text(statement, 0),
                  let titleString = sqlite3_column_text(statement, 1),
                  let notesString = sqlite3_column_text(statement, 2),
                  let id = UUID(uuidString: String(cString: idString)) else {
                continue
            }

            let isDone = sqlite3_column_int(statement, 3) == 1
            let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 4))

            let dueAt: Date?
            if sqlite3_column_type(statement, 5) == SQLITE_NULL {
                dueAt = nil
            } else {
                dueAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 5))
            }

            result.append(
                AstraTask(
                    id: id,
                    title: String(cString: titleString),
                    notes: String(cString: notesString),
                    isDone: isDone,
                    createdAt: createdAt,
                    dueAt: dueAt
                )
            )
        }

        return result
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(
    -1,
    to: sqlite3_destructor_type.self
)
