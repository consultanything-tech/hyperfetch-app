export type DownloadState =
  | "pending"
  | "connecting"
  | "downloading"
  | "paused"
  | "completed"
  | "failed"
  | "cancelled";

/**
 * Status mapping helper to align Swift's DownloadStatus with desktop frontend DownloadState.
 * Swift DownloadStatus enum cases:
 * - idle -> "pending"
 * - probing -> "connecting"
 * - downloading -> "downloading"
 * - paused -> "paused"
 * - completed -> "completed"
 * - failed(reason) -> "failed"
 */
export function mapSwiftStatusToDownloadState(
  rawStatus: string | { failed: { reason: string } }
): DownloadState {
  if (typeof rawStatus === "string") {
    switch (rawStatus.toLowerCase()) {
      case "idle":
        return "pending";
      case "probing":
        return "connecting";
      case "downloading":
        return "downloading";
      case "paused":
        return "paused";
      case "completed":
        return "completed";
      case "failed":
        return "failed";
      case "cancelled":
        return "cancelled";
      default:
        return "pending";
    }
  }
  if (
    typeof rawStatus === "object" &&
    rawStatus !== null &&
    "failed" in rawStatus
  ) {
    return "failed";
  }
  return "pending";
}

export const normalizeDownloadStatus = mapSwiftStatusToDownloadState;

export type DownloadCategory =
  | "videos"
  | "music"
  | "archives"
  | "documents"
  | "programs"
  | "others";

export type ViewMode = "comfortable" | "compact";

export type ThemeMode = "dark" | "light" | "system";

export interface Chunk {
  index: number;
  start_offset: number;
  end_offset: number;
  downloaded_bytes: number;
  total_bytes: number;
  completed: boolean;
}

export interface DownloadTask {
  id: string;
  url: string;
  filename: string;
  destination_path: string;
  total_bytes: number;
  downloaded_bytes: number;
  status: DownloadState;
  category: DownloadCategory;
  speed: number;
  eta: number;
  resumable: boolean;
  error?: string | null;
  chunks: Chunk[];
  created_at: number;
  completed_at?: number | null;
  headers?: Record<string, string>;
  etag?: string | null;
  last_modified?: string | null;
  preferred_chunk_count?: number | null;
  expected_checksum?: string | null;
  checksum_verified?: boolean | null;
}

export type QueueAction = "top" | "up" | "down" | "bottom";

export interface ProbeResult {
  content_length?: number | null;
  accept_ranges: boolean;
  suggested_filename?: string | null;
  mime_type?: string | null;
  is_redirect: boolean;
  final_url: string;
}

export type SidebarFilter =
  | "all"
  | "downloading"
  | "completed"
  | "failed"
  | DownloadCategory;
