//
//  AssistantSettings.swift
//  AstraAssistant
//
//  Created by Alex on 10/8/26.
//

import Foundation


enum ImageProvider: String, Codable, CaseIterable, Identifiable {
    case openAI
    case waveSpeed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openAI: return "OpenAI"
        case .waveSpeed: return "WaveSpeed Seedream"
        }
    }
}

enum WaveSpeedGenerateModel: String, Codable, CaseIterable, Identifiable {
    case seedreamV45 = "bytedance/seedream-v4.5"
    case seedreamV50Pro = "bytedance/seedream-v5.0-pro"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .seedreamV45: return "Seedream 4.5"
        case .seedreamV50Pro: return "Seedream V5.0 Pro"
        }
    }
}

enum WaveSpeedEditModel: String, Codable, CaseIterable, Identifiable {
    case seedreamV45Edit = "bytedance/seedream-v4.5/edit"
    case seedreamV50ProEdit = "bytedance/seedream-v5.0-pro/edit"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .seedreamV45Edit: return "Seedream 4.5 Edit"
        case .seedreamV50ProEdit: return "Seedream V5.0 Pro Edit"
        }
    }
}



enum MemoryMode: String, Codable, CaseIterable, Identifiable {
    case off
    case manual
    case askBeforeSaving
    case automatic

    var id: String { rawValue }
}

enum TTSProvider: String, Codable, CaseIterable, Identifiable {
    case macOS
    case waveSpeedQwen3
    case localQwen3

    var id: String { rawValue }

    var title: String {
        switch self {
        case .macOS:
            return "macOS Voice"
        case .waveSpeedQwen3:
            return "WaveSpeed Qwen3 Voice Clone API"
        case .localQwen3:
            return "Local Qwen3 TTS on Mac"
        }
    }
}

enum WebSearchMode: String, Codable, CaseIterable, Identifiable {
    case off
    case manualOnly
    case askBeforeSearch
    case automatic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off:
            return "Off"
        case .manualOnly:
            return "Manual only"
        case .askBeforeSearch:
            return "Ask before searching"
        case .automatic:
            return "Automatic"
        }
    }

    var details: String {
        switch self {
        case .off:
            return "Astra will never use web search."
        case .manualOnly:
            return "Astra will search only when you use /search."
        case .askBeforeSearch:
            return "Astra will ask before using web search."
        case .automatic:
            return "Astra may search automatically, but only for clearly current or online information."
        }
    }
}

enum LocalQwenTTSMode: String, Codable, CaseIterable, Identifiable, Hashable {
    case voiceCloning
    case customVoice
    case voiceDesign

    var id: String { rawValue }

    var title: String {
        switch self {
        case .voiceCloning:
            return "Voice Cloning"
        case .customVoice:
            return "Custom Voice"
        case .voiceDesign:
            return "Voice Design"
        }
    }

    var cliValue: String {
        switch self {
        case .voiceCloning:
            return "clone"
        case .customVoice:
            return "custom"
        case .voiceDesign:
            return "design"
        }
    }
}

enum ListeningMode: String, Codable, CaseIterable, Identifiable {
    case manual
    case pushToTalk
    case holdToTalk
    case continuous
    case wakePhrase

    var id: String { rawValue }
}

struct AssistantLanguage: Identifiable, Hashable {
    let id: String
    let title: String

    static let all: [AssistantLanguage] = [
        AssistantLanguage(id: "en-US", title: "English — United States"),
        AssistantLanguage(id: "en-GB", title: "English — United Kingdom"),
        AssistantLanguage(id: "ru-RU", title: "Russian — Russia"),
        AssistantLanguage(id: "es-ES", title: "Spanish — Spain"),
        AssistantLanguage(id: "de-DE", title: "German — Germany"),
        AssistantLanguage(id: "fr-FR", title: "French — France"),
        AssistantLanguage(id: "it-IT", title: "Italian — Italy"),
        AssistantLanguage(id: "pt-BR", title: "Portuguese — Brazil")
    ]
}

struct AssistantSettings: Codable {
    
 
    var assistantDisplayName: String = "Astra Assistant"
    var assistantAvatarPath: String = ""   // local copied path
    var userAvatarPath: String = ""        // local copied path
    
    var appLanguage: String = "en"
    var assistantLanguage: String = "ru-RU"

    var selectedChatModel: String = ""
    var selectedEmbeddingModel: String = "nomic-embed-text"
    var selectedVisionModel: String = ""

    var systemPrompt: String = """
    You are Astra Assistant, a private local-first AI assistant for macOS.

    Conversation style:
    - Be natural, warm, concise, and useful.
    - Respect the user's language.
    - Prefer practical, step-by-step help when solving problems.
    - If the request is ambiguous, ask one short clarifying question.
    - Do not overuse tools.
    - If you can answer from general knowledge, answer directly.

    Web search:
    - Do not use web search unless current, recent, external, or online information is explicitly needed.
    - If the user asks for general knowledge, programming help, explanations, writing, planning, or reasoning, answer locally.
    - Use web search only for things like news, current prices, current versions, recent events, weather, live facts, or when the user explicitly asks to search online.

    Memory:
    - Use long-term memory only when it is directly relevant.
    - Do not force memory into unrelated answers.
    - Treat memory as helpful context, not as absolute truth if it may be outdated.
    """

    var personalPrompt: String = ""

    var memoryMode: MemoryMode = .askBeforeSaving
    
    var webSearchMode: WebSearchMode? = .askBeforeSearch

    var temperature: Double = 0.7
    var contextSize: Int = 4096

    var ttsProvider: TTSProvider = .macOS

    // macOS TTS
    var macOSVoiceIdentifier: String = ""

    // Qwen3 TTS external wrapper
    var waveSpeedReferenceAudioURL: String = ""
    var waveSpeedReferenceText: String = ""
    var waveSpeedLanguage: String = "Russian"
    var waveSpeedMaxWaitSeconds: Int = 120
    var waveSpeedImageMaxWaitSeconds: Int = 240
    
    // Local Qwen3 TTS on Mac
    var localQwenProjectPath: String = ""
    var localQwenPythonPath: String = ""

    var localQwenMode: LocalQwenTTSMode = .voiceCloning

    var localQwenModelFolder: String = "Qwen3-TTS-12Hz-1.7B-Base-8bit"

    // Voice Cloning
    var localQwenReferenceAudioPath: String = ""
    var localQwenReferenceText: String = ""

    // Custom Voice / Voice Design
    var localQwenSpeaker: String = "Vivian"
    var localQwenInstruct: String = "Normal tone"

    var localQwenSpeed: Double = 1.0
    var localQwenMaxWaitSeconds: Int = 240
    
    

    var listeningMode: ListeningMode = .manual
    var wakePhrases: [String] = ["astra", "hey astra", "астра", "очнись"]

    var requireConfirmationForTools: Bool = true
    
    
    var imageProvider: ImageProvider = .openAI

    // OpenAI
    var enableOpenAIImages: Bool = false
    var openAIImageModel: String = "gpt-image-2"

    // WaveSpeed Seedream
    var waveSpeedGenerateModel: WaveSpeedGenerateModel = .seedreamV50Pro
    var waveSpeedEditModel: WaveSpeedEditModel = .seedreamV50ProEdit

    // V5 params
    var waveSpeedAspectRatio: String = "1:1"
    var waveSpeedResolution: String = "1k"      // 1k, 1.5k, 2k
    var waveSpeedOutputFormat: String = "jpeg"  // jpeg, png

    // V4.5 generate param
    var waveSpeedV45Size: String = "2048*2048"  // e.g. 1024*1024, 2048*2048, etc.
    
}
