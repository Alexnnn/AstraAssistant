//
//  ToolModels.swift
//  AstraAssistant
//
//  Created by Alex on 10/8/26.
//

import Foundation

enum ToolKind: String, Codable, CaseIterable, Identifiable {
    case webSearch
    case openURL
    case readFile
    case analyzeScreen
    case createTask
    case listTasks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .webSearch:
            return "Web Search"
        case .openURL:
            return "Open URL"
        case .readFile:
            return "Read File"
        case .analyzeScreen:
            return "Analyze Screen"
        case .createTask:
            return "Create Task"
        case .listTasks:
            return "List Tasks"
        }
    }

    var requiresConfirmation: Bool {
        switch self {
        case .webSearch:
            return false
        case .openURL:
            return true
        case .readFile:
            return true
        case .analyzeScreen:
            return true
        case .createTask:
            return false
        case .listTasks:
            return false
        }
    }
}

struct PendingToolConfirmation: Identifiable, Hashable {
    let id = UUID()
    let kind: ToolKind
    let title: String
    let details: String
    let payload: String
}
