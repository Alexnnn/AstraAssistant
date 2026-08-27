//
//  QRCodeView.swift
//  Astra AI Assistant
//
//  Created by Alex on 14/8/26.
//

import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import AppKit

struct QRCodeView: View {
    let text: String
    var size: CGFloat = 160

    var body: some View {
        Group {
            if let image = Self.makeQRCode(from: text) {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .padding(10)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            } else {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(0.12))
                    .frame(width: size, height: size)
                    .overlay {
                        Text("QR error")
                            .foregroundStyle(.white.opacity(0.7))
                    }
            }
        }
    }

    private static func makeQRCode(from string: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        let context = CIContext()

        guard let data = string.data(using: .utf8) else {
            return nil
        }

        filter.message = data
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else {
            return nil
        }

        let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: 12, y: 12))

        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: scaled.extent.width, height: scaled.extent.height))
    }
}
