//
//  CompanionSettingsView.swift
//  AstraCompanion
//
//  Created by Alex on 13/8/26.
//

import SwiftUI

struct CompanionSettingsView: View {
    @EnvironmentObject var appState: CompanionAppState
    @EnvironmentObject private var macStatus: MacConnectionStatusViewModel
    @EnvironmentObject private var avatarStore: IOSAvatarStore

    @AppStorage("ios.tts.mode") private var ttsModeRaw: String = IOSVoiceOutputMode.local.rawValue
    @AppStorage("ios.voice.locale") private var voiceLocale: String = "ru-RU"

    @State private var activeAvatarPicker: AvatarPickerTarget?

    var body: some View {
        NavigationStack {
            Form {
                Section("Voice Output") {
                    Picker("TTS Mode", selection: $ttsModeRaw) {
                        Text("iPhone Local").tag(IOSVoiceOutputMode.local.rawValue)
                        Text("Mac TTS").tag(IOSVoiceOutputMode.mac.rawValue)
                    }
                    .pickerStyle(.segmented)

                    if ttsModeRaw == IOSVoiceOutputMode.mac.rawValue {
                        Text("Uses your Mac's configured TTS provider: macOS, WaveSpeed, or Local Qwen3.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Speech Recognition") {
                    Picker("Voice input language", selection: $voiceLocale) {
                        Text("Russian").tag("ru-RU")
                        Text("English US").tag("en-US")
                        Text("English UK").tag("en-GB")
                        Text("Spanish").tag("es-ES")
                        Text("German").tag("de-DE")
                        Text("French").tag("fr-FR")
                    }
                }

                Section("Avatars") {
                    avatarRow(
                        title: "Assistant Avatar",
                        subtitle: "Shown next to Astra's messages",
                        kind: .assistant,
                        tint: .blue
                    )

                    avatarRow(
                        title: "User Avatar",
                        subtitle: "Shown next to your messages",
                        kind: .user,
                        tint: .green
                    )
                }

                Section("Mac Connection") {
                    HStack {
                        Circle()
                            .fill(macStatus.statusColor)
                            .frame(width: 10, height: 10)

                        Text(macStatus.statusText)
                    }

                    if let lastSeen = macStatus.lastSeen {
                        Text("Last seen: \(lastSeen.formatted(date: .abbreviated, time: .standard))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let platform = macStatus.platform {
                        Text("Platform: \(platform)")
                            .font(.caption)
                    }

                    if let appVersion = macStatus.appVersion {
                        Text("Version: \(appVersion)")
                            .font(.caption)
                    }

                    if let build = macStatus.build {
                        Text("Build: \(build)")
                            .font(.caption)
                    }

                    Button {
                        Task {
                            await macStatus.ping(profile: appState.profile)
                        }
                    } label: {
                        Label("Ping Mac", systemImage: "dot.radiowaves.left.and.right")
                    }

                    if let ping = macStatus.lastPingText {
                        Text(ping)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let error = macStatus.lastError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section("Connection Details") {
                    if let p = appState.profile {
                        Text("macUID: \(p.macUID)")
                            .font(.caption2)
                            .textSelection(.enabled)

                        Text("macDeviceID: \(p.macDeviceID)")
                            .font(.caption2)
                            .textSelection(.enabled)

                        Text("conversationId: \(p.conversationId ?? "-")")
                            .font(.caption2)
                            .textSelection(.enabled)
                    } else {
                        Text("No connection profile.")
                    }
                }

                Section {
                    Button("Disconnect", role: .destructive) {
                        appState.disconnect()
                    }
                }
            }
            .navigationTitle("Settings")
            .sheet(item: $activeAvatarPicker) { target in
                AvatarPickerView(
                    title: target.title,
                    onImageSelected: { data in
                        var transaction = Transaction()
                        transaction.animation = nil

                        withTransaction(transaction) {
                            switch target.kind {
                            case .assistant:
                                avatarStore.setAssistantAvatar(data: data)
                            case .user:
                                avatarStore.setUserAvatar(data: data)
                            }

                            activeAvatarPicker = nil
                        }
                    },
                    onCancel: {
                        activeAvatarPicker = nil
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
    }

    private func avatarRow(
        title: String,
        subtitle: String,
        kind: IOSAvatarKind,
        tint: Color
    ) -> some View {
        let hasAvatar: Bool = {
            switch kind {
            case .assistant:
                return avatarStore.hasAssistantAvatar
            case .user:
                return avatarStore.hasUserAvatar
            }
        }()

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            IOSAvatarView(kind: kind, size: 44)

            Button {
                activeAvatarPicker = AvatarPickerTarget(kind: kind)
            } label: {
                Image(systemName: "photo.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.blue)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)

            Button {
                var transaction = Transaction()
                transaction.animation = nil

                withTransaction(transaction) {
                    switch kind {
                    case .assistant:
                        avatarStore.clearAssistantAvatar()
                    case .user:
                        avatarStore.clearUserAvatar()
                    }
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.red)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .opacity(hasAvatar ? 1 : 0)
            .disabled(!hasAvatar)
        }
        .padding(.vertical, 4)
    }
}

private struct AvatarPickerTarget: Identifiable {
    let id = UUID()
    let kind: IOSAvatarKind

    var title: String {
        switch kind {
        case .assistant:
            return "Assistant Avatar"
        case .user:
            return "User Avatar"
        }
    }
}
