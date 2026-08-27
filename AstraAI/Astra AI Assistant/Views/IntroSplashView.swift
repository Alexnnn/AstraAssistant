//
//  IntroSplashView.swift
//  AstraAssistant
//
//  Created by Alex on 11/8/26.
//

import SwiftUI

struct IntroSplashView: View {
    let onFinished: () -> Void

    @State private var logoScale: CGFloat = 0.84
    @State private var glow: CGFloat = 0.0
    @State private var textOpacity: CGFloat = 0.0
    @State private var progress: CGFloat = 0.0

    var body: some View {
        ZStack {
            AstraUITheme.mainBackground

            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [AstraUITheme.accent.opacity(0.55), AstraUITheme.accent2.opacity(0.45)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 132, height: 132)
                        .blur(radius: 18 * glow)
                        .scaleEffect(1.0 + 0.07 * glow)

                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [AstraUITheme.accent, AstraUITheme.accent2],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 92, height: 92)
                        .overlay(
                            Image(systemName: "sparkles")
                                .font(.system(size: 34, weight: .bold))
                                .foregroundStyle(.white)
                        )
                        .shadow(color: .white.opacity(0.25), radius: 12, x: 0, y: 0)
                }
                .scaleEffect(logoScale)

                VStack(spacing: 6) {
                    Text("Astra Assistant")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("Private • Local-first • Proactive")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.75))
                }
                .opacity(textOpacity)

                VStack(spacing: 8) {
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.12))
                            .frame(width: 260, height: 8)

                        RoundedRectangle(cornerRadius: 8)
                            .fill(
                                LinearGradient(
                                    colors: [AstraUITheme.accent2, AstraUITheme.accent],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: 260 * progress, height: 8)
                    }

                    Text("Initializing...")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.72))
                }
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.75, dampingFraction: 0.78)) {
                logoScale = 1.0
                glow = 1.0
            }

            withAnimation(.easeInOut(duration: 0.55).delay(0.15)) {
                textOpacity = 1.0
            }

            withAnimation(.easeInOut(duration: 1.5)) {
                progress = 1.0
            }

            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                onFinished()
            }
        }
    }
}
