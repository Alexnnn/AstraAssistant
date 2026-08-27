//
//  CommandCheatSheetView.swift
//  AstraCompanion
//
//  Created by Alex on 13/8/26.
//

import SwiftUI
import UIKit

struct CommandCheatSheetView: View {
    private let commands: [String] = [
        "/help",
        "/search <query>",
        "/open <url>",
        "/task <text>",
        "/tasks",
        "/now",
        "/calendar today",
        "/calendar add YYYY-MM-DD HH:mm | Title"
    ]

    var body: some View {
        NavigationStack {
            List {
                Section("Quick command cheat sheet") {
                    ForEach(commands, id: \.self) { cmd in
                        HStack {
                            Text(cmd)
                                .font(.system(.body, design: .monospaced))
                            Spacer()
                            Button {
                                UIPasteboard.general.string = cmd
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .buttonStyle(.plain)
                        }
                        .contextMenu {
                            Button("Copy") {
                                UIPasteboard.general.string = cmd
                            }
                        }
                    }
                }
            }
            .navigationTitle("Commands")
        }
    }
}
