//
//  FileReaderService.swift
//  AstraAssistant
//
//  Created by Alex on 10/8/26.
//

import Foundation
import PDFKit

final class FileReaderService {
    static let shared = FileReaderService()

    private init() {}

    func readText(from url: URL) throws -> String {
        let ext = url.pathExtension.lowercased()

        if ext == "pdf" {
            return try readPDF(url)
        }

        if ["txt", "md", "markdown", "json", "csv", "log", "swift", "py", "js", "ts", "html", "css"].contains(ext) {
            return try String(contentsOf: url, encoding: .utf8)
        }

        throw NSError(
            domain: "FileReaderService",
            code: -1,
            userInfo: [
                NSLocalizedDescriptionKey: "Unsupported file type: \(ext)"
            ]
        )
    }

    private func readPDF(_ url: URL) throws -> String {
        guard let document = PDFDocument(url: url) else {
            throw NSError(
                domain: "FileReaderService",
                code: -2,
                userInfo: [
                    NSLocalizedDescriptionKey: "Failed to open PDF."
                ]
            )
        }

        var text = ""

        for index in 0..<document.pageCount {
            if let page = document.page(at: index),
               let pageText = page.string {
                text += "\n\n--- Page \(index + 1) ---\n\n"
                text += pageText
            }
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
