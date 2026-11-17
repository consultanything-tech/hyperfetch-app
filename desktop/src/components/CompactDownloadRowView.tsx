import React from "react";
import {
  Play,
  Pause,
  Trash2,
  FolderOpen,
  FileCheck,
} from "lucide-react";
import type { DownloadTask } from "../types/download";
import {
  formatBytes,
  formatSpeed,
  getCategoryIcon,
  getCategoryBadgeColor,
} from "../utils/format";

interface CompactDownloadRowViewProps {
  task: DownloadTask;
  isSelected: boolean;
  onSelectRow: (id: string, e: React.MouseEvent) => void;
  onToggleCheckbox: (id: string) => void;
  onPause: (id: string) => void;
  onResume: (id: string) => void;
  onDelete: (id: string) => void;
  onOpenFile: (path: string) => void;
  onOpenFolder: (path: string) => void;
  onContextMenu: (task: DownloadTask, e: React.MouseEvent) => void;
}

export const CompactDownloadRowView: React.FC<CompactDownloadRowViewProps> = ({
  task,
  isSelected,
  onSelectRow,
  onToggleCheckbox,
  onPause,
  onResume,
  onDelete,
  onOpenFile,
  onOpenFolder,
  onContextMenu,
}) => {
  const CategoryIcon = getCategoryIcon(task.category);
  const categoryColors = getCategoryBadgeColor(task.category);

  const progressPercent =
    task.total_bytes > 0
      ? Math.min(
          100,
          Math.round((task.downloaded_bytes / task.total_bytes) * 100)
        )
      : task.status === "completed"
      ? 100
      : 0;

  const isDownloading =
    task.status === "downloading" || task.status === "connecting";

  let statusDotColor = "bg-zinc-400";
  if (task.status === "downloading") statusDotColor = "bg-blue-500 animate-pulse";
  else if (task.status === "connecting") statusDotColor = "bg-cyan-500 animate-pulse";
  else if (task.status === "completed") statusDotColor = "bg-emerald-500";
  else if (task.status === "paused") statusDotColor = "bg-amber-500";
  else if (task.status === "failed") statusDotColor = "bg-rose-500";

  return (
    <div
      onClick={(e) => onSelectRow(task.id, e)}
      onContextMenu={(e) => {
        e.preventDefault();
        onContextMenu(task, e);
      }}
      className={`h-9 px-3 flex items-center gap-2.5 rounded-lg border text-xs select-none transition-colors group cursor-pointer ${
        isSelected
          ? "ring-1 ring-blue-500/50 bg-blue-50/50 dark:bg-blue-950/20 border-blue-500/50 shadow-xs"
          : "bg-white dark:bg-zinc-900/60 hover:bg-zinc-50 dark:hover:bg-zinc-800/40 border-zinc-200/80 dark:border-zinc-800/80"
      }`}
    >
      {/* Checkbox */}
      <input
        type="checkbox"
        checked={isSelected}
        onClick={(e) => e.stopPropagation()}
        onChange={() => onToggleCheckbox(task.id)}
        className="w-3.5 h-3.5 rounded text-blue-600 border-zinc-300 dark:border-zinc-700 focus:ring-blue-500 cursor-pointer focus-visible:ring-2 focus-visible:ring-blue-500"
        aria-label={`Select ${task.filename}`}
      />

      {/* Mini Format Icon */}
      <div
        className={`w-5 h-5 rounded flex items-center justify-center shrink-0 border ${categoryColors.bg} ${categoryColors.text} ${categoryColors.border}`}
      >
        <CategoryIcon className="w-3 h-3" />
      </div>

      {/* Status Dot */}
      <div
        className={`w-2 h-2 rounded-full shrink-0 ${statusDotColor}`}
        title={`Status: ${task.status}`}
      />

      {/* Filename */}
      <div
        className="flex-1 min-w-0 font-medium text-zinc-900 dark:text-zinc-100 truncate hover:underline text-[12px]"
        title={task.filename}
        onDoubleClick={(e) => {
          e.stopPropagation();
          if (task.status === "completed") {
            onOpenFile(task.destination_path);
          } else if (isDownloading) {
            onPause(task.id);
          } else {
            onResume(task.id);
          }
        }}
      >
        {task.filename}
      </div>

      {/* Inline Mini Progress Bar */}
      {task.status !== "completed" && (
        <div
          className="w-24 h-1.5 bg-zinc-200 dark:bg-zinc-800 rounded-full overflow-hidden shrink-0 hidden sm:block"
          role="progressbar"
          aria-valuenow={progressPercent}
          aria-valuemin={0}
          aria-valuemax={100}
          aria-label={`Progress for ${task.filename}`}
        >
          <div
            className={`h-full rounded-full transition-all duration-300 ${
              task.status === "failed"
                ? "bg-rose-500"
                : task.status === "paused"
                ? "bg-amber-500"
                : "bg-blue-500"
            }`}
            style={{ width: `${progressPercent}%` }}
          />
        </div>
      )}

      {/* Speed / Percentage / Size readout */}
      <div className="w-36 text-right font-mono text-[11px] text-zinc-500 dark:text-zinc-400 shrink-0 truncate">
        {isDownloading && task.speed > 0 ? (
          <span className="text-blue-600 dark:text-blue-400 font-semibold">
            {formatSpeed(task.speed)}
          </span>
        ) : task.status === "completed" ? (
          <span className="text-emerald-600 dark:text-emerald-400 font-medium">
            {formatBytes(task.downloaded_bytes)}
          </span>
        ) : task.total_bytes > 0 ? (
          <span>
            {progressPercent}% of {formatBytes(task.total_bytes)}
          </span>
        ) : (
          <span>{task.status}</span>
        )}
      </div>

      {/* Compact Quick Actions */}
      <div className="flex items-center gap-1 shrink-0 opacity-80 group-hover:opacity-100 transition-opacity">
        {isDownloading ? (
          <button
            onClick={(e) => {
              e.stopPropagation();
              onPause(task.id);
            }}
            className="w-6 h-6 rounded flex items-center justify-center text-zinc-500 hover:text-amber-500 hover:bg-zinc-100 dark:hover:bg-zinc-800 cursor-pointer focus-visible:ring-2 focus-visible:ring-blue-500"
            title="Pause"
            aria-label="Pause"
          >
            <Pause className="w-3 h-3 fill-current" />
          </button>
        ) : task.status !== "completed" ? (
          <button
            onClick={(e) => {
              e.stopPropagation();
              onResume(task.id);
            }}
            className="w-6 h-6 rounded flex items-center justify-center text-zinc-500 hover:text-blue-500 hover:bg-zinc-100 dark:hover:bg-zinc-800 cursor-pointer focus-visible:ring-2 focus-visible:ring-blue-500"
            title="Resume"
            aria-label="Resume"
          >
            <Play className="w-3 h-3 fill-current" />
          </button>
        ) : (
          <button
            onClick={(e) => {
              e.stopPropagation();
              onOpenFile(task.destination_path);
            }}
            className="w-6 h-6 rounded flex items-center justify-center text-emerald-600 hover:bg-emerald-500/10 cursor-pointer focus-visible:ring-2 focus-visible:ring-emerald-500"
            title="Open File"
            aria-label="Open File"
          >
            <FileCheck className="w-3 h-3" />
          </button>
        )}

        <button
          onClick={(e) => {
            e.stopPropagation();
            onOpenFolder(task.destination_path);
          }}
          className="w-6 h-6 rounded flex items-center justify-center text-zinc-500 hover:text-zinc-900 dark:hover:text-zinc-200 hover:bg-zinc-100 dark:hover:bg-zinc-800 cursor-pointer focus-visible:ring-2 focus-visible:ring-blue-500"
          title="Show in Folder"
          aria-label="Show in Folder"
        >
          <FolderOpen className="w-3 h-3" />
        </button>

        <button
          onClick={(e) => {
            e.stopPropagation();
            onDelete(task.id);
          }}
          className="w-6 h-6 rounded flex items-center justify-center text-zinc-400 hover:text-rose-500 hover:bg-zinc-100 dark:hover:bg-zinc-800 cursor-pointer focus-visible:ring-2 focus-visible:ring-rose-500"
          title="Delete"
          aria-label="Delete"
        >
          <Trash2 className="w-3 h-3" />
        </button>
      </div>
    </div>
  );
};
