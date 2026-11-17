//
//  HyperFetchApp.swift
//  HyperFetchApp
//

import AppKit
import SwiftUI
import DownloadKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = HyperFetchServiceProvider.shared
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            MainWindowDelegate.shared.reopenMainWindow()
            self.logMenuBarItems()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.logMenuBarItems()
        }
    }

    func logMenuBarItems() {
        guard let mainMenu = NSApp.mainMenu else { return }
        var lines: [String] = []
        for item in mainMenu.items {
            let title = item.title.isEmpty ? (item.submenu?.title ?? "<empty>") : item.title
            var subitems: [String] = []
            if let submenu = item.submenu {
                for sub in submenu.items {
                    if sub.isSeparatorItem {
                        subitems.append("---")
                    } else {
                        subitems.append(sub.title)
                    }
                }
            }
            lines.append("Menu '\(title)': [\(subitems.joined(separator: ", "))]")
        }
        try? lines.joined(separator: "\n").write(toFile: "/tmp/hyperfetch_menus.log", atomically: true, encoding: .utf8)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainWindowDelegate.shared.reopenMainWindow()
        logMenuBarItems()
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainWindowDelegate.shared.isTerminating = true
        AppState.shared?.flushSync()
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppState.shared?.flushSync()
    }
}

@main
struct HyperFetchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()
    @StateObject private var versionManager = AppVersionManager.shared

    private struct BrowserGuideMenuButton: View {
        let appState: AppState
        @Environment(\.openSettings) private var openSettings

        var body: some View {
            Button("Browser Integration Guide...") {
                appState.selectedSettingsTab = .browser
                openSettings()
            }
        }
    }

    var body: some Scene {
        WindowGroup("HyperFetch") {
            MainWindow()
                .environmentObject(appState)
                .environmentObject(versionManager)
                .preferredColorScheme(appState.preferredColorScheme)
                .sheet(isPresented: $versionManager.isUpdateSheetPresented) {
                    UpdateSheetView()
                        .environmentObject(versionManager)
                }
                .sheet(isPresented: $versionManager.isAboutSheetPresented) {
                    AboutView()
                        .environmentObject(versionManager)
                }
                .frame(minWidth: 1000, minHeight: 600)
                .onOpenURL { url in
                    appState.bringToFront()
                    appState.handleIncomingURLScheme(url)
                    (NSApp.delegate as? AppDelegate)?.logMenuBarItems()
                }
                .onAppear {
                    versionManager.checkOnLaunchIfNeeded()
                }
        }
        .defaultSize(width: 1200, height: 750)
        .windowResizability(.contentMinSize)
        .handlesExternalEvents(matching: Set(["*"]))
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About HyperFetch") {
                    versionManager.isAboutSheetPresented = true
                }
                Button("Check for Updates...") {
                    versionManager.checkForUpdates(userInitiated: true)
                }
            }

            CommandGroup(after: .appSettings) {
                BrowserGuideMenuButton(appState: appState)
            }

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

                Button("Select All") {
                    appState.selectAll()
                }
                .keyboardShortcut("a", modifiers: .command)

                Button("Reveal in Finder") {
                    appState.revealSelectedInFinder()
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(appState.selectedTaskIDs.isEmpty)

                Button("Open Downloaded File") {
                    appState.openSelectedFile()
                }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(appState.selectedTaskIDs.isEmpty)

                Button("Delete Selected...") {
                    appState.promptDeleteSelected()
                }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(appState.selectedTaskIDs.isEmpty)

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
                Toggle("Bring App to Front on Capture", isOn: $appState.bringToFrontOnCapture)

                Divider()

                Button("Browser Integration Guide...") {
                    appState.openSettingsWindow(tab: .browser)
                }
            }

            CommandGroup(after: .toolbar) {
                Divider()
                Menu("Appearance") {
                    ForEach(AppearanceMode.allCases) { mode in
                        Button {
                            appState.appearanceMode = mode
                        } label: {
                            HStack {
                                Text(mode.rawValue)
                                if appState.appearanceMode == mode {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }

                Menu("List View Style") {
                    ForEach(DownloadListViewMode.allCases) { mode in
                        Button {
                            appState.viewMode = mode
                        } label: {
                            HStack {
                                Text(mode.rawValue)
                                if appState.viewMode == mode {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            }

            CommandGroup(replacing: .help) {
                Button("Check for Updates...") {
                    versionManager.checkForUpdates(userInitiated: true)
                }

                Button("About HyperFetch") {
                    versionManager.isAboutSheetPresented = true
                }

                Divider()

                BrowserGuideMenuButton(appState: appState)

                Divider()

                Button("Support HyperFetch (Ko-fi)...") {
                    if let url = URL(string: "https://ko-fi.com/consultanythingtech") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
                .environmentObject(versionManager)
        }

        // Live status bar / menu bar companion
        MenuBarExtra {
            MenuBarCompanionView()
                .environmentObject(appState)
                .environmentObject(versionManager)
        } label: {
            if appState.totalDownloadSpeed > 0 {
                Text("↓ \(appState.formattedTotalSpeed)")
            } else {
                Image(systemName: "arrow.down.circle")
            }
        }
        .menuBarExtraStyle(.window)
    }
}
