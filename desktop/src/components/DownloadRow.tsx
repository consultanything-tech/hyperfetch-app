import React, { useState } from "react";
import {
  Play,
  Pause,
  Trash2,
  FolderOpen,
  FileCheck,
  ChevronDown,
  ChevronUp,
  Zap,
} from "lucide-react";
import type { DownloadTask } from "../types/download";
import {
  formatBytes,
  formatSpeed,
  formatEta,
  getCategoryIcon,
  getCategoryBadgeColor,
  getStatusDetails,
} from "../utils/format";
import { ChunkVisualizer } from "./ChunkVisualizer";

interface DownloadRowProps {
  task: DownloadTask;
  isSelected: boolean;
  onToggleSelect: (id: string) => void;
  onPause: (id: string) => void;
  onResume: (id: string) => void;
  onDelete: (id: string) => void;
  onOpenFile: (path: string) => void;
  onOpenFolder: (path: string) => void;
}

export const DownloadRow: React.FC<DownloadRowProps> = ({
  task,
  isSelected,
  onToggleSelect,
  onPause,
  onResume,
  onDelete,
  onOpenFile,
  onOpenFolder,
}) => {
  const [showChunks, setShowChunks] = useState(false);

  const CategoryIcon = getCategoryIcon(task.category);
  const categoryColors = getCategoryBadgeColor(task.category);
  const statusDetails = getStatusDetails(task.status);
  const StatusIcon = statusDetails.icon;

  const progressPercent =
    task.total_bytes > 0
      ? Math.min(
          100,
          Math.round((task.downloaded_bytes / task.total_bytes) * 1000) / 10
        )
      : task.status === "completed"
      ? 100
      : 0;

  const isDownloading =
    task.status === "downloading" || task.status === "connecting";

  return (
    <div
      className={`group relative rounded-xl border transition-all duration-150 p-3.5 select-none ${
        isSelected
          ? "bg-blue-50/80 dark:bg-blue-950/20 border-blue-500/50 shadow-sm"
          : "bg-white dark:bg-zinc-900/60 hover:bg-zinc-50 dark:hover:bg-zinc-800/40 border-zinc-200 dark:border-zinc-800/80 shadow-xs"
      }`}
    >
      <div className="flex items-start gap-3.5">
        {/* Selection Checkbox */}
        <div className="pt-2">
          <input
            type="checkbox"
            checked={isSelected}
            onChange={() => onToggleSelect(task.id)}
            className="w-4 h-4 rounded text-blue-600 border-zinc-300 dark:border-zinc-700 focus:ring-blue-500 cursor-pointer"
          />
        </div>

        {/* High Craft File Format Squircle Badge */}
        <div
          className={`w-11 h-11 rounded-xl flex items-center justify-center shrink-0 border ${categoryColors.bg} ${categoryColors.text} ${categoryColors.border}`}
        >
          <CategoryIcon className="w-5 h-5" />
        </div>

        {/* Core Content Area */}
        <div className="flex-1 min-w-0">
          {/* Row 1: Filename + Badges + Progress % */}
          <div className="flex items-center justify-between gap-2 mb-1.5">
            <div className="flex items-center gap-2 min-w-0">
              <span
                className="text-sm font-semibold text-zinc-900 dark:text-zinc-100 truncate cursor-pointer hover:underline"
                title={task.filename}
                onClick={() => {
                  if (task.status === "completed") {
                    onOpenFile(task.destination_path);
                  }
                }}
              >
                {task.filename}
              </span>

              {/* Multi-Chunk Acceleration Badge */}
              {task.resumable && task.status !== "completed" && (
                <span className="hidden sm:inline-flex items-center gap-1 px-1.5 py-0.5 rounded-full text-[10px] font-mono font-medium bg-blue-500/10 text-blue-600 dark:text-blue-400 border border-blue-500/20">
                  <Zap className="w-2.5 h-2.5 fill-current" />
                  Multi-Chunk
                </span>
              )}

              {/* Status Pill */}
              <span
                className={`inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[10.5px] font-medium border ${statusDetails.bg} ${statusDetails.color} ${statusDetails.border}`}
              >
                <StatusIcon className="w-3 h-3" />
                <span>{statusDetails.label}</span>
              </span>
            </div>

            {/* Percentage Display */}
            <div className="text-right shrink-0">
              <span className="text-sm font-bold font-mono text-zinc-900 dark:text-zinc-100">
                {task.total_bytes > 0
                  ? `${progressPercent.toFixed(1)}%`
                  : task.status === "completed"
                  ? "100%"
                  : "--"}
              </span>
            </div>
          </div>

          {/* Row 2: Progress Bar */}
          <div className="w-full h-2 bg-zinc-100 dark:bg-zinc-800 rounded-full overflow-hidden mb-2">
            <div
              className={`h-full rounded-full transition-all duration-300 ${
                task.status === "completed"
                  ? "bg-emerald-500"
                  : task.status === "failed"
                  ? "bg-rose-500"
                  : task.status === "paused"
                  ? "bg-amber-500"
                  : "bg-gradient-to-r from-blue-600 to-cyan-500 shadow-sm"
              }`}
              style={{
                width: `${task.status === "completed" ? 100 : progressPercent}%`,
              }}
            />
          </div>

          {/* Row 3: Metrics (Size, Speed, ETA) + Actions */}
          <div className="flex items-center justify-between gap-4 text-xs">
            {/* Left Metrics */}
            <div className="flex items-center gap-3 text-zinc-500 dark:text-zinc-400 font-mono text-[11px] flex-wrap">
              <span>
                {formatBytes(task.downloaded_bytes)}
                {task.total_bytes > 0 && ` / ${formatBytes(task.total_bytes)}`}
              </span>

              {isDownloading && task.speed > 0 && (
                <>
                  <span className="text-zinc-300 dark:text-zinc-700">•</span>
                  <span className="text-blue-600 dark:text-blue-400 font-semibold">
                    {formatSpeed(task.speed)}
                  </span>
                </>
              )}

              {isDownloading && task.eta > 0 && (
                <>
                  <span className="text-zinc-300 dark:text-zinc-700">•</span>
                  <span>ETA: {formatEta(task.eta)}</span>
                </>
              )}

              {task.error && (
                <span className="text-rose-500 font-sans truncate max-w-xs">
                  {task.error}
                </span>
              )}
            </div>

            {/* Right Action Buttons */}
            <div className="flex items-center gap-1.5 shrink-0">
              {/* Chunk visualizer toggle */}
              {task.chunks && task.chunks.length > 0 && (
                <button
                  onClick={() => setShowChunks(!showChunks)}
                  className={`h-7 px-2 rounded-lg text-[11px] font-medium flex items-center gap-1 transition-colors cursor-pointer border ${
                    showChunks
                      ? "bg-blue-500/10 text-blue-600 dark:text-blue-400 border-blue-500/30"
                      : "bg-zinc-100 hover:bg-zinc-200 dark:bg-zinc-800 dark:hover:bg-zinc-700 text-zinc-600 dark:text-zinc-300 border-zinc-200 dark:border-zinc-700"
                  }`}
                  title="Toggle active chunks visualizer"
                >
                  <span>Chunks ({task.chunks.length})</span>
                  {showChunks ? (
                    <ChevronUp className="w-3 h-3" />
                  ) : (
                    <ChevronDown className="w-3 h-3" />
                  )}
                </button>
              )}

              {/* Pause / Resume button */}
              {isDownloading ? (
                <button
                  onClick={() => onPause(task.id)}
                  className="h-7 w-7 rounded-lg bg-zinc-100 hover:bg-amber-500/10 hover:text-amber-600 dark:bg-zinc-800 dark:hover:bg-amber-500/20 dark:hover:text-amber-400 text-zinc-600 dark:text-zinc-300 flex items-center justify-center transition-colors cursor-pointer border border-zinc-200 dark:border-zinc-700"
                  title="Pause Download"
                >
                  <Pause className="w-3.5 h-3.5 fill-current" />
                </button>
              ) : task.status !== "completed" ? (
                <button
                  onClick={() => onResume(task.id)}
                  className="h-7 w-7 rounded-lg bg-zinc-100 hover:bg-blue-500/10 hover:text-blue-600 dark:bg-zinc-800 dark:hover:bg-blue-500/20 dark:hover:text-blue-400 text-zinc-600 dark:text-zinc-300 flex items-center justify-center transition-colors cursor-pointer border border-zinc-200 dark:border-zinc-700"
                  title="Resume Download"
                >
                  <Play className="w-3.5 h-3.5 fill-current" />
                </button>
              ) : (
                <button
                  onClick={() => onOpenFile(task.destination_path)}
                  className="h-7 px-2.5 rounded-lg bg-emerald-500/10 hover:bg-emerald-500/20 text-emerald-600 dark:text-emerald-400 flex items-center gap-1 text-[11px] font-medium transition-colors cursor-pointer border border-emerald-500/30"
                  title="Open Downloaded File"
                >
                  <FileCheck className="w-3.5 h-3.5" />
                  <span>Open</span>
                </button>
              )}

              {/* Open in Folder (Finder/Explorer) button */}
              <button
                onClick={() => onOpenFolder(task.destination_path)}
                className="h-7 w-7 rounded-lg bg-zinc-100 hover:bg-zinc-200 dark:bg-zinc-800 dark:hover:bg-zinc-700 text-zinc-600 dark:text-zinc-300 flex items-center justify-center transition-colors cursor-pointer border border-zinc-200 dark:border-zinc-700"
                title="Show in Folder"
              >
                <FolderOpen className="w-3.5 h-3.5" />
              </button>

              {/* Delete button */}
              <button
                onClick={() => onDelete(task.id)}
                className="h-7 w-7 rounded-lg bg-zinc-100 hover:bg-rose-500/10 hover:text-rose-600 dark:bg-zinc-800 dark:hover:bg-rose-500/20 dark:hover:text-rose-400 text-zinc-400 hover:text-rose-500 flex items-center justify-center transition-colors cursor-pointer border border-zinc-200 dark:border-zinc-700"
                title="Delete Download Task"
              >
                <Trash2 className="w-3.5 h-3.5" />
              </button>
            </div>
          </div>

          {/* Collapsible Chunk Visualizer */}
          {showChunks && (
            <ChunkVisualizer
              chunks={task.chunks}
              totalBytes={task.total_bytes}
              isDownloading={isDownloading}
            />
          )}
        </div>
      </div>
    </div>
  );
};
