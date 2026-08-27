//
//  ConnectView.swift
//  AstraCompanion
//
//  Created by Alex on 13/8/26.
//

import SwiftUI

struct ConnectView: View {
    @EnvironmentObject var appState: CompanionAppState

    @State private var code = ""
    @State private var isConnecting = false
    @State private var showScanner = false
    @State private var scannerError: String?

    @FocusState private var isCodeFocused: Bool

    var body: some View {
        ZStack {
            background

            ScrollView {
                VStack(spacing: 22) {
                    hero

                    connectionCard

                    guideCard

                    if let err = appState.errorText {
                        errorCard(err)
                    }

                    if let scannerError {
                        errorCard(scannerError)
                    }

                    Text(appState.statusText)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.55))
                }
                .padding(22)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
        }
        .sheet(isPresented: $showScanner) {
            NavigationStack {
                QRCodeScannerView { raw in
                    handleScannedPayload(raw)
                } onError: { error in
                    scannerError = error
                }
                .ignoresSafeArea()
                .navigationTitle("Scan QR")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Close") {
                            showScanner = false
                        }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    isCodeFocused = false
                }
            }
        }
    }

    private var background: some View {
        LinearGradient(
            colors: [
                Color(red: 0.06, green: 0.08, blue: 0.16),
                Color(red: 0.02, green: 0.03, blue: 0.08),
                Color.black
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        .overlay {
            Circle()
                .fill(Color.blue.opacity(0.22))
                .frame(width: 260, height: 260)
                .blur(radius: 60)
                .offset(x: -150, y: -260)

            Circle()
                .fill(Color.cyan.opacity(0.16))
                .frame(width: 240, height: 240)
                .blur(radius: 70)
                .offset(x: 150, y: 260)
        }
    }

    private var hero: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 84, height: 84)
                    .shadow(color: .cyan.opacity(0.35), radius: 24)

                Image(systemName: "sparkles")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 6) {
                Text("Connect to Astra")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("Pair your iPhone with Astra Assistant running on your Mac.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.72))
                    .padding(.horizontal, 12)
            }
        }
        .padding(.top, 28)
    }

    private var connectionCard: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Pairing Code")
                    .font(.headline)
                    .foregroundStyle(.white)

                Text("Generate a code on Mac: Astra Settings → iPhone / iPad Pairing.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.68))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            TextField("123456", text: codeBinding)
                .keyboardType(.numberPad)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($isCodeFocused)
                .font(.system(size: 28, weight: .bold, design: .monospaced))
                .multilineTextAlignment(.center)
                .padding(.vertical, 14)
                .background(Color.white.opacity(0.10))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(isCodeFocused ? 0.35 : 0.12), lineWidth: 1)
                }

            HStack(spacing: 12) {
                Button {
                    showScanner = true
                } label: {
                    Label("Scan QR", systemImage: "qrcode.viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    Task {
                        await connect()
                    }
                } label: {
                    if isConnecting {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Label("Connect", systemImage: "link")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(code.count != 6 || isConnecting)
            }

            Text("You can scan the QR code or enter the 6-digit code manually.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.55))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        }
    }

    private var guideCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How to pair")
                .font(.headline)
                .foregroundStyle(.white)

            guideRow("1", "Open Astra on your Mac")
            guideRow("2", "Go to Settings → iPhone / iPad Pairing")
            guideRow("3", "Generate code and scan QR here")
        }
        .padding(16)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        }
    }

    private func guideRow(_ number: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.cyan.opacity(0.20))
                    .frame(width: 26, height: 26)

                Text(number)
                    .font(.caption.bold())
                    .foregroundStyle(.white)
            }

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.78))

            Spacer()
        }
    }

    private func errorCard(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.red)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.red.opacity(0.22), lineWidth: 1)
            }
    }

    private var codeBinding: Binding<String> {
        Binding(
            get: { code },
            set: { newValue in
                let digits = newValue.filter { $0.isNumber }
                code = String(digits.prefix(6))
            }
        )
    }

    private func connect() async {
        let clean = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count == 6 else { return }

        isConnecting = true
        scannerError = nil
        isCodeFocused = false

        await appState.connectWithCode(clean)

        isConnecting = false
    }

    private func handleScannedPayload(_ raw: String) {
        showScanner = false
        scannerError = nil

        guard let extracted = extractPairingCode(from: raw) else {
            scannerError = "QR code does not contain a valid Astra pairing code."
            return
        }

        code = extracted

        Task {
            await connect()
        }
    }

    private func extractPairingCode(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Raw: 123456
        let onlyDigits = trimmed.filter { $0.isNumber }
        if trimmed.count == 6, onlyDigits.count == 6 {
            return trimmed
        }

        // 2. URL: astra://pair?code=123456
        if let components = URLComponents(string: trimmed),
           let code = components.queryItems?.first(where: { $0.name == "code" })?.value {
            let digits = code.filter { $0.isNumber }
            if digits.count == 6 {
                return String(digits.prefix(6))
            }
        }

        // 3. JSON: {"code":"123456"}
        if let data = trimmed.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let code = json["code"] as? String {
            let digits = code.filter { $0.isNumber }
            if digits.count == 6 {
                return String(digits.prefix(6))
            }
        }

        // 4. Fallback: first 6-digit sequence
        if let regex = try? NSRegularExpression(pattern: #"(?<!\d)\d{6}(?!\d)"#) {
            let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
            if let match = regex.firstMatch(in: trimmed, range: range),
               let r = Range(match.range, in: trimmed) {
                return String(trimmed[r])
            }
        }

        return nil
    }
}
