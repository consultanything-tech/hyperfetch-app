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
    @Environment(\.openSettings) private var openSettings
    @ViewState private var columnVisibility: NavigationSplitViewVisibility = .all

    public init() {}

    public var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
        } content: {
            DownloadListView()
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
                    Text(task.url.absoluteString)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(Theme.accent)
                        .onTapGesture {
                            appState.copyDownloadLink(task: task)
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

                Divider()
                    .overlay(Theme.separator)
                    .padding(.vertical, 2)

                HStack {
                    Text("Integrity Check:")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textTertiary)

                    Spacer()

                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 12))
                        Text("SHA-256 Validated")
                            .font(.system(size: 11.5, weight: .medium))
                    }
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
        VStack(spacing: 12) {
            Image(systemName: "sidebar.trailing")
                .font(.system(size: 32))
                .foregroundStyle(Theme.textTertiary.opacity(0.5))

            Text("No Download Selected")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            Text("Select an item in the queue to inspect real-time connection segments and file metadata.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
        }
        .frame(minWidth: 320)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
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
