//
//  AstraMotion.swift
//  AstraAssistant
//
//  Created by Alex on 11/8/26.
//

import SwiftUI

// MARK: - Motion presets

extension Animation {
    static let astraScreen = Animation.spring(response: 0.42, dampingFraction: 0.92, blendDuration: 0.15)
    static let astraHover = Animation.easeOut(duration: 0.16)
    static let astraPress = Animation.easeOut(duration: 0.10)
}

extension AnyTransition {
    static var astraScreen: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 1.01)),
            removal: .opacity.combined(with: .scale(scale: 0.995))
        )
    }
}

// MARK: - Shimmer

struct ShimmerModifier: ViewModifier {
    var active: Bool
    @State private var phase: CGFloat = -0.9

    func body(content: Content) -> some View {
        content
            .overlay {
                if active {
                    GeometryReader { proxy in
                        let w = proxy.size.width
                        let h = proxy.size.height

                        LinearGradient(
                            colors: [
                                Color.clear,
                                Color.white.opacity(0.14),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(width: w * 0.35, height: h * 1.3)
                        .rotationEffect(.degrees(18))
                        .offset(x: w * phase)
                        .blendMode(.plusLighter)
                        .allowsHitTesting(false)
                        .onAppear {
                            withAnimation(.linear(duration: 1.25).repeatForever(autoreverses: false)) {
                                phase = 1.25
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
    }
}

extension View {
    func shimmer(_ active: Bool) -> some View {
        modifier(ShimmerModifier(active: active))
    }
}

// MARK: - Hover / card interaction

struct PremiumHoverCardModifier: ViewModifier {
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovering ? 1.006 : 1.0)
            .shadow(color: .black.opacity(isHovering ? 0.22 : 0.10), radius: isHovering ? 16 : 8, x: 0, y: isHovering ? 8 : 3)
            .animation(.astraHover, value: isHovering)
            .onHover { hovering in
                isHovering = hovering
            }
    }
}

extension View {
    func premiumHoverCard() -> some View {
        modifier(PremiumHoverCardModifier())
    }
}
