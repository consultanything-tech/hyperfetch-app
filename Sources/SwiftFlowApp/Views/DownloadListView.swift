//
//  DownloadListView.swift
//  SwiftFlowApp
//

import SwiftUI
import DownloadKit

/// Main list displaying filtered download tasks with context menus and empty state handling.
public struct DownloadListView: View {
    @EnvironmentObject private var appState: AppState
    @ViewState private var taskPendingDeletion: DownloadTaskModel? = nil
    @ViewState private var shouldDeleteDiskFile = false
    @ViewState private var showDeleteConfirmation = false

    public init() {}

    public var body: some View {
        Group {
            if appState.filteredTasks.isEmpty {
                emptyStateView
            } else {
                taskListView
            }
        }
        .confirmationDialog(
            "Delete Download?",
            isPresented: $showDeleteConfirmation,
            presenting: taskPendingDeletion
        ) { task in
            Button("Remove from List", role: .destructive) {
                appState.remove(id: task.id, deleteFile: false)
            }
            Button("Delete File from Disk", role: .destructive) {
                appState.remove(id: task.id, deleteFile: true)
            }
            Button("Cancel", role: .cancel) {}
        } message: { task in
            Text("Are you sure you want to remove '\(task.filename)'?")
        }
    }

    // MARK: - Subviews

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: emptyStateIcon)
                .font(.system(size: 48))
                .foregroundStyle(.secondary.opacity(0.6))

            VStack(spacing: 6) {
                Text(emptyStateTitle)
                    .font(.title3.bold())

                Text(emptyStateSubtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                appState.isAddSheetPresented = true
            } label: {
                Label("Add Download", systemImage: "plus")
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private var taskListView: some View {
        List(selection: $appState.selectedTaskId) {
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
            taskPendingDeletion = task
            showDeleteConfirmation = true
        }
    }

    private var emptyStateIcon: String {
        if !appState.searchText.isEmpty {
            return "magnifyingglass"
        }
        switch appState.statusFilter {
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
        switch appState.statusFilter {
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
        return "Click '+' or paste a URL to start downloading with multi-chunk acceleration."
    }
}
