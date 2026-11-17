import React, { useState, useEffect, useCallback, useMemo } from "react";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import {
  DownloadCloud,
  Plus,
  SearchX,
  Trash2,
  Pause,
  Play,
} from "lucide-react";
import type {
  DownloadTask,
  SidebarFilter,
  ViewMode,
  ThemeMode,
  QueueAction,
} from "./types/download";
import { Sidebar } from "./components/Sidebar";
import { Toolbar } from "./components/Toolbar";
import { DownloadRow } from "./components/DownloadRow";
import { CompactDownloadRowView } from "./components/CompactDownloadRowView";
import { TaskDetailInspector } from "./components/TaskDetailInspector";
import { ContextMenu } from "./components/ContextMenu";
import { AddDownloadModal } from "./components/AddDownloadModal";
import { SettingsModal } from "./components/SettingsModal";
import "./App.css";

export function App() {
  const [tasks, setTasks] = useState<DownloadTask[]>([]);
  const [selectedTaskId, setSelectedTaskId] = useState<string | null>(null);
  const [selectedTaskIds, setSelectedTaskIds] = useState<Set<string>>(
    new Set()
  );
  const [lastClickedIndex, setLastClickedIndex] = useState<number | null>(null);
  const [showInspector, setShowInspector] = useState<boolean>(true);

  const [activeFilter, setActiveFilter] = useState<SidebarFilter>("all");
  const [searchQuery, setSearchQuery] = useState("");
  const [viewMode, setViewMode] = useState<ViewMode>("comfortable");
  const [theme, setTheme] = useState<ThemeMode>("dark");

  const [isAddModalOpen, setIsAddModalOpen] = useState(false);
  const [isSettingsModalOpen, setIsSettingsModalOpen] = useState(false);
  const [sheetUrl, setSheetUrl] = useState("");
  const [sheetFilename, setSheetFilename] = useState("");

  const [contextMenu, setContextMenu] = useState<{
    task: DownloadTask;
    position: { x: number; y: number };
  } | null>(null);

  // Refresh tasks from backend
  const refreshTasks = useCallback(async () => {
    try {
      const data = await invoke<DownloadTask[]>("get_downloads");
      setTasks(data || []);
    } catch (err) {
      console.error("Failed to load downloads:", err);
    }
  }, []);

  // Initial load
  useEffect(() => {
    refreshTasks();
  }, [refreshTasks]);

  // Listen for Tauri events
  useEffect(() => {
    let unlistenProgress: (() => void) | undefined;
    let unlistenSheet: (() => void) | undefined;
    let unlistenTheme: (() => void) | undefined;

    listen<DownloadTask[]>("download-progress", (event) => {
      if (Array.isArray(event.payload)) {
        setTasks(event.payload);
      }
    }).then((unlisten) => {
      unlistenProgress = unlisten;
    });

    listen<{ url?: string; filename?: string }>("open-add-sheet", (event) => {
      setSheetUrl(event.payload?.url || "");
      setSheetFilename(event.payload?.filename || "");
      setIsAddModalOpen(true);
    }).then((unlisten) => {
      unlistenSheet = unlisten;
    });

    listen<string>("set-theme", (event) => {
      const mode = event.payload?.toLowerCase();
      if (mode === "dark" || mode === "light" || mode === "system") {
        setTheme(mode as ThemeMode);
      }
    }).then((unlisten) => {
      unlistenTheme = unlisten;
    });

    return () => {
      if (unlistenProgress) unlistenProgress();
      if (unlistenSheet) unlistenSheet();
      if (unlistenTheme) unlistenTheme();
    };
  }, []);

  // Theme application
  useEffect(() => {
    const root = document.documentElement;
    if (theme === "dark") {
      root.classList.add("dark");
    } else if (theme === "light") {
      root.classList.remove("dark");
    } else {
      const prefersDark = window.matchMedia(
        "(prefers-color-scheme: dark)"
      ).matches;
      if (prefersDark) {
        root.classList.add("dark");
      } else {
        root.classList.remove("dark");
      }
    }
  }, [theme]);

  // Filtered tasks calculation
  const filteredTasks = useMemo(() => {
    return tasks.filter((task) => {
      let matchesCategory = true;
      if (activeFilter === "all") {
        matchesCategory = true;
      } else if (activeFilter === "downloading") {
        matchesCategory =
          task.status === "downloading" || task.status === "connecting";
      } else if (activeFilter === "completed") {
        matchesCategory = task.status === "completed";
      } else if (activeFilter === "failed") {
        matchesCategory = task.status === "failed";
      } else {
        matchesCategory = task.category === activeFilter;
      }

      if (!matchesCategory) return false;

      if (searchQuery.trim()) {
        const query = searchQuery.trim().toLowerCase();
        const matchesName = task.filename.toLowerCase().includes(query);
        const matchesUrl = task.url.toLowerCase().includes(query);
        return matchesName || matchesUrl;
      }

      return true;
    });
  }, [tasks, activeFilter, searchQuery]);

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

  // Active downloading count
  const activeCount = useMemo(() => {
    return tasks.filter(
      (t) => t.status === "downloading" || t.status === "connecting"
    ).length;
  }, [tasks]);

  // Desktop Multi-Selection Semantics
  const handleSelectRow = (id: string, e: React.MouseEvent) => {
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
  };

  const handleToggleCheckbox = (id: string) => {
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
  };

  const handleSelectAll = () => {
    if (selectedTaskIds.size === filteredTasks.length) {
      setSelectedTaskIds(new Set());
    } else {
      setSelectedTaskIds(new Set(filteredTasks.map((t) => t.id)));
      if (filteredTasks.length > 0 && !selectedTaskId) {
        setSelectedTaskId(filteredTasks[0].id);
      }
    }
  };

  // Context Menu
  const handleContextMenu = (task: DownloadTask, e: React.MouseEvent) => {
    if (!selectedTaskIds.has(task.id)) {
      setSelectedTaskIds(new Set([task.id]));
      setSelectedTaskId(task.id);
    }
    setContextMenu({
      task,
      position: { x: e.clientX, y: e.clientY },
    });
  };

  // Queue reordering
  const handleQueueMove = async (id: string, action: QueueAction) => {
    try {
      const updated = await invoke<DownloadTask[]>("reorder_task", {
        id,
        action,
      });
      if (Array.isArray(updated)) {
        setTasks(updated);
        return;
      }
    } catch {
      // Fallback local reorder
    }

    setTasks((prev) => {
      const pos = prev.findIndex((t) => t.id === id);
      if (pos === -1) return prev;
      const copy = [...prev];
      if (action === "top" && pos > 0) {
        const [item] = copy.splice(pos, 1);
        copy.unshift(item);
      } else if (action === "up" && pos > 0) {
        const temp = copy[pos];
        copy[pos] = copy[pos - 1];
        copy[pos - 1] = temp;
      } else if (action === "down" && pos + 1 < copy.length) {
        const temp = copy[pos];
        copy[pos] = copy[pos + 1];
        copy[pos + 1] = temp;
      } else if (action === "bottom" && pos + 1 < copy.length) {
        const [item] = copy.splice(pos, 1);
        copy.push(item);
      }
      return copy;
    });
  };

  // Action handlers
  const handlePause = async (id: string) => {
    try {
      await invoke("pause_download", { id });
      await refreshTasks();
    } catch (err) {
      console.error("Failed to pause download:", err);
    }
  };

  const handleResume = async (id: string) => {
    try {
      await invoke("resume_download", { id });
      await refreshTasks();
    } catch (err) {
      console.error("Failed to resume download:", err);
    }
  };

  const handleDelete = async (id: string) => {
    if (!confirm("Are you sure you want to remove this download task?")) {
      return;
    }
    try {
      await invoke("delete_download", { id, deleteFile: false });
      setSelectedTaskIds((prev) => {
        const next = new Set(prev);
        next.delete(id);
        return next;
      });
      if (selectedTaskId === id) {
        setSelectedTaskId(null);
      }
      await refreshTasks();
    } catch (err) {
      console.error("Failed to delete download:", err);
    }
  };

  const handlePauseAll = async () => {
    try {
      await invoke("pause_all");
      await refreshTasks();
    } catch (err) {
      console.error("Failed to pause all downloads:", err);
    }
  };

  const handleResumeAll = async () => {
    try {
      await invoke("resume_all");
      await refreshTasks();
    } catch (err) {
      console.error("Failed to resume all downloads:", err);
    }
  };

  const handleOpenFile = async (path: string) => {
    try {
      await invoke("open_file", { path });
    } catch (err) {
      console.error("Failed to open file:", err);
      alert(`Could not open file: ${err}`);
    }
  };

  const handleOpenFolder = async (path: string) => {
    try {
      await invoke("open_containing_folder", { path });
    } catch (err) {
      console.error("Failed to open folder:", err);
      alert(`Could not reveal file in folder: ${err}`);
    }
  };

  const handleCopyUrl = async (url: string) => {
    try {
      await navigator.clipboard.writeText(url);
    } catch (err) {
      console.error("Failed to copy URL:", err);
    }
  };

  const handleCopyChecksum = async (checksum?: string | null) => {
    if (!checksum) return;
    try {
      await navigator.clipboard.writeText(checksum);
    } catch (err) {
      console.error("Failed to copy checksum:", err);
    }
  };

  // Bulk actions on selected tasks
  const handleBulkPause = async () => {
    for (const id of selectedTaskIds) {
      await invoke("pause_download", { id }).catch(() => {});
    }
    await refreshTasks();
  };

  const handleBulkResume = async () => {
    for (const id of selectedTaskIds) {
      await invoke("resume_download", { id }).catch(() => {});
    }
    await refreshTasks();
  };

  const handleBulkDelete = async () => {
    if (
      !confirm(
        `Are you sure you want to remove ${selectedTaskIds.size} selected tasks?`
      )
    ) {
      return;
    }
    for (const id of selectedTaskIds) {
      await invoke("delete_download", { id, deleteFile: false }).catch(() => {});
    }
    setSelectedTaskIds(new Set());
    setSelectedTaskId(null);
    await refreshTasks();
  };

  // Global keyboard shortcuts (Cmd+N, Cmd+I, Cmd+,, Space, Esc, Arrows)
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      // Toggle New Download: Cmd+N or Ctrl+N
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "n") {
        e.preventDefault();
        setIsAddModalOpen(true);
        return;
      }
      // Toggle Inspector: Cmd+I or Ctrl+I
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "i") {
        e.preventDefault();
        setShowInspector((prev) => !prev);
        return;
      }
      // Settings: Cmd+, or Ctrl+,
      if ((e.metaKey || e.ctrlKey) && e.key === ",") {
        e.preventDefault();
        setIsSettingsModalOpen(true);
        return;
      }
      // Select All: Cmd+A or Ctrl+A
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "a") {
        const activeTag = (document.activeElement?.tagName || "").toLowerCase();
        if (activeTag !== "input" && activeTag !== "textarea") {
          e.preventDefault();
          handleSelectAll();
          return;
        }
      }
      // Escape: deselect all
      if (e.key === "Escape") {
        if (selectedTaskIds.size > 0) {
          setSelectedTaskIds(new Set());
        }
        return;
      }
      // Space: Toggle pause/resume on selected task
      if (e.key === " " && selectedTaskId) {
        const activeTag = (document.activeElement?.tagName || "").toLowerCase();
        if (activeTag !== "input" && activeTag !== "textarea") {
          e.preventDefault();
          const target = tasks.find((t) => t.id === selectedTaskId);
          if (target) {
            if (target.status === "downloading" || target.status === "connecting") {
              handlePause(target.id);
            } else if (target.status !== "completed") {
              handleResume(target.id);
            }
          }
        }
      }
      // Arrow Up / Down: Navigate list selection
      if (e.key === "ArrowDown" || e.key === "ArrowUp") {
        const activeTag = (document.activeElement?.tagName || "").toLowerCase();
        if (activeTag !== "input" && activeTag !== "textarea") {
          e.preventDefault();
          if (filteredTasks.length === 0) return;
          const currIdx = selectedTaskId
            ? filteredTasks.findIndex((t) => t.id === selectedTaskId)
            : -1;
          let nextIdx = 0;
          if (e.key === "ArrowDown") {
            nextIdx = currIdx + 1 < filteredTasks.length ? currIdx + 1 : 0;
          } else {
            nextIdx = currIdx - 1 >= 0 ? currIdx - 1 : filteredTasks.length - 1;
          }
          const nextTask = filteredTasks[nextIdx];
          setSelectedTaskId(nextTask.id);
          setSelectedTaskIds(new Set([nextTask.id]));
          setLastClickedIndex(nextIdx);
        }
      }
    };
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [tasks, filteredTasks, selectedTaskId, selectedTaskIds]);

  return (
    <div className="flex h-screen w-screen overflow-hidden bg-zinc-100 dark:bg-zinc-950 text-zinc-900 dark:text-zinc-100 font-sans">
      {/* Left Sidebar */}
      <Sidebar
        currentFilter={activeFilter}
        onSelectFilter={setActiveFilter}
        tasks={tasks}
      />

      {/* Main Content Area */}
      <main className="flex-1 flex flex-col min-w-0 h-full overflow-hidden bg-white/40 dark:bg-zinc-950/40">
        {/* Top Toolbar */}
        <Toolbar
          searchQuery={searchQuery}
          onSearchChange={setSearchQuery}
          viewMode={viewMode}
          onViewModeChange={setViewMode}
          onOpenAddModal={() => {
            setSheetUrl("");
            setSheetFilename("");
            setIsAddModalOpen(true);
          }}
          onOpenSettingsModal={() => setIsSettingsModalOpen(true)}
          onPauseAll={handlePauseAll}
          onResumeAll={handleResumeAll}
          activeDownloadCount={activeCount}
          showInspector={showInspector}
          onToggleInspector={() => setShowInspector((prev) => !prev)}
        />

        {/* Bulk Action Bar (visible when items selected) */}
        {selectedTaskIds.size > 0 && (
          <div className="px-5 py-2 bg-blue-50/90 dark:bg-blue-950/40 border-b border-blue-500/20 flex items-center justify-between text-xs animate-in slide-in-from-top-2 duration-150 select-none">
            <div className="flex items-center gap-2 text-blue-700 dark:text-blue-300 font-medium">
              <span>{selectedTaskIds.size} item(s) selected</span>
              <button
                onClick={handleSelectAll}
                className="underline hover:text-blue-900 dark:hover:text-blue-100 cursor-pointer ml-1"
              >
                {selectedTaskIds.size === filteredTasks.length
                  ? "Deselect All"
                  : "Select All"}
              </button>
            </div>

            <div className="flex items-center gap-2">
              <button
                onClick={handleBulkResume}
                className="px-2.5 py-1 rounded-md bg-white dark:bg-zinc-900 border border-blue-200 dark:border-blue-900 text-zinc-700 dark:text-zinc-200 hover:bg-zinc-50 flex items-center gap-1 font-medium cursor-pointer"
              >
                <Play className="w-3 h-3 fill-current" />
                <span>Resume</span>
              </button>
              <button
                onClick={handleBulkPause}
                className="px-2.5 py-1 rounded-md bg-white dark:bg-zinc-900 border border-blue-200 dark:border-blue-900 text-zinc-700 dark:text-zinc-200 hover:bg-zinc-50 flex items-center gap-1 font-medium cursor-pointer"
              >
                <Pause className="w-3 h-3 fill-current" />
                <span>Pause</span>
              </button>
              <button
                onClick={handleBulkDelete}
                className="px-2.5 py-1 rounded-md bg-rose-50 dark:bg-rose-950/40 border border-rose-200 dark:border-rose-900 text-rose-600 dark:text-rose-400 hover:bg-rose-100 flex items-center gap-1 font-medium cursor-pointer"
              >
                <Trash2 className="w-3 h-3" />
                <span>Delete</span>
              </button>
            </div>
          </div>
        )}

        {/* Downloads Scrollable Container */}
        <div className="flex-1 overflow-y-auto p-4">
          {filteredTasks.length === 0 ? (
            /* Empty State */
            <div className="h-full min-h-[350px] flex flex-col items-center justify-center text-center p-8 select-none">
              <div className="w-16 h-16 rounded-2xl bg-zinc-100 dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 flex items-center justify-center text-zinc-400 mb-4 shadow-xs">
                {searchQuery ? (
                  <SearchX className="w-8 h-8" />
                ) : (
                  <DownloadCloud className="w-8 h-8 stroke-[1.5]" />
                )}
              </div>
              <h3 className="text-sm font-semibold text-zinc-800 dark:text-zinc-200 mb-1">
                {searchQuery
                  ? "No matching downloads found"
                  : activeFilter !== "all"
                  ? `No downloads in "${activeFilter}"`
                  : "No downloads yet"}
              </h3>
              <p className="text-xs text-zinc-400 dark:text-zinc-500 max-w-sm mb-5">
                {searchQuery
                  ? `No items match "${searchQuery}". Try searching with a different filename or clear the search query.`
                  : "Paste a direct download URL or use the HyperFetch Chrome/Firefox browser extension to capture downloads automatically."}
              </p>
              {!searchQuery && (
                <button
                  onClick={() => {
                    setSheetUrl("");
                    setSheetFilename("");
                    setIsAddModalOpen(true);
                  }}
                  className="h-8 px-4 rounded-lg bg-blue-600 hover:bg-blue-500 text-white font-medium text-xs flex items-center gap-1.5 shadow-sm shadow-blue-500/25 transition-all cursor-pointer"
                >
                  <Plus className="w-4 h-4 stroke-[2.5]" />
                  <span>Add New Download</span>
                </button>
              )}
            </div>
          ) : viewMode === "comfortable" ? (
            /* Comfortable Card Rows */
            <div className="space-y-2.5 max-w-5xl mx-auto">
              {filteredTasks.map((task) => (
                <DownloadRow
                  key={task.id}
                  task={task}
                  isSelected={selectedTaskIds.has(task.id)}
                  onSelectRow={handleSelectRow}
                  onToggleCheckbox={handleToggleCheckbox}
                  onPause={handlePause}
                  onResume={handleResume}
                  onDelete={handleDelete}
                  onOpenFile={handleOpenFile}
                  onOpenFolder={handleOpenFolder}
                  onContextMenu={handleContextMenu}
                />
              ))}
            </div>
          ) : (
            /* Compact 36px High Density Rows */
            <div className="space-y-1 max-w-5xl mx-auto">
              {filteredTasks.map((task) => (
                <CompactDownloadRowView
                  key={task.id}
                  task={task}
                  isSelected={selectedTaskIds.has(task.id)}
                  onSelectRow={handleSelectRow}
                  onToggleCheckbox={handleToggleCheckbox}
                  onPause={handlePause}
                  onResume={handleResume}
                  onDelete={handleDelete}
                  onOpenFile={handleOpenFile}
                  onOpenFolder={handleOpenFolder}
                  onContextMenu={handleContextMenu}
                />
              ))}
            </div>
          )}
        </div>
      </main>

      {/* Right-Hand Task Details Inspector */}
      {showInspector && (
        <TaskDetailInspector
          task={selectedTask}
          onClose={() => setShowInspector(false)}
          onPause={handlePause}
          onResume={handleResume}
          onDelete={handleDelete}
          onOpenFile={handleOpenFile}
          onOpenFolder={handleOpenFolder}
        />
      )}

      {/* Right-Click Context Menu */}
      {contextMenu && (
        <ContextMenu
          task={contextMenu.task}
          position={contextMenu.position}
          isFirst={
            filteredTasks.length > 0 &&
            filteredTasks[0].id === contextMenu.task.id
          }
          isLast={
            filteredTasks.length > 0 &&
            filteredTasks[filteredTasks.length - 1].id === contextMenu.task.id
          }
          onClose={() => setContextMenu(null)}
          onPause={handlePause}
          onResume={handleResume}
          onDelete={handleDelete}
          onOpenFile={handleOpenFile}
          onOpenFolder={handleOpenFolder}
          onCopyUrl={handleCopyUrl}
          onCopyChecksum={handleCopyChecksum}
          onQueueMove={handleQueueMove}
        />
      )}

      {/* Add Download Sheet Modal */}
      <AddDownloadModal
        isOpen={isAddModalOpen}
        onClose={() => setIsAddModalOpen(false)}
        onAddSuccess={refreshTasks}
        initialUrl={sheetUrl}
        initialFilename={sheetFilename}
      />

      {/* Preferences & Settings Modal */}
      <SettingsModal
        isOpen={isSettingsModalOpen}
        onClose={() => setIsSettingsModalOpen(false)}
        theme={theme}
        onThemeChange={setTheme}
      />
    </div>
  );
}

export default App;
