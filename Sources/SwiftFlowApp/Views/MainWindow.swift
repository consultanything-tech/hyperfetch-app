//
//  MainWindow.swift
//  SwiftFlowApp
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers
import DownloadKit

/// Primary application window structure featuring a 3-column NavigationSplitView and full toolbar.
public struct MainWindow: View {
    @EnvironmentObject private var appState: AppState

    public init() {}

    public var body: some View {
        NavigationSplitView {
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
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                appState.isAddSheetPresented = true
            } label: {
                Label("Add Download", systemImage: "plus")
            }
            .help("Add New Download (⌘N)")
            .keyboardShortcut("n", modifiers: .command)

            Divider()

            Button {
                appState.pauseAll()
            } label: {
                Label("Pause All", systemImage: "pause.circle")
            }
            .help("Pause All Downloads")

            Button {
                appState.resumeAll()
            } label: {
                Label("Resume All", systemImage: "play.circle")
            }
            .help("Resume All Downloads")

            Divider()

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
                Label("Speed Limit", systemImage: "gauge.with.needle")
            }
            .help("Download Speed Limiter")
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

                case .paused, .idle, .failed:
                    Button {
                        appState.resume(id: task.id)
                    } label: {
                        Label("Resume", systemImage: "play.fill")
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
        VStack(alignment: .leading, spacing: 12) {
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
                }

                GridRow {
                    Text("Downloaded:")
                        .foregroundStyle(.secondary)
                    Text("\(AppState.formatBytes(task.downloadedBytes)) (\(Int(task.progress * 100))%)")
                }

                if task.status == .downloading {
                    GridRow {
                        Text("Transfer Speed:")
                            .foregroundStyle(.secondary)
                        Text(AppState.formatSpeed(task.bytesPerSecond))
                            .foregroundStyle(.blue)
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
