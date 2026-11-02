//
//  SwiftFlowApp.swift
//  SwiftFlowApp
//

import AppKit
import SwiftUI
import DownloadKit

@main
struct SwiftFlowApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            MainWindow()
                .environmentObject(appState)
                .frame(minWidth: 850, minHeight: 550)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Download...") {
                    appState.isAddSheetPresented = true
                }
                .keyboardShortcut("n", modifiers: .command)
            }

            CommandMenu("Downloads") {
                Button("Pause All") {
                    appState.pauseAll()
                }

                Button("Resume All") {
                    appState.resumeAll()
                }

                Divider()

                Menu("Speed Limit") {
                    ForEach(SpeedLimitPreset.allCases) { preset in
                        Button {
                            appState.setSpeedLimit(preset: preset)
                        } label: {
                            HStack {
                                Text(preset.rawValue)
                                if appState.speedLimitPreset == preset {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            }
        }

        // Live status bar / menu bar companion
        MenuBarExtra {
            Button("Open SwiftFlow") {
                NSApp.activate(ignoringOtherApps: true)
                for window in NSApp.windows where window.canBecomeMain {
                    window.makeKeyAndOrderFront(nil)
                }
            }

            Divider()

            Text("Active: \(appState.activeDownloadCount)  •  \(appState.formattedTotalSpeed)")

            Divider()

            Button("Pause All") {
                appState.pauseAll()
            }
            .disabled(appState.activeDownloadCount == 0)

            Button("Resume All") {
                appState.resumeAll()
            }
            .disabled(appState.pausedDownloadCount == 0)

            Divider()

            Button("Quit SwiftFlow") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        } label: {
            if appState.totalDownloadSpeed > 0 {
                Text("↓ \(appState.formattedTotalSpeed)")
            } else {
                Image(systemName: "arrow.down.circle")
            }
        }
    }
}
