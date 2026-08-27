//
//  CompanionModels.swift
//  Astra AI Assistant
//
//  Created by Alex on 13/8/26.
//


import Foundation

enum CompanionCommandType: String, Codable {
    case systemPing = "system.ping"
    case chatSend = "chat.send"
    case tasksList = "tasks.list"
    case tasksAdd = "tasks.add"
    case tasksSetDone = "tasks.setDone"
    case tasksDelete = "tasks.delete"
    case imageGenerate = "image.generate"
    case imageAnalyze = "image.analyze"
    case imageEdit = "image.edit"
    case fileSummarize = "file.summarize"
    case ttsSynthesize = "tts.synthesize"
    
    case webSearch = "web.search"
    case dailyBriefing = "briefing.daily"
    case calendarToday = "calendar.today"
    
    case conversationDelete = "conversation.delete"

}

enum CompanionCommandStatus: String, Codable {
    case queued
    case running
    case done
    case error
}

struct CompanionCommandRequest {
    let id: String
    let uid: String
    let sourceDevice: String
    let targetDevice: String
    let type: CompanionCommandType
    let payload: [String: Any]
}

struct CompanionCommandResult {
    let data: [String: Any]
}
