//
//  DownloadListView.swift
//  HyperFetchApp
//

import SwiftUI
import UniformTypeIdentifiers
import DownloadKit

/// Main list displaying filtered download tasks with context menus and empty state handling.
public struct DownloadListView: View {
    @EnvironmentObject private var appState: AppState

    public init() {}

    public var body: some View {
        Group {
            if appState.filteredTasks.isEmpty {
                emptyStateView
            } else {
                VStack(spacing: 0) {
                    selectionActionBar
                    Divider()
                    taskListView
                }
            }
        }
        .onDrop(of: [.url, .utf8PlainText], isTargeted: nil) { providers in
            handleDrop(providers: providers)
        }
        .confirmationDialog(
            "Delete Download?",
            isPresented: $appState.showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove from List", role: .destructive) {
                if !appState.tasksPendingDeletion.isEmpty {
                    for task in appState.tasksPendingDeletion {
                        appState.remove(id: task.id, deleteFile: false)
                    }
                    appState.tasksPendingDeletion = []
                    appState.taskPendingDeletion = nil
                } else if let task = appState.taskPendingDeletion {
                    appState.remove(id: task.id, deleteFile: false)
                    appState.taskPendingDeletion = nil
                }
            }
            Button("Delete File from Disk", role: .destructive) {
                if !appState.tasksPendingDeletion.isEmpty {
                    for task in appState.tasksPendingDeletion {
                        appState.remove(id: task.id, deleteFile: true)
                    }
                    appState.tasksPendingDeletion = []
                    appState.taskPendingDeletion = nil
                } else if let task = appState.taskPendingDeletion {
                    appState.remove(id: task.id, deleteFile: true)
                    appState.taskPendingDeletion = nil
                }
            }
            Button("Cancel", role: .cancel) {
                appState.tasksPendingDeletion = []
                appState.taskPendingDeletion = nil
            }
        } message: {
            if appState.tasksPendingDeletion.count > 1 {
                Text("Are you sure you want to remove \(appState.tasksPendingDeletion.count) downloads?")
            } else if let task = appState.tasksPendingDeletion.first ?? appState.taskPendingDeletion {
                Text("Are you sure you want to remove '\(task.filename)'?")
            } else {
                Text("Are you sure you want to remove the selected downloads?")
            }
        }
    }

    // MARK: - Drag and Drop Handler

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                _ = provider.loadObject(ofClass: NSURL.self) { item, _ in
                    if let url = item as? URL,
                       let scheme = url.scheme?.lowercased(),
                       scheme == "http" || scheme == "https" {
                        Task { @MainActor in
                            appState.presentAddSheet(url: url.absoluteString)
                        }
                    }
                }
                return true
            } else if provider.hasItemConformingToTypeIdentifier(UTType.utf8PlainText.identifier) {
                _ = provider.loadObject(ofClass: NSString.self) { item, _ in
                    guard let text = (item as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                          let url = URL(string: text),
                          let scheme = url.scheme?.lowercased(),
                          scheme == "http" || scheme == "https" else {
                        return
                    }
                    Task { @MainActor in
                        appState.presentAddSheet(url: url.absoluteString)
                    }
                }
                return true
            }
        }
        return false
    }

    // MARK: - Subviews

    // MARK: - Selection & Batch Action Bar

    private var selectionActionBar: some View {
        HStack(spacing: 12) {
            // Left Side: Select All Checkbox & Selection Status
            HStack(spacing: 8) {
                Button {
                    appState.toggleSelectAll()
                } label: {
                    Image(systemName: selectAllCheckboxIcon)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(selectAllCheckboxColor)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(appState.isAllSelected ? "Deselect All (Esc)" : "Select All (⌘A)")

                Button {
                    appState.toggleSelectAll()
                } label: {
                    if appState.selectedTaskIDs.isEmpty {
                        Text("Select All (\(appState.filteredTasks.count))")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(appState.selectedTasks.count) of \(appState.filteredTasks.count) selected")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                }
                .buttonStyle(.plain)
                .help(appState.isAllSelected ? "Deselect All (Esc)" : "Select All (⌘A)")
            }

            Spacer()

            // Right Side: Batch Action Controls
            if !appState.selectedTaskIDs.isEmpty {
                batchActionControls
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var selectAllCheckboxIcon: String {
        if appState.isAllSelected {
            return "checkmark.square.fill"
        } else if appState.isPartiallySelected {
            return "minus.square.fill"
        } else {
            return "square"
        }
    }

    private var selectAllCheckboxColor: Color {
        if appState.isAllSelected || appState.isPartiallySelected {
            return .accentColor
        } else {
            return .secondary
        }
    }

    @ViewBuilder
    private var batchActionControls: some View {
        ViewThatFits(in: .horizontal) {
            fullBatchActionControls
            compactBatchActionControls
        }
        .animation(.easeInOut(duration: 0.15), value: appState.selectedTaskIDs.isEmpty)
    }

    private var fullBatchActionControls: some View {
        HStack(spacing: 6) {
            Button {
                appState.pauseSelected()
            } label: {
                Label("Pause", systemImage: "pause.fill")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!hasActiveSelectedTasks)
            .help("Pause selected downloads")

            Button {
                appState.resumeSelected()
            } label: {
                Label("Resume", systemImage: "play.fill")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!hasResumableSelectedTasks)
            .help("Resume selected downloads")

            Button {
                appState.removeSelected(deleteFile: false)
            } label: {
                Label("Remove", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Remove selected downloads from list")

            Button(role: .destructive) {
                appState.promptDeleteSelected()
            } label: {
                Label("Delete...", systemImage: "trash.fill")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Delete selected downloads and files from disk...")

            Button {
                appState.deselectAll()
            } label: {
                Text("Deselect")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .foregroundStyle(.secondary)
            .help("Clear selection (Esc)")
        }
    }

    private var compactBatchActionControls: some View {
        HStack(spacing: 4) {
            Button {
                appState.pauseSelected()
            } label: {
                Image(systemName: "pause.fill")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!hasActiveSelectedTasks)
            .help("Pause selected downloads")

            Button {
                appState.resumeSelected()
            } label: {
                Image(systemName: "play.fill")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!hasResumableSelectedTasks)
            .help("Resume selected downloads")

            Button {
                appState.removeSelected(deleteFile: false)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Remove selected from list")

            Button(role: .destructive) {
                appState.promptDeleteSelected()
            } label: {
                Image(systemName: "trash.fill")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Delete selected from disk...")

            Button {
                appState.deselectAll()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .foregroundStyle(.secondary)
            .help("Clear selection (Esc)")
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 84, height: 84)

                Image(systemName: emptyStateIcon)
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(spacing: 6) {
                Text(emptyStateTitle)
                    .font(.title3.bold())

                Text(emptyStateSubtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }

            Button {
                appState.isAddSheetPresented = true
            } label: {
                Label("Add Download", systemImage: "plus")
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut("n", modifiers: .command)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private var taskListView: some View {
        List(selection: $appState.selectedTaskIDs) {
            ForEach(appState.filteredTasks) { task in
                DownloadRowView(task: task)
                    .tag(task.id)
                    .contextMenu {
                        rowContextMenu(for: task)
                    }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    @ViewBuilder
    private func rowContextMenu(for task: DownloadTaskModel) -> some View {
        let isMulti = appState.selectedTaskIDs.contains(task.id) && appState.selectedTaskIDs.count > 1
        if isMulti {
            multiRowContextMenu
        } else {
            singleRowContextMenu(for: task)
        }
    }

    @ViewBuilder
    private var multiRowContextMenu: some View {
        let count = appState.selectedTasks.count
        Button("Pause Selected (\(count))") {
            appState.pauseSelected()
        }
        .disabled(!hasActiveSelectedTasks)

        Button("Resume Selected (\(count))") {
            appState.resumeSelected()
        }
        .disabled(!hasResumableSelectedTasks)

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
    }

    private var hasActiveSelectedTasks: Bool {
        appState.selectedTasks.contains { $0.status == .downloading || $0.status == .probing }
    }

    private var hasResumableSelectedTasks: Bool {
        appState.selectedTasks.contains { task in
            switch task.status {
            case .paused, .idle, .failed:
                return true
            case .downloading, .probing, .completed:
                return false
            }
        }
    }

    @ViewBuilder
    private func singleRowContextMenu(for task: DownloadTaskModel) -> some View {
        switch task.status {
        case .downloading, .probing:
            Button("Pause Download") {
                appState.pause(id: task.id)
            }
        case .paused, .idle, .failed:
            Button("Resume Download") {
                appState.resume(id: task.id)
            }
        case .completed:
            Button("Open File") {
                appState.openFile(task: task)
            }
        }

        Button("Show in Finder") {
            appState.openInFinder(task: task)
        }

        Button("Copy Download Link") {
            appState.copyDownloadLink(task: task)
        }

        Divider()

        Button("Remove from List", role: .destructive) {
            appState.remove(id: task.id, deleteFile: false)
        }

        Button("Delete File from Disk...", role: .destructive) {
            appState.promptDelete(task: task)
        }
    }

    private var emptyStateIcon: String {
        if !appState.searchText.isEmpty {
            return "magnifyingglass"
        }
        if case .category(let category) = appState.sidebarSelection {
            switch category {
            case .all:
                return "tray"
            case .archives:
                return "archivebox"
            case .documents:
                return "doc.text"
            case .video:
                return "film"
            case .music:
                return "music.note"
            case .applications:
                return "app"
            case .other:
                return "questionmark.folder"
            }
        }
        let filter: StatusFilter = if case .status(let f) = appState.sidebarSelection { f } else { .all }
        switch filter {
        case .all:
            return "arrow.down.circle"
        case .active:
            return "arrow.down.circle.fill"
        case .completed:
            return "checkmark.circle"
        case .paused:
            return "pause.circle"
        case .failed:
            return "exclamationmark.circle"
        }
    }

    private var emptyStateTitle: String {
        if !appState.searchText.isEmpty {
            return "No Results Found"
        }
        if case .category(let category) = appState.sidebarSelection {
            return "No \(category.rawValue) Downloads"
        }
        let filter: StatusFilter = if case .status(let f) = appState.sidebarSelection { f } else { .all }
        switch filter {
        case .all:
            return "No Downloads Yet"
        case .active:
            return "No Active Downloads"
        case .completed:
            return "No Completed Downloads"
        case .paused:
            return "No Paused Downloads"
        case .failed:
            return "No Failed Downloads"
        }
    }

    private var emptyStateSubtitle: String {
        if !appState.searchText.isEmpty {
            return "No downloads match your query '\(appState.searchText)'."
        }
        if case .category(let category) = appState.sidebarSelection {
            return "Downloaded files categorized as \(category.rawValue) will appear here."
        }
        let filter: StatusFilter = if case .status(let f) = appState.sidebarSelection { f } else { .all }
        switch filter {
        case .all:
            return "Add a file URL or copy a download link to get started with multi-chunk acceleration."
        case .active:
            return "There are no downloads currently in progress."
        case .completed:
            return "Downloaded files will appear here once finished."
        case .paused:
            return "Paused downloads will appear here."
        case .failed:
            return "No failed download attempts recorded."
        }
    }
}
