//
//  ToolRoutingModels.swift
//  AstraAssistant
//
//  Created by Alex on 10/8/26.
//

import Foundation

enum ToolRoutingAction: String, Codable {
    case none
    case webSearch
    case openURL
    case createTask
    case listTasks
}

struct ToolRoutingDecision: Codable {
    let action: ToolRoutingAction
    let query: String?
    let url: String?
    let title: String?
    let reason: String?
}
