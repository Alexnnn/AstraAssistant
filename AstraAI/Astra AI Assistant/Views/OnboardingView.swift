//
//  OnboardingView.swift
//  AstraAssistant
//
//  Created by Alex on 11/8/26.
//

import SwiftUI
import AppKit

struct OnboardingView: View {
    let onOpenSettings: () -> Void
    let onOpenModels: () -> Void
    let onOpenHelp: () -> Void
    let onFinish: () -> Void

    @State private var stepIndex = 0

    private var steps: [OnboardingStep] {
        [
            OnboardingStep(
                title: "Welcome to Astra Assistant",
                subtitle: "Private-by-default assistant for macOS",
                imageName: "onboarding_intro",
                description: """
                Astra is designed as a local-first assistant: conversations, memory, and task workflows remain on your Mac unless you explicitly enable cloud tools.
                
                You get one place for chat, voice, long-term memory, tasks, file summarization, screen analysis, and image tools.
                """,
                bullets: [
                    "Local chat with Ollama models",
                    "Built-in memory + tasks + calendar helpers",
                    "Voice input/output with multiple modes",
                    "Optional cloud image and TTS features"
                ],
                primaryActionTitle: "Open Help Center",
                primaryAction: onOpenHelp
            ),
            OnboardingStep(
                title: "Set up Models",
                subtitle: "Chat, embedding, and vision roles",
                imageName: "onboarding_models",
                description: """
                Astra needs model roles to work correctly:
                - Chat model: main assistant responses
                - Embedding model: memory retrieval
                - Vision model: image/screenshot analysis
                
                Install models with Ollama, then assign them in Models section.
                """,
                bullets: [
                    "Recommended chat: qwen2.5:14b",
                    "Recommended embedding: nomic-embed-text",
                    "Recommended vision: llama3.2-vision",
                    "You can switch models anytime"
                ],
                primaryActionTitle: "Open Models",
                primaryAction: onOpenModels
            ),
            OnboardingStep(
                title: "Voice & Permissions",
                subtitle: "Hands-free workflows",
                imageName: "onboarding_voice",
                description: """
                To use voice, macOS permissions are required:
                - Microphone
                - Speech Recognition
                
                Continuous and Wake Phrase modes are powerful, but best used with TTS pause protection enabled (already built in your app).
                """,
                bullets: [
                    "Manual / Push-to-talk / Hold-to-talk",
                    "Continuous and Wake Phrase modes",
                    "macOS TTS or WaveSpeed clone voice",
                    "Diagnostics can quickly verify permissions"
                ],
                primaryActionTitle: "Open Settings",
                primaryAction: onOpenSettings
            ),
            OnboardingStep(
                title: "Images & Public URLs",
                subtitle: "OpenAI + Seedream pipelines",
                imageName: "onboarding_images",
                description: """
                Astra supports image generation/editing with:
                - OpenAI
                - WaveSpeed Seedream
                
                For Seedream Edit and voice sample URLs, Astra can auto-upload local files to Firebase Storage to produce public links.
                """,
                bullets: [
                    "Choose provider in Settings → Images",
                    "Tune aspect ratio / resolution / format",
                    "Seedream timeout can be increased in Settings"
                    
                ],
                primaryActionTitle: "Open Settings",
                primaryAction: onOpenSettings
            ),
            OnboardingStep(
                title: "Commands & Daily Flow",
                subtitle: "Use Astra efficiently",
                imageName: "onboarding_commands",
                description: """
                Astra supports direct slash commands and natural phrasing.
                You can also use quick actions in Chat UI.
                
                Start simple: ask, search, create tasks, check calendar, and generate daily briefing.
                """,
                bullets: [
                    "/help, /search <query>, /task <title>, /tasks",
                    "/calendar today, /calendar add ...",
                    "Daily Briefing from tasks + memory",
                    "Use Diagnostics whenever something feels off"
                ],
                primaryActionTitle: "Open Help Center",
                primaryAction: onOpenHelp
            )
        ]
    }

    var body: some View {
        ZStack {
            AstraUITheme.mainBackground

            VStack(spacing: 14) {
                headerCard
                contentCard
                controlsCard
            }
            .padding(14)
            .frame(maxWidth: 1040)
            .animation(.spring(response: 0.38, dampingFraction: 0.9), value: stepIndex)
        }
    }

    // MARK: Header

    private var headerCard: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [AstraUITheme.accent, AstraUITheme.accent2],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 42, height: 42)

                Image(systemName: "sparkles")
                    .foregroundStyle(.white)
                    .font(.system(size: 16, weight: .bold))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Getting Started")
                    .font(.title2.bold())
                    .foregroundStyle(.white)

                Text("Step \(stepIndex + 1) of \(steps.count)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.72))
            }

            Spacer()

            HStack(spacing: 6) {
                ForEach(0..<steps.count, id: \.self) { idx in
                    Capsule()
                        .fill(idx == stepIndex ? AstraUITheme.accent2 : Color.white.opacity(0.22))
                        .frame(width: idx == stepIndex ? 24 : 10, height: 7)
                        .animation(.easeInOut(duration: 0.2), value: stepIndex)
                }
            }
        }
        .padding(14)
        .premiumCard()
    }

    // MARK: Content

    private var contentCard: some View {
        let step = steps[stepIndex]

        return HStack(spacing: 16) {
            // Illustration panel
            VStack {
                OnboardingIllustrationView(imageName: step.imageName)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: 420, height: 480)
            .background(Color.white.opacity(0.04))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))

            // Text panel
            VStack(alignment: .leading, spacing: 12) {
                Text(step.title)
                    .font(.title.bold())
                    .foregroundStyle(.white)

                Text(step.subtitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AstraUITheme.accent2)

                Text(step.description)
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(step.bullets, id: \.self) { point in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(AstraUITheme.accent2)
                                .font(.caption.weight(.bold))
                                .padding(.top, 2)

                            Text(point)
                                .foregroundStyle(.white.opacity(0.84))
                        }
                    }
                }
                .padding(10)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                Spacer()

                HStack {
                    Button {
                        step.primaryAction()
                    } label: {
                        Label(step.primaryActionTitle, systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(AstraGhostButtonStyle())

                    Spacer()

                    Button {
                        onFinish()
                    } label: {
                        Text("Skip")
                    }
                    .buttonStyle(AstraGhostButtonStyle())
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(14)
        .frame(minHeight: 520)
        .premiumCard()
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .move(edge: .trailing)),
            removal: .opacity.combined(with: .move(edge: .leading))
        ))
    }

    // MARK: Controls

    private var controlsCard: some View {
        HStack {
            Button {
                if stepIndex > 0 {
                    stepIndex -= 1
                }
            } label: {
                Label("Back", systemImage: "chevron.left")
            }
            .buttonStyle(AstraGhostButtonStyle())
            .disabled(stepIndex == 0)

            Spacer()

            if stepIndex < steps.count - 1 {
                Button {
                    stepIndex += 1
                } label: {
                    Label("Next", systemImage: "chevron.right")
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button {
                    onFinish()
                } label: {
                    Label("Get Started", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
        .premiumCard()
    }
}

// MARK: - Illustration View

private struct OnboardingIllustrationView: View {
    let imageName: String

    var body: some View {
        if let nsImage = NSImage(named: imageName) {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFit()
                .padding(14)
                .transition(.opacity)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "photo")
                    .font(.system(size: 46, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))

                Text("Missing asset: \(imageName)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Data Model

private struct OnboardingStep {
    let title: String
    let subtitle: String
    let imageName: String
    let description: String
    let bullets: [String]
    let primaryActionTitle: String
    let primaryAction: () -> Void
}

