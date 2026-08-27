//
//  VoiceControlView.swift
//  AstraAssistant
//
//  Created by Alex on 10/8/26.
//

import SwiftUI

struct VoiceControlView: View {
    @EnvironmentObject private var appViewModel: AppViewModel

    @ObservedObject var chatViewModel: ChatViewModel

    @StateObject private var voiceController = VoiceModeController()

    @State private var speakResponses = true
    @State private var isHolding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header

            Divider()

            statusPanel

            controlsPanel

            transcriptPanel

            Spacer()
        }
        .padding()
        .onAppear {
            configureVoice()
        }
        .onChange(of: appViewModel.settingsStore.settings.listeningMode) {
            configureVoice()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Voice")
                .font(.largeTitle.bold())

            Text("Control Astra using push-to-talk, hold-to-talk, continuous listening, or wake phrase mode.")
                .foregroundStyle(.secondary)
        }
    }

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Circle()
                    .fill(voiceController.isActive ? Color.green : Color.gray)
                    .frame(width: 12, height: 12)

                Text(voiceController.statusText)
                    .font(.headline)

                Spacer()

                Toggle("Speak responses", isOn: $speakResponses)
                    .toggleStyle(.switch)
            }

            let settings = appViewModel.settingsStore.settings

            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                GridRow {
                    Text("Mode")
                        .foregroundStyle(.secondary)

                    Text(settings.listeningMode.rawValue)
                }

                GridRow {
                    Text("Language")
                        .foregroundStyle(.secondary)

                    Text(settings.assistantLanguage)
                }

                GridRow {
                    Text("Wake phrases")
                        .foregroundStyle(.secondary)

                    Text(settings.wakePhrases.joined(separator: ", "))
                }

                GridRow {
                    Text("TTS")
                        .foregroundStyle(.secondary)

                    Text(settings.ttsProvider.rawValue)
                }
            }
            .font(.callout)
        }
        .padding()
        .background(Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var controlsPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Controls")
                .font(.headline)

            HStack {
                Button {
                    Task {
                        configureVoice()
                        await voiceController.start()
                    }
                } label: {
                    Label("Start Listening", systemImage: "mic.circle")
                }

                Button {
                    voiceController.stop()
                } label: {
                    Label("Stop Listening", systemImage: "stop.circle")
                }

                Button {
                    chatViewModel.stopSpeaking()
                } label: {
                    Label("Stop Speaking", systemImage: "speaker.slash")
                }
            }

            HStack {
                Button {
                    Task {
                        configureVoice()
                        await voiceController.pushToTalkPressed()
                    }
                } label: {
                    Label("Push To Talk Start", systemImage: "mic.fill")
                }

                Button {
                    voiceController.pushToTalkReleased()
                } label: {
                    Label("Push To Talk Send", systemImage: "paperplane")
                }
            }

            holdToTalkButton
        }
    }

    private var holdToTalkButton: some View {
        Text(isHolding ? "Release to send..." : "Hold to Talk")
            .font(.headline)
            .frame(width: 220, height: 54)
            .background(isHolding ? Color.blue.opacity(0.25) : Color.gray.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !isHolding else {
                            return
                        }

                        isHolding = true

                        Task {
                            configureVoice()
                            await voiceController.holdToTalkBegan()
                        }
                    }
                    .onEnded { _ in
                        isHolding = false
                        voiceController.holdToTalkEnded()
                    }
            )
    }

    private var transcriptPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Live Transcript")
                .font(.headline)

            Text(voiceController.transcript.isEmpty ? "Nothing recognized yet." : voiceController.transcript)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
                .padding()
                .background(Color.black.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            if let error = voiceController.inputService.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
    }

    private func configureVoice() {
        let settings = appViewModel.settingsStore.settings

        voiceController.configure(settings: settings)

        voiceController.onUserUtterance = { text in
            Task {
                await chatViewModel.send(
                    text,
                    speakResponse: speakResponses
                )
            }
        }
    }
}
