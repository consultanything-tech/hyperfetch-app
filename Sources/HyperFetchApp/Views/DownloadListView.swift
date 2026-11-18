//
//  DownloadListView.swift
//  HyperFetchApp
//
//  Modernized card list displaying accelerated downloads with selection toolbar,
//  rich batch actions, and Obsidian Sequoia styling.
//

import SwiftUI
import UniformTypeIdentifiers
import DownloadKit

/// Main list displaying filtered download tasks as cards with toolbar controls and empty state handling.
public struct DownloadListView: View {
    @EnvironmentObject private var appState: AppState
    @ViewState private var isDropTargeted: Bool = false

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            if !appState.selectedTaskIDs.isEmpty {
                floatingSelectionBar
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Theme.cardBackground)
                    .overlay(Divider().overlay(Theme.separator), alignment: .bottom)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Main Content Area
            if appState.filteredTasks.isEmpty {
                emptyStateView
            } else {
                taskCardsScrollView
            }

            Divider()
                .overlay(Theme.separator)

            // Bottom Engine Status Telemetry Bar
            queueBottomStatusBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        .onDrop(of: [.url, .utf8PlainText], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
        }
        .overlay {
            if isDropTargeted {
                dragDropTargetOverlay
            }
        }
        .confirmationDialog(
            "Delete Download?",
            isPresented: $appState.showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove from List", role: .destructive) {
                appState.confirmDelete(deleteFile: false)
            }
            Button("Delete File from Disk", role: .destructive) {
                appState.confirmDelete(deleteFile: true)
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

    // MARK: - Floating Selection & Batch Action Accessory

    private var floatingSelectionBar: some View {
        HStack(spacing: 10) {
            // Checkbox and selection count
            Button {
                appState.toggleSelectAll()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: appState.isAllSelected ? "checkmark.circle.fill" : "circle.inset.filled")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.accent)

                    Text("\(appState.selectedTasks.count) selected")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                }
            }
            .buttonStyle(.plain)

            Divider()
                .frame(height: 14)
                .overlay(Theme.separator)

            // Batch action buttons
            HStack(spacing: 6) {
                Button {
                    appState.pauseSelected()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 10))
                        Text("Pause")
                    }
                    .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!appState.hasActiveSelectedTasks)
                .help("Pause selected downloads")

                Button {
                    appState.resumeSelected()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10))
                        Text("Resume")
                    }
                    .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!appState.hasResumableSelectedTasks)
                .help("Resume selected downloads")

                Button {
                    appState.revealSelectedInFinder()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                            .font(.system(size: 10))
                        Text("Finder")
                    }
                    .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Show selected in Finder")

                Divider()
                    .frame(height: 12)
                    .overlay(Theme.separator)
                    .padding(.horizontal, 2)

                Button(role: .destructive) {
                    appState.promptDeleteSelected()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                        Text("Delete")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.critical)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Delete selected downloads from disk...")

                Button {
                    appState.deselectAll()
                } label: {
                    Text("Done")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .padding(.leading, 4)
                .help("Clear selection (Esc)")
            }

            Spacer()
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: appState.selectedTaskIDs.count)
    }

    // MARK: - Task Cards ScrollView

    private var taskCardsScrollView: some View {
        ScrollView(.vertical, showsIndicators: true) {
            if appState.viewMode == .compact {
                LazyVStack(spacing: 2) {
                    ForEach(appState.filteredTasks) { task in
                        CompactDownloadRowView(task: task)
                            .id(task.id)
                            .contextMenu {
                                rowContextMenu(for: task)
                            }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(appState.filteredTasks) { task in
                        DownloadRowView(task: task)
                            .id(task.id)
                            .contextMenu {
                                rowContextMenu(for: task)
                            }
                    }
                }
                .padding(16)
            }
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: - Context Menus

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
            DispatchQueue.main.async {
                appState.pauseSelected()
            }
        }
        .disabled(!appState.hasActiveSelectedTasks)

        Button("Resume Selected (\(count))") {
            DispatchQueue.main.async {
                appState.resumeSelected()
            }
        }
        .disabled(!appState.hasResumableSelectedTasks)

        Divider()

        Button("Show in Finder") {
            DispatchQueue.main.async {
                appState.revealSelectedInFinder()
            }
        }

        Button("Remove Selected from List", role: .destructive) {
            DispatchQueue.main.async {
                appState.removeSelected(deleteFile: false)
            }
        }

        Button("Delete Selected Files from Disk...", role: .destructive) {
            DispatchQueue.main.async {
                appState.promptDeleteSelected()
            }
        }
    }

    @ViewBuilder
    private func singleRowContextMenu(for task: DownloadTaskModel) -> some View {
        switch task.status {
        case .downloading, .probing:
            Button("Pause Download") {
                DispatchQueue.main.async {
                    appState.pause(id: task.id)
                }
            }
        case .paused, .idle, .failed:
            Button("Resume Download") {
                DispatchQueue.main.async {
                    appState.resume(id: task.id)
                }
            }
        case .completed:
            Button("Open File") {
                DispatchQueue.main.async {
                    appState.openFile(task: task)
                }
            }
        }

        Button("Show in Finder") {
            DispatchQueue.main.async {
                appState.openInFinder(task: task)
            }
        }

        if task.status == .completed {
            Button("Quick Look File") {
                DispatchQueue.main.async {
                    appState.quickLookFile(task: task)
                }
            }
        }

        Button("Copy Download Link") {
            DispatchQueue.main.async {
                appState.copyDownloadLink(task: task)
            }
        }

        Button("Copy File Path") {
            DispatchQueue.main.async {
                appState.copyFilePath(task: task)
            }
        }

        Button("Restart Download") {
            DispatchQueue.main.async {
                appState.restartTask(id: task.id)
            }
        }

        Divider()

        Menu {
            let taskIndex = appState.tasks.firstIndex(where: { $0.id == task.id })
            let isFirst = taskIndex == 0
            let isLast = taskIndex == (appState.tasks.count - 1)

            Button {
                DispatchQueue.main.async {
                    appState.moveTaskToTop(id: task.id)
                }
            } label: {
                Label("Move to Top", systemImage: "arrow.up.to.line")
            }
            .disabled(isFirst)

            Button {
                DispatchQueue.main.async {
                    appState.moveTaskUp(id: task.id)
                }
            } label: {
                Label("Move Up", systemImage: "arrow.up")
            }
            .disabled(isFirst)

            Button {
                DispatchQueue.main.async {
                    appState.moveTaskDown(id: task.id)
                }
            } label: {
                Label("Move Down", systemImage: "arrow.down")
            }
            .disabled(isLast)

            Button {
                DispatchQueue.main.async {
                    appState.moveTaskToBottom(id: task.id)
                }
            } label: {
                Label("Move to Bottom", systemImage: "arrow.down.to.line")
            }
            .disabled(isLast)
        } label: {
            Label("Queue Position", systemImage: "arrow.up.arrow.down")
        }

        Divider()

        Button("Remove from List", role: .destructive) {
            DispatchQueue.main.async {
                appState.remove(id: task.id, deleteFile: false)
            }
        }

        Button("Delete File from Disk...", role: .destructive) {
            DispatchQueue.main.async {
                appState.promptDelete(task: task)
            }
        }
    }

    // MARK: - Drag and Drop Overlay

    private var dragDropTargetOverlay: some View {
        ZStack {
            Color.black.opacity(0.35)
                .background(.ultraThinMaterial)

            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Theme.accent.opacity(0.2))
                        .frame(width: 72, height: 72)
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(Theme.accent)
                }

                Text("Drop Link to Download")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)

                Text("Multi-chunk parallel acceleration will start automatically")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(28)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
            )
            .shadow(color: Theme.accent.opacity(0.25), radius: 20)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            isDropTargeted = false
        }
        .transition(.opacity)
        .animation(.easeOut(duration: 0.2), value: isDropTargeted)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Theme.accent.opacity(0.12))
                    .frame(width: 80, height: 80)

                Image(systemName: emptyStateIcon)
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(Theme.accent)
            }

            VStack(spacing: 5) {
                Text(emptyStateTitle)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)

                Text(emptyStateSubtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }

            if !appState.searchText.isEmpty {
                Button {
                    appState.searchText = ""
                } label: {
                    Label("Clear Search Filter", systemImage: "xmark.circle")
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .tint(Theme.accent)
            } else {
                Button {
                    appState.isAddSheetPresented = true
                } label: {
                    Label("Add Download", systemImage: "plus")
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .tint(Theme.accent)
                .keyboardShortcut("n", modifiers: .command)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
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

    // MARK: - Bottom Engine Status Telemetry Bar

    private var queueBottomStatusBar: some View {
        HStack(spacing: 14) {
            // Engine status & active sockets
            HStack(spacing: 10) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(Theme.success)
                        .frame(width: 6, height: 6)
                    Text("HyperFetch Engine: Ready")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }

                Text("•")
                    .foregroundStyle(Theme.textTertiary)

                Text("Active TCP Sockets: \(appState.activeSocketCount)")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)

                Text("•")
                    .foregroundStyle(Theme.textTertiary)

                Text("Allocated RAM: \(appState.allocatedMemoryMB) MB")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
            }

            Spacer()

            // Today's total downloaded & refresh button
            HStack(spacing: 10) {
                if appState.hasCompletedTasks {
                    Button {
                        appState.clearCompletedTasks()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle")
                                .font(.system(size: 10))
                            Text("Clear Finished")
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .help("Remove finished downloads from the list without deleting files (⌥⌘K)")
                    .keyboardShortcut("k", modifiers: [.command, .option])

                    Text("•")
                        .foregroundStyle(Theme.textTertiary)
                }

                Text("Total Downloaded Today: \(appState.formattedTotalDownloadedToday)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)

                Button {
                    appState.refreshStatus()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .help("Refresh Status")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 26)
        .frame(maxWidth: .infinity)
        .background(Theme.statusBarBackground)
    }
}
