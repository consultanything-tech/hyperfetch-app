import React, { useEffect, useRef } from "react";
import {
  Play,
  Pause,
  FolderOpen,
  FileCheck,
  Copy,
  Trash2,
  ArrowUpToLine,
  ArrowUp,
  ArrowDown,
  ArrowDownToLine,
  FileCode,
  ListOrdered,
  CheckSquare,
} from "lucide-react";
import type { DownloadTask, QueueAction } from "../types/download";

export interface ContextMenuPosition {
  x: number;
  y: number;
}

interface ContextMenuProps {
  task: DownloadTask;
  position: ContextMenuPosition;
  isFirst: boolean;
  isLast: boolean;
  onClose: () => void;
  onPause: (id: string) => void;
  onResume: (id: string) => void;
  onDelete: (id: string) => void;
  onOpenFile: (path: string) => void;
  onOpenFolder: (path: string) => void;
  onCopyUrl: (url: string) => void;
  onCopyChecksum: (checksum?: string | null) => void;
  onQueueMove: (id: string, action: QueueAction) => void;
  onSelectAll?: () => void;
}

export const ContextMenu: React.FC<ContextMenuProps> = ({
  task,
  position,
  isFirst,
  isLast,
  onClose,
  onPause,
  onResume,
  onDelete,
  onOpenFile,
  onOpenFolder,
  onCopyUrl,
  onCopyChecksum,
  onQueueMove,
  onSelectAll,
}) => {
  const menuRef = useRef<HTMLDivElement>(null);

  // Close on outside click, blur, scroll, or Escape
  useEffect(() => {
    const handleClickOutside = (e: MouseEvent) => {
      if (menuRef.current && !menuRef.current.contains(e.target as Node)) {
        onClose();
      }
    };

    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        onClose();
      }
    };

    const handleBlur = () => {
      onClose();
    };

    const handleScroll = (e: Event) => {
      if (menuRef.current && !menuRef.current.contains(e.target as Node)) {
        onClose();
      }
    };

    window.addEventListener("mousedown", handleClickOutside);
    window.addEventListener("keydown", handleKeyDown);
    window.addEventListener("blur", handleBlur);
    window.addEventListener("scroll", handleScroll, true);
    return () => {
      window.removeEventListener("mousedown", handleClickOutside);
      window.removeEventListener("keydown", handleKeyDown);
      window.removeEventListener("blur", handleBlur);
      window.removeEventListener("scroll", handleScroll, true);
    };
  }, [onClose]);

  // Adjust position to stay inside viewport
  const menuWidth = 220;
  const menuHeight = 350;
  const adjustedX = Math.min(position.x, window.innerWidth - menuWidth - 10);
  const adjustedY = Math.min(position.y, window.innerHeight - menuHeight - 10);

  const isDownloading =
    task.status === "downloading" || task.status === "connecting";
  const isCompleted = task.status === "completed";

  return (
    <div
      ref={menuRef}
      style={{ left: `${Math.max(10, adjustedX)}px`, top: `${Math.max(10, adjustedY)}px` }}
      className="fixed z-50 w-56 rounded-xl bg-white/95 dark:bg-zinc-900/95 backdrop-blur-md border border-zinc-200 dark:border-zinc-800 shadow-xl py-1.5 text-xs text-zinc-700 dark:text-zinc-200 select-none animate-in fade-in-0 zoom-in-95 duration-100"
    >
      {/* Task preview title */}
      <div className="px-3 py-1.5 border-b border-zinc-100 dark:border-zinc-800/80 mb-1">
        <div className="font-semibold text-[11px] text-zinc-900 dark:text-zinc-100 truncate">
          {task.filename}
        </div>
        <div className="text-[10px] text-zinc-400 dark:text-zinc-500 capitalize">
          {task.status}
        </div>
      </div>

      {/* Pause / Resume */}
      {isDownloading ? (
        <button
          onClick={() => {
            onPause(task.id);
            onClose();
          }}
          className="w-full px-3 py-1.5 flex items-center gap-2 hover:bg-zinc-100 dark:hover:bg-zinc-800 text-left transition-colors cursor-pointer"
        >
          <Pause className="w-3.5 h-3.5 text-amber-500 fill-current" />
          <span>Pause Download</span>
        </button>
      ) : !isCompleted ? (
        <button
          onClick={() => {
            onResume(task.id);
            onClose();
          }}
          className="w-full px-3 py-1.5 flex items-center gap-2 hover:bg-zinc-100 dark:hover:bg-zinc-800 text-left transition-colors cursor-pointer"
        >
          <Play className="w-3.5 h-3.5 text-blue-500 fill-current" />
          <span>Resume Download</span>
        </button>
      ) : null}

      {/* Open File */}
      <button
        onClick={() => {
          if (isCompleted) {
            onOpenFile(task.destination_path);
            onClose();
          }
        }}
        disabled={!isCompleted}
        className={`w-full px-3 py-1.5 flex items-center gap-2 text-left transition-colors ${
          isCompleted
            ? "hover:bg-zinc-100 dark:hover:bg-zinc-800 cursor-pointer text-zinc-900 dark:text-zinc-100"
            : "text-zinc-400 dark:text-zinc-600 cursor-not-allowed"
        }`}
      >
        <FileCheck className="w-3.5 h-3.5 text-emerald-500" />
        <span>Open File</span>
      </button>

      {/* Show in Explorer */}
      <button
        onClick={() => {
          onOpenFolder(task.destination_path);
          onClose();
        }}
        className="w-full px-3 py-1.5 flex items-center gap-2 hover:bg-zinc-100 dark:hover:bg-zinc-800 text-left transition-colors cursor-pointer"
      >
        <FolderOpen className="w-3.5 h-3.5 text-zinc-500 dark:text-zinc-400" />
        <span>Show in Explorer</span>
      </button>

      <div className="my-1 border-t border-zinc-100 dark:border-zinc-800/80" />

      {onSelectAll && (
        <button
          onClick={() => {
            onSelectAll();
            onClose();
          }}
          className="w-full px-3 py-1.5 flex items-center justify-between hover:bg-zinc-100 dark:hover:bg-zinc-800 text-left transition-colors cursor-pointer"
        >
          <div className="flex items-center gap-2">
            <CheckSquare className="w-3.5 h-3.5 text-blue-500" />
            <span>Select All</span>
          </div>
          <span className="text-[10px] text-zinc-400 font-mono">⌘A</span>
        </button>
      )}

      {/* Copy Download Link */}
      <button
        onClick={() => {
          onCopyUrl(task.url);
          onClose();
        }}
        className="w-full px-3 py-1.5 flex items-center gap-2 hover:bg-zinc-100 dark:hover:bg-zinc-800 text-left transition-colors cursor-pointer"
      >
        <Copy className="w-3.5 h-3.5 text-zinc-400" />
        <span>Copy Download Link</span>
      </button>

      {/* Copy Checksum */}
      <button
        onClick={() => {
          onCopyChecksum(task.expected_checksum);
          onClose();
        }}
        disabled={!task.expected_checksum}
        className={`w-full px-3 py-1.5 flex items-center gap-2 text-left transition-colors ${
          task.expected_checksum
            ? "hover:bg-zinc-100 dark:hover:bg-zinc-800 cursor-pointer"
            : "text-zinc-400 dark:text-zinc-600 cursor-not-allowed"
        }`}
      >
        <FileCode className="w-3.5 h-3.5 text-zinc-400" />
        <span>Copy SHA-256 Checksum</span>
      </button>

      <div className="my-1 border-t border-zinc-100 dark:border-zinc-800/80" />

      {/* Queue Position section */}
      <div className="px-3 py-1 text-[10px] font-semibold uppercase tracking-wider text-zinc-400 dark:text-zinc-500 flex items-center gap-1.5">
        <ListOrdered className="w-3 h-3" />
        <span>Queue Position</span>
      </div>

      <button
        onClick={() => {
          onQueueMove(task.id, "top");
          onClose();
        }}
        disabled={isFirst}
        className={`w-full px-3 py-1.5 flex items-center gap-2 text-left transition-colors ${
          !isFirst
            ? "hover:bg-zinc-100 dark:hover:bg-zinc-800 cursor-pointer"
            : "text-zinc-400 dark:text-zinc-600 cursor-not-allowed"
        }`}
      >
        <ArrowUpToLine className="w-3.5 h-3.5" />
        <span>Move to Top</span>
      </button>

      <button
        onClick={() => {
          onQueueMove(task.id, "up");
          onClose();
        }}
        disabled={isFirst}
        className={`w-full px-3 py-1.5 flex items-center gap-2 text-left transition-colors ${
          !isFirst
            ? "hover:bg-zinc-100 dark:hover:bg-zinc-800 cursor-pointer"
            : "text-zinc-400 dark:text-zinc-600 cursor-not-allowed"
        }`}
      >
        <ArrowUp className="w-3.5 h-3.5" />
        <span>Move Up</span>
      </button>

      <button
        onClick={() => {
          onQueueMove(task.id, "down");
          onClose();
        }}
        disabled={isLast}
        className={`w-full px-3 py-1.5 flex items-center gap-2 text-left transition-colors ${
          !isLast
            ? "hover:bg-zinc-100 dark:hover:bg-zinc-800 cursor-pointer"
            : "text-zinc-400 dark:text-zinc-600 cursor-not-allowed"
        }`}
      >
        <ArrowDown className="w-3.5 h-3.5" />
        <span>Move Down</span>
      </button>

      <button
        onClick={() => {
          onQueueMove(task.id, "bottom");
          onClose();
        }}
        disabled={isLast}
        className={`w-full px-3 py-1.5 flex items-center gap-2 text-left transition-colors ${
          !isLast
            ? "hover:bg-zinc-100 dark:hover:bg-zinc-800 cursor-pointer"
            : "text-zinc-400 dark:text-zinc-600 cursor-not-allowed"
        }`}
      >
        <ArrowDownToLine className="w-3.5 h-3.5" />
        <span>Move to Bottom</span>
      </button>

      <div className="my-1 border-t border-zinc-100 dark:border-zinc-800/80" />

      {/* Delete */}
      <button
        onClick={() => {
          onDelete(task.id);
          onClose();
        }}
        className="w-full px-3 py-1.5 flex items-center gap-2 hover:bg-rose-50 dark:hover:bg-rose-950/40 text-rose-600 dark:text-rose-400 text-left transition-colors cursor-pointer"
      >
        <Trash2 className="w-3.5 h-3.5" />
        <span>Delete Task</span>
      </button>
    </div>
  );
};
