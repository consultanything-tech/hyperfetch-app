import React from "react";
import {
  Plus,
  Pause,
  Play,
  Search,
  X,
  SlidersHorizontal,
  LayoutList,
  Rows3,
} from "lucide-react";
import type { ViewMode } from "../types/download";

interface ToolbarProps {
  searchQuery: string;
  onSearchChange: (query: string) => void;
  viewMode: ViewMode;
  onViewModeChange: (mode: ViewMode) => void;
  onOpenAddModal: () => void;
  onOpenSettingsModal: () => void;
  onPauseAll: () => void;
  onResumeAll: () => void;
  activeDownloadCount: number;
}

export const Toolbar: React.FC<ToolbarProps> = ({
  searchQuery,
  onSearchChange,
  viewMode,
  onViewModeChange,
  onOpenAddModal,
  onOpenSettingsModal,
  onPauseAll,
  onResumeAll,
  activeDownloadCount,
}) => {
  return (
    <header className="h-14 px-4 bg-white/70 dark:bg-zinc-950/70 backdrop-blur-md border-b border-zinc-200 dark:border-zinc-800 flex items-center justify-between gap-4 select-none shrink-0 z-10">
      {/* Left Action Buttons */}
      <div className="flex items-center gap-2">
        <button
          onClick={onOpenAddModal}
          className="h-8 px-3 rounded-lg bg-blue-600 hover:bg-blue-500 active:bg-blue-700 text-white font-medium text-xs flex items-center gap-1.5 shadow-sm shadow-blue-500/25 transition-all cursor-pointer"
          title="New Download (Cmd+N)"
        >
          <Plus className="w-4 h-4 stroke-[2.5]" />
          <span>New</span>
        </button>

        <div className="h-4 w-[1px] bg-zinc-200 dark:bg-zinc-800 mx-1" />

        <button
          onClick={onResumeAll}
          className="h-8 px-2.5 rounded-lg bg-zinc-100 hover:bg-zinc-200 dark:bg-zinc-800/80 dark:hover:bg-zinc-700/80 text-zinc-700 dark:text-zinc-200 font-medium text-xs flex items-center gap-1.5 transition-colors cursor-pointer border border-zinc-200 dark:border-zinc-700/60"
          title="Resume All Downloads"
        >
          <Play className="w-3.5 h-3.5 fill-current" />
          <span className="hidden sm:inline">Resume All</span>
        </button>

        <button
          onClick={onPauseAll}
          className="h-8 px-2.5 rounded-lg bg-zinc-100 hover:bg-zinc-200 dark:bg-zinc-800/80 dark:hover:bg-zinc-700/80 text-zinc-700 dark:text-zinc-200 font-medium text-xs flex items-center gap-1.5 transition-colors cursor-pointer border border-zinc-200 dark:border-zinc-700/60"
          title="Pause All Downloads"
        >
          <Pause className="w-3.5 h-3.5 fill-current" />
          <span className="hidden sm:inline">Pause All</span>
          {activeDownloadCount > 0 && (
            <span className="ml-0.5 px-1.5 py-0.2 rounded-full text-[10px] bg-blue-500/10 text-blue-600 dark:text-blue-400 font-mono">
              {activeDownloadCount}
            </span>
          )}
        </button>
      </div>

      {/* Center Search Bar */}
      <div className="flex-1 max-w-md relative">
        <div className="absolute inset-y-0 left-0 pl-2.5 flex items-center pointer-events-none text-zinc-400">
          <Search className="w-3.5 h-3.5" />
        </div>
        <input
          type="text"
          value={searchQuery}
          onChange={(e) => onSearchChange(e.target.value)}
          placeholder="Filter downloads by filename or URL..."
          className="w-full h-8 pl-8 pr-7 rounded-lg text-xs bg-zinc-100/90 dark:bg-zinc-900/90 border border-zinc-200 dark:border-zinc-800 text-zinc-900 dark:text-zinc-100 placeholder-zinc-400 focus:outline-none focus:ring-1 focus:ring-blue-500 focus:border-blue-500 transition-all"
        />
        {searchQuery && (
          <button
            onClick={() => onSearchChange("")}
            className="absolute inset-y-0 right-0 pr-2.5 flex items-center text-zinc-400 hover:text-zinc-600 dark:hover:text-zinc-200 cursor-pointer"
          >
            <X className="w-3.5 h-3.5" />
          </button>
        )}
      </div>

      {/* Right Controls: View Mode & Settings */}
      <div className="flex items-center gap-2">
        {/* Segmented View Mode Switcher */}
        <div className="h-8 p-0.5 rounded-lg bg-zinc-100 dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 flex items-center">
          <button
            onClick={() => onViewModeChange("comfortable")}
            className={`h-7 px-2.5 rounded-md flex items-center gap-1.5 text-xs font-medium transition-all cursor-pointer ${
              viewMode === "comfortable"
                ? "bg-white dark:bg-zinc-800 text-zinc-900 dark:text-zinc-100 shadow-xs font-semibold"
                : "text-zinc-500 hover:text-zinc-900 dark:hover:text-zinc-200"
            }`}
            title="Comfortable Detailed View"
          >
            <LayoutList className="w-3.5 h-3.5" />
            <span className="hidden md:inline">Comfortable</span>
          </button>

          <button
            onClick={() => onViewModeChange("compact")}
            className={`h-7 px-2.5 rounded-md flex items-center gap-1.5 text-xs font-medium transition-all cursor-pointer ${
              viewMode === "compact"
                ? "bg-white dark:bg-zinc-800 text-zinc-900 dark:text-zinc-100 shadow-xs font-semibold"
                : "text-zinc-500 hover:text-zinc-900 dark:hover:text-zinc-200"
            }`}
            title="Compact High-Density 36px View"
          >
            <Rows3 className="w-3.5 h-3.5" />
            <span className="hidden md:inline">Compact</span>
          </button>
        </div>

        {/* Settings button */}
        <button
          onClick={onOpenSettingsModal}
          className="h-8 w-8 rounded-lg bg-zinc-100 hover:bg-zinc-200 dark:bg-zinc-800/80 dark:hover:bg-zinc-700/80 text-zinc-600 dark:text-zinc-300 flex items-center justify-center transition-colors cursor-pointer border border-zinc-200 dark:border-zinc-700/60"
          title="Preferences & Settings"
        >
          <SlidersHorizontal className="w-4 h-4" />
        </button>
      </div>
    </header>
  );
};
