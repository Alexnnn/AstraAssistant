//
//  DiagnosticsReportSheetView.swift
//  AstraAssistant
//
//  Created by Alex on 10/8/26.
//

import SwiftUI

struct DiagnosticsReportSheetView: View {
    let report: DependencyReport?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Diagnostics")
                .font(.largeTitle.bold())

            if let report {
                List(report.items) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Circle()
                                .fill(color(for: item.status))
                                .frame(width: 10, height: 10)

                            Text(item.title)
                                .font(.headline)

                            Spacer()

                            Text(item.status.rawValue.uppercased())
                                .font(.caption)
                                .foregroundStyle(color(for: item.status))
                        }

                        Text(item.details)
                            .foregroundStyle(.secondary)

                        if let instruction = item.instruction, !instruction.isEmpty {
                            Text(instruction)
                                .font(.system(.body, design: .monospaced))
                                .padding(8)
                                .background(Color.black.opacity(0.05))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding(.vertical, 6)
                }
            } else {
                Text("No diagnostics report yet.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(minWidth: 760, minHeight: 520)
    }

    private func color(for status: DependencyStatus) -> Color {
        switch status {
        case .ok: return .green
        case .warning: return .orange
        case .missing: return .red
        }
    }
}
