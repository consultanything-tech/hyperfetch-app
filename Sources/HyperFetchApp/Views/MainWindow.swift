//
//  MainWindow.swift
//  HyperFetchApp
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers
import DownloadKit

/// Primary application window structure featuring a 3-column NavigationSplitView and full toolbar.
public struct MainWindow: View {
    @EnvironmentObject private var appState: AppState
    @ViewState private var columnVisibility: NavigationSplitViewVisibility = .all

    public init() {}

    public var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } content: {
            DownloadListView()
                .navigationSplitViewColumnWidth(min: 340, ideal: 440)
        } detail: {
            if let task = appState.selectedTask {
                taskDetailView(for: task)
            } else {
                noTaskSelectedView
            }
        }
        .searchable(text: $appState.searchText, prompt: "Search downloads...")
        .toolbar {
            toolbarContent
        }
        .sheet(isPresented: $appState.isAddSheetPresented) {
            AddDownloadSheet()
        }
        .background {
            keyboardShortcutTriggers
        }
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
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

            // Pause All / Resume All grouped nicely
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

            // Speed Limit picker styled with speed indicator
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
                        .foregroundStyle(appState.speedLimitPreset == .unlimited ? Color.secondary : Color.orange)
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

            // Inspector toggle button
            Button {
                toggleDetailPane()
            } label: {
                Image(systemName: "sidebar.trailing")
            }
            .help("Toggle Details Inspector")
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

    private func toggleDetailPane() {
        withAnimation(.easeInOut(duration: 0.2)) {
            if columnVisibility == .all {
                columnVisibility = .doubleColumn
            } else {
                columnVisibility = .all
            }
        }
    }

    // MARK: - Detail Pane

    private func taskDetailView(for task: DownloadTaskModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Top Header Card
                taskHeaderCard(for: task)

                Divider()

                // Multi-chunk visualizer
                ChunkVisualizer(task: task)

                Divider()

                // Information & Metadata Card
                taskMetadataCard(for: task)
            }
            .padding(20)
        }
    }

    private func taskHeaderCard(for task: DownloadTaskModel) -> some View {
        HStack(alignment: .top, spacing: 14) {
            let ext = (task.filename as NSString).pathExtension
            let utType = UTType(filenameExtension: ext) ?? .data
            Image(nsImage: NSWorkspace.shared.icon(for: utType))
                .resizable()
                .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text(task.filename)
                    .font(.title3.bold())
                    .lineLimit(2)
                    .truncationMode(.middle)

                HStack(spacing: 8) {
                    Text(task.category.rawValue)
                        .font(.caption.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))

                    if task.supportsRange {
                        Label("Multi-Chunk Accelerated", systemImage: "bolt.fill")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }
            }

            Spacer()

            // Header Action Buttons
            HStack(spacing: 8) {
                switch task.status {
                case .downloading, .probing:
                    Button {
                        appState.pause(id: task.id)
                    } label: {
                        Label("Pause", systemImage: "pause.fill")
                    }

                case .paused, .idle:
                    Button {
                        appState.resume(id: task.id)
                    } label: {
                        Label("Resume", systemImage: "play.fill")
                    }

                case .failed:
                    Button {
                        appState.resume(id: task.id)
                    } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                    }

                case .completed:
                    Button {
                        appState.openFile(task: task)
                    } label: {
                        Label("Open", systemImage: "arrow.up.forward.app")
                    }
                }

                Button {
                    appState.openInFinder(task: task)
                } label: {
                    Label("Finder", systemImage: "folder")
                }
            }
        }
    }

    private func taskMetadataCard(for task: DownloadTaskModel) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Error Diagnostics section if task has failed
            if case .failed(let reason) = task.status {
                errorDiagnosticsCard(reason: reason, task: task)
            }

            Text("File Information")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    Text("Source URL:")
                        .foregroundStyle(.secondary)
                    Text(task.url.absoluteString)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }

                GridRow {
                    Text("Save Path:")
                        .foregroundStyle(.secondary)
                    Text(task.destinationURL.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }

                GridRow {
                    Text("File Size:")
                        .foregroundStyle(.secondary)
                    Text(AppState.formatBytes(task.totalBytes))
                        .monospacedDigit()
                }

                GridRow {
                    Text("Downloaded:")
                        .foregroundStyle(.secondary)
                    Text("\(AppState.formatBytes(task.downloadedBytes)) (\(Int(task.progress * 100))%)")
                        .monospacedDigit()
                }

                if task.status == .downloading {
                    GridRow {
                        Text("Transfer Speed:")
                            .foregroundStyle(.secondary)
                        Text(AppState.formatSpeed(task.bytesPerSecond))
                            .foregroundStyle(.blue)
                            .monospacedDigit()
                    }
                }

                GridRow {
                    Text("Date Added:")
                        .foregroundStyle(.secondary)
                    Text(task.createdAt, style: .date)
                }

                if let completedAt = task.completedAt {
                    GridRow {
                        Text("Completed At:")
                            .foregroundStyle(.secondary)
                        Text(completedAt, style: .date)
                    }
                }
            }
            .font(.callout)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private func errorDiagnosticsCard(reason: String, task: DownloadTaskModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.octagon.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.red)

                Text("Error Diagnostics")
                    .font(.headline)
                    .foregroundStyle(.red)

                Spacer()
            }

            Text(reason)
                .font(.callout)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 6))

            HStack(spacing: 10) {
                Button {
                    appState.resume(id: task.id)
                } label: {
                    Label("Retry Download", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(reason, forType: .string)
                } label: {
                    Label("Copy Error", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.red.opacity(0.25), lineWidth: 1)
        )
    }

    private var noTaskSelectedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.split.3x1")
                .font(.system(size: 44))
                .foregroundStyle(.secondary.opacity(0.4))

            Text("No Download Selected")
                .font(.headline)

            Text("Select an item in the list to view its real-time chunk visualization and file details.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}
