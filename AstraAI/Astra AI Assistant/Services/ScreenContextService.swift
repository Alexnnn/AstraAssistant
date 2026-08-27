//
//  ScreenContextService.swift
//  AstraAssistant
//
//  Created by Alex on 10/8/26.
//

import Foundation
import AppKit
import ScreenCaptureKit
import CoreGraphics

final class ScreenContextService {
    static let shared = ScreenContextService()

    private init() {}

    @available(macOS 14.0, *)
    func captureMainScreenToTemporaryPNG() async throws -> URL {
        /*
         ScreenCaptureKit требует разрешение Screen Recording.
         Если разрешения нет, macOS покажет системный prompt или capture упадёт с ошибкой.
         */

        let availableContent = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )

        guard !availableContent.displays.isEmpty else {
            throw NSError(
                domain: "ScreenContextService",
                code: -1,
                userInfo: [
                    NSLocalizedDescriptionKey: "No displays are available for screen capture."
                ]
            )
        }

        let selectedDisplay = selectMainDisplay(from: availableContent.displays)

        let filter = SCContentFilter(
            display: selectedDisplay,
            excludingWindows: []
        )

        let configuration = SCStreamConfiguration()

        configuration.width = selectedDisplay.width
        configuration.height = selectedDisplay.height
        configuration.showsCursor = true
        configuration.pixelFormat = kCVPixelFormatType_32BGRA

        let cgImage = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )

        let bitmap = NSBitmapImageRep(cgImage: cgImage)

        guard let pngData = bitmap.representation(
            using: .png,
            properties: [:]
        ) else {
            throw NSError(
                domain: "ScreenContextService",
                code: -2,
                userInfo: [
                    NSLocalizedDescriptionKey: "Failed to encode screenshot as PNG."
                ]
            )
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("astra-screen-\(UUID().uuidString).png")

        try pngData.write(to: url)

        return url
    }

    @available(macOS 14.0, *)
    private func selectMainDisplay(from displays: [SCDisplay]) -> SCDisplay {
        guard let mainScreen = NSScreen.main,
              let screenNumber = mainScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return displays[0]
        }

        let mainDisplayID = CGDirectDisplayID(screenNumber.uint32Value)

        return displays.first { display in
            display.displayID == mainDisplayID
        } ?? displays[0]
    }
}
