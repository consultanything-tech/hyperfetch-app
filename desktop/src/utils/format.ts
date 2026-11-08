import {
  Film,
  Music,
  FileText,
  Archive,
  Cpu,
  File,
  CheckCircle2,
  Clock,
  AlertCircle,
  PauseCircle,
  Download,
  Ban,
  Radio,
} from "lucide-react";
import type { DownloadCategory, DownloadState } from "../types/download";

export function formatBytes(bytes: number, decimals = 1): string {
  if (!bytes || bytes === 0) return "0 B";
  const k = 1024;
  const dm = decimals < 0 ? 0 : decimals;
  const sizes = ["B", "KB", "MB", "GB", "TB", "PB"];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  if (i >= sizes.length) return `${(bytes / Math.pow(k, sizes.length - 1)).toFixed(dm)} ${sizes[sizes.length - 1]}`;
  return `${parseFloat((bytes / Math.pow(k, i)).toFixed(dm))} ${sizes[i]}`;
}

export function formatSpeed(bytesPerSec: number): string {
  if (!bytesPerSec || bytesPerSec === 0) return "0 KB/s";
  return `${formatBytes(bytesPerSec)}/s`;
}

export function formatEta(seconds: number): string {
  if (!seconds || seconds <= 0 || !isFinite(seconds)) return "--";
  if (seconds < 60) return `${Math.round(seconds)}s`;
  if (seconds < 3600) {
    const mins = Math.floor(seconds / 60);
    const secs = Math.round(seconds % 60);
    return `${mins}m ${secs}s`;
  }
  const hours = Math.floor(seconds / 3600);
  const mins = Math.floor((seconds % 3600) / 60);
  return `${hours}h ${mins}m`;
}

export function getCategoryIcon(category: DownloadCategory) {
  switch (category) {
    case "videos":
      return Film;
    case "music":
      return Music;
    case "documents":
      return FileText;
    case "archives":
      return Archive;
    case "programs":
      return Cpu;
    case "others":
    default:
      return File;
  }
}

export function getCategoryBadgeColor(category: DownloadCategory): {
  bg: string;
  text: string;
  border: string;
} {
  switch (category) {
    case "videos":
      return {
        bg: "bg-purple-500/10 dark:bg-purple-500/15",
        text: "text-purple-600 dark:text-purple-400",
        border: "border-purple-500/20",
      };
    case "music":
      return {
        bg: "bg-pink-500/10 dark:bg-pink-500/15",
        text: "text-pink-600 dark:text-pink-400",
        border: "border-pink-500/20",
      };
    case "documents":
      return {
        bg: "bg-blue-500/10 dark:bg-blue-500/15",
        text: "text-blue-600 dark:text-blue-400",
        border: "border-blue-500/20",
      };
    case "archives":
      return {
        bg: "bg-amber-500/10 dark:bg-amber-500/15",
        text: "text-amber-600 dark:text-amber-400",
        border: "border-amber-500/20",
      };
    case "programs":
      return {
        bg: "bg-emerald-500/10 dark:bg-emerald-500/15",
        text: "text-emerald-600 dark:text-emerald-400",
        border: "border-emerald-500/20",
      };
    case "others":
    default:
      return {
        bg: "bg-zinc-500/10 dark:bg-zinc-500/15",
        text: "text-zinc-600 dark:text-zinc-400",
        border: "border-zinc-500/20",
      };
  }
}

export function getStatusDetails(status: DownloadState) {
  switch (status) {
    case "downloading":
      return {
        label: "Downloading",
        color: "text-blue-500",
        bg: "bg-blue-500/10",
        border: "border-blue-500/30",
        icon: Download,
      };
    case "connecting":
      return {
        label: "Connecting",
        color: "text-cyan-500",
        bg: "bg-cyan-500/10",
        border: "border-cyan-500/30",
        icon: Radio,
      };
    case "completed":
      return {
        label: "Completed",
        color: "text-emerald-500",
        bg: "bg-emerald-500/10",
        border: "border-emerald-500/30",
        icon: CheckCircle2,
      };
    case "paused":
      return {
        label: "Paused",
        color: "text-amber-500",
        bg: "bg-amber-500/10",
        border: "border-amber-500/30",
        icon: PauseCircle,
      };
    case "failed":
      return {
        label: "Failed",
        color: "text-rose-500",
        bg: "bg-rose-500/10",
        border: "border-rose-500/30",
        icon: AlertCircle,
      };
    case "cancelled":
      return {
        label: "Cancelled",
        color: "text-zinc-400",
        bg: "bg-zinc-500/10",
        border: "border-zinc-500/30",
        icon: Ban,
      };
    case "pending":
    default:
      return {
        label: "Pending",
        color: "text-zinc-400",
        bg: "bg-zinc-500/10",
        border: "border-zinc-500/30",
        icon: Clock,
      };
  }
}
