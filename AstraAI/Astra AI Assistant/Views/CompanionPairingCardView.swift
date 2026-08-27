//
//  CompanionPairingCardView.swift
//  Astra AI Assistant
//
//  Created by Alex on 13/8/26.
//

import SwiftUI
import Combine
import AppKit

struct CompanionPairingCardView: View {
    @ObservedObject var companion: FirebaseCompanionService
    @StateObject private var pairing = CompanionPairingService.shared

    private var qrPayload: String? {
        guard let code = pairing.currentCode else { return nil }
        return "astra://pair?code=\(code)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("iPhone / iPad Pairing")
                        .font(.headline)
                        .foregroundStyle(.white)

                    Text("Scan QR in iOS app or enter the 6-digit code manually.")
                        .foregroundStyle(.white.opacity(0.75))
                        .font(.caption)
                }

                Spacer()

                Button {
                    Task {
                        guard let uid = companion.uid else { return }
                        await pairing.generateCode(uid: uid, deviceId: companion.deviceId)
                    }
                } label: {
                    Label(pairing.isGenerating ? "Generating..." : "Generate Code", systemImage: "qrcode")
                }
                .buttonStyle(.borderedProminent)
                .disabled(companion.uid == nil || pairing.isGenerating)
            }

            if let code = pairing.currentCode {
                HStack(alignment: .center, spacing: 18) {
                    if let qrPayload {
                        QRCodeView(text: qrPayload, size: 150)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Pairing code")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.65))

                        Text(code)
                            .font(.system(size: 32, weight: .bold, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                        HStack {
                            Button("Copy Code") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(code, forType: .string)
                            }

                            if let qrPayload {
                                Button("Copy QR Payload") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(qrPayload, forType: .string)
                                }
                            }
                        }
                        .buttonStyle(.bordered)

                        if let exp = pairing.expiresAt {
                            Text("Expires: \(exp.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.65))
                        }
                    }

                    Spacer()
                }
                .padding(12)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.75))

                    Text("Generate a pairing code to show QR.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))

                    Spacer()
                }
                .padding(12)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            if let err = pairing.lastError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
