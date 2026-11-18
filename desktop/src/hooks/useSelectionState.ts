import { useCallback, useEffect, useMemo, useState } from "react";
import type React from "react";
import type { DownloadTask } from "../types/download";

export function useSelectionState(
  tasks: DownloadTask[],
  filteredTasks: DownloadTask[],
) {
  const [selectedTaskId, setSelectedTaskId] = useState<string | null>(null);
  const [selectedTaskIds, setSelectedTaskIds] = useState<Set<string>>(
    new Set(),
  );
  const [lastClickedIndex, setLastClickedIndex] = useState<number | null>(null);

  // Derive the active task for the inspector
  const selectedTask = useMemo(() => {
    if (!selectedTaskId) {
      if (selectedTaskIds.size === 1) {
        const id = Array.from(selectedTaskIds)[0];
        return tasks.find((t) => t.id === id) || null;
      }
      return null;
    }
    return tasks.find((t) => t.id === selectedTaskId) || null;
  }, [tasks, selectedTaskId, selectedTaskIds]);

  // Keep selectedTaskId synced if task list changes
  useEffect(() => {
    if (selectedTaskId && !tasks.some((t) => t.id === selectedTaskId)) {
      if (tasks.length > 0) {
        setSelectedTaskId(tasks[0].id);
        setSelectedTaskIds(new Set([tasks[0].id]));
      } else {
        setSelectedTaskId(null);
        setSelectedTaskIds(new Set());
      }
    }
  }, [tasks, selectedTaskId]);

  // Desktop Multi-Selection Semantics
  const handleSelectRow = useCallback(
    (id: string, e: React.MouseEvent) => {
      const currentIndex = filteredTasks.findIndex((t) => t.id === id);

      if (e.shiftKey && lastClickedIndex !== null && currentIndex !== -1) {
        // Shift+Click: contiguous range selection
        const start = Math.min(lastClickedIndex, currentIndex);
        const end = Math.max(lastClickedIndex, currentIndex);
        const next = new Set(selectedTaskIds);
        for (let i = start; i <= end; i++) {
          next.add(filteredTasks[i].id);
        }
        setSelectedTaskIds(next);
        setSelectedTaskId(id);
      } else if (e.metaKey || e.ctrlKey) {
        // Ctrl+Click / Cmd+Click: toggle without clearing others
        const next = new Set(selectedTaskIds);
        if (next.has(id)) {
          next.delete(id);
          if (selectedTaskId === id) {
            setSelectedTaskId(next.size > 0 ? Array.from(next)[0] : null);
          }
        } else {
          next.add(id);
          setSelectedTaskId(id);
        }
        setSelectedTaskIds(next);
        setLastClickedIndex(currentIndex);
      } else {
        // Regular click: single select
        setSelectedTaskIds(new Set([id]));
        setSelectedTaskId(id);
        setLastClickedIndex(currentIndex);
      }
    },
    [filteredTasks, lastClickedIndex, selectedTaskId, selectedTaskIds],
  );

  const handleToggleCheckbox = useCallback(
    (id: string) => {
      setSelectedTaskIds((prev) => {
        const next = new Set(prev);
        if (next.has(id)) {
          next.delete(id);
          if (selectedTaskId === id) {
            setSelectedTaskId(next.size > 0 ? Array.from(next)[0] : null);
          }
        } else {
          next.add(id);
          if (!selectedTaskId) {
            setSelectedTaskId(id);
          }
        }
        return next;
      });
    },
    [selectedTaskId],
  );

  const handleSelectAll = useCallback(() => {
    if (selectedTaskIds.size === filteredTasks.length) {
      setSelectedTaskIds(new Set());
    } else {
      setSelectedTaskIds(new Set(filteredTasks.map((t) => t.id)));
      if (filteredTasks.length > 0 && !selectedTaskId) {
        setSelectedTaskId(filteredTasks[0].id);
      }
    }
  }, [filteredTasks, selectedTaskId, selectedTaskIds.size]);

  const clearSelection = useCallback(() => {
    setSelectedTaskIds(new Set());
    setSelectedTaskId(null);
  }, []);

  return {
    selectedTaskId,
    setSelectedTaskId,
    selectedTaskIds,
    setSelectedTaskIds,
    lastClickedIndex,
    setLastClickedIndex,
    selectedTask,
    handleSelectRow,
    handleToggleCheckbox,
    handleSelectAll,
    clearSelection,
  };
}
