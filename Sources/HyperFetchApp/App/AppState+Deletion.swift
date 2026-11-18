//
//  AppState+Deletion.swift
//  HyperFetchApp
//

import Foundation
import DownloadKit

@MainActor
extension AppState {
    /// Prompts the delete confirmation sheet/dialog for the given task, or the selected tasks if none specified.
    public func promptDelete(task: DownloadTaskModel? = nil) {
        if let task {
            self.taskPendingDeletion = task
            self.tasksPendingDeletion = [task]
            self.showDeleteConfirmation = true
        } else {
            promptDeleteSelected()
        }
    }

    /// Sets up delete confirmation for the selected task(s).
    public func promptDeleteSelected() {
        let targets = selectedTasks
        guard !targets.isEmpty else { return }
        self.tasksPendingDeletion = targets
        self.taskPendingDeletion = targets.first
        self.showDeleteConfirmation = true
    }

    /// Confirms deletion of pending task(s), optionally removing destination files from disk.
    public func confirmDelete(deleteFile: Bool) {
        if !tasksPendingDeletion.isEmpty {
            for task in tasksPendingDeletion {
                remove(id: task.id, deleteFile: deleteFile)
            }
            tasksPendingDeletion = []
            taskPendingDeletion = nil
        } else if let task = taskPendingDeletion {
            remove(id: task.id, deleteFile: deleteFile)
            taskPendingDeletion = nil
        }
    }

    /// Removes a task from the list and optionally deletes its file from disk.
    public func remove(id: UUID, deleteFile: Bool = false) {
        selectedTaskIDs.remove(id)
        if selectedTaskIDs.isEmpty, let next = tasks.first(where: { $0.id != id })?.id {
            selectedTaskIDs = [next]
        }
        self.tasks.removeAll(where: { $0.id == id })
        Task {
            try? await queueManager.removeTask(id: id, deleteFile: deleteFile)
        }
    }

    /// Removes all selected tasks from the queue and resets selection.
    public func removeSelected(deleteFile: Bool = false) {
        let targets = selectedTasks
        let targetIDs = Set(targets.map(\.id))
        selectedTaskIDs.removeAll()
        self.tasks.removeAll(where: { targetIDs.contains($0.id) })
        if let first = self.tasks.first?.id {
            self.selectedTaskIDs = [first]
        }
        Task {
            for task in targets {
                try? await queueManager.removeTask(id: task.id, deleteFile: deleteFile)
            }
        }
    }

    /// Removes all completed downloads from the queue without deleting files from disk.
    public func clearCompletedTasks() {
        let completedIDs = tasks.filter { $0.status == .completed }.map(\.id)
        guard !completedIDs.isEmpty else { return }
        for id in completedIDs {
            remove(id: id, deleteFile: false)
        }
    }

    /// Convenience alias for clearCompletedTasks.
    public func clearCompleted() {
        clearCompletedTasks()
    }

    /// Cleans up completed tasks whose destination files no longer exist on disk.
    public func cleanMissingFiles() {
        for task in tasks where task.status == .completed {
            if !FileManager.default.fileExists(atPath: task.destinationURL.path) {
                remove(id: task.id, deleteFile: false)
            }
        }
    }
}
