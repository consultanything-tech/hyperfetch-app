import React, { useState, useEffect } from "react";
import {
  Layers,
  Download,
  Pause,
  CheckCircle2,
  AlertCircle,
  Film,
  Music,
  FileText,
  Archive,
  Cpu,
  File,
  HardDrive,
  Coffee,
  ExternalLink,
  ArrowDown,
} from "lucide-react";
import type { DownloadTask, SidebarFilter } from "../types/download";
import { formatSpeed } from "../utils/format";
import { openUrl } from "@tauri-apps/plugin-opener";

interface SidebarProps {
  currentFilter: SidebarFilter;
  onSelectFilter: (filter: SidebarFilter) => void;
  tasks: DownloadTask[];
}

export const Sidebar: React.FC<SidebarProps> = ({
  currentFilter,
  onSelectFilter,
  tasks,
}) => {
  // Rolling speed samples for live sparkline (8-10 samples)
  const [speedHistory, setSpeedHistory] = useState<number[]>([
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  ]);

  // Counts calculation
  const totalCount = tasks.length;
  const downloadingCount = tasks.filter(
    (t) => t.status === "downloading" || t.status === "connecting"
  ).length;
  const pausedCount = tasks.filter((t) => t.status === "paused").length;
  const completedCount = tasks.filter((t) => t.status === "completed").length;
  const failedCount = tasks.filter((t) => t.status === "failed").length;

  const videosCount = tasks.filter((t) => t.category === "videos").length;
  const musicCount = tasks.filter((t) => t.category === "music").length;
  const documentsCount = tasks.filter((t) => t.category === "documents").length;
  const archivesCount = tasks.filter((t) => t.category === "archives").length;
  const programsCount = tasks.filter((t) => t.category === "programs").length;
  const othersCount = tasks.filter((t) => t.category === "others").length;

  // Bandwidth telemetry
  const totalSpeed = tasks
    .filter((t) => t.status === "downloading" || t.status === "connecting")
    .reduce((acc, t) => acc + (t.speed || 0), 0);

  // Maintain rolling speed history buffer sampled every second
  useEffect(() => {
    const timer = setInterval(() => {
      setSpeedHistory((prev) => {
        const next = [...prev.slice(1), totalSpeed];
        return next;
      });
    }, 1000);
    return () => clearInterval(timer);
  }, [totalSpeed]);

  const transferItems = [
    {
      id: "all" as SidebarFilter,
      label: "All Downloads",
      icon: Layers,
      count: totalCount,
      color: "text-blue-500",
    },
    {
      id: "downloading" as SidebarFilter,
      label: "Downloading",
      icon: Download,
      count: downloadingCount,
      color: "text-blue-500",
    },
    {
      id: "paused" as SidebarFilter,
      label: "Paused",
      icon: Pause,
      count: pausedCount,
      color: "text-amber-500",
    },
    {
      id: "completed" as SidebarFilter,
      label: "Completed",
      icon: CheckCircle2,
      count: completedCount,
      color: "text-emerald-500",
    },
    {
      id: "failed" as SidebarFilter,
      label: "Failed",
      icon: AlertCircle,
      count: failedCount,
      color: "text-rose-500",
    },
  ];

  // Category labels aligned with macOS HyperFetch
  const categoryItems = [
    {
      id: "videos" as SidebarFilter,
      label: "Video & Media",
      icon: Film,
      count: videosCount,
      color: "text-purple-500",
    },
    {
      id: "music" as SidebarFilter,
      label: "Audio & Music",
      icon: Music,
      count: musicCount,
      color: "text-pink-500",
    },
    {
      id: "archives" as SidebarFilter,
      label: "Archives",
      icon: Archive,
      count: archivesCount,
      color: "text-amber-500",
    },
    {
      id: "documents" as SidebarFilter,
      label: "Documents",
      icon: FileText,
      count: documentsCount,
      color: "text-blue-400",
    },
    {
      id: "programs" as SidebarFilter,
      label: "Applications & Disk",
      icon: Cpu,
      count: programsCount,
      color: "text-emerald-400",
    },
    {
      id: "others" as SidebarFilter,
      label: "Other",
      icon: File,
      count: othersCount,
      color: "text-zinc-400",
    },
  ];

  const handleOpenKofi = async () => {
    try {
      await openUrl("https://ko-fi.com/consultanything");
    } catch {
      window.open("https://ko-fi.com/consultanything", "_blank");
    }
  };

  // Compute maximum speed in current rolling window for normalization
  const maxRecordedSpeed = Math.max(...speedHistory, 1);

  return (
    <aside className="w-64 h-full flex flex-col bg-zinc-50/80 dark:bg-zinc-900/40 border-r border-zinc-200 dark:border-zinc-800/80 select-none shrink-0">
      {/* App brand header */}
      <div className="h-14 px-5 flex items-center gap-3 border-b border-zinc-200 dark:border-zinc-800/60 shrink-0">
        <div className="w-8 h-8 rounded-xl bg-gradient-to-tr from-blue-600 to-indigo-500 flex items-center justify-center shadow-md shadow-blue-500/20 text-white font-bold text-sm">
          <Download className="w-4 h-4 stroke-[2.5]" />
        </div>
        <div>
          <div className="text-sm font-bold tracking-tight text-zinc-900 dark:text-zinc-100 flex items-center gap-1.5">
            HyperFetch
            <span className="text-[10px] font-mono font-medium px-1.5 py-0.5 rounded bg-blue-500/10 text-blue-600 dark:text-blue-400 border border-blue-500/20">
              v1.2.2.5
            </span>
          </div>
          <div className="text-[11px] text-zinc-500 dark:text-zinc-400">
            High-Speed Multi-Chunk
          </div>
        </div>
      </div>

      {/* Nav List */}
      <div className="flex-1 overflow-y-auto px-3 py-4 space-y-6">
        {/* Transfers Group */}
        <div>
          <div className="px-3 mb-1.5 text-[11px] font-semibold tracking-wider uppercase text-zinc-400 dark:text-zinc-500">
            Transfers
          </div>
          <div className="space-y-0.5">
            {transferItems.map((item) => {
              const isSelected = currentFilter === item.id;
              const Icon = item.icon;
              return (
                <button
                  key={item.id}
                  onClick={() => onSelectFilter(item.id)}
                  className={`w-full flex items-center justify-between px-3 py-1.5 rounded-lg text-xs font-medium transition-all cursor-pointer focus-visible:ring-2 focus-visible:ring-blue-500 ${
                    isSelected
                      ? "bg-blue-600 text-white shadow-sm shadow-blue-600/25"
                      : "text-zinc-700 dark:text-zinc-300 hover:bg-zinc-200/60 dark:hover:bg-zinc-800/50"
                  }`}
                >
                  <div className="flex items-center gap-2.5">
                    <Icon
                      className={`w-4 h-4 ${
                        isSelected ? "text-white" : item.color
                      }`}
                    />
                    <span>{item.label}</span>
                  </div>
                  {item.count > 0 && (
                    <span
                      className={`text-[11px] font-mono px-1.5 py-0.2 rounded-full ${
                        isSelected
                          ? "bg-blue-700/60 text-white"
                          : "bg-zinc-200/60 dark:bg-zinc-800 text-zinc-500 dark:text-zinc-400"
                      }`}
                    >
                      {item.count}
                    </span>
                  )}
                </button>
              );
            })}
          </div>
        </div>

        {/* Categories Group */}
        <div>
          <div className="px-3 mb-1.5 text-[11px] font-semibold tracking-wider uppercase text-zinc-400 dark:text-zinc-500">
            Categories
          </div>
          <div className="space-y-0.5">
            {categoryItems.map((item) => {
              const isSelected = currentFilter === item.id;
              const Icon = item.icon;
              return (
                <button
                  key={item.id}
                  onClick={() => onSelectFilter(item.id)}
                  className={`w-full flex items-center justify-between px-3 py-1.5 rounded-lg text-xs font-medium transition-all cursor-pointer focus-visible:ring-2 focus-visible:ring-blue-500 ${
                    isSelected
                      ? "bg-blue-600 text-white shadow-sm shadow-blue-600/25"
                      : "text-zinc-700 dark:text-zinc-300 hover:bg-zinc-200/60 dark:hover:bg-zinc-800/50"
                  }`}
                >
                  <div className="flex items-center gap-2.5">
                    <Icon
                      className={`w-4 h-4 ${
                        isSelected ? "text-white" : item.color
                      }`}
                    />
                    <span>{item.label}</span>
                  </div>
                  {item.count > 0 && (
                    <span
                      className={`text-[11px] font-mono px-1.5 py-0.2 rounded-full ${
                        isSelected
                          ? "bg-blue-700/60 text-white"
                          : "bg-zinc-200/60 dark:bg-zinc-800 text-zinc-500 dark:text-zinc-400"
                      }`}
                    >
                      {item.count}
                    </span>
                  )}
                </button>
              );
            })}
          </div>
        </div>
      </div>

      {/* Footer Area: Bandwidth Telemetry & Ko-fi */}
      <div className="p-3 space-y-2 border-t border-zinc-200 dark:border-zinc-800/80 bg-zinc-100/50 dark:bg-zinc-950/40 shrink-0">
        {/* Real-time Bandwidth Telemetry Card */}
        <div className="p-2.5 rounded-xl bg-white dark:bg-zinc-900/80 border border-zinc-200 dark:border-zinc-800 shadow-xs space-y-2">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-1.5">
              <span
                className={`w-2 h-2 rounded-full ${
                  downloadingCount > 0
                    ? "bg-emerald-500 animate-pulse"
                    : "bg-zinc-400/50"
                }`}
              />
              <span className="text-[11px] font-semibold text-zinc-700 dark:text-zinc-300">
                Total Bandwidth
              </span>
            </div>
            <span className="text-[9.5px] font-mono font-semibold px-1.5 py-0.5 rounded bg-emerald-500/10 text-emerald-600 dark:text-emerald-400 border border-emerald-500/20">
              UNLIMITED
            </span>
          </div>

          <div className="flex items-baseline justify-between">
            <span className="text-base font-bold font-mono text-zinc-900 dark:text-zinc-100">
              {formatSpeed(totalSpeed)}
            </span>
            <span className="flex items-center gap-1 text-[11px] font-mono text-zinc-500 dark:text-zinc-400">
              <ArrowDown
                className={`w-3 h-3 ${
                  downloadingCount > 0 ? "text-emerald-500" : "text-zinc-400"
                }`}
              />
              {downloadingCount} active
            </span>
          </div>

          {/* Dynamic Rolling Speed Sparkline */}
          <div
            className="h-5 flex items-end gap-[3px] pt-1"
            role="img"
            aria-label="Network throughput sparkline"
          >
            {speedHistory.map((sampleSpeed, idx) => {
              const heightPct =
                downloadingCount > 0 && maxRecordedSpeed > 0
                  ? Math.max(
                      15,
                      Math.min(
                        100,
                        Math.round((sampleSpeed / maxRecordedSpeed) * 100)
                      )
                    )
                  : 18;

              return (
                <div
                  key={idx}
                  className={`flex-1 rounded-xs transition-all duration-300 ${
                    downloadingCount > 0 && sampleSpeed > 0
                      ? "bg-blue-500/80 dark:bg-blue-500"
                      : "bg-zinc-300 dark:bg-zinc-700/50"
                  }`}
                  style={{
                    height: `${heightPct}%`,
                  }}
                  title={`Sample #${idx + 1}: ${formatSpeed(sampleSpeed)}`}
                />
              );
            })}
          </div>

          {/* Disk storage status */}
          <div className="pt-2 border-t border-zinc-100 dark:border-zinc-800/80 flex items-center justify-between text-[10px] text-zinc-500 dark:text-zinc-400">
            <div className="flex items-center gap-1">
              <HardDrive className="w-3 h-3" />
              <span>Storage</span>
            </div>
            <span className="font-mono text-emerald-600 dark:text-emerald-400 font-medium">
              Available
            </span>
          </div>
        </div>

        {/* Support HyperFetch Ko-fi card */}
        <button
          onClick={handleOpenKofi}
          className="w-full p-2 rounded-xl bg-orange-500/10 hover:bg-orange-500/15 border border-orange-500/20 text-left transition-colors flex items-center gap-2.5 group cursor-pointer focus-visible:ring-2 focus-visible:ring-orange-500"
        >
          <div className="w-7 h-7 rounded-lg bg-orange-500/20 flex items-center justify-center text-orange-600 dark:text-orange-400 shrink-0">
            <Coffee className="w-4 h-4 group-hover:scale-110 transition-transform" />
          </div>
          <div className="flex-1 min-w-0">
            <div className="text-[11px] font-semibold text-zinc-900 dark:text-zinc-100 truncate">
              Support HyperFetch
            </div>
            <div className="text-[9.5px] text-zinc-500 dark:text-zinc-400 truncate">
              Buy us a coffee on Ko-fi
            </div>
          </div>
          <ExternalLink className="w-3 h-3 text-orange-500 shrink-0 opacity-80 group-hover:opacity-100 group-hover:translate-x-0.5 transition-all" />
        </button>
      </div>
    </aside>
  );
};
