import React, { useState, useEffect } from "react";
import {
  X,
  Download,
  Loader2,
  Folder,
  Zap,
  Globe,
  FileText,
  Pause,
  AlertCircle,
} from "lucide-react";
import { invoke } from "@tauri-apps/api/core";
import type { ProbeResult } from "../types/download";
import { formatBytes } from "../utils/format";

interface AddDownloadModalProps {
  isOpen: boolean;
  onClose: () => void;
  onAddSuccess: () => void;
  initialUrl?: string;
  initialFilename?: string;
}

export const AddDownloadModal: React.FC<AddDownloadModalProps> = ({
  isOpen,
  onClose,
  onAddSuccess,
  initialUrl = "",
  initialFilename = "",
}) => {
  const [url, setUrl] = useState(initialUrl);
  const [customFilename, setCustomFilename] = useState(initialFilename);
  const [destinationPath, setDestinationPath] = useState("");
  const [autoStart, setAutoStart] = useState(true);

  const [isProbing, setIsProbing] = useState(false);
  const [probeResult, setProbeResult] = useState<ProbeResult | null>(null);
  const [probeError, setProbeError] = useState<string | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [submitError, setSubmitError] = useState<string | null>(null);

  // Sync initial inputs when opening
  useEffect(() => {
    if (isOpen) {
      setSubmitError(null);
      if (initialUrl) {
        setUrl(initialUrl);
      }
      if (initialFilename) {
        setCustomFilename(initialFilename);
      }
      // Load default download directory
      invoke<string>("get_default_download_dir", { category: null })
        .then((dir) => setDestinationPath(dir))
        .catch(() => {});
    } else {
      setUrl("");
      setCustomFilename("");
      setProbeResult(null);
      setProbeError(null);
      setSubmitError(null);
    }
  }, [isOpen, initialUrl, initialFilename]);

  // Debounced URL probe
  useEffect(() => {
    const trimmed = url.trim();
    if (!trimmed || !trimmed.startsWith("http")) {
      setProbeResult(null);
      setProbeError(null);
      setIsProbing(false);
      return;
    }

    setIsProbing(true);
    setProbeError(null);

    const timer = setTimeout(async () => {
      try {
        const result = await invoke<ProbeResult>("probe_url_info", {
          url: trimmed,
        });
        setProbeResult(result);
        if (result.suggested_filename && !customFilename) {
          setCustomFilename(result.suggested_filename);
        }
      } catch (err: unknown) {
        setProbeError(
          typeof err === "string" ? err : "Failed to probe remote URL"
        );
      } finally {
        setIsProbing(false);
      }
    }, 600);

    return () => clearTimeout(timer);
  }, [url]);

  if (!isOpen) return null;

  const handleCreateDownload = async (startImmediately: boolean) => {
    const trimmedUrl = url.trim();
    if (!trimmedUrl) return;

    setIsSubmitting(true);
    setSubmitError(null);
    try {
      await invoke("add_download", {
        url: trimmedUrl,
        filename: customFilename.trim() || null,
        destination: destinationPath.trim() || null,
        autoStart: startImmediately,
        headers: null,
      });
      onAddSuccess();
      onClose();
    } catch (err: unknown) {
      setSubmitError(
        typeof err === "string" ? err : "Failed to add download"
      );
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-xs select-none">
      <div className="w-full max-w-lg rounded-2xl bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 shadow-2xl overflow-hidden animate-in fade-in zoom-in-95 duration-150">
        {/* Header */}
        <div className="px-5 py-4 border-b border-zinc-200 dark:border-zinc-800 flex items-center justify-between">
          <div className="flex items-center gap-2">
            <div className="w-8 h-8 rounded-lg bg-blue-500/10 text-blue-600 dark:text-blue-400 flex items-center justify-center">
              <Download className="w-4 h-4 stroke-[2.5]" />
            </div>
            <div>
              <h3 className="text-sm font-semibold text-zinc-900 dark:text-zinc-100">
                Add Download
              </h3>
              <p className="text-xs text-zinc-500 dark:text-zinc-400">
                Multi-chunk parallel file acceleration
              </p>
            </div>
          </div>
          <button
            onClick={onClose}
            className="w-7 h-7 rounded-lg text-zinc-400 hover:text-zinc-700 dark:hover:text-zinc-200 hover:bg-zinc-100 dark:hover:bg-zinc-800 flex items-center justify-center transition-colors cursor-pointer"
          >
            <X className="w-4 h-4" />
          </button>
        </div>

        {/* Form Body */}
        <div className="p-5 space-y-4 text-xs">
          {/* URL Input */}
          <div className="space-y-1.5">
            <label className="font-medium text-zinc-700 dark:text-zinc-300 flex items-center gap-1.5">
              <Globe className="w-3.5 h-3.5 text-zinc-400" />
              Source URL
            </label>
            <div className="relative">
              <input
                type="url"
                value={url}
                onChange={(e) => setUrl(e.target.value)}
                placeholder="https://example.com/file.zip"
                autoFocus
                className="w-full h-9 pl-3 pr-8 rounded-lg bg-zinc-50 dark:bg-zinc-950 border border-zinc-200 dark:border-zinc-800 text-zinc-900 dark:text-zinc-100 placeholder-zinc-400 focus:outline-none focus:ring-1 focus:ring-blue-500 font-mono text-xs"
              />
              {isProbing && (
                <div className="absolute right-2.5 top-2.5 text-blue-500 animate-spin">
                  <Loader2 className="w-4 h-4" />
                </div>
              )}
            </div>
          </div>

          {/* Live Probed Information Card */}
          {probeResult && (
            <div className="p-3 rounded-xl bg-blue-50/60 dark:bg-blue-950/20 border border-blue-500/20 space-y-2">
              <div className="flex items-center justify-between">
                <span className="font-semibold text-blue-700 dark:text-blue-300 flex items-center gap-1.5">
                  <FileText className="w-3.5 h-3.5" />
                  Remote Resource Detected
                </span>
                {probeResult.accept_ranges ? (
                  <span className="px-2 py-0.5 rounded-full text-[10px] font-mono font-medium bg-emerald-500/10 text-emerald-600 dark:text-emerald-400 border border-emerald-500/20 flex items-center gap-1">
                    <Zap className="w-2.5 h-2.5 fill-current" />
                    Resumable (8 Chunks)
                  </span>
                ) : (
                  <span className="px-2 py-0.5 rounded-full text-[10px] font-mono font-medium bg-amber-500/10 text-amber-600 dark:text-amber-400 border border-amber-500/20">
                    Single Stream
                  </span>
                )}
              </div>

              <div className="grid grid-cols-2 gap-2 pt-1 text-[11px] font-mono">
                <div>
                  <span className="text-zinc-500 dark:text-zinc-400">
                    Content Size:{" "}
                  </span>
                  <span className="font-semibold text-zinc-900 dark:text-zinc-100">
                    {probeResult.content_length
                      ? formatBytes(probeResult.content_length)
                      : "Dynamic / Stream"}
                  </span>
                </div>
                <div>
                  <span className="text-zinc-500 dark:text-zinc-400">
                    Content Type:{" "}
                  </span>
                  <span className="text-zinc-700 dark:text-zinc-300 truncate block">
                    {probeResult.mime_type || "application/octet-stream"}
                  </span>
                </div>
              </div>
            </div>
          )}

          {probeError && (
            <div className="p-2.5 rounded-lg bg-rose-500/10 border border-rose-500/20 text-rose-600 dark:text-rose-400 text-[11px]">
              Could not probe remote headers: {probeError}. Download can still be
              attempted.
            </div>
          )}

          {/* Filename Input */}
          <div className="space-y-1.5">
            <label className="font-medium text-zinc-700 dark:text-zinc-300 flex items-center gap-1.5">
              <FileText className="w-3.5 h-3.5 text-zinc-400" />
              Filename (optional)
            </label>
            <input
              type="text"
              value={customFilename}
              onChange={(e) => setCustomFilename(e.target.value)}
              placeholder="Leave blank to detect automatically"
              className="w-full h-9 px-3 rounded-lg bg-zinc-50 dark:bg-zinc-950 border border-zinc-200 dark:border-zinc-800 text-zinc-900 dark:text-zinc-100 placeholder-zinc-400 focus:outline-none focus:ring-1 focus:ring-blue-500 text-xs"
            />
          </div>

          {/* Destination Folder */}
          <div className="space-y-1.5">
            <label className="font-medium text-zinc-700 dark:text-zinc-300 flex items-center gap-1.5">
              <Folder className="w-3.5 h-3.5 text-zinc-400" />
              Destination Directory
            </label>
            <div className="flex gap-2">
              <input
                type="text"
                value={destinationPath}
                onChange={(e) => setDestinationPath(e.target.value)}
                placeholder="/Users/.../Downloads/HyperFetch"
                className="flex-1 h-9 px-3 rounded-lg bg-zinc-50 dark:bg-zinc-950 border border-zinc-200 dark:border-zinc-800 text-zinc-900 dark:text-zinc-100 placeholder-zinc-400 focus:outline-none focus:ring-1 focus:ring-blue-500 font-mono text-xs"
              />
              <button
                type="button"
                onClick={() => {
                  invoke<string>("get_default_download_dir", { category: null })
                    .then((dir) => setDestinationPath(dir))
                    .catch(() => {});
                }}
                className="h-9 px-2.5 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-zinc-100 hover:bg-zinc-200 dark:bg-zinc-800 text-zinc-700 dark:text-zinc-300 cursor-pointer text-xs"
                title="Reset to default HyperFetch folder"
              >
                Default
              </button>
            </div>
          </div>

          {/* Auto Start Checkbox */}
          <div className="flex items-center gap-2 pt-1">
            <input
              type="checkbox"
              id="autoStartCheckbox"
              checked={autoStart}
              onChange={(e) => setAutoStart(e.target.checked)}
              className="w-4 h-4 rounded text-blue-600 border-zinc-300 dark:border-zinc-700 focus:ring-blue-500 cursor-pointer"
            />
            <label
              htmlFor="autoStartCheckbox"
              className="text-zinc-700 dark:text-zinc-300 cursor-pointer"
            >
              Start downloading immediately after adding
            </label>
          </div>

          {/* Submit Error Banner */}
          {submitError && (
            <div className="p-2.5 rounded-lg bg-rose-500/10 border border-rose-500/20 text-rose-600 dark:text-rose-400 text-xs flex items-center gap-2">
              <AlertCircle className="w-4 h-4 shrink-0" />
              <span>{submitError}</span>
            </div>
          )}
        </div>

        {/* Modal Actions Footer */}
        <div className="px-5 py-3.5 border-t border-zinc-200 dark:border-zinc-800 bg-zinc-50 dark:bg-zinc-950/60 flex items-center justify-between">
          <button
            type="button"
            onClick={onClose}
            className="h-8 px-3 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white hover:bg-zinc-100 dark:bg-zinc-900 dark:hover:bg-zinc-800 text-zinc-700 dark:text-zinc-300 font-medium text-xs transition-colors cursor-pointer"
          >
            Cancel
          </button>

          <div className="flex items-center gap-2">
            <button
              type="button"
              disabled={!url.trim() || isSubmitting}
              onClick={() => handleCreateDownload(false)}
              className="h-8 px-3 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-zinc-100 hover:bg-zinc-200 dark:bg-zinc-800 dark:hover:bg-zinc-700 text-zinc-700 dark:text-zinc-200 font-medium text-xs flex items-center gap-1.5 transition-colors cursor-pointer disabled:opacity-50"
            >
              <Pause className="w-3.5 h-3.5" />
              <span>Add Paused</span>
            </button>

            <button
              type="button"
              disabled={!url.trim() || isSubmitting}
              onClick={() => handleCreateDownload(true)}
              className="h-8 px-4 rounded-lg bg-blue-600 hover:bg-blue-500 active:bg-blue-700 text-white font-medium text-xs flex items-center gap-1.5 shadow-sm shadow-blue-500/25 transition-all cursor-pointer disabled:opacity-50"
            >
              {isSubmitting ? (
                <Loader2 className="w-3.5 h-3.5 animate-spin" />
              ) : (
                <Download className="w-3.5 h-3.5 stroke-[2.5]" />
              )}
              <span>Download Now</span>
            </button>
          </div>
        </div>
      </div>
    </div>
  );
};
