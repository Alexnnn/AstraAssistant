//
//  CompanionRootView.swift
//  AstraCompanion
//
//  Created by Alex on 13/8/26.
//

import SwiftUI

struct CompanionRootView: View {
    @EnvironmentObject var appState: CompanionAppState

    var body: some View {
        Group {
            if let _ = appState.profile {
                CompanionMainTabView()
            } else {
                ConnectView()
            }
        }
    }
}
