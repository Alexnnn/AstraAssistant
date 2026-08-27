//
//  SetupWizardView.swift
//  AstraAssistant
//
//  Created by Alex on 10/8/26.
//

import SwiftUI
import AppKit

struct SetupWizardView: View {
    @EnvironmentObject private var appViewModel: AppViewModel
    @Environment(\.openWindow) private var openWindow
    

    let report: DependencyReport

    var body: some View {
        ZStack {
            AstraUITheme.mainBackground

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    headerCard
                    actionBarCard
                    fastPathCard
                    issuesCard
                }
                .padding(14)
                .frame(maxWidth: 980, alignment: .leading)
            }
        }
    }

    // MARK: Header

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .foregroundStyle(AstraUITheme.accent2)
                    .font(.title2.weight(.bold))

                Text("Astra Assistant Setup")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
            }

            Text("Complete required setup steps below. Red items are blocking startup.")
                .foregroundStyle(.white.opacity(0.75))

            HStack(spacing: 8) {
                if report.hasBlockingIssues {
                    AstraStatusChip(text: "Blocking issues found", tint: .red)
                } else {
                    AstraStatusChip(text: "Ready to continue", tint: .green)
                }

                AstraStatusChip(text: "\(report.items.count) checks", tint: AstraUITheme.accent)
            }
        }
        .padding(14)
        .premiumCard()
    }

    // MARK: Action bar

    private var actionBarCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick Actions")
                .font(.headline)
                .foregroundStyle(.white)

            HStack(spacing: 8) {
                actionButton("Run Diagnostics", "stethoscope") {
                    Task {
                        await appViewModel.refreshDiagnostics()
                        await appViewModel.refreshModels()
                    }
                }

                actionButton("Open Settings", "gearshape.fill") {
                    openWindow(id: "app-settings")
                }

                actionButton("Open Help Center", "questionmark.circle.fill") {
                    openWindow(id: "help-center")
                }

                actionButton("Open Models", "cpu.fill") {
                    astraNavigateTo(.models)
                }

                actionButton("Open Ollama", "safari") {
                    if let url = URL(string: "https://ollama.com") {
                        NSWorkspace.shared.open(url)
                    }
                }

                Spacer()
            }
        }
        .padding(14)
        .premiumCard()
    }

    // MARK: Fast path

    private var fastPathCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Fast setup path")
                .font(.headline)
                .foregroundStyle(.white)

            stepRow("1", "Install and run Ollama", "Download from ollama.com and run: ollama serve")
            stepRow("2", "Install models", "Pull chat / embedding / vision models in terminal")
            stepRow("3", "Open Models section", "Assign model roles (Chat, Embedding, Vision)")
            stepRow("4", "Open Settings", "Configure Voice, Image provider, and API keys")
            stepRow("5", "Run Diagnostics again", "All red items should become green")
        }
        .padding(14)
        .premiumCard()
    }

    private func stepRow(_ idx: String, _ title: String, _ subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(AstraUITheme.accent.opacity(0.35))
                    .frame(width: 24, height: 24)
                Text(idx)
                    .font(.caption.bold())
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.72))
            }

            Spacer()
        }
        .padding(10)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: Issues list

    private var issuesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Diagnostics Report")
                .font(.headline)
                .foregroundStyle(.white)

            ForEach(report.items) { item in
                issueRow(item)
            }
        }
        .padding(14)
        .premiumCard()
    }

    private func issueRow(_ item: DependencyCheckItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                statusDot(item.status)

                Text(item.title)
                    .font(.headline)
                    .foregroundStyle(.white)

                Spacer()

                Text(statusText(item.status))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(color(for: item.status))
            }

            Text(item.details)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))

            if let instruction = item.instruction, !instruction.isEmpty {
                Text(instruction)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            HStack(spacing: 8) {
                if item.status == .missing || item.status == .warning {
                    Button {
                        openWindow(id: "app-settings")
                    } label: {
                        compactFixButton("Open Settings", "gearshape.fill")
                    }
                    .buttonStyle(.plain)

                    Button {
                        openWindow(id: "help-center")
                    } label: {
                        compactFixButton("Open Help", "questionmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: UI helpers

    private func actionButton(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
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
        .buttonStyle(.plain)
    }

    private func compactFixButton(_ title: String, _ icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
            Text(title)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.10))
        .clipShape(Capsule())
    }

    private func statusDot(_ status: DependencyStatus) -> some View {
        Circle()
            .fill(color(for: status))
            .frame(width: 10, height: 10)
    }

    private func statusText(_ status: DependencyStatus) -> String {
        switch status {
        case .ok: return "OK"
        case .warning: return "WARNING"
        case .missing: return "MISSING"
        }
    }

    private func color(for status: DependencyStatus) -> Color {
        switch status {
        case .ok: return .green
        case .warning: return .orange
        case .missing: return .red
        }
    }
}
