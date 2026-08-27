//
//  CompanionDTO.swift
//  AstraCompanion
//
//  Created by Alex on 13/8/26.
//

import Foundation

enum CompanionCommandStatus: String {
    case queued
    case running
    case done
    case error
}

// Добавляем новый тип команды
enum CompanionCommandType: String {
    case chatSend = "chat.send"
    case imageGenerate = "image.generate"
    case imageAnalyze = "image.analyze"
    case imageEdit = "image.edit"
    case fileSummarize = "file.summarize"
    
    case systemPing = "system.ping"
    case tasksList = "tasks.list"
    case tasksAdd = "tasks.add"
    case tasksSetDone = "tasks.setDone"
    case tasksDelete = "tasks.delete"
    
    case ttsSynthesize = "tts.synthesize"
    case webSearch = "web.search"
    case dailyBriefing = "briefing.daily"
    case calendarToday = "calendar.today"
    
    // Новый тип для удаления чата
    case conversationDelete = "conversation.delete"
}

struct CompanionMessage: Identifiable, Hashable {
    let id = UUID()
    let role: String  // user | assistant | system
    let text: String
}

struct CompanionChatResponse {
    let assistantText: String
    let conversationId: String?
}
