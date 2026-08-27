//
//  RootView.swift
//  AstraAssistant
//
//  Created by Alex on 10/8/26.
//

import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appViewModel: AppViewModel
    @Environment(\.openWindow) private var openWindow

    @AppStorage("astra.onboarding.completed") private var onboardingCompleted = false
    @State private var showIntro = true

    @State private var startupDeadlinePassed = false
    @State private var startupWatchdogScheduled = false

    var body: some View {
        Group {
            if showIntro {
                IntroSplashView {
                    showIntro = false
                }
                .frame(minWidth: 900, minHeight: 650)

            } else if !onboardingCompleted {
                OnboardingView(
                    onOpenSettings: { openAstraSettingsWindow() },
                    onOpenModels: { astraNavigateTo(.models) },
                    onOpenHelp: { openWindow(id: "help-center") },
                    onFinish: { onboardingCompleted = true }
                )
                .frame(minWidth: 980, minHeight: 700)

            } else if appViewModel.isStartupLoading && !startupDeadlinePassed {
                ProgressView("Initializing...")
                    .frame(minWidth: 900, minHeight: 650)
                    .onAppear {
                        scheduleStartupWatchdogIfNeeded()
                    }

            } else {
                MainShellView()
                    .frame(minWidth: 1100, minHeight: 750)
            }
        }
    }

    private func scheduleStartupWatchdogIfNeeded() {
        guard !startupWatchdogScheduled else { return }
        startupWatchdogScheduled = true

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 12_000_000_000)

            if appViewModel.isStartupLoading {
                startupDeadlinePassed = true
                appViewModel.forceFinishLoadingIfNeeded()
            }
        }
    }
}
