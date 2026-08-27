//
//  CompanionMainTabView.swift
//  AstraCompanion
//
//  Created by Alex on 13/8/26.
//


import SwiftUI

struct CompanionMainTabView: View {
    @EnvironmentObject var appState: CompanionAppState
    @StateObject private var macStatus = MacConnectionStatusViewModel()

    private var profileKey: String {
        guard let profile = appState.profile else {
            return "none"
        }

        return "\(profile.macUID)|\(profile.macDeviceID)"
    }

    var body: some View {
        TabView(selection: $appState.selectedTab) {
            CompanionConversationsView(
                macUID: appState.profile?.macUID ?? "",
                macDeviceID: appState.profile?.macDeviceID ?? "",
                onSelectConversation: { cid in
                    appState.openConversation(cid)
                },
                onNewChat: {
                    appState.createNewConversation()
                }
            )
            .tabItem {
                Label("Chats", systemImage: "bubble.left.and.bubble.right.fill")
            }
            .tag(AppTab.conversations)

            CompanionChatView(vm: appState.chatVM)
                .tabItem {
                    Label("Chat", systemImage: "message.fill")
                }
                .tag(AppTab.chat)

            CompanionTasksView()
                .tabItem {
                    Label("Tasks", systemImage: "checklist")
                }
                .tag(AppTab.tasks)

            CompanionActionsView()
                .tabItem {
                    Label("Actions", systemImage: "square.grid.2x2.fill")
                }
                .tag(AppTab.commands)

            CompanionSettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(AppTab.settings)
        }
        .environmentObject(macStatus)
        .task(id: profileKey) {
            macStatus.start(profile: appState.profile)
        }
        .onDisappear {
            macStatus.stop()
        }
    }
}
