import { useCallback, useEffect, useRef, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import type { DownloadTask } from "../types/download";

export function useDownloadState() {
  const [tasks, setTasks] = useState<DownloadTask[]>([]);
  const [isAddModalOpen, setIsAddModalOpen] = useState(false);
  const [sheetUrl, setSheetUrl] = useState("");
  const [sheetFilename, setSheetFilename] = useState("");
  const lastProgressTimestamp = useRef(Date.now());

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

    listen<DownloadTask[]>("download-progress", (event) => {
      lastProgressTimestamp.current = Date.now();
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

    return () => {
      if (unlistenProgress) unlistenProgress();
      if (unlistenSheet) unlistenSheet();
    };
  }, []);

  // Fallback recovery watchdog: If downloads are active but no progress event
  // has arrived for 5s, poll refreshTasks() to recover from dropped IPC events.
  useEffect(() => {
    const timer = setInterval(() => {
      const hasActiveTasks = tasks.some(
        (t) => t.status === "downloading" || t.status === "connecting"
      );
      if (hasActiveTasks && Date.now() - lastProgressTimestamp.current > 5000) {
        refreshTasks();
      }
    }, 5000);

    return () => clearInterval(timer);
  }, [tasks, refreshTasks]);

  const openAddModal = useCallback((url = "", filename = "") => {
    setSheetUrl(url);
    setSheetFilename(filename);
    setIsAddModalOpen(true);
  }, []);

  const closeAddModal = useCallback(() => {
    setIsAddModalOpen(false);
  }, []);

  return {
    tasks,
    setTasks,
    refreshTasks,
    isAddModalOpen,
    setIsAddModalOpen,
    sheetUrl,
    setSheetUrl,
    sheetFilename,
    setSheetFilename,
    openAddModal,
    closeAddModal,
  };
}
