import React, { useState } from "react";
import {
  X,
  Play,
  Pause,
  Trash2,
  FolderOpen,
  FileCheck,
  Copy,
  Check,
  RotateCcw,
  ShieldCheck,
  ShieldAlert,
  Shield,
  Layers,
  Cpu,
  Radio,
  AlertCircle,
  FileCode,
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

interface TaskDetailInspectorProps {
  task: DownloadTask | null;
  onClose: () => void;
  onPause: (id: string) => void;
  onResume: (id: string) => void;
  onDelete: (id: string) => void;
  onOpenFile: (path: string) => void;
  onOpenFolder: (path: string) => void;
}

export const TaskDetailInspector: React.FC<TaskDetailInspectorProps> = ({
  task,
  onClose,
  onPause,
  onResume,
  onDelete,
  onOpenFile,
  onOpenFolder,
}) => {
  const [copiedUrl, setCopiedUrl] = useState(false);
  const [copiedChecksum, setCopiedChecksum] = useState(false);
  const [copiedPath, setCopiedPath] = useState(false);
  const [copiedError, setCopiedError] = useState(false);

  if (!task) {
    return (
      <aside className="w-[350px] shrink-0 border-l border-zinc-200 dark:border-zinc-800 bg-white/70 dark:bg-zinc-950/70 backdrop-blur-md flex flex-col h-full select-none">
        <div className="h-14 px-4 flex items-center justify-between border-b border-zinc-200 dark:border-zinc-800/80">
          <div className="text-xs font-semibold uppercase tracking-wider text-zinc-400 dark:text-zinc-500">
            Inspector
          </div>
          <button
            onClick={onClose}
            className="w-7 h-7 rounded-lg flex items-center justify-center text-zinc-400 hover:text-zinc-600 dark:hover:text-zinc-200 hover:bg-zinc-100 dark:hover:bg-zinc-800 transition-colors cursor-pointer"
            title="Close Inspector"
          >
            <X className="w-4 h-4" />
          </button>
        </div>
        <div className="flex-1 flex flex-col items-center justify-center text-center p-6 text-zinc-400 dark:text-zinc-500">
          <div className="w-12 h-12 rounded-2xl bg-zinc-100 dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 flex items-center justify-center mb-3 text-zinc-400">
            <Layers className="w-6 h-6 stroke-[1.5]" />
          </div>
          <div className="text-xs font-medium text-zinc-700 dark:text-zinc-300 mb-1">
            No Task Selected
          </div>
          <p className="text-[11px] text-zinc-400 dark:text-zinc-500 leading-relaxed max-w-[200px]">
            Click any download item in the list to inspect telemetry and connection chunks.
          </p>
        </div>
      </aside>
    );
  }

  const CategoryIcon = getCategoryIcon(task.category);
  const categoryColors = getCategoryBadgeColor(task.category);
  const statusDetails = getStatusDetails(task.status);
  const StatusIcon = statusDetails.icon;

  const isDownloading =
    task.status === "downloading" || task.status === "connecting";
  const progressPercent =
    task.total_bytes > 0
      ? Math.min(
          100,
          Math.round((task.downloaded_bytes / task.total_bytes) * 1000) / 10
        )
      : task.status === "completed"
      ? 100
      : 0;

  const chunkCount =
    task.chunks && task.chunks.length > 0
      ? task.chunks.length
      : task.preferred_chunk_count || 8;
  const completedChunks = task.chunks
    ? task.chunks.filter((c) => c.completed).length
    : 0;

  const handleCopyUrl = async () => {
    try {
      await navigator.clipboard.writeText(task.url);
      setCopiedUrl(true);
      setTimeout(() => setCopiedUrl(false), 1500);
    } catch (err) {
      console.error("Failed to copy URL:", err);
    }
  };

  const handleCopyPath = async () => {
    try {
      await navigator.clipboard.writeText(task.destination_path);
      setCopiedPath(true);
      setTimeout(() => setCopiedPath(false), 1500);
    } catch (err) {
      console.error("Failed to copy path:", err);
    }
  };

  const handleCopyChecksum = async () => {
    if (!task.expected_checksum) return;
    try {
      await navigator.clipboard.writeText(task.expected_checksum);
      setCopiedChecksum(true);
      setTimeout(() => setCopiedChecksum(false), 1500);
    } catch (err) {
      console.error("Failed to copy checksum:", err);
    }
  };

  const handleCopyError = async () => {
    if (!task.error) return;
    try {
      await navigator.clipboard.writeText(task.error);
      setCopiedError(true);
      setTimeout(() => setCopiedError(false), 1500);
    } catch (err) {
      console.error("Failed to copy error:", err);
    }
  };

  return (
    <aside
      className="w-[350px] shrink-0 border-l border-zinc-200 dark:border-zinc-800 bg-white/70 dark:bg-zinc-950/70 backdrop-blur-md flex flex-col h-full select-none overflow-hidden"
      aria-label="Download Inspector"
    >
      {/* Top Header */}
      <div className="h-14 px-4 flex items-center justify-between border-b border-zinc-200 dark:border-zinc-800/80 shrink-0">
        <div className="flex items-center gap-2">
          <span className="text-[11px] font-bold uppercase tracking-wider text-zinc-400 dark:text-zinc-500">
            Download Inspector
          </span>
          <span
            className={`inline-flex items-center gap-1 px-1.5 py-0.5 rounded-full text-[10px] font-medium border ${statusDetails.bg} ${statusDetails.color} ${statusDetails.border}`}
          >
            <StatusIcon className="w-2.5 h-2.5" />
            <span>{statusDetails.label}</span>
          </span>
        </div>

        <div className="flex items-center gap-1">
          {/* Quick Header Action (Pause/Resume) */}
          {isDownloading ? (
            <button
              onClick={() => onPause(task.id)}
              className="w-7 h-7 rounded-lg flex items-center justify-center text-zinc-500 hover:text-amber-500 hover:bg-zinc-100 dark:hover:bg-zinc-800 transition-colors cursor-pointer"
              title="Pause Download"
            >
              <Pause className="w-3.5 h-3.5 fill-current" />
            </button>
          ) : task.status !== "completed" ? (
            <button
              onClick={() => onResume(task.id)}
              className="w-7 h-7 rounded-lg flex items-center justify-center text-zinc-500 hover:text-blue-500 hover:bg-zinc-100 dark:hover:bg-zinc-800 transition-colors cursor-pointer"
              title="Resume Download"
            >
              <Play className="w-3.5 h-3.5 fill-current" />
            </button>
          ) : null}

          <button
            onClick={onClose}
            className="w-7 h-7 rounded-lg flex items-center justify-center text-zinc-400 hover:text-zinc-700 dark:hover:text-zinc-200 hover:bg-zinc-100 dark:hover:bg-zinc-800 transition-colors cursor-pointer"
            title="Close Inspector"
          >
            <X className="w-4 h-4" />
          </button>
        </div>
      </div>

      {/* Scrollable Inspector Body */}
      <div className="flex-1 overflow-y-auto p-4 space-y-4">
        {/* File Overview Card */}
        <div className="p-3 rounded-xl bg-white dark:bg-zinc-900/80 border border-zinc-200 dark:border-zinc-800/80 shadow-xs space-y-3">
          <div className="flex items-start gap-3">
            <div
              className={`w-11 h-11 rounded-xl flex items-center justify-center shrink-0 border ${categoryColors.bg} ${categoryColors.text} ${categoryColors.border}`}
            >
              <CategoryIcon className="w-5 h-5" />
            </div>
            <div className="flex-1 min-w-0">
              <h4
                className="text-xs font-bold text-zinc-900 dark:text-zinc-100 truncate cursor-pointer hover:underline"
                title={task.filename}
                onClick={() => {
                  if (task.status === "completed") {
                    onOpenFile(task.destination_path);
                  }
                }}
              >
                {task.filename}
              </h4>
              <div className="text-[10px] text-zinc-400 dark:text-zinc-500 capitalize mt-0.5">
                {task.category}
              </div>

              {/* Protocol Badges */}
              <div className="flex items-center gap-1.5 mt-2 flex-wrap">
                <span className="px-1.5 py-0.5 rounded text-[10px] font-mono font-medium bg-blue-500/10 text-blue-600 dark:text-blue-400 border border-blue-500/20">
                  {task.resumable ? `${chunkCount} Chunks` : "Single Stream"}
                </span>
                <span className="px-1.5 py-0.5 rounded text-[10px] font-mono font-medium bg-emerald-500/10 text-emerald-600 dark:text-emerald-400 border border-emerald-500/20">
                  {task.resumable ? "HTTP/2" : "HTTP/1.1"}
                </span>
                <span className="px-1.5 py-0.5 rounded text-[10px] font-mono text-zinc-500 dark:text-zinc-400 bg-zinc-100 dark:bg-zinc-800 border border-zinc-200 dark:border-zinc-700/60">
                  TLS 1.3
                </span>
              </div>
            </div>
          </div>

          {/* Progress Bar & Percentage */}
          <div className="space-y-1.5 pt-1">
            <div className="flex items-center justify-between text-[11px] font-mono">
              <span className="text-zinc-500 dark:text-zinc-400">Progress</span>
              <span className="font-bold text-zinc-900 dark:text-zinc-100">
                {task.total_bytes > 0
                  ? `${progressPercent.toFixed(1)}%`
                  : task.status === "completed"
                  ? "100%"
                  : "--"}
              </span>
            </div>
            <div
              className="w-full h-2 bg-zinc-100 dark:bg-zinc-800 rounded-full overflow-hidden"
              role="progressbar"
              aria-valuenow={task.status === "completed" ? 100 : progressPercent}
              aria-valuemin={0}
              aria-valuemax={100}
              aria-label={`Download progress for ${task.filename}`}
            >
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
          </div>
        </div>

        {/* Real-time Connection Segments Visualizer */}
        <div className="p-3 rounded-xl bg-white dark:bg-zinc-900/80 border border-zinc-200 dark:border-zinc-800/80 shadow-xs space-y-2.5">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-1.5 text-xs font-bold text-zinc-800 dark:text-zinc-200 uppercase tracking-wide">
              <Cpu className="w-3.5 h-3.5 text-blue-500" />
              <span>Connection Segments</span>
            </div>
            {task.chunks && task.chunks.length > 0 && (
              <span className="text-[10px] font-mono font-medium px-2 py-0.5 rounded-full bg-blue-500/10 text-blue-600 dark:text-blue-400 border border-blue-500/20">
                {completedChunks}/{task.chunks.length} completed
              </span>
            )}
          </div>

          {!task.chunks || task.chunks.length === 0 ? (
            <div className="p-3 rounded-lg bg-zinc-50 dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 text-[11px] text-zinc-500 dark:text-zinc-400 flex items-center gap-2">
              <Radio className="w-4 h-4 text-zinc-400 shrink-0" />
              <span>Segments will be allocated once server handshake finishes.</span>
            </div>
          ) : !task.resumable ? (
            <div className="p-2.5 rounded-lg bg-amber-500/10 border border-amber-500/20 text-[11px] text-amber-700 dark:text-amber-300 flex items-start gap-2">
              <AlertCircle className="w-4 h-4 text-amber-500 shrink-0 mt-0.5" />
              <div>
                <div className="font-semibold">Single Stream Direct Mode</div>
                <div className="text-[10.5px] opacity-90">
                  Server does not support range headers; downloading as 1 stream.
                </div>
              </div>
            </div>
          ) : (
            <>
              {/* Legend */}
              <div className="flex items-center gap-3 text-[10px] text-zinc-500 dark:text-zinc-400">
                <span className="flex items-center gap-1">
                  <span className="w-2 h-2 rounded-full bg-emerald-500 inline-block" />
                  Completed
                </span>
                <span className="flex items-center gap-1">
                  <span className="w-2 h-2 rounded-full bg-blue-500 inline-block" />
                  Active
                </span>
                <span className="flex items-center gap-1">
                  <span className="w-2 h-2 rounded-full bg-zinc-300 dark:bg-zinc-700 inline-block" />
                  Pending
                </span>
              </div>

              {/* Continuous Segmented Chunk Bar */}
              <div
                className="w-full h-3.5 bg-zinc-100 dark:bg-zinc-800 rounded-lg overflow-hidden flex gap-[2px] p-[2px] border border-zinc-200 dark:border-zinc-700/60"
                role="progressbar"
                aria-label="Multi-chunk download bar"
              >
                {task.chunks.map((chunk) => {
                  const chunkProgress =
                    chunk.total_bytes > 0
                      ? Math.min(
                          100,
                          Math.round((chunk.downloaded_bytes / chunk.total_bytes) * 100)
                        )
                      : chunk.completed
                      ? 100
                      : 0;

                  const isChunkActive =
                    isDownloading && !chunk.completed && chunk.downloaded_bytes > 0;

                  let bgClass = "bg-zinc-200 dark:bg-zinc-800";
                  if (chunk.completed) {
                    bgClass = "bg-emerald-500 dark:bg-emerald-500 shadow-xs";
                  } else if (isChunkActive) {
                    bgClass = "bg-blue-500";
                  } else if (chunk.downloaded_bytes > 0) {
                    bgClass = "bg-blue-400/50 dark:bg-blue-600/50";
                  }

                  return (
                    <div
                      key={chunk.index}
                      className={`h-full flex-1 rounded-xs relative overflow-hidden transition-all duration-300 ${bgClass}`}
                      title={`Chunk #${chunk.index + 1}: ${chunkProgress}% (${formatBytes(
                        chunk.downloaded_bytes
                      )} / ${formatBytes(chunk.total_bytes)})`}
                    >
                      {!chunk.completed && chunkProgress > 0 && (
                        <div
                          className="h-full bg-blue-500 transition-all duration-200"
                          style={{ width: `${chunkProgress}%` }}
                        />
                      )}
                    </div>
                  );
                })}
              </div>

              {/* Chunks Micro-Grid */}
              <div className="grid grid-cols-2 gap-2 pt-1 max-h-48 overflow-y-auto pr-1">
                {task.chunks.map((chunk) => {
                  const chunkPct =
                    chunk.total_bytes > 0
                      ? Math.min(
                          100,
                          Math.round(
                            (chunk.downloaded_bytes / chunk.total_bytes) * 100
                          )
                        )
                      : chunk.completed
                      ? 100
                      : 0;
                  const isActive =
                    isDownloading &&
                    !chunk.completed &&
                    chunk.downloaded_bytes > 0;

                  return (
                    <div
                      key={chunk.index}
                      className={`p-2 rounded-lg border text-[10px] font-mono flex flex-col justify-between transition-colors ${
                        chunk.completed
                          ? "bg-emerald-500/5 dark:bg-emerald-950/20 border-emerald-500/30 text-emerald-700 dark:text-emerald-300"
                          : isActive
                          ? "bg-blue-500/10 dark:bg-blue-950/30 border-blue-500/40 text-blue-700 dark:text-blue-300"
                          : "bg-zinc-50 dark:bg-zinc-900 border-zinc-200 dark:border-zinc-800 text-zinc-500 dark:text-zinc-400"
                      }`}
                    >
                      <div className="flex items-center justify-between font-semibold">
                        <span>Chunk #{chunk.index + 1}</span>
                        <span>{chunkPct}%</span>
                      </div>
                      <div className="text-[9px] opacity-80 mt-1 truncate">
                        {formatBytes(chunk.downloaded_bytes)} / {formatBytes(chunk.total_bytes)}
                      </div>
                      <div className="text-[8.5px] opacity-60 mt-0.5 truncate">
                        Bytes: {chunk.start_offset.toLocaleString()} - {chunk.end_offset.toLocaleString()}
                      </div>
                      {/* Micro progress line */}
                      <div className="w-full h-1 bg-zinc-200 dark:bg-zinc-800 rounded-full overflow-hidden mt-1.5">
                        <div
                          className={`h-full ${
                            chunk.completed
                              ? "bg-emerald-500"
                              : isActive
                              ? "bg-blue-500"
                              : "bg-zinc-400"
                          }`}
                          style={{ width: `${chunkPct}%` }}
                        />
                      </div>
                    </div>
                  );
                })}
              </div>
            </>
          )}
        </div>

        {/* Transfer Telemetry Metrics */}
        <div className="p-3 rounded-xl bg-white dark:bg-zinc-900/80 border border-zinc-200 dark:border-zinc-800/80 shadow-xs space-y-2.5">
          <div className="text-xs font-bold text-zinc-800 dark:text-zinc-200 uppercase tracking-wide">
            Telemetry & Metrics
          </div>

          <div className="space-y-2 text-xs">
            <div className="flex items-center justify-between">
              <span className="text-zinc-500 dark:text-zinc-400">Transferred:</span>
              <span className="font-mono font-medium text-zinc-900 dark:text-zinc-100">
                {formatBytes(task.downloaded_bytes)}
                {task.total_bytes > 0 && ` / ${formatBytes(task.total_bytes)}`}
              </span>
            </div>

            {isDownloading && (
              <>
                <div className="flex items-center justify-between">
                  <span className="text-zinc-500 dark:text-zinc-400">Current Speed:</span>
                  <span className="font-mono font-bold text-blue-600 dark:text-blue-400">
                    {formatSpeed(task.speed)}
                  </span>
                </div>
                <div className="flex items-center justify-between">
                  <span className="text-zinc-500 dark:text-zinc-400">Estimated Time:</span>
                  <span className="font-mono font-medium text-zinc-900 dark:text-zinc-100">
                    {formatEta(task.eta)}
                  </span>
                </div>
              </>
            )}

            <div className="flex items-center justify-between">
              <span className="text-zinc-500 dark:text-zinc-400">Connection Mode:</span>
              <span className="font-mono text-[11px] font-semibold text-zinc-700 dark:text-zinc-300">
                {task.resumable ? "Multi-Chunk Range" : "Single-Stream Direct"}
              </span>
            </div>

            {/* ETag Integrity Badge */}
            <div className="flex items-center justify-between pt-1 border-t border-zinc-100 dark:border-zinc-800/60">
              <span className="text-zinc-500 dark:text-zinc-400">ETag Status:</span>
              {task.etag ? (
                <span
                  className="inline-flex items-center gap-1 px-1.5 py-0.5 rounded text-[10px] font-mono bg-emerald-500/10 text-emerald-600 dark:text-emerald-400 border border-emerald-500/20 max-w-[170px] truncate"
                  title={`ETag: ${task.etag}`}
                >
                  <ShieldCheck className="w-3 h-3 shrink-0" />
                  <span className="truncate">{task.etag}</span>
                </span>
              ) : (
                <span className="text-[11px] font-mono text-zinc-400">None</span>
              )}
            </div>

            {/* SHA-256 Checksum Verification Badge */}
            <div className="flex items-center justify-between">
              <span className="text-zinc-500 dark:text-zinc-400">SHA-256 Integrity:</span>
              {task.checksum_verified === true ? (
                <span className="inline-flex items-center gap-1 px-1.5 py-0.5 rounded text-[10px] font-mono font-semibold bg-emerald-500/10 text-emerald-600 dark:text-emerald-400 border border-emerald-500/20">
                  <ShieldCheck className="w-3 h-3" />
                  <span>SHA-256: Verified</span>
                </span>
              ) : task.checksum_verified === false ? (
                <span className="inline-flex items-center gap-1 px-1.5 py-0.5 rounded text-[10px] font-mono font-semibold bg-rose-500/10 text-rose-600 dark:text-rose-400 border border-rose-500/20">
                  <ShieldAlert className="w-3 h-3" />
                  <span>SHA-256: Mismatch</span>
                </span>
              ) : task.expected_checksum ? (
                <span className="inline-flex items-center gap-1 px-1.5 py-0.5 rounded text-[10px] font-mono bg-amber-500/10 text-amber-600 dark:text-amber-400 border border-amber-500/20">
                  <Shield className="w-3 h-3" />
                  <span>Pending</span>
                </span>
              ) : (
                <span className="text-[11px] font-mono text-zinc-400">None</span>
              )}
            </div>

            {/* Date added / completed */}
            <div className="flex items-center justify-between pt-1 border-t border-zinc-100 dark:border-zinc-800/60">
              <span className="text-zinc-500 dark:text-zinc-400">Date Added:</span>
              <span className="font-mono text-[11px] text-zinc-600 dark:text-zinc-400">
                {new Date(task.created_at * 1000).toLocaleString(undefined, {
                  month: "short",
                  day: "numeric",
                  hour: "2-digit",
                  minute: "2-digit",
                })}
              </span>
            </div>

            {task.completed_at && (
              <div className="flex items-center justify-between">
                <span className="text-zinc-500 dark:text-zinc-400">Completed At:</span>
                <span className="font-mono text-[11px] text-zinc-600 dark:text-zinc-400">
                  {new Date(task.completed_at * 1000).toLocaleString(undefined, {
                    month: "short",
                    day: "numeric",
                    hour: "2-digit",
                    minute: "2-digit",
                  })}
                </span>
              </div>
            )}
          </div>
        </div>

        {/* Destination Path & Source Card */}
        <div className="p-3 rounded-xl bg-white dark:bg-zinc-900/80 border border-zinc-200 dark:border-zinc-800/80 shadow-xs space-y-3">
          <div className="text-xs font-bold text-zinc-800 dark:text-zinc-200 uppercase tracking-wide">
            Location & Destination
          </div>

          {/* Source URL */}
          <div className="space-y-1">
            <div className="flex items-center justify-between text-[11px] text-zinc-500 dark:text-zinc-400">
              <span>Source URL:</span>
              <button
                onClick={handleCopyUrl}
                className="flex items-center gap-1 text-[10.5px] text-blue-600 dark:text-blue-400 hover:underline cursor-pointer"
              >
                {copiedUrl ? (
                  <>
                    <Check className="w-3 h-3 text-emerald-500" />
                    <span className="text-emerald-500 font-semibold">Copied!</span>
                  </>
                ) : (
                  <>
                    <Copy className="w-3 h-3" />
                    <span>Copy URL</span>
                  </>
                )}
              </button>
            </div>
            <div
              className="p-1.5 rounded bg-zinc-50 dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 text-[10.5px] font-mono text-zinc-700 dark:text-zinc-300 break-all select-text"
              title={task.url}
            >
              {task.url}
            </div>
          </div>

          {/* Save Path */}
          <div className="space-y-1">
            <div className="flex items-center justify-between text-[11px] text-zinc-500 dark:text-zinc-400">
              <span>Destination Path:</span>
              <div className="flex items-center gap-2">
                <button
                  onClick={handleCopyPath}
                  className="flex items-center gap-1 text-[10.5px] text-zinc-500 hover:text-zinc-800 dark:hover:text-zinc-200 cursor-pointer"
                  title="Copy full path"
                >
                  {copiedPath ? (
                    <Check className="w-3 h-3 text-emerald-500" />
                  ) : (
                    <Copy className="w-3 h-3" />
                  )}
                </button>
                <button
                  onClick={() => onOpenFolder(task.destination_path)}
                  className="flex items-center gap-1 text-[10.5px] text-blue-600 dark:text-blue-400 hover:underline cursor-pointer"
                >
                  <FolderOpen className="w-3 h-3" />
                  <span>Reveal</span>
                </button>
              </div>
            </div>
            <div
              className="p-1.5 rounded bg-zinc-50 dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 text-[10.5px] font-mono text-zinc-700 dark:text-zinc-300 break-all select-text"
              title={task.destination_path}
            >
              {task.destination_path}
            </div>
          </div>

          {/* Checksum Value if present */}
          {task.expected_checksum && (
            <div className="space-y-1 pt-1 border-t border-zinc-100 dark:border-zinc-800/60">
              <div className="flex items-center justify-between text-[11px] text-zinc-500 dark:text-zinc-400">
                <span>Expected SHA-256:</span>
                <button
                  onClick={handleCopyChecksum}
                  className="flex items-center gap-1 text-[10.5px] text-blue-600 dark:text-blue-400 hover:underline cursor-pointer"
                >
                  {copiedChecksum ? (
                    <>
                      <Check className="w-3 h-3 text-emerald-500" />
                      <span className="text-emerald-500">Copied!</span>
                    </>
                  ) : (
                    <>
                      <Copy className="w-3 h-3" />
                      <span>Copy</span>
                    </>
                  )}
                </button>
              </div>
              <div className="p-1.5 rounded bg-zinc-50 dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 text-[10px] font-mono text-zinc-700 dark:text-zinc-300 break-all select-text">
                {task.expected_checksum}
              </div>
            </div>
          )}
        </div>

        {/* Error Diagnostics Card if failed */}
        {task.status === "failed" && task.error && (
          <div className="p-3 rounded-xl bg-rose-500/10 border border-rose-500/30 text-rose-700 dark:text-rose-300 space-y-2">
            <div className="flex items-center gap-1.5 text-xs font-bold">
              <AlertCircle className="w-4 h-4 text-rose-500" />
              <span>Error Diagnostics</span>
            </div>
            <div className="p-2 rounded bg-white/60 dark:bg-zinc-900/60 border border-rose-500/20 text-[11px] font-mono break-all select-text">
              {task.error}
            </div>
            <div className="flex items-center gap-2 pt-1">
              <button
                onClick={() => onResume(task.id)}
                className="px-2.5 py-1 rounded-md bg-rose-600 hover:bg-rose-500 text-white font-medium text-xs flex items-center gap-1 cursor-pointer"
              >
                <RotateCcw className="w-3 h-3" />
                <span>Retry Download</span>
              </button>
              <button
                onClick={handleCopyError}
                className="px-2 py-1 rounded-md bg-white dark:bg-zinc-900 border border-rose-300 dark:border-rose-900 text-rose-700 dark:text-rose-300 text-xs flex items-center gap-1 cursor-pointer"
              >
                {copiedError ? <Check className="w-3 h-3" /> : <Copy className="w-3 h-3" />}
                <span>Copy Error</span>
              </button>
            </div>
          </div>
        )}
      </div>

      {/* Footer Action Buttons */}
      <div className="p-3 border-t border-zinc-200 dark:border-zinc-800/80 bg-zinc-50/70 dark:bg-zinc-900/40 space-y-2 shrink-0">
        <div className="grid grid-cols-2 gap-2">
          {task.status === "completed" ? (
            <button
              onClick={() => onOpenFile(task.destination_path)}
              className="h-8 px-3 rounded-lg bg-emerald-600 hover:bg-emerald-500 active:bg-emerald-700 text-white font-medium text-xs flex items-center justify-center gap-1.5 shadow-sm transition-all cursor-pointer"
            >
              <FileCheck className="w-3.5 h-3.5" />
              <span>Open File</span>
            </button>
          ) : isDownloading ? (
            <button
              onClick={() => onPause(task.id)}
              className="h-8 px-3 rounded-lg bg-amber-500 hover:bg-amber-400 active:bg-amber-600 text-white font-medium text-xs flex items-center justify-center gap-1.5 shadow-sm transition-all cursor-pointer"
            >
              <Pause className="w-3.5 h-3.5 fill-current" />
              <span>Pause</span>
            </button>
          ) : (
            <button
              onClick={() => onResume(task.id)}
              className="h-8 px-3 rounded-lg bg-blue-600 hover:bg-blue-500 active:bg-blue-700 text-white font-medium text-xs flex items-center justify-center gap-1.5 shadow-sm transition-all cursor-pointer"
            >
              <Play className="w-3.5 h-3.5 fill-current" />
              <span>Resume</span>
            </button>
          )}

          <button
            onClick={() => onOpenFolder(task.destination_path)}
            className="h-8 px-3 rounded-lg bg-zinc-100 hover:bg-zinc-200 dark:bg-zinc-800 dark:hover:bg-zinc-700 text-zinc-700 dark:text-zinc-200 font-medium text-xs flex items-center justify-center gap-1.5 border border-zinc-200 dark:border-zinc-700/60 transition-colors cursor-pointer"
          >
            <FolderOpen className="w-3.5 h-3.5" />
            <span>In Explorer</span>
          </button>
        </div>

        <div className="flex items-center gap-2">
          <button
            onClick={handleCopyUrl}
            className="flex-1 h-7 rounded-md bg-white dark:bg-zinc-900 hover:bg-zinc-50 dark:hover:bg-zinc-800 text-zinc-600 dark:text-zinc-300 text-[11px] font-medium flex items-center justify-center gap-1 border border-zinc-200 dark:border-zinc-800 transition-colors cursor-pointer"
          >
            {copiedUrl ? <Check className="w-3 h-3 text-emerald-500" /> : <Copy className="w-3 h-3" />}
            <span>Copy URL</span>
          </button>

          {task.expected_checksum && (
            <button
              onClick={handleCopyChecksum}
              className="flex-1 h-7 rounded-md bg-white dark:bg-zinc-900 hover:bg-zinc-50 dark:hover:bg-zinc-800 text-zinc-600 dark:text-zinc-300 text-[11px] font-medium flex items-center justify-center gap-1 border border-zinc-200 dark:border-zinc-800 transition-colors cursor-pointer"
            >
              {copiedChecksum ? (
                <Check className="w-3 h-3 text-emerald-500" />
              ) : (
                <FileCode className="w-3 h-3" />
              )}
              <span>Checksum</span>
            </button>
          )}

          <button
            onClick={() => onDelete(task.id)}
            className="h-7 px-2.5 rounded-md bg-rose-500/10 hover:bg-rose-500/20 text-rose-600 dark:text-rose-400 text-[11px] font-medium flex items-center justify-center gap-1 border border-rose-500/20 transition-colors cursor-pointer"
            title="Delete Download Task"
          >
            <Trash2 className="w-3 h-3" />
            <span>Delete</span>
          </button>
        </div>
      </div>
    </aside>
  );
};
