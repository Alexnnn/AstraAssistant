//
//  SetupLauncherView.swift
//  AstraAssistant
//
//  Created by Alex on 11/8/26.
//

import SwiftUI

struct SetupLauncherView: View {
    @EnvironmentObject private var appViewModel: AppViewModel

    var body: some View {
        Group {
            if let report = appViewModel.dependencyReport {
                SetupWizardView(report: report)
            } else {
                ProgressView("Loading diagnostics...")
                    .task {
                        await appViewModel.refreshDiagnostics()
                        await appViewModel.refreshModels()
                    }
            }
        }
    }
}
