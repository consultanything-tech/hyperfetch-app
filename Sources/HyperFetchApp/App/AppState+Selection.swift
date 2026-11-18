//
//  AppState+Selection.swift
//  HyperFetchApp
//

import Foundation
import DownloadKit

@MainActor
extension AppState {
    /// Retrieves the currently selected task, if any.
    public var selectedTask: DownloadTaskModel? {
        guard let selectedTaskId else { return nil }
        return tasks.first(where: { $0.id == selectedTaskId })
    }

    /// Retrieves all currently selected tasks.
    public var selectedTasks: [DownloadTaskModel] {
        tasks.filter { selectedTaskIDs.contains($0.id) }
    }

    /// Whether any of the selected tasks are currently active (downloading or probing).
    public var hasActiveSelectedTasks: Bool {
        selectedTasks.contains { $0.status == .downloading || $0.status == .probing }
    }

    /// Whether any of the selected tasks can be resumed (paused, idle, or failed).
    public var hasResumableSelectedTasks: Bool {
        selectedTasks.contains { task in
            switch task.status {
            case .paused, .idle, .failed:
                return true
            case .downloading, .probing, .completed:
                return false
            }
        }
    }

    /// Indicates whether all currently filtered tasks are selected.
    public var isAllSelected: Bool {
        !filteredTasks.isEmpty && filteredTasks.allSatisfy { selectedTaskIDs.contains($0.id) }
    }

    /// Indicates whether some, but not all, currently filtered tasks are selected.
    public var isPartiallySelected: Bool {
        !isAllSelected && filteredTasks.contains { selectedTaskIDs.contains($0.id) }
    }

    /// Selects all tasks currently visible under active filters.
    public func selectAll() {
        selectedTaskIDs = Set(filteredTasks.map(\.id))
    }

    /// Deselects all tasks.
    public func deselectAll() {
        selectedTaskIDs = []
    }

    /// Toggles the selection state for a specific task ID.
    public func toggleSelection(id: UUID) {
        if selectedTaskIDs.contains(id) {
            selectedTaskIDs.remove(id)
        } else {
            selectedTaskIDs.insert(id)
        }
    }

    /// Toggles selection between all filtered tasks and none.
    public func toggleSelectAll() {
        if isAllSelected {
            deselectAll()
        } else {
            selectAll()
        }
    }

    /// Selects the next task in the filtered tasks list (arrow navigation).
    public func selectNextTask() {
        guard !filteredTasks.isEmpty else { return }
        guard let currentId = selectedTaskId,
              let currentIndex = filteredTasks.firstIndex(where: { $0.id == currentId }) else {
            selectedTaskIDs = [filteredTasks[0].id]
            return
        }
        let nextIndex = min(currentIndex + 1, filteredTasks.count - 1)
        selectedTaskIDs = [filteredTasks[nextIndex].id]
    }

    /// Selects the previous task in the filtered tasks list (arrow navigation).
    public func selectPreviousTask() {
        guard !filteredTasks.isEmpty else { return }
        guard let currentId = selectedTaskId,
              let currentIndex = filteredTasks.firstIndex(where: { $0.id == currentId }) else {
            selectedTaskIDs = [filteredTasks[0].id]
            return
        }
        let prevIndex = max(0, currentIndex - 1)
        selectedTaskIDs = [filteredTasks[prevIndex].id]
    }

    /// Selects a contiguous range of tasks from the anchor/selected task to the target task.
    public func selectRange(to targetId: UUID) {
        guard let anchorId = selectedTaskId,
              let anchorIndex = filteredTasks.firstIndex(where: { $0.id == anchorId }),
              let targetIndex = filteredTasks.firstIndex(where: { $0.id == targetId }) else {
            selectedTaskIDs = [targetId]
            return
        }
        let start = min(anchorIndex, targetIndex)
        let end = max(anchorIndex, targetIndex)
        let rangeTasks = filteredTasks[start...end]
        selectedTaskIDs.formUnion(rangeTasks.map(\.id))
    }

    /// Selects a contiguous range of tasks between two specific task IDs.
    public func selectRange(from startId: UUID, to endId: UUID) {
        guard let startIndex = filteredTasks.firstIndex(where: { $0.id == startId }),
              let endIndex = filteredTasks.firstIndex(where: { $0.id == endId }) else {
            selectedTaskIDs = [endId]
            return
        }
        let start = min(startIndex, endIndex)
        let end = max(startIndex, endIndex)
        let rangeTasks = filteredTasks[start...end]
        selectedTaskIDs.formUnion(rangeTasks.map(\.id))
    }
}
