import { listen } from "@tauri-apps/api/event";
import { useEffect, useState } from "react";
import type { SidebarFilter, ThemeMode, ViewMode } from "../types/download";

export function useUIState() {
  const [activeFilter, setActiveFilter] = useState<SidebarFilter>("all");
  const [searchQuery, setSearchQuery] = useState("");
  const [viewMode, setViewMode] = useState<ViewMode>("comfortable");
  const [theme, setTheme] = useState<ThemeMode>("dark");
  const [showInspector, setShowInspector] = useState<boolean>(true);
  const [isSettingsModalOpen, setIsSettingsModalOpen] = useState(false);

  // Listen for set-theme events from Tauri
  useEffect(() => {
    let unlistenTheme: (() => void) | undefined;

    listen<string>("set-theme", (event) => {
      const mode = event.payload?.toLowerCase();
      if (mode === "dark" || mode === "light" || mode === "system") {
        setTheme(mode as ThemeMode);
      }
    }).then((unlisten) => {
      unlistenTheme = unlisten;
    });

    return () => {
      if (unlistenTheme) unlistenTheme();
    };
  }, []);

  // Apply theme class to document root
  useEffect(() => {
    const root = document.documentElement;
    if (theme === "dark") {
      root.classList.add("dark");
    } else if (theme === "light") {
      root.classList.remove("dark");
    } else {
      const prefersDark = window.matchMedia(
        "(prefers-color-scheme: dark)",
      ).matches;
      if (prefersDark) {
        root.classList.add("dark");
      } else {
        root.classList.remove("dark");
      }
    }
  }, [theme]);

  return {
    activeFilter,
    setActiveFilter,
    searchQuery,
    setSearchQuery,
    viewMode,
    setViewMode,
    theme,
    setTheme,
    showInspector,
    setShowInspector,
    isSettingsModalOpen,
    setIsSettingsModalOpen,
  };
}
