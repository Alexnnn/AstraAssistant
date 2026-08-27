//
//  IOSAvatarView.swift
//  AstraCompanion
//
//  Created by Alex on 23/8/26.
//

import SwiftUI
import UIKit

enum IOSAvatarKind {
    case assistant
    case user
}

struct IOSAvatarView: View {
    @EnvironmentObject private var avatarStore: IOSAvatarStore

    let kind: IOSAvatarKind
    var size: CGFloat = 30

    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(Color.gray.opacity(0.25), lineWidth: 1)
        )
        .contentShape(Circle())
    }

    private var image: UIImage? {
        switch kind {
        case .assistant:
            return avatarStore.assistantImage
        case .user:
            return avatarStore.userImage
        }
    }

    @ViewBuilder
    private var placeholder: some View {
        switch kind {
        case .assistant:
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Image(systemName: "sparkles")
                    .font(.system(size: size * 0.43, weight: .bold))
                    .foregroundStyle(.white)
            }

        case .user:
            ZStack {
                Circle()
                    .fill(Color(.tertiarySystemBackground))

                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.43, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
