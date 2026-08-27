//
//  AstraUITheme.swift
//  AstraAssistant
//
//  Created by Alex on 11/8/26.
//

import SwiftUI

enum AstraUITheme {
    static let bgTop = Color(red: 0.08, green: 0.09, blue: 0.14)
    static let bgBottom = Color(red: 0.03, green: 0.04, blue: 0.08)

    static let accent = Color(red: 0.43, green: 0.57, blue: 0.98)
    static let accent2 = Color(red: 0.43, green: 0.87, blue: 0.86)

    static let assistantBubble = Color(red: 0.28, green: 0.40, blue: 0.95).opacity(0.18)
    static let userBubble = Color.white.opacity(0.08)

    static let border = Color.white.opacity(0.14)
    static let subtle = Color.white.opacity(0.65)

    static var mainBackground: some View {
        LinearGradient(
            colors: [bgTop, bgBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    static var cardBackground: some ShapeStyle {
        .ultraThinMaterial
    }
}
