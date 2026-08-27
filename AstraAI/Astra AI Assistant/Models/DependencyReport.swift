//
//  DependencyReport.swift
//  AstraAssistant
//
//  Created by Alex on 10/8/26.
//

import Foundation

enum DependencyStatus: String, Codable {
    case ok
    case warning
    case missing
}

struct DependencyCheckItem: Identifiable, Codable {
    let id = UUID()
    let title: String
    let status: DependencyStatus
    let details: String
    let instruction: String?
}

struct DependencyReport {
    let items: [DependencyCheckItem]
    
    var hasBlockingIssues: Bool {
        // Только missing статусы блокируют запуск
        items.contains { $0.status == .missing }
    }
    
    var allOk: Bool {
        items.allSatisfy { $0.status == .ok }
    }
}
