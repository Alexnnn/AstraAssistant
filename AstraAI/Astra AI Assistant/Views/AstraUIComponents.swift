//
//  AstraUIComponents.swift
//  AstraAssistant
//
//  Created by Alex on 11/8/26.
//

import SwiftUI

struct AstraSectionHeader: View {
    let title: String
    let subtitle: String?
    let icon: String

    init(_ title: String, subtitle: String? = nil, icon: String) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AstraUITheme.accent2)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }

            Spacer()
        }
    }
}

struct AstraStatusChip: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.35))
            .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
            .clipShape(Capsule())
    }
}

struct AstraGhostButtonStyle: ButtonStyle {
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.17 : (isHovering ? 0.14 : 0.10)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(isHovering ? 0.18 : 0.12), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.975 : 1.0)
            .animation(.astraPress, value: configuration.isPressed)
            .onHover { hovering in
                isHovering = hovering
            }
    }
}

extension View {
    func premiumCard(corner: CGFloat = 14) -> some View {
        self
            .background(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: corner)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: corner))
            .premiumHoverCard()
    }
}
