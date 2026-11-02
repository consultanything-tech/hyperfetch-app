//
//  SettingsView.swift
//  HyperFetchApp
//
//  Created by HyperFetch on 2026-11-02.
//

import AppKit
import SwiftUI
import UserNotifications
import DownloadKit

/// Native macOS Settings window providing configurations for General preferences,
/// clipboard automation, and browser extension integration onboarding.
public struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    public init() {}

    public var body: some View {
        TabView(selection: $appState.selectedSettingsTab) {
            GeneralSettingsTab()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
                .tag(SettingsTab.general)

            AutomationSettingsTab()
                .tabItem {
                    Label("Automation", systemImage: "bolt.badge.automatic")
                }
                .tag(SettingsTab.automation)

            BrowserSettingsTab()
                .tabItem {
                    Label("Browser", systemImage: "globe")
                }
                .tag(SettingsTab.browser)

            UpdatesSettingsTab()
                .tabItem {
                    Label("Updates", systemImage: "arrow.triangle.2.circlepath")
                }
                .tag(SettingsTab.updates)
        }
        .frame(width: 560, height: 480)
        .preferredColorScheme(appState.preferredColorScheme)
    }
}

// MARK: - 1. General Settings Tab

private struct GeneralSettingsTab: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section("Appearance") {
                VStack(alignment: .leading, spacing: 6) {
                    Picker("Theme", selection: $appState.appearanceMode) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Label(mode.rawValue, systemImage: mode.iconName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(appearanceDescription(for: appState.appearanceMode))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Default Download Location") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(.tint)
                            .font(.system(size: 16))

                        Text(appState.defaultDownloadDirectoryURL.path)
                            .font(.system(size: 12, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.primary)

                        Spacer()
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1)
                    )

                    HStack(spacing: 10) {
                        Button("Change...") {
                            chooseDownloadLocation()
                        }
                        .buttonStyle(.bordered)

                        Button("Reveal in Finder") {
                            revealDownloadLocation()
                        }
                        .buttonStyle(.bordered)

                        Spacer()
                    }
                }
            }

            Section("Acceleration & Concurrency") {
                VStack(alignment: .leading, spacing: 6) {
                    Picker("Acceleration Chunks", selection: $appState.defaultChunkCount) {
                        Text("1").tag(1)
                        Text("2").tag(2)
                        Text("4").tag(4)
                        Text("8").tag(8)
                        Text("16").tag(16)
                    }
                    .pickerStyle(.segmented)

                    Text(chunkDescription(for: appState.defaultChunkCount))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Picker("Max Concurrent Downloads", selection: $appState.maxConcurrentDownloads) {
                            ForEach(1...8, id: \.self) { count in
                                Text("\(count) \(count == 1 ? "download" : "downloads")").tag(count)
                            }
                        }

                        Stepper("", value: $appState.maxConcurrentDownloads, in: 1...8)
                            .labelsHidden()
                    }

                    Text("Controls how many downloads run simultaneously. Additional tasks wait in the queue.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Network Bandwidth") {
                VStack(alignment: .leading, spacing: 6) {
                    Picker("Speed Limit", selection: Binding(
                        get: { appState.speedLimitPreset },
                        set: { appState.setSpeedLimit(preset: $0) }
                    )) {
                        ForEach(SpeedLimitPreset.allCases) { preset in
                            Text(preset.rawValue).tag(preset)
                        }
                    }

                    Text("Global rate limiter caps aggregate download bandwidth across all active tasks.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding(8)
    }

    private func appearanceDescription(for mode: AppearanceMode) -> String {
        switch mode {
        case .system:
            return "Follows macOS system appearance automatically."
        case .dark:
            return "Obsidian Sequoia theme optimized for low-light environments."
        case .light:
            return "Clean Apple native light appearance."
        }
    }

    private func chunkDescription(for count: Int) -> String {
        switch count {
        case 1:
            return "1 chunk: Direct single-stream download without range splitting (conservative)."
        case 2:
            return "2 chunks: Mild multi-stream acceleration for modest connections."
        case 4:
            return "4 chunks: Recommended default balancing high speed and server compliance."
        case 8:
            return "8 chunks: High throughput parallel acceleration for fast broadband."
        case 16:
            return "16 chunks: Maximum concurrency for gigabit fiber connections."
        default:
            return "\(count) parallel chunks per download."
        }
    }

    private func chooseDownloadLocation() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = appState.defaultDownloadDirectoryURL
        panel.prompt = "Select"
        if panel.runModal() == .OK, let selectedURL = panel.url {
            appState.defaultDownloadDirectoryURL = selectedURL
        }
    }

    private func revealDownloadLocation() {
        NSWorkspace.shared.activateFileViewerSelecting([appState.defaultDownloadDirectoryURL])
    }
}

// MARK: - 2. Automation Settings Tab

private struct AutomationSettingsTab: View {
    @EnvironmentObject private var appState: AppState
    @ViewState private var notificationStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        Form {
            Section("Download Capture") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Bring App to Front on Capture", isOn: $appState.bringToFrontOnCapture)

                    Text("Automatically brings HyperFetch to the foreground when a download is captured from browser or clipboard.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Divider()
                        .padding(.vertical, 2)

                    Toggle("Auto-Capture Download Links from Clipboard", isOn: $appState.autoCaptureClipboard)

                    Text("Automatically detects copied file URLs in macOS pasteboard and presents quick download actions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Divider()
                        .padding(.vertical, 2)

                    Toggle("Auto-Start Captured Downloads (Bypass Quick-Add HUD)", isOn: $appState.autoStartCapturedDownloads)
                        .disabled(!appState.autoCaptureClipboard)

                    Text("When enabled, detected links start downloading immediately without showing the Quick-Add HUD popup.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Supported File Extensions") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("HyperFetch recognizes clipboard links ending in these media, archive, and installer formats:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    extensionGrid
                }
            }

            Section("Notifications & Alerts") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(statusColor)
                                .frame(width: 9, height: 9)

                            Text(statusText)
                                .font(.subheadline)
                        }

                        Spacer()

                        if notificationStatus == .denied {
                            Button("Open System Settings...") {
                                openSystemNotificationSettings()
                            }
                            .buttonStyle(.bordered)
                        } else if notificationStatus == .notDetermined {
                            Button("Request Permission") {
                                appState.notificationManager.requestAuthorization()
                                refreshNotificationStatus()
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    Divider()

                    Toggle("Show Banner Notification on Download Complete", isOn: $appState.showCompletionNotification)

                    Toggle("Play Sound Alert on Download Complete", isOn: $appState.playCompletionSound)
                }
            }
        }
        .formStyle(.grouped)
        .padding(8)
        .onAppear {
            refreshNotificationStatus()
        }
    }

    private var statusColor: Color {
        switch notificationStatus {
        case .authorized, .provisional:
            return .green
        case .denied:
            return .red
        case .notDetermined:
            return .orange
        @unknown default:
            return .gray
        }
    }

    private var statusText: String {
        switch notificationStatus {
        case .authorized:
            return "System Notifications Authorized"
        case .denied:
            return "Notifications Disabled in System Settings"
        case .notDetermined:
            return "Notifications Not Configured"
        case .provisional:
            return "Provisional Notifications Enabled"
        @unknown default:
            return "Unknown Notification State"
        }
    }

    private func refreshNotificationStatus() {
        Task {
            let status = await appState.notificationManager.getAuthorizationStatus()
            await MainActor.run {
                self.notificationStatus = status
            }
        }
    }

    private func openSystemNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
    }

    private var extensionGrid: some View {
        let archives = [".zip", ".dmg", ".pkg", ".iso", ".tar", ".gz", ".7z", ".rar"]
        let media = [".mp4", ".mkv", ".avi", ".mov", ".mp3", ".wav", ".flac"]
        let installers = [".pdf", ".exe", ".msi", ".deb", ".rpm", ".app", ".bin"]

        return VStack(alignment: .leading, spacing: 6) {
            extensionRow(title: "Archives", items: archives)
            extensionRow(title: "Media", items: media)
            extensionRow(title: "Installers", items: installers)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func extensionRow(title: String, items: [String]) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("\(title):")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 65, alignment: .leading)

            Text(items.joined(separator: "  "))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary)

            Spacer()
        }
    }
}

// MARK: - 3. Browser Extension Tab

private struct BrowserSettingsTab: View {
    @EnvironmentObject private var appState: AppState
    @ViewState private var copiedPath: Bool = false
    @ViewState private var copiedURL: Bool = false

    var body: some View {
        Form {
            Section("Localhost Bridge Status") {
                bridgeStatusCard
            }

            Section("Chrome & Chromium Extension Setup") {
                onboardingGuideView
            }
        }
        .formStyle(.grouped)
        .padding(8)
        .onAppear {
            appState.refreshBridgeStatus()
        }
    }

    // MARK: - Bridge Status Card

    private var bridgeStatusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Circle()
                    .fill(appState.isBridgeRunning ? Color.green : Color.red)
                    .frame(width: 10, height: 10)

                VStack(alignment: .leading, spacing: 2) {
                    Text(appState.isBridgeRunning ? "Localhost Bridge Active" : "Localhost Bridge Offline")
                        .font(.headline)

                    Text("http://127.0.0.1:\(String(appState.bridgeListeningPort))")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(appState.isBridgeRunning ? "Active" : "Offline")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(appState.isBridgeRunning ? Color.green : Color.red)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill((appState.isBridgeRunning ? Color.green : Color.red).opacity(0.15))
                    )

                if !appState.isBridgeRunning {
                    Button("Restart Bridge") {
                        appState.restartLocalhostBridge()
                    }
                    .buttonStyle(.bordered)
                }
            }

            Text("HyperFetch listens on loopback (127.0.0.1) so browser extensions, bookmarklets, and CLI tools can dispatch downloads seamlessly.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(8)
    }

    // MARK: - Onboarding Guide

    private var onboardingGuideView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Step 1
            HStack(alignment: .top, spacing: 8) {
                Text("1.")
                    .font(.headline)
                    .foregroundStyle(.tint)
                    .frame(width: 20, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Open Extensions Management")
                        .font(.subheadline.weight(.semibold))

                    Text("Open ")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    + Text("chrome://extensions")
                        .font(.system(size: 11, design: .monospaced).weight(.medium))
                        .foregroundStyle(.primary)
                    + Text(" in Chrome, Brave, Microsoft Edge, or Arc.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button {
                        copyExtensionsURL()
                    } label: {
                        Label(copiedURL ? "Copied URL!" : "Copy chrome://extensions URL",
                              systemImage: copiedURL ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }

            Divider()

            // Step 2
            HStack(alignment: .top, spacing: 8) {
                Text("2.")
                    .font(.headline)
                    .foregroundStyle(.tint)
                    .frame(width: 20, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Enable Developer Mode")
                        .font(.subheadline.weight(.semibold))

                    Text("Turn on the 'Developer mode' toggle switch in the top-right corner of the extensions page.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            // Step 3
            HStack(alignment: .top, spacing: 8) {
                Text("3.")
                    .font(.headline)
                    .foregroundStyle(.tint)
                    .frame(width: 20, alignment: .leading)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Click 'Load unpacked'")
                        .font(.subheadline.weight(.semibold))

                    Text("Select the HyperFetch Chrome extension directory on your Mac:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    // Path Preview Box
                    HStack {
                        Image(systemName: "folder.badge.gearshape")
                            .foregroundStyle(.tint)

                        Text(appState.extensionDirectoryPath)
                            .font(.system(size: 11, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.primary)

                        Spacer()
                    }
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 1)
                    )

                    // Action buttons
                    HStack(spacing: 10) {
                        Button {
                            revealExtensionInFinder()
                        } label: {
                            Label("Reveal Extension in Finder", systemImage: "folder")
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            copyExtensionPath()
                        } label: {
                            Label(copiedPath ? "Path Copied!" : "Copy Extension Path",
                                  systemImage: copiedPath ? "checkmark" : "doc.on.doc")
                        }
                        .buttonStyle(.bordered)

                        Spacer()
                    }
                    .padding(.top, 4)
                }
            }
        }
        .padding(8)
    }

    private func copyExtensionsURL() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("chrome://extensions", forType: .string)
        withAnimation {
            copiedURL = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                copiedURL = false
            }
        }
    }

    private func revealExtensionInFinder() {
        let path = appState.extensionDirectoryPath
        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
    }

    private func copyExtensionPath() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(appState.extensionDirectoryPath, forType: .string)
        withAnimation {
            copiedPath = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                copiedPath = false
            }
        }
    }
}

// MARK: - 4. Updates Tab

private struct UpdatesSettingsTab: View {
    @EnvironmentObject private var versionManager: AppVersionManager

    var body: some View {
        Form {
            Section("Current Version") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.tint)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("HyperFetch")
                                .font(.headline)
                            Text("Version \(versionManager.currentVersion) (Build \(versionManager.buildNumber))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button("Check for Updates Now") {
                            versionManager.checkForUpdates(userInitiated: true)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.vertical, 4)

                    Divider()

                    HStack {
                        Text("Last checked:")
                            .foregroundStyle(.secondary)
                        Text(versionManager.formattedLastCheckedDate)
                            .foregroundStyle(.primary)
                    }
                    .font(.caption)
                }
            }

            Section("Update Preferences") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Automatically check for updates on launch", isOn: $versionManager.autoCheckOnLaunch)

                    Text("When enabled, HyperFetch checks for newer releases in the background once every 24 hours.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Divider()
                        .padding(.vertical, 2)

                    Picker("Update Channel", selection: $versionManager.updateChannel) {
                        Text("Stable (Recommended)").tag("Stable")
                        Text("Beta / Pre-Release").tag("Beta")
                    }

                    Text("Stable builds receive thoroughly tested features. Beta builds receive early releases.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding(8)
    }
}
