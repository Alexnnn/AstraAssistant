//
//  IOSAvatarStore.swift
//  AstraCompanion
//
//  Created by Alex on 23/8/26.
//

import Foundation
import UIKit
import SwiftUI
import Combine

@MainActor
final class IOSAvatarStore: ObservableObject {
    static let assistantKey = "ios.assistant.avatar.data"
    static let userKey = "ios.user.avatar.data"

    @Published private(set) var assistantImage: UIImage?
    @Published private(set) var userImage: UIImage?

    init() {
        reload()
    }

    var hasAssistantAvatar: Bool {
        assistantImage != nil
    }

    var hasUserAvatar: Bool {
        userImage != nil
    }

    func reload() {
        if let data = UserDefaults.standard.data(forKey: Self.assistantKey) {
            assistantImage = UIImage(data: data)
        } else {
            assistantImage = nil
        }

        if let data = UserDefaults.standard.data(forKey: Self.userKey) {
            userImage = UIImage(data: data)
        } else {
            userImage = nil
        }
    }

    func setAssistantAvatar(data: Data) {
        guard let processed = Self.processAvatarData(data) else { return }

        UserDefaults.standard.set(processed, forKey: Self.assistantKey)
        assistantImage = UIImage(data: processed)
    }

    func setUserAvatar(data: Data) {
        guard let processed = Self.processAvatarData(data) else { return }

        UserDefaults.standard.set(processed, forKey: Self.userKey)
        userImage = UIImage(data: processed)
    }

    func clearAssistantAvatar() {
        UserDefaults.standard.removeObject(forKey: Self.assistantKey)
        assistantImage = nil
    }

    func clearUserAvatar() {
        UserDefaults.standard.removeObject(forKey: Self.userKey)
        userImage = nil
    }

    private static func processAvatarData(
        _ data: Data,
        targetPixelSize: CGFloat = 512,
        compressionQuality: CGFloat = 0.82
    ) -> Data? {
        guard let source = UIImage(data: data) else {
            return nil
        }

        let normalized = source.normalizedForDrawing()
        let square = normalized.centerCroppedSquare()
        let resized = square.resized(to: CGSize(width: targetPixelSize, height: targetPixelSize))

        return resized.jpegData(compressionQuality: compressionQuality)
    }
}

private extension UIImage {
    func normalizedForDrawing() -> UIImage {
        if imageOrientation == .up {
            return self
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(size: size, format: format)

        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    func centerCroppedSquare() -> UIImage {
        let side = min(size.width, size.height)

        let cropRect = CGRect(
            x: (size.width - side) / 2,
            y: (size.height - side) / 2,
            width: side,
            height: side
        )

        guard let cgImage,
              let croppedCG = cgImage.cropping(to: CGRect(
                x: cropRect.origin.x * scale,
                y: cropRect.origin.y * scale,
                width: cropRect.width * scale,
                height: cropRect.height * scale
              )) else {
            return self
        }

        return UIImage(cgImage: croppedCG, scale: scale, orientation: .up)
    }

    func resized(to targetSize: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)

        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}
