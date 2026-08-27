//
//  SettingsView.swift
//  AstraAssistant
//
//  Created by Alex on 10/8/26.
//


import SwiftUI
import AVFoundation
import AppKit

struct SettingsView: View {
    @EnvironmentObject private var appViewModel: AppViewModel
    @AppStorage("astra.onboarding.completed") private var onboardingCompleted = false
    
    @State private var showOnboardingResetAlert = false


    @State private var uploadStatus: String?
    @State private var uploadError: String?
    
    private let localQwenBuiltInSpeakers = [
        "Ryan",
        "Aiden",
        "Ethan",
        "Chelsie",
        "Serena",
        "Vivian",
        "Uncle_Fu",
        "Dylan",
        "Eric",
        "Ono_Anna",
        "Sohee"
    ]

    var body: some View {
        ZStack {
            AstraUITheme.mainBackground

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    headerCard
                    profileCard
                    onboardingCard
                    CompanionPairingCardView(companion: FirebaseCompanionService.shared)
                    aiModelsCard
                    memoryCard
                    webSearchCard
                    voiceCard
                    imagesCard
                    promptsCard
                    diagnosticsCard
                }
                .padding(14)
                .frame(maxWidth: 980, alignment: .leading)
            }
        }
    }

    // MARK: Header

    private var headerCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Settings")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)

                Text("Configure models, memory, voice, tools, and image providers.")
                    .foregroundStyle(.white.opacity(0.72))
            }

            Spacer()

            Button {
                Task {
                    await appViewModel.refreshModels()
                    await appViewModel.refreshDiagnostics()
                }
            } label: {
                labelButton("Refresh", "arrow.clockwise")
            }

            Button {
                if let url = URL(string: "https://ollama.com") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                labelButton("Open Ollama", "safari")
            }
        }
        .padding(14)
        .cardStyle()
    }

    // MARK: Profile
    
    private var onboardingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Onboarding", "sparkles")

            Text("Reopen first-run onboarding anytime.")
                .foregroundStyle(.white.opacity(0.75))

            Button {
                showOnboardingResetAlert = true
            } label: {
                labelButton("Replay Onboarding", "arrow.counterclockwise")
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .cardStyle()
        .alert("Replay onboarding?", isPresented: $showOnboardingResetAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Replay") {
                onboardingCompleted = false
                astraNavigateTo(.chat)
            }
        } message: {
            Text("Main window will switch to onboarding flow.")
        }
    }

    private var profileCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Assistant Profile", "person.crop.circle")

            TextField("Assistant display name", text: Binding(
                get: { appViewModel.settingsStore.settings.assistantDisplayName },
                set: { value in
                    appViewModel.settingsStore.update { $0.assistantDisplayName = value }
                }
            ))
            .textFieldStyle(.roundedBorder)

            HStack {
                Button("Choose Assistant Avatar") {
                    chooseAvatar { path in
                        appViewModel.settingsStore.update { $0.assistantAvatarPath = path }
                    }
                }

                Button("Reset Assistant Avatar") {
                    appViewModel.settingsStore.update { $0.assistantAvatarPath = "" }
                }

                Spacer()

                Button("Choose User Avatar") {
                    chooseAvatar { path in
                        appViewModel.settingsStore.update { $0.userAvatarPath = path }
                    }
                }

                Button("Reset User Avatar") {
                    appViewModel.settingsStore.update { $0.userAvatarPath = "" }
                }
            }
        }
        .padding(14)
        .cardStyle()
    }

    // MARK: AI models

    private var aiModelsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("AI Models", "cpu.fill")

            Picker("Chat model", selection: Binding(
                get: { appViewModel.settingsStore.settings.selectedChatModel },
                set: { appViewModel.selectChatModel($0) }
            )) {
                Text("Not selected").tag("")
                ForEach(appViewModel.installedModels) { model in
                    Text(model.name).tag(model.name)
                }
            }

            Picker("Vision model", selection: Binding(
                get: { appViewModel.settingsStore.settings.selectedVisionModel },
                set: { appViewModel.selectVisionModel($0) }
            )) {
                Text("Not selected").tag("")
                ForEach(appViewModel.installedModels) { model in
                    Text(model.name).tag(model.name)
                }
            }

            Picker("Embedding model", selection: Binding(
                get: { appViewModel.settingsStore.settings.selectedEmbeddingModel },
                set: { appViewModel.selectEmbeddingModel($0) }
            )) {
                Text("nomic-embed-text").tag("nomic-embed-text")
                ForEach(appViewModel.installedModels) { model in
                    Text(model.name).tag(model.name)
                }
            }

            Slider(
                value: Binding(
                    get: { appViewModel.settingsStore.settings.temperature },
                    set: { value in
                        appViewModel.settingsStore.update { $0.temperature = value }
                    }
                ),
                in: 0...1
            ) {
                Text("Temperature")
            }

            Stepper(
                "Context size: \(appViewModel.settingsStore.settings.contextSize) tokens",
                value: Binding(
                    get: { appViewModel.settingsStore.settings.contextSize },
                    set: { value in
                        appViewModel.settingsStore.update {
                            $0.contextSize = min(max(value, 1024), 262_144)
                        }
                    }
                ),
                in: 1024...262_144,
                step: 4096
            )

            Text("Higher context improves long conversations but increases RAM usage and response time.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(14)
        .cardStyle()
    }

    // MARK: Memory

    private var memoryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Memory", "brain.head.profile")

            Picker("Memory mode", selection: Binding(
                get: { appViewModel.settingsStore.settings.memoryMode },
                set: { value in
                    appViewModel.settingsStore.update { $0.memoryMode = value }
                }
            )) {
                ForEach(MemoryMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
        }
        .padding(14)
        .cardStyle()
    }
    
    private var webSearchCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Web Search", "globe")

            Picker("Web search mode", selection: Binding(
                get: {
                    appViewModel.settingsStore.settings.webSearchMode ?? .askBeforeSearch
                },
                set: { mode in
                    appViewModel.settingsStore.update {
                        $0.webSearchMode = mode
                    }
                }
            )) {
                ForEach(WebSearchMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }

            let mode = appViewModel.settingsStore.settings.webSearchMode ?? .askBeforeSearch

            Text(mode.details)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.75))

            VStack(alignment: .leading, spacing: 6) {
                Text("Recommendation")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                Text("""
                For best conversation quality use “Ask before searching”.
                Astra will answer locally by default and ask before using the internet for current/live information.
                """)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.75))
            }
            .padding(10)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(14)
        .cardStyle()
    }

    // MARK: Voice

    private var voiceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Voice", "waveform.circle.fill")

            Picker("Assistant language", selection: Binding(
                get: { appViewModel.settingsStore.settings.assistantLanguage },
                set: { value in
                    appViewModel.settingsStore.update { $0.assistantLanguage = value }
                }
            )) {
                ForEach(AssistantLanguage.all) { lang in
                    Text(lang.title).tag(lang.id)
                }
            }

            Picker("Listening mode", selection: Binding(
                get: { appViewModel.settingsStore.settings.listeningMode },
                set: { value in
                    appViewModel.settingsStore.update { $0.listeningMode = value }
                }
            )) {
                ForEach(ListeningMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }

            TextField("Wake phrases (comma separated)", text: Binding(
                get: { appViewModel.settingsStore.settings.wakePhrases.joined(separator: ", ") },
                set: { value in
                    let arr = value
                        .split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }

                    appViewModel.settingsStore.update {
                        $0.wakePhrases = arr.isEmpty ? ["astra"] : arr
                    }
                }
            ))
            .textFieldStyle(.roundedBorder)

            Divider().padding(.vertical, 4)

            Picker("TTS provider", selection: Binding(
                get: { appViewModel.settingsStore.settings.ttsProvider },
                set: { value in
                    appViewModel.settingsStore.update { $0.ttsProvider = value }
                }
            )) {
                ForEach(TTSProvider.allCases) { provider in
                    Text(provider.title).tag(provider)
                }
            }

            Picker("macOS voice", selection: Binding(
                get: { appViewModel.settingsStore.settings.macOSVoiceIdentifier },
                set: { value in
                    appViewModel.settingsStore.update { $0.macOSVoiceIdentifier = value }
                }
            )) {
                Text("Automatic").tag("")
                ForEach(AVSpeechSynthesisVoice.speechVoices(), id: \.identifier) { voice in
                    Text("\(voice.name) — \(voice.language)").tag(voice.identifier)
                }
            }

            if appViewModel.settingsStore.settings.ttsProvider == .waveSpeedQwen3 {
                Divider().padding(.vertical, 4)

                Text("WaveSpeed Voice Clone")
                    .font(.headline)

                SecureField("WaveSpeed API key", text: Binding(
                    get: { KeychainStore.shared.getWaveSpeedKey() ?? "" },
                    set: { value in
                        if value.isEmpty {
                            KeychainStore.shared.deleteWaveSpeedKey()
                        } else {
                            try? KeychainStore.shared.saveWaveSpeedKey(value)
                        }
                    }
                ))

                TextField("Reference audio URL", text: Binding(
                    get: { appViewModel.settingsStore.settings.waveSpeedReferenceAudioURL },
                    set: { value in
                        appViewModel.settingsStore.update { $0.waveSpeedReferenceAudioURL = value }
                    }
                ))
                .textFieldStyle(.roundedBorder)

                HStack {
                    Button("Upload voice sample to Firebase") {
                        uploadVoiceSampleToFirebase()
                    }

                    if let uploadStatus {
                        Text(uploadStatus)
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }

                if let uploadError {
                    Text(uploadError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                TextEditor(text: Binding(
                    get: { appViewModel.settingsStore.settings.waveSpeedReferenceText },
                    set: { value in
                        appViewModel.settingsStore.update { $0.waveSpeedReferenceText = value }
                    }
                ))
                .frame(height: 80)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.2)))

                Picker("WaveSpeed language", selection: Binding(
                    get: { appViewModel.settingsStore.settings.waveSpeedLanguage },
                    set: { value in
                        appViewModel.settingsStore.update { $0.waveSpeedLanguage = value }
                    }
                )) {
                    ForEach(["auto","Russian","English","German","Italian","Portuguese","Spanish","Japanese","Korean","French","Chinese"], id: \.self) {
                        Text($0).tag($0)
                    }
                }

                Stepper(
                    "TTS max wait: \(appViewModel.settingsStore.settings.waveSpeedMaxWaitSeconds)s",
                    value: Binding(
                        get: { appViewModel.settingsStore.settings.waveSpeedMaxWaitSeconds },
                        set: { value in
                            appViewModel.settingsStore.update { $0.waveSpeedMaxWaitSeconds = value }
                        }
                    ),
                    in: 20...300,
                    step: 5
                )
            }
            
            if appViewModel.settingsStore.settings.ttsProvider == .localQwen3 {
                Divider().padding(.vertical, 4)

                Text("Local Qwen3 TTS on Mac")
                    .font(.headline)

                Text("""
                Runs local Python script from your Qwen3 TTS project.
                Supports Voice Cloning, Custom Voice and Voice Design.
                """)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))

                TextField("Qwen project folder", text: Binding(
                    get: { appViewModel.settingsStore.settings.localQwenProjectPath },
                    set: { value in
                        appViewModel.settingsStore.update {
                            $0.localQwenProjectPath = value
                        }
                    }
                ))
                .textFieldStyle(.roundedBorder)

                HStack {
                    Button("Choose Qwen Project Folder") {
                        chooseLocalQwenProjectFolder()
                    }

                    Button("Open Folder") {
                        let path = appViewModel.settingsStore.settings.localQwenProjectPath
                            .trimmingCharacters(in: .whitespacesAndNewlines)

                        if !path.isEmpty {
                            NSWorkspace.shared.open(URL(fileURLWithPath: path, isDirectory: true))
                        }
                    }
                }

                TextField("Python path optional, default: .venv/bin/python", text: Binding(
                    get: { appViewModel.settingsStore.settings.localQwenPythonPath },
                    set: { value in
                        appViewModel.settingsStore.update {
                            $0.localQwenPythonPath = value
                        }
                    }
                ))
                .textFieldStyle(.roundedBorder)

                Picker("Local Qwen mode", selection: Binding(
                    get: { appViewModel.settingsStore.settings.localQwenMode },
                    set: { value in
                        appViewModel.settingsStore.update {
                            $0.localQwenMode = value

                            switch value {
                            case .voiceCloning:
                                if !$0.localQwenModelFolder.contains("Base") {
                                    $0.localQwenModelFolder = "Qwen3-TTS-12Hz-1.7B-Base-8bit"
                                }

                            case .customVoice:
                                if !$0.localQwenModelFolder.contains("CustomVoice") {
                                    $0.localQwenModelFolder = "Qwen3-TTS-12Hz-1.7B-CustomVoice-8bit"
                                }

                            case .voiceDesign:
                                if !$0.localQwenModelFolder.contains("VoiceDesign") {
                                    $0.localQwenModelFolder = "Qwen3-TTS-12Hz-1.7B-VoiceDesign-8bit"
                                }
                            }
                        }
                    }
                )) {
                    ForEach(LocalQwenTTSMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }

                Picker("Local Qwen model", selection: Binding(
                    get: { appViewModel.settingsStore.settings.localQwenModelFolder },
                    set: { value in
                        appViewModel.settingsStore.update {
                            $0.localQwenModelFolder = value
                        }
                    }
                )) {
                    if appViewModel.settingsStore.settings.localQwenMode == .voiceCloning {
                        Text("1.7B Base Voice Cloning").tag("Qwen3-TTS-12Hz-1.7B-Base-8bit")
                        Text("0.6B Base Voice Cloning").tag("Qwen3-TTS-12Hz-0.6B-Base-8bit")
                    }

                    if appViewModel.settingsStore.settings.localQwenMode == .customVoice {
                        Text("1.7B Custom Voice").tag("Qwen3-TTS-12Hz-1.7B-CustomVoice-8bit")
                        Text("0.6B Custom Voice").tag("Qwen3-TTS-12Hz-0.6B-CustomVoice-8bit")
                    }

                    if appViewModel.settingsStore.settings.localQwenMode == .voiceDesign {
                        Text("1.7B Voice Design").tag("Qwen3-TTS-12Hz-1.7B-VoiceDesign-8bit")
                        Text("0.6B Voice Design").tag("Qwen3-TTS-12Hz-0.6B-VoiceDesign-8bit")
                    }
                }

                if appViewModel.settingsStore.settings.localQwenMode == .voiceCloning {
                    Divider().padding(.vertical, 4)

                    Text("Voice Cloning")
                        .font(.headline)

                    TextField("Reference audio local path", text: Binding(
                        get: { appViewModel.settingsStore.settings.localQwenReferenceAudioPath },
                        set: { value in
                            appViewModel.settingsStore.update {
                                $0.localQwenReferenceAudioPath = value
                            }
                        }
                    ))
                    .textFieldStyle(.roundedBorder)

                    HStack {
                        Button("Choose Reference Audio") {
                            chooseLocalQwenReferenceAudio()
                        }

                        Button("Use saved voice from Qwen voices/ folder") {
                            chooseLocalQwenSavedVoice()
                        }
                    }

                    Text("Reference transcript")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)

                    TextEditor(text: Binding(
                        get: { appViewModel.settingsStore.settings.localQwenReferenceText },
                        set: { value in
                            appViewModel.settingsStore.update {
                                $0.localQwenReferenceText = value
                            }
                        }
                    ))
                    .frame(height: 80)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.2)))
                }

                if appViewModel.settingsStore.settings.localQwenMode == .customVoice {
                    Divider().padding(.vertical, 4)

                    Text("Custom Voice")
                        .font(.headline)

                    Picker("Built-in speaker", selection: Binding(
                        get: { appViewModel.settingsStore.settings.localQwenSpeaker },
                        set: { value in
                            appViewModel.settingsStore.update {
                                $0.localQwenSpeaker = value
                            }
                        }
                    )) {
                        ForEach(localQwenBuiltInSpeakers, id: \.self) { speaker in
                            Text(speaker).tag(speaker)
                        }
                    }

                    Text("Emotion / speaking instruction")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)

                    TextEditor(text: Binding(
                        get: { appViewModel.settingsStore.settings.localQwenInstruct },
                        set: { value in
                            appViewModel.settingsStore.update {
                                $0.localQwenInstruct = value
                            }
                        }
                    ))
                    .frame(height: 80)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.2)))

                    HStack {
                        Button("Normal") {
                            appViewModel.settingsStore.update {
                                $0.localQwenInstruct = "Normal tone"
                            }
                        }

                        Button("Happy Fast") {
                            appViewModel.settingsStore.update {
                                $0.localQwenInstruct = "Excited and happy, speaking very fast"
                            }
                        }

                        Button("Sad Slow") {
                            appViewModel.settingsStore.update {
                                $0.localQwenInstruct = "Sad and crying, speaking slowly"
                            }
                        }

                        Button("Whisper") {
                            appViewModel.settingsStore.update {
                                $0.localQwenInstruct = "Whispering quietly"
                            }
                        }
                    }
                }

                if appViewModel.settingsStore.settings.localQwenMode == .voiceDesign {
                    Divider().padding(.vertical, 4)

                    Text("Voice Design")
                        .font(.headline)

                    Text("Describe the voice")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)

                    TextEditor(text: Binding(
                        get: { appViewModel.settingsStore.settings.localQwenInstruct },
                        set: { value in
                            appViewModel.settingsStore.update {
                                $0.localQwenInstruct = value
                            }
                        }
                    ))
                    .frame(height: 100)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.2)))

                    HStack {
                        Button("Soft female voice") {
                            appViewModel.settingsStore.update {
                                $0.localQwenInstruct = "A soft, warm, friendly female voice"
                            }
                        }

                        Button("Deep male voice") {
                            appViewModel.settingsStore.update {
                                $0.localQwenInstruct = "A deep, calm, confident male voice"
                            }
                        }
                    }
                    
                    
                    HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Circle()
                                        .fill(appViewModel.isTTSServerReady ? Color.green : Color.red)
                                        .frame(width: 10, height: 10)
                                    
                                    Text(appViewModel.isTTSServerReady ? "Server running" : "Server stopped")
                                        .font(.caption)
                                        .foregroundStyle(appViewModel.isTTSServerReady ? .green : .red)
                                }
                                
                                if let error = appViewModel.ttsServerError {
                                    Text(error)
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                            }
                            
                            Spacer()
                            
                            Button {
                                Task {
                                    if appViewModel.isTTSServerReady {
                                        appViewModel.stopTTSServer()
                                    } else {
                                        await appViewModel.startTTSServerIfNeeded()
                                    }
                                }
                            } label: {
                                Label(
                                    appViewModel.isTTSServerReady ? "Stop Server" : "Start Server",
                                    systemImage: appViewModel.isTTSServerReady ? "stop.circle" : "play.circle"
                                )
                            }
                            .buttonStyle(.bordered)
                            
                            Button {
                                Task {
                                    await appViewModel.restartTTSServer()
                                }
                            } label: {
                                Label("Restart", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    
                    
                    
                    
                
                
                Slider(
                    value: Binding(
                        get: { appViewModel.settingsStore.settings.localQwenSpeed },
                        set: { value in
                            appViewModel.settingsStore.update {
                                $0.localQwenSpeed = value
                            }
                        }
                    ),
                    in: 0.6...1.5
                ) {
                    Text("Speed")
                }

                Text("Speed: \(String(format: "%.2f", appViewModel.settingsStore.settings.localQwenSpeed))x")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))

                Stepper(
                    "Local Qwen max wait: \(appViewModel.settingsStore.settings.localQwenMaxWaitSeconds)s",
                    value: Binding(
                        get: { appViewModel.settingsStore.settings.localQwenMaxWaitSeconds },
                        set: { value in
                            appViewModel.settingsStore.update {
                                $0.localQwenMaxWaitSeconds = value
                            }
                        }
                    ),
                    in: 30...900,
                    step: 10
                )
            }
        }
        .padding(14)
        .cardStyle()
    }

    // MARK: Images (OpenAI + Seedream)

    private var imagesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Images", "photo.on.rectangle.angled")

            Picker("Image provider", selection: Binding(
                get: { appViewModel.settingsStore.settings.imageProvider },
                set: { value in
                    appViewModel.settingsStore.update { $0.imageProvider = value }
                }
            )) {
                ForEach(ImageProvider.allCases) { p in
                    Text(p.title).tag(p)
                }
            }

            if appViewModel.settingsStore.settings.imageProvider == .openAI {
                Toggle("Enable OpenAI image generation/editing", isOn: Binding(
                    get: { appViewModel.settingsStore.settings.enableOpenAIImages },
                    set: { value in
                        appViewModel.settingsStore.update { $0.enableOpenAIImages = value }
                    }
                ))

                TextField("OpenAI image model", text: Binding(
                    get: { appViewModel.settingsStore.settings.openAIImageModel },
                    set: { value in
                        appViewModel.settingsStore.update { $0.openAIImageModel = value }
                    }
                ))
                .textFieldStyle(.roundedBorder)

                SecureField("OpenAI API key", text: Binding(
                    get: { KeychainStore.shared.getOpenAIKey() ?? "" },
                    set: { value in
                        if value.isEmpty {
                            KeychainStore.shared.deleteOpenAIKey()
                        } else {
                            try? KeychainStore.shared.saveOpenAIKey(value)
                        }
                    }
                ))
            } else {
                Text("WaveSpeed Seedream")
                    .font(.headline)

                SecureField("WaveSpeed API key", text: Binding(
                    get: { KeychainStore.shared.getWaveSpeedKey() ?? "" },
                    set: { value in
                        if value.isEmpty {
                            KeychainStore.shared.deleteWaveSpeedKey()
                        } else {
                            try? KeychainStore.shared.saveWaveSpeedKey(value)
                        }
                    }
                ))

                Picker("Generate model", selection: Binding(
                    get: { appViewModel.settingsStore.settings.waveSpeedGenerateModel },
                    set: { value in
                        appViewModel.settingsStore.update { $0.waveSpeedGenerateModel = value }
                    }
                )) {
                    ForEach(WaveSpeedGenerateModel.allCases) { m in
                        Text(m.title).tag(m)
                    }
                }

                Picker("Edit model", selection: Binding(
                    get: { appViewModel.settingsStore.settings.waveSpeedEditModel },
                    set: { value in
                        appViewModel.settingsStore.update { $0.waveSpeedEditModel = value }
                    }
                )) {
                    ForEach(WaveSpeedEditModel.allCases) { m in
                        Text(m.title).tag(m)
                    }
                }

                if appViewModel.settingsStore.settings.waveSpeedGenerateModel == .seedreamV45 {
                    TextField("Seedream 4.5 size (e.g. 2048*2048)", text: Binding(
                        get: { appViewModel.settingsStore.settings.waveSpeedV45Size },
                        set: { value in
                            appViewModel.settingsStore.update { $0.waveSpeedV45Size = value }
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                } else {
                    Picker("Aspect ratio", selection: Binding(
                        get: { appViewModel.settingsStore.settings.waveSpeedAspectRatio },
                        set: { value in
                            appViewModel.settingsStore.update { $0.waveSpeedAspectRatio = value }
                        }
                    )) {
                        ForEach(["1:1","1:2","2:1","1:3","3:1","2:3","3:2","3:4","4:3","4:5","5:4","9:16","16:9","9:21","21:9"], id: \.self) {
                            Text($0).tag($0)
                        }
                    }

                    Picker("Resolution", selection: Binding(
                        get: { appViewModel.settingsStore.settings.waveSpeedResolution },
                        set: { value in
                            appViewModel.settingsStore.update { $0.waveSpeedResolution = value }
                        }
                    )) {
                        ForEach(["1k","1.5k","2k"], id: \.self) { Text($0).tag($0) }
                    }

                    Picker("Output format", selection: Binding(
                        get: { appViewModel.settingsStore.settings.waveSpeedOutputFormat },
                        set: { value in
                            appViewModel.settingsStore.update { $0.waveSpeedOutputFormat = value }
                        }
                    )) {
                        ForEach(["jpeg","png"], id: \.self) { Text($0).tag($0) }
                    }
                }

                Stepper(
                    "Seedream max wait: \(appViewModel.settingsStore.settings.waveSpeedImageMaxWaitSeconds)s",
                    value: Binding(
                        get: { appViewModel.settingsStore.settings.waveSpeedImageMaxWaitSeconds },
                        set: { value in
                            appViewModel.settingsStore.update { $0.waveSpeedImageMaxWaitSeconds = value }
                        }
                    ),
                    in: 60...600,
                    step: 10
                )
            }
        }
        .padding(14)
        .cardStyle()
    }

    // MARK: Prompts

    private var promptsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Prompts", "text.quote")

            Text("System Prompt")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)

            TextEditor(text: Binding(
                get: { appViewModel.settingsStore.settings.systemPrompt },
                set: { value in
                    appViewModel.settingsStore.update { $0.systemPrompt = value }
                }
            ))
            .frame(height: 120)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.2)))

            Text("Personal Prompt")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)

            TextEditor(text: Binding(
                get: { appViewModel.settingsStore.settings.personalPrompt },
                set: { value in
                    appViewModel.settingsStore.update { $0.personalPrompt = value }
                }
            ))
            .frame(height: 120)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.2)))
        }
        .padding(14)
        .cardStyle()
    }

    // MARK: Diagnostics

    private var diagnosticsCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Diagnostics")
                    .font(.headline)
                    .foregroundStyle(.white)

                Text("Refresh dependencies and model status.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }

            Spacer()

            Button {
                Task {
                    await appViewModel.refreshDiagnostics()
                    await appViewModel.refreshModels()
                }
            } label: {
                labelButton("Run Diagnostics", "stethoscope")
            }
        }
        .padding(14)
        .cardStyle()
    }

    // MARK: Helpers UI
    
    private func chooseLocalQwenProjectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            appViewModel.settingsStore.update {
                $0.localQwenProjectPath = url.path
            }
        }
    }

    private func chooseLocalQwenReferenceAudio() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.audio]

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            appViewModel.settingsStore.update {
                $0.localQwenReferenceAudioPath = url.path
            }
        }
    }

    private func chooseLocalQwenSavedVoice() {
        let projectPath = appViewModel.settingsStore.settings.localQwenProjectPath
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let startURL: URL?

        if projectPath.isEmpty {
            startURL = nil
        } else {
            startURL = URL(fileURLWithPath: projectPath, isDirectory: true)
                .appendingPathComponent("voices", isDirectory: true)
        }

        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.audio]

        if let startURL {
            panel.directoryURL = startURL
        }

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            let txtURL = url.deletingPathExtension().appendingPathExtension("txt")
            let transcript = (try? String(contentsOf: txtURL, encoding: .utf8)) ?? ""

            appViewModel.settingsStore.update {
                $0.localQwenReferenceAudioPath = url.path

                if !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    $0.localQwenReferenceText = transcript
                }
            }
        }
    }

    private func sectionTitle(_ title: String, _ icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(AstraUITheme.accent2)
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
        }
    }

    private func labelButton(_ title: String, _ icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(title)
        }
        .font(.callout.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func chooseAvatar(onSaved: @escaping (String) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            do {
                let copied = try copyToAppSupport(from: url, folder: "Avatars", prefix: "avatar")
                onSaved(copied.path)
            } catch {
                print("Avatar copy error:", error.localizedDescription)
            }
        }
    }

    private func uploadVoiceSampleToFirebase() {
        uploadStatus = nil
        uploadError = nil

        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.audio]

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            Task {
                do {
                    let safe = try copyToAppSupport(from: url, folder: "VoiceSamples", prefix: "voice")
                    let publicURL = try await FirebaseStorageService.shared.uploadFile(localURL: safe, purpose: .audio)

                    await MainActor.run {
                        appViewModel.settingsStore.update {
                            $0.waveSpeedReferenceAudioURL = publicURL
                        }
                        uploadStatus = "Uploaded successfully"
                        uploadError = nil
                    }
                } catch {
                    await MainActor.run {
                        uploadError = error.localizedDescription
                        uploadStatus = nil
                    }
                }
            }
        }
    }

    private func copyToAppSupport(from originalURL: URL, folder: String, prefix: String) throws -> URL {
        let didStart = originalURL.startAccessingSecurityScopedResource()
        defer {
            if didStart { originalURL.stopAccessingSecurityScopedResource() }
        }

        let data = try Data(contentsOf: originalURL)

        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base
            .appendingPathComponent("Astra Assistant", isDirectory: true)
            .appendingPathComponent(folder, isDirectory: true)

        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let ext = originalURL.pathExtension.isEmpty ? "bin" : originalURL.pathExtension
        let dst = dir.appendingPathComponent("\(prefix)-\(UUID().uuidString).\(ext)")

        try data.write(to: dst, options: .atomic)
        return dst
    }
}

// MARK: - Card style

private extension View {
    func cardStyle() -> some View {
        self
            .background(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
