//
//  ToolConfirmationView.swift
//  AstraAssistant
//
//  Created by Alex on 10/8/26.
//

import SwiftUI

struct ToolConfirmationView: View {
    let pending: PendingToolConfirmation
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)

                VStack(alignment: .leading) {
                    Text(pending.title)
                        .font(.title2.bold())

                    Text(pending.kind.title)
                        .foregroundStyle(.secondary)
                }
            }

            Text(pending.details)
                .textSelection(.enabled)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            Text("Astra requires your confirmation before performing this action.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("Cancel") {
                    onCancel()
                }

                Spacer()

                Button("Allow") {
                    onConfirm()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 520)
    }
}
