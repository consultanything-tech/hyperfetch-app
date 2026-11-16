use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// Lifecycle state of a download task.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum DownloadState {
    Pending,
    Connecting,
    Downloading,
    Paused,
    Completed,
    Failed,
    Cancelled,
}

/// Download category based on file extension or MIME type.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum DownloadCategory {
    Videos,
    Music,
    Archives,
    Documents,
    Programs,
    Others,
}

impl DownloadCategory {
    /// Categorizes a file based on its filename and extension.
    pub fn from_filename(name: &str) -> Self {
        let trimmed = name.trim();
        if trimmed.is_empty() {
            return Self::Others;
        }
        let lower = trimmed.to_lowercase();

        // Check compound archive extensions first (e.g., .tar.gz)
        let compound_archives = [
            ".tar.gz", ".tar.bz2", ".tar.xz", ".tar.z", ".tar.lz", ".tar.sz", ".tgz", ".tbz2",
        ];
        for ext in compound_archives {
            if lower.ends_with(ext) {
                return Self::Archives;
            }
        }

        let extension = lower.rsplit('.').next().unwrap_or("");
        if extension.is_empty() || extension == lower {
            return Self::Others;
        }

        match extension {
            "dmg" | "pkg" | "app" | "exe" | "msi" | "apk" | "ipa" | "deb" | "rpm" | "bin" => {
                Self::Programs
            }
            "zip" | "rar" | "7z" | "tar" | "gz" | "bz2" | "xz" | "iso" | "z" | "cab" | "arj"
            | "lz" | "lzma" => Self::Archives,
            "pdf" | "doc" | "docx" | "xls" | "xlsx" | "ppt" | "pptx" | "txt" | "rtf" | "csv"
            | "epub" | "pages" | "numbers" | "keynote" | "md" | "odt" | "ods" | "odp" => {
                Self::Documents
            }
            "mp4" | "mkv" | "mov" | "avi" | "wmv" | "flv" | "webm" | "m4v" | "mpeg" | "mpg"
            | "3gp" | "ts" | "vob" => Self::Videos,
            "mp3" | "wav" | "flac" | "aac" | "ogg" | "m4a" | "aiff" | "wma" | "alac" | "opus" => {
                Self::Music
            }
            _ => Self::Others,
        }
    }

    /// Categorizes a file based on its MIME content type.
    pub fn from_mime_type(mime: &str) -> Self {
        let trimmed = mime.trim().to_lowercase();
        if trimmed.is_empty() {
            return Self::Others;
        }

        if trimmed.starts_with("video/") {
            return Self::Videos;
        }
        if trimmed.starts_with("audio/") {
            return Self::Music;
        }
        if trimmed.starts_with("text/")
            || trimmed.contains("pdf")
            || trimmed.contains("msword")
            || trimmed.contains("wordprocessing")
            || trimmed.contains("spreadsheet")
            || trimmed.contains("presentation")
            || trimmed.contains("opendocument")
            || trimmed.contains("epub")
            || trimmed.contains("csv")
            || trimmed.contains("json")
            || trimmed.contains("xml")
        {
            return Self::Documents;
        }
        if trimmed.contains("zip")
            || trimmed.contains("compressed")
            || trimmed.contains("tar")
            || trimmed.contains("archive")
            || trimmed.contains("gzip")
            || trimmed.contains("x-bzip")
            || trimmed.contains("x-xz")
            || trimmed.contains("x-7z-compressed")
            || trimmed.contains("x-rar")
            || trimmed.contains("iso9660")
        {
            return Self::Archives;
        }
        if trimmed.contains("executable")
            || trimmed.contains("x-msdownload")
            || trimmed.contains("android.package-archive")
            || trimmed.contains("x-apple-diskimage")
            || trimmed.contains("x-debian-package")
            || trimmed.contains("x-redhat-package-manager")
        {
            return Self::Programs;
        }

        Self::Others
    }

    /// Returns the standard subfolder name under HyperFetch downloads.
    pub fn folder_name(&self) -> &'static str {
        match self {
            Self::Videos => "Videos",
            Self::Music => "Music",
            Self::Archives => "Archives",
            Self::Documents => "Documents",
            Self::Programs => "Programs",
            Self::Others => "Others",
        }
    }
}

/// Represents an individual byte-range chunk within a segmented download.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Chunk {
    pub index: usize,
    pub start_offset: u64,
    pub end_offset: u64,
    pub downloaded_bytes: u64,
    pub total_bytes: u64,
    pub completed: bool,
}

impl Chunk {
    pub fn new(index: usize, start_offset: u64, end_offset: u64) -> Self {
        let total_bytes = if end_offset >= start_offset {
            end_offset - start_offset + 1
        } else {
            0
        };
        Self {
            index,
            start_offset,
            end_offset,
            downloaded_bytes: 0,
            total_bytes,
            completed: false,
        }
    }
}

/// Core domain model representing a file download task.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct DownloadTask {
    pub id: String,
    pub url: String,
    pub filename: String,
    pub destination_path: String,
    pub total_bytes: u64,
    pub downloaded_bytes: u64,
    pub status: DownloadState,
    pub category: DownloadCategory,
    pub speed: u64,
    pub eta: u64,
    pub resumable: bool,
    pub error: Option<String>,
    pub chunks: Vec<Chunk>,
    pub created_at: u64,
    pub completed_at: Option<u64>,
    pub headers: Option<HashMap<String, String>>,
    #[serde(default)]
    pub etag: Option<String>,
    #[serde(default)]
    pub last_modified: Option<String>,
    #[serde(default)]
    pub preferred_chunk_count: Option<usize>,
    #[serde(default)]
    pub expected_checksum: Option<String>,
    #[serde(default)]
    pub checksum_verified: Option<bool>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct QuietHoursConfig {
    pub enabled: bool,
    pub start_hour: u8,
    pub start_minute: u8,
    pub end_hour: u8,
    pub end_minute: u8,
    pub speed_limit_bytes_per_sec: u64, // e.g. 2_000_000 (2 MB/s)
}

impl Default for QuietHoursConfig {
    fn default() -> Self {
        Self {
            enabled: false,
            start_hour: 23,
            start_minute: 0,
            end_hour: 7,
            end_minute: 0,
            speed_limit_bytes_per_sec: 2_000_000,
        }
    }
}

impl DownloadTask {
    /// Computes overall progress as a ratio between 0.0 and 1.0.
    pub fn progress(&self) -> f64 {
        if self.total_bytes > 0 {
            (self.downloaded_bytes as f64 / self.total_bytes as f64).clamp(0.0, 1.0)
        } else if self.status == DownloadState::Completed {
            1.0
        } else {
            0.0
        }
    }
}

/// View display mode for download items.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ViewMode {
    Comfortable,
    Compact,
}

/// Persistent all-time download metrics retained across app sessions.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct AllTimeStats {
    pub total_downloaded_bytes: u64,
    pub total_completed_count: u64,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_category_from_filename() {
        assert_eq!(
            DownloadCategory::from_filename("archive.tar.gz"),
            DownloadCategory::Archives
        );
        assert_eq!(
            DownloadCategory::from_filename("backup.zip"),
            DownloadCategory::Archives
        );
        assert_eq!(
            DownloadCategory::from_filename("movie.mp4"),
            DownloadCategory::Videos
        );
        assert_eq!(
            DownloadCategory::from_filename("song.flac"),
            DownloadCategory::Music
        );
        assert_eq!(
            DownloadCategory::from_filename("installer.dmg"),
            DownloadCategory::Programs
        );
        assert_eq!(
            DownloadCategory::from_filename("setup.exe"),
            DownloadCategory::Programs
        );
        assert_eq!(
            DownloadCategory::from_filename("report.pdf"),
            DownloadCategory::Documents
        );
        assert_eq!(
            DownloadCategory::from_filename("notes.txt"),
            DownloadCategory::Documents
        );
        assert_eq!(
            DownloadCategory::from_filename("data.unknown"),
            DownloadCategory::Others
        );
        assert_eq!(
            DownloadCategory::from_filename("noextension"),
            DownloadCategory::Others
        );
    }

    #[test]
    fn test_category_from_mime_type() {
        assert_eq!(
            DownloadCategory::from_mime_type("video/mp4"),
            DownloadCategory::Videos
        );
        assert_eq!(
            DownloadCategory::from_mime_type("audio/mpeg"),
            DownloadCategory::Music
        );
        assert_eq!(
            DownloadCategory::from_mime_type("application/zip"),
            DownloadCategory::Archives
        );
        assert_eq!(
            DownloadCategory::from_mime_type("application/pdf"),
            DownloadCategory::Documents
        );
        assert_eq!(
            DownloadCategory::from_mime_type("application/x-msdownload"),
            DownloadCategory::Programs
        );
        assert_eq!(
            DownloadCategory::from_mime_type("application/octet-stream"),
            DownloadCategory::Others
        );
    }

    #[test]
    fn test_serde_serialization() {
        let state = DownloadState::Downloading;
        let json = serde_json::to_string(&state).unwrap();
        assert_eq!(json, "\"downloading\"");

        let category = DownloadCategory::Videos;
        let json_cat = serde_json::to_string(&category).unwrap();
        assert_eq!(json_cat, "\"videos\"");

        let view = ViewMode::Comfortable;
        let json_view = serde_json::to_string(&view).unwrap();
        assert_eq!(json_view, "\"comfortable\"");

        let stats = AllTimeStats {
            total_downloaded_bytes: 1048576,
            total_completed_count: 5,
        };
        let json_stats = serde_json::to_string(&stats).unwrap();
        let decoded: AllTimeStats = serde_json::from_str(&json_stats).unwrap();
        assert_eq!(decoded, stats);
    }

    #[test]
    fn test_chunk_new() {
        let chunk = Chunk::new(0, 0, 99);
        assert_eq!(chunk.index, 0);
        assert_eq!(chunk.start_offset, 0);
        assert_eq!(chunk.end_offset, 99);
        assert_eq!(chunk.total_bytes, 100);
        assert_eq!(chunk.downloaded_bytes, 0);
        assert!(!chunk.completed);
    }

    #[test]
    fn test_download_task_etag_last_modified_serde() {
        let task_json = r#"{
            "id": "test-task-1",
            "url": "https://example.com/file.iso",
            "filename": "file.iso",
            "destination_path": "/tmp/file.iso",
            "total_bytes": 1024,
            "downloaded_bytes": 512,
            "status": "downloading",
            "category": "archives",
            "speed": 100,
            "eta": 5,
            "resumable": true,
            "error": null,
            "chunks": [],
            "created_at": 1700000000,
            "completed_at": null,
            "headers": null,
            "etag": "\"abc-123\"",
            "last_modified": "Sun, 15 Nov 2026 00:00:00 GMT"
        }"#;

        let task: DownloadTask = serde_json::from_str(task_json).unwrap();
        assert_eq!(task.etag, Some("\"abc-123\"".to_string()));
        assert_eq!(task.last_modified, Some("Sun, 15 Nov 2026 00:00:00 GMT".to_string()));

        let serialized = serde_json::to_string(&task).unwrap();
        assert!(serialized.contains("\"etag\":\"\\\"abc-123\\\"\""));

        // Omitted etag and last_modified defaults to None
        let minimal_json = r#"{
            "id": "test-task-2",
            "url": "https://example.com/file2.iso",
            "filename": "file2.iso",
            "destination_path": "/tmp/file2.iso",
            "total_bytes": 1024,
            "downloaded_bytes": 0,
            "status": "pending",
            "category": "archives",
            "speed": 0,
            "eta": 0,
            "resumable": true,
            "error": null,
            "chunks": [],
            "created_at": 1700000000,
            "completed_at": null,
            "headers": null
        }"#;
        let task2: DownloadTask = serde_json::from_str(minimal_json).unwrap();
        assert_eq!(task2.etag, None);
        assert_eq!(task2.last_modified, None);
        assert_eq!(task2.preferred_chunk_count, None);
        assert_eq!(task2.expected_checksum, None);
        assert_eq!(task2.checksum_verified, None);
    }

    #[test]
    fn test_quiet_hours_config_default_and_serde() {
        let default_cfg = QuietHoursConfig::default();
        assert!(!default_cfg.enabled);
        assert_eq!(default_cfg.start_hour, 23);
        assert_eq!(default_cfg.start_minute, 0);
        assert_eq!(default_cfg.end_hour, 7);
        assert_eq!(default_cfg.end_minute, 0);
        assert_eq!(default_cfg.speed_limit_bytes_per_sec, 2_000_000);

        let json = serde_json::to_string(&default_cfg).unwrap();
        let deserialized: QuietHoursConfig = serde_json::from_str(&json).unwrap();
        assert_eq!(deserialized, default_cfg);
    }

    #[test]
    fn test_download_task_checksum_and_chunks_serde() {
        let task_json = r#"{
            "id": "test-task-checksum",
            "url": "https://example.com/file.tar.gz",
            "filename": "file.tar.gz",
            "destination_path": "/tmp/file.tar.gz",
            "total_bytes": 2048,
            "downloaded_bytes": 2048,
            "status": "completed",
            "category": "archives",
            "speed": 0,
            "eta": 0,
            "resumable": true,
            "error": null,
            "chunks": [],
            "created_at": 1700000000,
            "completed_at": 1700000010,
            "headers": null,
            "preferred_chunk_count": 4,
            "expected_checksum": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
            "checksum_verified": true
        }"#;

        let task: DownloadTask = serde_json::from_str(task_json).unwrap();
        assert_eq!(task.preferred_chunk_count, Some(4));
        assert_eq!(
            task.expected_checksum,
            Some("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855".to_string())
        );
        assert_eq!(task.checksum_verified, Some(true));
    }
}
