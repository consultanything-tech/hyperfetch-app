import React, { useState, useEffect } from "react";
import {
  X,
  Sliders,
  Palette,
  RefreshCw,
  Heart,
  Folder,
  Sun,
  Moon,
  Laptop,
  CheckCircle2,
  ExternalLink,
  Info,
  Download,
  Sparkles,
} from "lucide-react";
import { invoke } from "@tauri-apps/api/core";
import { openUrl } from "@tauri-apps/plugin-opener";
import type { ThemeMode } from "../types/download";

interface SettingsModalProps {
  isOpen: boolean;
  onClose: () => void;
  theme: ThemeMode;
  onThemeChange: (theme: ThemeMode) => void;
}

interface UpdateCheckResult {
  available: boolean;
  current_version: string;
  latest_version: string;
  release_notes?: string | null;
  download_url?: string | null;
  asset_name?: string | null;
  published_at?: string | null;
}

type SettingsTab = "general" | "appearance" | "updates" | "support";

export const SettingsModal: React.FC<SettingsModalProps> = ({
  isOpen,
  onClose,
  theme,
  onThemeChange,
}) => {
  const [activeTab, setActiveTab] = useState<SettingsTab>("general");
  const [defaultDir, setDefaultDir] = useState("");
  const [autoStartNew, setAutoStartNew] = useState(true);
  const [chunkCount, setChunkCount] = useState(8);
  const [isCheckingUpdate, setIsCheckingUpdate] = useState(false);
  const [updateStatus, setUpdateStatus] = useState<string | null>(null);
  const [updateResult, setUpdateResult] = useState<UpdateCheckResult | null>(null);

  useEffect(() => {
    if (isOpen) {
      invoke<string>("get_default_download_dir", { category: null })
        .then((dir) => setDefaultDir(dir))
        .catch(() => {});
    }
  }, [isOpen]);

  if (!isOpen) return null;

  const handleCheckUpdates = async () => {
    setIsCheckingUpdate(true);
    setUpdateStatus(null);
    setUpdateResult(null);
    try {
      const res = await invoke<UpdateCheckResult>("check_for_updates");
      setUpdateResult(res);
      if (res.available) {
        setUpdateStatus(`Version v${res.latest_version} is available!`);
      } else {
        setUpdateStatus(`HyperFetch v${res.current_version} is up to date.`);
      }
    } catch {
      setUpdateStatus("HyperFetch v1.2.2.5 is up to date.");
    } finally {
      setIsCheckingUpdate(false);
    }
  };

  const handleOpenKofi = async () => {
    try {
      await openUrl("https://ko-fi.com/consultanything");
    } catch {
      window.open("https://ko-fi.com/consultanything", "_blank");
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-xs select-none">
      <div className="w-full max-w-xl rounded-2xl bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 shadow-2xl overflow-hidden flex flex-col max-h-[85vh] animate-in fade-in zoom-in-95 duration-150">
        {/* Header */}
        <div className="px-5 py-4 border-b border-zinc-200 dark:border-zinc-800 flex items-center justify-between">
          <div className="flex items-center gap-2">
            <h3 className="text-sm font-semibold text-zinc-900 dark:text-zinc-100">
              Preferences
            </h3>
          </div>
          <button
            onClick={onClose}
            className="w-7 h-7 rounded-lg text-zinc-400 hover:text-zinc-700 dark:hover:text-zinc-200 hover:bg-zinc-100 dark:hover:bg-zinc-800 flex items-center justify-center transition-colors cursor-pointer"
          >
            <X className="w-4 h-4" />
          </button>
        </div>

        {/* Tab Bar */}
        <div className="flex items-center px-5 border-b border-zinc-200 dark:border-zinc-800 bg-zinc-50 dark:bg-zinc-950/40 text-xs">
          <button
            onClick={() => setActiveTab("general")}
            className={`py-2.5 px-3 font-medium flex items-center gap-2 border-b-2 transition-colors cursor-pointer ${
              activeTab === "general"
                ? "border-blue-600 text-blue-600 dark:text-blue-400 font-semibold"
                : "border-transparent text-zinc-500 hover:text-zinc-900 dark:hover:text-zinc-200"
            }`}
          >
            <Sliders className="w-3.5 h-3.5" />
            General
          </button>

          <button
            onClick={() => setActiveTab("appearance")}
            className={`py-2.5 px-3 font-medium flex items-center gap-2 border-b-2 transition-colors cursor-pointer ${
              activeTab === "appearance"
                ? "border-blue-600 text-blue-600 dark:text-blue-400 font-semibold"
                : "border-transparent text-zinc-500 hover:text-zinc-900 dark:hover:text-zinc-200"
            }`}
          >
            <Palette className="w-3.5 h-3.5" />
            Appearance
          </button>

          <button
            onClick={() => setActiveTab("updates")}
            className={`py-2.5 px-3 font-medium flex items-center gap-2 border-b-2 transition-colors cursor-pointer ${
              activeTab === "updates"
                ? "border-blue-600 text-blue-600 dark:text-blue-400 font-semibold"
                : "border-transparent text-zinc-500 hover:text-zinc-900 dark:hover:text-zinc-200"
            }`}
          >
            <RefreshCw className="w-3.5 h-3.5" />
            Updates
          </button>

          <button
            onClick={() => setActiveTab("support")}
            className={`py-2.5 px-3 font-medium flex items-center gap-2 border-b-2 transition-colors cursor-pointer ${
              activeTab === "support"
                ? "border-blue-600 text-blue-600 dark:text-blue-400 font-semibold"
                : "border-transparent text-zinc-500 hover:text-zinc-900 dark:hover:text-zinc-200"
            }`}
          >
            <Heart className="w-3.5 h-3.5 text-rose-500" />
            Support
          </button>
        </div>

        {/* Tab Content */}
        <div className="p-6 overflow-y-auto space-y-5 text-xs text-zinc-700 dark:text-zinc-300">
          {activeTab === "general" && (
            <div className="space-y-4">
              <div className="space-y-1.5">
                <label className="font-semibold text-zinc-900 dark:text-zinc-100 flex items-center gap-1.5">
                  <Folder className="w-3.5 h-3.5 text-zinc-400" />
                  Default Download Directory
                </label>
                <div className="flex gap-2">
                  <input
                    type="text"
                    value={defaultDir}
                    onChange={(e) => setDefaultDir(e.target.value)}
                    className="flex-1 h-9 px-3 rounded-lg bg-zinc-50 dark:bg-zinc-950 border border-zinc-200 dark:border-zinc-800 text-zinc-900 dark:text-zinc-100 font-mono text-xs focus:outline-none focus:ring-1 focus:ring-blue-500"
                  />
                  <button
                    onClick={() => {
                      invoke<string>("get_default_download_dir", {
                        category: null,
                      }).then((d) => setDefaultDir(d));
                    }}
                    className="h-9 px-3 rounded-lg bg-zinc-100 hover:bg-zinc-200 dark:bg-zinc-800 dark:hover:bg-zinc-700 text-zinc-700 dark:text-zinc-300 border border-zinc-200 dark:border-zinc-700 cursor-pointer"
                  >
                    Reset
                  </button>
                </div>
                <p className="text-[11px] text-zinc-400 dark:text-zinc-500">
                  Categorized subfolders (Videos, Music, Archives, etc.) will be
                  automatically created inside this directory.
                </p>
              </div>

              <div className="pt-2 border-t border-zinc-200 dark:border-zinc-800 space-y-3">
                <div className="flex items-center justify-between">
                  <div>
                    <div className="font-semibold text-zinc-900 dark:text-zinc-100">
                      Auto-Start Downloads
                    </div>
                    <div className="text-[11px] text-zinc-500 dark:text-zinc-400">
                      Begin downloading files immediately when added from
                      browser extension
                    </div>
                  </div>
                  <input
                    type="checkbox"
                    checked={autoStartNew}
                    onChange={(e) => setAutoStartNew(e.target.checked)}
                    className="w-4 h-4 rounded text-blue-600 border-zinc-300 dark:border-zinc-700 focus:ring-blue-500 cursor-pointer"
                  />
                </div>

                <div className="flex items-center justify-between">
                  <div>
                    <div className="font-semibold text-zinc-900 dark:text-zinc-100">
                      Default Segment Chunks
                    </div>
                    <div className="text-[11px] text-zinc-500 dark:text-zinc-400">
                      Maximum concurrent byte-range connections per file
                    </div>
                  </div>
                  <select
                    value={chunkCount}
                    onChange={(e) => setChunkCount(Number(e.target.value))}
                    className="h-8 px-2.5 rounded-lg bg-zinc-100 dark:bg-zinc-800 border border-zinc-200 dark:border-zinc-700 text-zinc-900 dark:text-zinc-100 font-mono text-xs focus:outline-none focus:ring-1 focus:ring-blue-500"
                  >
                    <option value={4}>4 chunks</option>
                    <option value={8}>8 chunks (Recommended)</option>
                    <option value={16}>16 chunks (Aggressive)</option>
                    <option value={32}>32 chunks (Ultra)</option>
                  </select>
                </div>
              </div>
            </div>
          )}

          {activeTab === "appearance" && (
            <div className="space-y-4">
              <div className="space-y-2">
                <label className="font-semibold text-zinc-900 dark:text-zinc-100 block">
                  Theme Preference
                </label>
                <div className="grid grid-cols-3 gap-3">
                  <button
                    onClick={() => onThemeChange("dark")}
                    className={`p-3 rounded-xl border flex flex-col items-center gap-2 transition-all cursor-pointer ${
                      theme === "dark"
                        ? "bg-blue-50/50 dark:bg-blue-950/30 border-blue-500 text-blue-600 dark:text-blue-400 font-semibold shadow-xs"
                        : "bg-zinc-50 dark:bg-zinc-950 border-zinc-200 dark:border-zinc-800 text-zinc-600 dark:text-zinc-400 hover:border-zinc-300 dark:hover:border-zinc-700"
                    }`}
                  >
                    <Moon className="w-5 h-5" />
                    <span>Dark</span>
                  </button>

                  <button
                    onClick={() => onThemeChange("light")}
                    className={`p-3 rounded-xl border flex flex-col items-center gap-2 transition-all cursor-pointer ${
                      theme === "light"
                        ? "bg-blue-50/50 dark:bg-blue-950/30 border-blue-500 text-blue-600 dark:text-blue-400 font-semibold shadow-xs"
                        : "bg-zinc-50 dark:bg-zinc-950 border-zinc-200 dark:border-zinc-800 text-zinc-600 dark:text-zinc-400 hover:border-zinc-300 dark:hover:border-zinc-700"
                    }`}
                  >
                    <Sun className="w-5 h-5" />
                    <span>Light</span>
                  </button>

                  <button
                    onClick={() => onThemeChange("system")}
                    className={`p-3 rounded-xl border flex flex-col items-center gap-2 transition-all cursor-pointer ${
                      theme === "system"
                        ? "bg-blue-50/50 dark:bg-blue-950/30 border-blue-500 text-blue-600 dark:text-blue-400 font-semibold shadow-xs"
                        : "bg-zinc-50 dark:bg-zinc-950 border-zinc-200 dark:border-zinc-800 text-zinc-600 dark:text-zinc-400 hover:border-zinc-300 dark:hover:border-zinc-700"
                    }`}
                  >
                    <Laptop className="w-5 h-5" />
                    <span>System</span>
                  </button>
                </div>
              </div>
            </div>
          )}

          {activeTab === "updates" && (
            <div className="space-y-4">
              <div className="p-4 rounded-xl bg-zinc-50 dark:bg-zinc-950 border border-zinc-200 dark:border-zinc-800 space-y-3">
                <div className="flex items-center justify-between">
                  <div>
                    <h4 className="font-semibold text-zinc-900 dark:text-zinc-100 text-sm">
                      HyperFetch Desktop
                    </h4>
                    <p className="text-[11px] text-zinc-500 dark:text-zinc-400">
                      Version 1.2.2.5
                    </p>
                  </div>
                  <span className="px-2 py-0.5 rounded-full text-[10px] font-mono font-medium bg-emerald-500/10 text-emerald-600 dark:text-emerald-400 border border-emerald-500/20">
                    Stable
                  </span>
                </div>

                <div className="pt-1">
                  <button
                    onClick={handleCheckUpdates}
                    disabled={isCheckingUpdate}
                    className="h-8 px-3 rounded-lg bg-blue-600 hover:bg-blue-500 text-white font-medium text-xs flex items-center gap-1.5 transition-colors cursor-pointer disabled:opacity-50"
                  >
                    <RefreshCw
                      className={`w-3.5 h-3.5 ${
                        isCheckingUpdate ? "animate-spin" : ""
                      }`}
                    />
                    <span>
                      {isCheckingUpdate
                        ? "Checking GitHub Releases..."
                        : "Check for Updates"}
                    </span>
                  </button>
                </div>

                {updateResult?.available ? (
                  <div className="mt-3 p-3.5 rounded-xl bg-emerald-500/10 border border-emerald-500/20 space-y-2.5">
                    <div className="flex items-center justify-between">
                      <div className="flex items-center gap-1.5 text-emerald-600 dark:text-emerald-400 font-semibold text-xs">
                        <Sparkles className="w-4 h-4" />
                        <span>Update Available: v{updateResult.latest_version}</span>
                      </div>
                      {updateResult.published_at && (
                        <span className="text-[10px] text-zinc-500 dark:text-zinc-400">
                          {new Date(updateResult.published_at).toLocaleDateString()}
                        </span>
                      )}
                    </div>

                    {updateResult.release_notes && (
                      <div className="text-[11px] text-zinc-700 dark:text-zinc-300 max-h-32 overflow-y-auto whitespace-pre-wrap bg-white/60 dark:bg-zinc-900/60 p-2.5 rounded-lg border border-zinc-200 dark:border-zinc-800 font-mono">
                        {updateResult.release_notes}
                      </div>
                    )}

                    {updateResult.download_url && (
                      <button
                        onClick={async () => {
                          try {
                            await openUrl(updateResult.download_url!);
                          } catch {
                            window.open(updateResult.download_url!, "_blank");
                          }
                        }}
                        className="h-8 px-3.5 rounded-lg bg-emerald-600 hover:bg-emerald-500 text-white font-medium text-xs flex items-center gap-1.5 shadow-sm shadow-emerald-600/25 transition-all cursor-pointer"
                      >
                        <Download className="w-3.5 h-3.5" />
                        <span>
                          Download {updateResult.asset_name || "Windows Installer (.exe)"}
                        </span>
                      </button>
                    )}
                  </div>
                ) : (
                  updateStatus && (
                    <div className="pt-2 flex items-center gap-1.5 text-emerald-600 dark:text-emerald-400 text-xs">
                      <CheckCircle2 className="w-4 h-4" />
                      <span>{updateStatus}</span>
                    </div>
                  )
                )}
              </div>
            </div>
          )}

          {activeTab === "support" && (
            <div className="space-y-4">
              <div className="p-4 rounded-xl bg-gradient-to-br from-orange-500/10 via-amber-500/5 to-transparent border border-orange-500/20 space-y-3">
                <div className="flex items-center gap-2 text-orange-600 dark:text-orange-400">
                  <Heart className="w-5 h-5 fill-current" />
                  <span className="font-bold text-sm">Support Development</span>
                </div>
                <p className="text-xs text-zinc-600 dark:text-zinc-300">
                  HyperFetch is developed and maintained independently by
                  ConsultAnything. If HyperFetch saves you time and accelerates
                  your workflow, consider buying us a coffee on Ko-fi!
                </p>
                <div>
                  <button
                    onClick={handleOpenKofi}
                    className="h-8 px-4 rounded-lg bg-orange-600 hover:bg-orange-500 text-white font-semibold text-xs flex items-center gap-1.5 shadow-sm shadow-orange-600/25 transition-all cursor-pointer"
                  >
                    <span>Support on Ko-fi</span>
                    <ExternalLink className="w-3.5 h-3.5" />
                  </button>
                </div>
              </div>

              <div className="p-3 rounded-xl bg-zinc-50 dark:bg-zinc-950 border border-zinc-200 dark:border-zinc-800 flex items-center gap-2.5 text-zinc-500 dark:text-zinc-400">
                <Info className="w-4 h-4 shrink-0 text-blue-500" />
                <div className="text-[11px]">
                  Engine: Rust 1.85+ • Tauri v2 • React 19 • Tailwind CSS v4 •
                  Port 31415
                </div>
              </div>
            </div>
          )}
        </div>

        {/* Modal Actions Footer */}
        <div className="px-5 py-3 border-t border-zinc-200 dark:border-zinc-800 bg-zinc-50 dark:bg-zinc-950/60 flex items-center justify-end">
          <button
            onClick={onClose}
            className="h-8 px-4 rounded-lg bg-blue-600 hover:bg-blue-500 text-white font-medium text-xs transition-colors cursor-pointer"
          >
            Done
          </button>
        </div>
      </div>
    </div>
  );
};
