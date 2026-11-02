//
//  HyperFetchApp.swift
//  HyperFetchApp
//

import AppKit
import SwiftUI
import DownloadKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            for window in NSApp.windows where window.canBecomeMain {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if !flag {
            for window in sender.windows where window.canBecomeMain {
                window.makeKeyAndOrderFront(nil)
            }
        }
        return true
    }
}

@main
struct HyperFetchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup("HyperFetch") {
            MainWindow()
                .environmentObject(appState)
                .frame(minWidth: 850, minHeight: 550)
                .onOpenURL { url in
                    appState.handleIncomingURLScheme(url)
                }
        }
        .defaultSize(width: 950, height: 600)
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

                Divider()

                Toggle("Auto-Capture Clipboard Links", isOn: $appState.autoCaptureClipboard)
                Toggle("Auto-Start Captured Downloads (Bypass HUD)", isOn: $appState.autoStartCapturedDownloads)
            }
        }

        // Live status bar / menu bar companion
        MenuBarExtra {
            Button("Open HyperFetch") {
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

            Button("Quit HyperFetch") {
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
