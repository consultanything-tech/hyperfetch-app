import React from "react";
import type { Chunk } from "../types/download";
import { formatBytes } from "../utils/format";

interface ChunkVisualizerProps {
  chunks: Chunk[];
  totalBytes: number;
  isDownloading: boolean;
}

export const ChunkVisualizer: React.FC<ChunkVisualizerProps> = ({
  chunks,
  totalBytes,
  isDownloading,
}) => {
  if (!chunks || chunks.length === 0) {
    return null;
  }

  return (
    <div className="w-full space-y-2 mt-3 pt-3 border-t border-zinc-200 dark:border-zinc-800/80">
      <div className="flex items-center justify-between text-[11px] text-zinc-500 dark:text-zinc-400 font-mono">
        <span className="flex items-center gap-1.5 font-medium">
          <span className="w-2 h-2 rounded-full bg-blue-500 inline-block"></span>
          Parallel Chunks ({chunks.length} segments)
        </span>
        <span className="text-[10px]">
          {chunks.filter((c) => c.completed).length} / {chunks.length} completed
          {totalBytes > 0 && ` (${formatBytes(totalBytes)})`}
        </span>
      </div>

      {/* Multi-segment chunk bar */}
      <div className="w-full h-3 bg-zinc-200 dark:bg-zinc-800/90 rounded-md overflow-hidden flex gap-[2px] p-[2px]">
        {chunks.map((chunk) => {
          const chunkProgress =
            chunk.total_bytes > 0
              ? Math.min(100, Math.round((chunk.downloaded_bytes / chunk.total_bytes) * 100))
              : chunk.completed
              ? 100
              : 0;

          const isChunkActive =
            isDownloading && !chunk.completed && chunk.downloaded_bytes > 0;

          let bgClass = "bg-zinc-400/30 dark:bg-zinc-700/50";
          if (chunk.completed) {
            bgClass = "bg-blue-500 dark:bg-blue-500 shadow-sm";
          } else if (isChunkActive) {
            bgClass = "bg-cyan-500 animate-pulse";
          } else if (chunk.downloaded_bytes > 0) {
            bgClass = "bg-blue-400/60 dark:bg-blue-600/60";
          }

          return (
            <div
              key={chunk.index}
              className={`h-full flex-1 rounded-xs transition-all duration-300 relative group overflow-hidden ${bgClass}`}
              title={`Chunk #${chunk.index + 1}: ${chunkProgress}% (${formatBytes(
                chunk.downloaded_bytes
              )} / ${formatBytes(chunk.total_bytes)})`}
            >
              {/* Internal micro-progress bar for partially downloaded chunk */}
              {!chunk.completed && chunkProgress > 0 && (
                <div
                  className="h-full bg-blue-500/80 transition-all duration-200"
                  style={{ width: `${chunkProgress}%` }}
                />
              )}
            </div>
          );
        })}
      </div>

      {/* Micro-grid of chunk pills */}
      <div className="grid grid-cols-4 sm:grid-cols-8 gap-1.5 pt-1">
        {chunks.map((chunk) => {
          const chunkProgress =
            chunk.total_bytes > 0
              ? Math.min(100, Math.round((chunk.downloaded_bytes / chunk.total_bytes) * 100))
              : chunk.completed
              ? 100
              : 0;

          const isActive =
            isDownloading && !chunk.completed && chunk.downloaded_bytes > 0;

          return (
            <div
              key={chunk.index}
              className={`px-1.5 py-1 rounded text-[10px] font-mono flex flex-col items-center justify-center border transition-colors ${
                chunk.completed
                  ? "bg-blue-500/10 border-blue-500/30 text-blue-600 dark:text-blue-400 font-semibold"
                  : isActive
                  ? "bg-cyan-500/10 border-cyan-500/40 text-cyan-600 dark:text-cyan-400 animate-pulse"
                  : "bg-zinc-100 dark:bg-zinc-900/60 border-zinc-200 dark:border-zinc-800 text-zinc-500 dark:text-zinc-400"
              }`}
            >
              <div className="flex items-center gap-1">
                <span>#{chunk.index + 1}</span>
                <span className="text-[9px] opacity-80">{chunkProgress}%</span>
              </div>
              <div className="text-[8.5px] opacity-70 truncate max-w-full">
                {formatBytes(chunk.downloaded_bytes)}
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
};
