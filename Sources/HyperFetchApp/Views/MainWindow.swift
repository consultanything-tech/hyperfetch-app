//
//  MainWindow.swift
//  HyperFetchApp
//
//  Modernized macOS primary application window with Obsidian Sequoia styling,
//  three-column navigation split view, connection inspector, and bottom status telemetry.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers
import DownloadKit

/// Primary application window structure featuring a 3-column NavigationSplitView,
/// modernized inspector pane, and system telemetry status bar.
public struct MainWindow: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var versionManager: AppVersionManager
    @Environment(\.openSettings) private var openSettings
    @ViewState private var columnVisibility: NavigationSplitViewVisibility = .all
    @ViewState private var copiedTaskId: UUID? = nil

    public init() {}

    public var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
        } content: {
            VStack(spacing: 0) {
                if let banner = updateNotificationBanner {
                    banner
                }
                DownloadListView()
            }
            .navigationSplitViewColumnWidth(min: 440, ideal: 580)
        } detail: {
            Group {
                if let task = appState.selectedTask {
                    taskDetailView(for: task)
                } else {
                    noTaskSelectedView
                }
            }
            .navigationSplitViewColumnWidth(min: 320, ideal: 360, max: 440)
        }
        .navigationSplitViewStyle(.balanced)
        .background(Theme.canvasBackground)
        .searchable(text: $appState.searchText, prompt: "Search downloads...")
        .preferredColorScheme(appState.preferredColorScheme)
        .toolbar {
            toolbarContent
        }
        .sheet(isPresented: $appState.isAddSheetPresented) {
            AddDownloadSheet()
        }
        .background {
            keyboardShortcutTriggers
                .allowsHitTesting(false)
        }
        .background {
            WindowAccessor { window in
                MainWindowDelegate.shared.configure(window: window)
            }
            .allowsHitTesting(false)
        }
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            HyperFetchServiceProvider.shared.appState = appState
            appState.openSettingsHandler = { [openSettings] in
                openSettings()
            }
        }
    }

    // MARK: - Update Banner

    private var updateNotificationBanner: AnyView? {
        if case .readyToInstall(let newVersion, let stagedAppURL) = versionManager.state,
           versionManager.isBannerDismissedForVersion != newVersion {
            return AnyView(
                HStack(spacing: 10) {
                    Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                        .foregroundStyle(Theme.accent)
                        .font(.system(size: 14, weight: .semibold))

                    Text("HyperFetch v\(newVersion) is downloaded and ready to install.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)

                    Spacer()

                    Button("Later") {
                        versionManager.isBannerDismissedForVersion = newVersion
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Theme.textSecondary)

                    Button("Restart & Launch") {
                        versionManager.installAndRelaunch(stagedAppURL: stagedAppURL)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Theme.accent.opacity(0.12))
                .overlay(
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(Theme.accent.opacity(0.3)),
                    alignment: .bottom
                )
            )
        } else if case .updateAvailable(let newVersion, _, _, _, _) = versionManager.state,
                  versionManager.isBannerDismissedForVersion != newVersion {
            return AnyView(
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(Color.orange)
                        .font(.system(size: 14, weight: .semibold))

                    Text("HyperFetch v\(newVersion) is available.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)

                    Spacer()

                    Button("Dismiss") {
                        versionManager.isBannerDismissedForVersion = newVersion
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Theme.textSecondary)

                    Button("Update Now") {
                        versionManager.isUpdateSheetPresented = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .controlSize(.small)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.12))
                .overlay(
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(Color.orange.opacity(0.3)),
                    alignment: .bottom
                )
            )
        }
        return nil
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            // Prominent Add Download button
            Button {
                appState.isAddSheetPresented = true
            } label: {
                Label("Add Download", systemImage: "plus")
            }
            .help("Add New Download (⌘N)")
            .keyboardShortcut("n", modifiers: .command)

            // Pause All / Resume All grouped
            ControlGroup {
                Button {
                    appState.pauseAll()
                } label: {
                    Label("Pause All", systemImage: "pause.fill")
                }
                .help("Pause All Downloads")
                .disabled(appState.activeDownloadCount == 0)

                Button {
                    appState.resumeAll()
                } label: {
                    Label("Resume All", systemImage: "play.fill")
                }
                .help("Resume All Downloads")
                .disabled(appState.pausedDownloadCount == 0)
            }

            // Speed Limit picker
            Menu {
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
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "gauge.with.needle.fill")
                        .foregroundStyle(appState.speedLimitPreset == .unlimited ? Theme.textSecondary : Theme.warning)
                    Text(appState.speedLimitPreset == .unlimited ? "Speed Limit" : appState.speedLimitPreset.rawValue)
                        .font(.system(size: 12))
                }
            }
            .help("Bandwidth Throttling / Speed Limiter")

            // Sort Menu
            Menu {
                ForEach(SortOption.allCases) { option in
                    Button {
                        appState.sortOption = option
                    } label: {
                        HStack {
                            Text(option.rawValue)
                            if appState.sortOption == option {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            .help("Sort Downloads By (\(appState.sortOption.rawValue))")

            // View Mode Segmented Picker
            Picker("View Mode", selection: $appState.viewMode) {
                Image(systemName: "rectangle.grid.1x2")
                    .tag(DownloadListViewMode.comfortable)
                    .help("Default Card View")
                Image(systemName: "list.bullet")
                    .tag(DownloadListViewMode.compact)
                    .help("Compact List View")
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .help("Switch View Style (Comfortable / Compact)")

            // Batch Actions for Selected Items
            if !appState.selectedTaskIDs.isEmpty {
                Menu {
                    Button("Pause Selected (\(appState.selectedTasks.count))") {
                        appState.pauseSelected()
                    }
                    .disabled(!appState.hasActiveSelectedTasks)

                    Button("Resume Selected (\(appState.selectedTasks.count))") {
                        appState.resumeSelected()
                    }
                    .disabled(!appState.hasResumableSelectedTasks)

                    Divider()

                    Button("Show in Finder") {
                        appState.revealSelectedInFinder()
                    }

                    Button("Remove Selected from List", role: .destructive) {
                        appState.removeSelected(deleteFile: false)
                    }

                    Button("Delete Selected Files from Disk...", role: .destructive) {
                        appState.promptDeleteSelected()
                    }

                    Divider()

                    Button("Deselect All") {
                        appState.deselectAll()
                    }
                } label: {
                    Label("Selected (\(appState.selectedTasks.count))", systemImage: "checklist")
                }
                .help("Batch Actions for \(appState.selectedTasks.count) Selected Downloads")
            }

            // Appearance Mode Menu
            Menu {
                ForEach(AppearanceMode.allCases) { mode in
                    Button {
                        appState.appearanceMode = mode
                    } label: {
                        HStack {
                            Label(mode.rawValue, systemImage: mode.iconName)
                            if appState.appearanceMode == mode {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: appState.appearanceMode == .dark ? "moon.fill" : (appState.appearanceMode == .light ? "sun.max.fill" : "circle.righthalf.filled"))
            }
            .help("Appearance: \(appState.appearanceMode.rawValue)")

            // Inspector toggle button
            Button {
                MainWindowDelegate.shared.toggleDetailPane()
            } label: {
                Image(systemName: "sidebar.trailing")
            }
            .help("Toggle Details Inspector (⌘I)")
            .keyboardShortcut("i", modifiers: .command)
        }
    }

    // MARK: - Keyboard Shortcuts

    @ViewBuilder
    private var keyboardShortcutTriggers: some View {
        Group {
            Button("Select All") {
                appState.selectAll()
            }
            .keyboardShortcut("a", modifiers: .command)

            Button("Deselect All") {
                appState.deselectAll()
            }
            .keyboardShortcut(.escape, modifiers: [])

            Button("Select Next") {
                appState.selectNextTask()
            }
            .keyboardShortcut(.downArrow, modifiers: [])

            Button("Select Previous") {
                appState.selectPreviousTask()
            }
            .keyboardShortcut(.upArrow, modifiers: [])

            Button("Toggle Pause") {
                appState.togglePauseSelected()
            }
            .keyboardShortcut(.space, modifiers: [])

            Button("Delete Selected") {
                appState.promptDeleteSelected()
            }
            .keyboardShortcut(.delete, modifiers: [])

            Button("Reveal in Finder") {
                appState.revealSelectedInFinder()
            }
            .keyboardShortcut("r", modifiers: .command)

            Button("Open Completed") {
                appState.openSelectedFile()
            }
            .keyboardShortcut("o", modifiers: .command)
        }
        .opacity(0)
        .allowsHitTesting(false)
        .frame(width: 0, height: 0)
    }

    // MARK: - Detail Inspector Pane

    private func taskDetailView(for task: DownloadTaskModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Inspector Selected Header
                inspectorSelectedHeader(for: task)

                Divider()
                    .overlay(Theme.separator)

                // Multi-chunk visualizer
                ChunkVisualizer(task: task)

                Divider()
                    .overlay(Theme.separator)

                // Information & Metadata Card
                taskMetadataCard(for: task)

                // Error diagnostics if failed
                if case .failed(let reason) = task.status {
                    errorDiagnosticsCard(reason: reason, task: task)
                }
            }
            .padding(18)
        }
        .frame(minWidth: 320)
        .background(Theme.inspectorBackground)
    }

    private func inspectorSelectedHeader(for task: DownloadTaskModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Top Section Title and Quick Actions
            HStack {
                Text("Download Inspector")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .textCase(.uppercase)
                    .tracking(0.6)

                Spacer()

                HStack(spacing: 4) {
                    if task.status == .downloading || task.status == .probing {
                        Button {
                            appState.pause(id: task.id)
                        } label: {
                            Image(systemName: "pause.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.textSecondary)
                                .frame(width: 24, height: 24)
                                .background(Theme.tagBackground, in: RoundedRectangle(cornerRadius: 5))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                        .help("Pause")
                    } else if isResumable(task.status) {
                        Button {
                            appState.resume(id: task.id)
                        } label: {
                            Image(systemName: "play.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.accent)
                                .frame(width: 24, height: 24)
                                .background(Theme.tagBackground, in: RoundedRectangle(cornerRadius: 5))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                        .help("Resume")
                    }

                    Button {
                        appState.openInFinder(task: task)
                    } label: {
                        Image(systemName: "folder")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(width: 24, height: 24)
                            .background(Theme.tagBackground, in: RoundedRectangle(cornerRadius: 5))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .help("Show in Finder")

                    if task.status == .completed {
                        Button {
                            appState.openFile(task: task)
                        } label: {
                            Image(systemName: "arrow.up.forward.app")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.accent)
                                .frame(width: 24, height: 24)
                                .background(Theme.tagBackground, in: RoundedRectangle(cornerRadius: 5))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                        .help("Open File")
                    }
                }
            }

            // File Icon & Title with Tech Badges
            HStack(alignment: .top, spacing: 12) {
                let ext = (task.filename as NSString).pathExtension
                let style = Theme.fileBadge(for: ext)

                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(style.gradientTop.opacity(0.8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(style.borderColor, lineWidth: 1)
                        )
                        .frame(width: 42, height: 42)

                    Image(systemName: style.systemIcon)
                        .font(.system(size: 18))
                        .foregroundStyle(style.tintColor)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(task.filename)
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                        .truncationMode(.middle)

                    HStack(spacing: 6) {
                        let chunkCount = task.chunks.isEmpty ? (task.preferredChunkCount ?? 4) : task.chunks.count
                        Text("\(chunkCount) Chunks")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))

                        Text(task.supportsRange ? "HTTP/2" : "HTTP/1.1")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.success)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.success.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))

                        Text("TLS 1.3")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }
        }
        .padding(14)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusLarge, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadiusLarge, style: .continuous)
                .stroke(Theme.cardBorder, lineWidth: 1)
        )
    }

    private func taskMetadataCard(for task: DownloadTaskModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)

                Text("File Information")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .textCase(.uppercase)
                    .tracking(0.5)
            }

            VStack(spacing: 8) {
                metadataRow(label: "Source URL:") {
                    HStack(spacing: 5) {
                        Text(task.url.absoluteString)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(Theme.accent)

                        Button {
                            appState.copyDownloadLink(task: task)
                            withAnimation(.easeOut(duration: 0.15)) {
                                copiedTaskId = task.id
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                withAnimation(.easeIn(duration: 0.15)) {
                                    if copiedTaskId == task.id {
                                        copiedTaskId = nil
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: copiedTaskId == task.id ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 10))
                                .foregroundStyle(copiedTaskId == task.id ? Theme.success : Theme.textTertiary)
                        }
                        .buttonStyle(.tactile)
                        .help("Copy Source URL")
                    }
                }

                metadataRow(label: "Save Path:") {
                    Text(task.destinationURL.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(Theme.textPrimary)
                }

                metadataRow(label: "File Size:") {
                    let exactBytes = task.totalBytes > 0 ? " (\(task.totalBytes.formatted()) bytes)" : ""
                    Text("\(AppState.formatBytes(task.totalBytes))\(exactBytes)")
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(Theme.textPrimary)
                }

                metadataRow(label: "Downloaded:") {
                    let percent = Int(task.progress * 100)
                    Text("\(AppState.formatBytes(task.downloadedBytes)) (\(percent)%)")
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(Theme.textPrimary)
                }

                if task.status == .downloading {
                    metadataRow(label: "Transfer Speed:") {
                        Text(AppState.formatSpeed(task.bytesPerSecond))
                            .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.success)
                    }
                }

                metadataRow(label: "Date Added:") {
                    Text(task.createdAt, style: .date)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textSecondary)
                }

                if let completedAt = task.completedAt {
                    metadataRow(label: "Completed At:") {
                        Text(completedAt, style: .date)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
        .padding(14)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusLarge, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadiusLarge, style: .continuous)
                .stroke(Theme.cardBorder, lineWidth: 1)
        )
    }

    private func metadataRow<V: View>(label: String, @ViewBuilder value: () -> V) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 95, alignment: .leading)

            Spacer()

            value()
                .font(.system(size: 11.5))
                .frame(maxWidth: 220, alignment: .trailing)
        }
    }

    private func errorDiagnosticsCard(reason: String, task: DownloadTaskModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.octagon.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.critical)

                Text("Error Diagnostics")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.critical)

                Spacer()
            }

            Text(reason)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.canvasBackground, in: RoundedRectangle(cornerRadius: 6))

            HStack(spacing: 8) {
                Button {
                    appState.resume(id: task.id)
                } label: {
                    Label("Retry Download", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.critical)
                .controlSize(.small)

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(reason, forType: .string)
                } label: {
                    Label("Copy Error", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(Theme.critical.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.cornerRadiusLarge))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadiusLarge)
                .stroke(Theme.critical.opacity(0.25), lineWidth: 1)
        )
    }

    private func isResumable(_ status: DownloadStatus) -> Bool {
        switch status {
        case .paused, .idle, .failed:
            return true
        default:
            return false
        }
    }

    private var noTaskSelectedView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Theme.accent.opacity(0.12))
                            .frame(width: 32, height: 32)
                        Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                            .font(.system(size: 16))
                            .foregroundStyle(Theme.accent)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Queue Telemetry")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Live Aggregate Monitor")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.textTertiary)
                    }

                    Spacer()
                }
                .padding(12)
                .background(Theme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusLarge, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cornerRadiusLarge, style: .continuous)
                        .stroke(Theme.cardBorder, lineWidth: 1)
                )

                // Network & Concurrency
                VStack(alignment: .leading, spacing: 10) {
                    Text("Performance")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                        .textCase(.uppercase)
                        .tracking(0.5)

                    VStack(spacing: 8) {
                        metadataRow(label: "Current Speed:") {
                            Text(appState.formattedTotalSpeed)
                                .font(.system(size: 12.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(appState.totalDownloadSpeed > 0 ? Theme.success : Theme.textSecondary)
                        }

                        metadataRow(label: "Active Sockets:") {
                            Text("\(appState.activeSocketCount) open")
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(Theme.textPrimary)
                        }

                        metadataRow(label: "Engine Memory:") {
                            Text("\(appState.allocatedMemoryMB) MB")
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(Theme.textPrimary)
                        }

                        metadataRow(label: "Bandwidth Cap:") {
                            Text(appState.speedLimitPreset.rawValue)
                                .font(.system(size: 11.5))
                                .foregroundStyle(appState.speedLimitPreset == .unlimited ? Theme.success : Theme.warning)
                        }
                    }
                }
                .padding(14)
                .background(Theme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusLarge, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cornerRadiusLarge, style: .continuous)
                        .stroke(Theme.cardBorder, lineWidth: 1)
                )

                // Queue Status
                VStack(alignment: .leading, spacing: 10) {
                    Text("Queue Status")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                        .textCase(.uppercase)
                        .tracking(0.5)

                    VStack(spacing: 8) {
                        metadataRow(label: "Total Items:") {
                            Text("\(appState.tasks.count)")
                                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Theme.textPrimary)
                        }

                        metadataRow(label: "Downloading:") {
                            Text("\(appState.activeDownloadCount)")
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(Theme.accent)
                        }

                        metadataRow(label: "Completed:") {
                            Text("\(appState.completedDownloadCount)")
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(Theme.success)
                        }

                        metadataRow(label: "Paused:") {
                            Text("\(appState.pausedDownloadCount)")
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(Theme.warning)
                        }
                    }
                }
                .padding(14)
                .background(Theme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusLarge, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cornerRadiusLarge, style: .continuous)
                        .stroke(Theme.cardBorder, lineWidth: 1)
                )

                // Storage
                VStack(alignment: .leading, spacing: 10) {
                    Text("Storage")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                        .textCase(.uppercase)
                        .tracking(0.5)

                    VStack(spacing: 8) {
                        metadataRow(label: "Today's Total:") {
                            Text(appState.formattedTotalDownloadedToday)
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(Theme.textPrimary)
                        }

                        metadataRow(label: "Disk Free:") {
                            Text(appState.availableDiskSpaceString)
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(Theme.success)
                        }
                    }
                }
                .padding(14)
                .background(Theme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusLarge, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cornerRadiusLarge, style: .continuous)
                        .stroke(Theme.cardBorder, lineWidth: 1)
                )

                // Helper note
                HStack(spacing: 8) {
                    Image(systemName: "hand.tap")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                    Text("Select any download to inspect live multi-stream chunk progress and HTTP connection headers.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(.horizontal, 4)
            }
            .padding(16)
        }
        .frame(minWidth: 320)
        .background(Theme.inspectorBackground)
    }
}

// MARK: - Window Accessor

struct WindowAccessor: NSViewRepresentable {
    let callback: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                callback(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Window configuration is handled once in makeNSView to avoid redundant calls on SwiftUI redraws.
    }
}
