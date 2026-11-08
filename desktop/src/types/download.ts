export type DownloadState =
  | "pending"
  | "connecting"
  | "downloading"
  | "paused"
  | "completed"
  | "failed"
  | "cancelled";

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
}

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
