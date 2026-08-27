//
//  VectorMemoryStore.swift
//  AstraAssistant
//
//  Created by Alex on 10/8/26.
//

import Foundation
import SQLite3

final class VectorMemoryStore {
    static let shared = VectorMemoryStore()

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
            print("Failed to open SQLite database.")
        }
    }

    private func createTables() {
        let sql = """
        CREATE TABLE IF NOT EXISTS memories (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            type TEXT NOT NULL,
            content TEXT NOT NULL,
            importance INTEGER NOT NULL DEFAULT 5,
            embedding BLOB NOT NULL,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
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

    func addMemory(
        type: String,
        content: String,
        importance: Int,
        embedding: [Float]
    ) {
        let sql = """
        INSERT INTO memories
        (type, content, importance, embedding, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?);
        """

        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return
        }

        defer {
            sqlite3_finalize(statement)
        }

        let now = Date().timeIntervalSince1970
        let embeddingData = floatsToData(embedding)

        sqlite3_bind_text(statement, 1, type, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, content, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(statement, 3, Int32(importance))

        embeddingData.withUnsafeBytes { bytes in
            sqlite3_bind_blob(
                statement,
                4,
                bytes.baseAddress,
                Int32(embeddingData.count),
                SQLITE_TRANSIENT
            )
        }

        sqlite3_bind_double(statement, 5, now)
        sqlite3_bind_double(statement, 6, now)

        if sqlite3_step(statement) != SQLITE_DONE {
            print("Failed to insert memory.")
        }
    }

    func listMemories() -> [MemoryItem] {
        let sql = """
        SELECT id, type, content, importance, created_at, updated_at
        FROM memories
        ORDER BY updated_at DESC;
        """

        var statement: OpaquePointer?
        var result: [MemoryItem] = []

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return []
        }

        defer {
            sqlite3_finalize(statement)
        }

        while sqlite3_step(statement) == SQLITE_ROW {
            let id = sqlite3_column_int64(statement, 0)
            let type = String(cString: sqlite3_column_text(statement, 1))
            let content = String(cString: sqlite3_column_text(statement, 2))
            let importance = Int(sqlite3_column_int(statement, 3))
            let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 4))
            let updatedAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 5))

            result.append(
                MemoryItem(
                    id: id,
                    type: type,
                    content: content,
                    importance: importance,
                    createdAt: createdAt,
                    updatedAt: updatedAt
                )
            )
        }

        return result
    }

    func searchSimilar(
        queryEmbedding: [Float],
        limit: Int = 5,
        minSimilarity: Float = 0.35
    ) -> [MemoryItem] {
        let sql = """
        SELECT id, type, content, importance, embedding, created_at, updated_at
        FROM memories;
        """

        var statement: OpaquePointer?
        var scored: [(item: MemoryItem, similarity: Float, score: Float)] = []

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return []
        }

        defer {
            sqlite3_finalize(statement)
        }

        while sqlite3_step(statement) == SQLITE_ROW {
            let id = sqlite3_column_int64(statement, 0)
            let type = String(cString: sqlite3_column_text(statement, 1))
            let content = String(cString: sqlite3_column_text(statement, 2))
            let importance = Int(sqlite3_column_int(statement, 3))

            let blobPointer = sqlite3_column_blob(statement, 4)
            let blobSize = Int(sqlite3_column_bytes(statement, 4))

            guard let blobPointer else {
                continue
            }

            let data = Data(bytes: blobPointer, count: blobSize)
            let embedding = dataToFloats(data)

            let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 5))
            let updatedAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 6))

            let item = MemoryItem(
                id: id,
                type: type,
                content: content,
                importance: importance,
                createdAt: createdAt,
                updatedAt: updatedAt
            )

            let similarity = cosineSimilarity(queryEmbedding, embedding)

            guard similarity >= minSimilarity else {
                continue
            }

            let importanceBoost = Float(importance) * 0.01
            let score = similarity + importanceBoost

            scored.append((item, similarity, score))
        }

        return scored
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0.item }
    }

    func deleteMemory(id: Int64) {
        let sql = "DELETE FROM memories WHERE id = ?;"

        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return
        }

        defer {
            sqlite3_finalize(statement)
        }

        sqlite3_bind_int64(statement, 1, id)

        sqlite3_step(statement)
    }

    private func floatsToData(_ floats: [Float]) -> Data {
        floats.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
    }

    private func dataToFloats(_ data: Data) -> [Float] {
        data.withUnsafeBytes { rawBuffer in
            let buffer = rawBuffer.bindMemory(to: Float.self)
            return Array(buffer)
        }
    }

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else {
            return 0
        }

        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0

        for i in 0..<a.count {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }

        if normA == 0 || normB == 0 {
            return 0
        }

        return dot / (sqrt(normA) * sqrt(normB))
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(
    -1,
    to: sqlite3_destructor_type.self
)
