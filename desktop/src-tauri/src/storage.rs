use serde::Serialize;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use thiserror::Error;

/// Errors that can occur during storage and file operations.
#[derive(Debug, Error, Serialize, Clone, PartialEq, Eq)]
pub enum StorageError {
    #[error("I/O error: {0}")]
    Io(String),

    #[error("Invalid path: {0}")]
    InvalidPath(String),

    #[error("Allocation error: {0}")]
    AllocationError(String),

    #[error("Write error at offset {offset}: {message}")]
    WriteError { offset: u64, message: String },
}

impl From<std::io::Error> for StorageError {
    fn from(err: std::io::Error) -> Self {
        StorageError::Io(err.to_string())
    }
}

/// High-performance, cross-platform file writer that manages disk I/O,
/// file pre-allocation, and concurrent chunk writes at direct byte offsets.
#[derive(Clone, Debug)]
pub struct FileWriter {
    pub destination_path: PathBuf,
    file: Arc<tokio::sync::RwLock<std::fs::File>>,
}

impl FileWriter {
    /// Creates a new `FileWriter` at the specified destination path.
    /// Creates parent directories if they don't exist, and opens or creates
    /// the file with read and write permissions.
    pub fn new(destination_path: impl Into<PathBuf>) -> Result<Self, StorageError> {
        let path = destination_path.into();

        if let Some(parent) = path.parent() {
            if !parent.as_os_str().is_empty() {
                std::fs::create_dir_all(parent).map_err(|e| {
                    StorageError::Io(format!(
                        "Failed to create directory {}: {}",
                        parent.display(),
                        e
                    ))
                })?;
            }
        }

        let file = std::fs::OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .open(&path)
            .map_err(|e| {
                StorageError::Io(format!("Failed to open file {}: {}", path.display(), e))
            })?;

        Ok(Self {
            destination_path: path,
            file: Arc::new(tokio::sync::RwLock::new(file)),
        })
    }

    /// Pre-allocates the file size using `set_len` (ftruncate on POSIX, SetEndOfFile on Windows).
    pub async fn allocate(&self, total_bytes: u64) -> Result<(), StorageError> {
        let file = self.file.write().await;
        file.set_len(total_bytes).map_err(|e| {
            if e.raw_os_error() == Some(28) || e.to_string().to_lowercase().contains("space") {
                StorageError::Io(format!(
                    "Insufficient disk space: cannot allocate {} bytes ({})",
                    total_bytes, e
                ))
            } else {
                StorageError::AllocationError(format!(
                    "Failed to allocate {} bytes: {}",
                    total_bytes, e
                ))
            }
        })?;
        Ok(())
    }

    /// Thread-safe write of byte slice at exact byte offset.
    /// Uses POSIX `pwrite` via `FileExt` on Unix platforms and `seek_write` on Windows
    /// without mutating the global file pointer, allowing parallel chunk writes.
    pub async fn write_at(&self, data: &[u8], offset: u64) -> Result<(), StorageError> {
        if data.is_empty() {
            return Ok(());
        }

        #[cfg(unix)]
        {
            use std::os::unix::fs::FileExt;
            let file = self.file.read().await;
            file.write_all_at(data, offset).map_err(|e| {
                StorageError::WriteError {
                    offset,
                    message: e.to_string(),
                }
            })?;
        }

        #[cfg(windows)]
        {
            use std::os::windows::fs::FileExt;
            let file = self.file.read().await;
            let mut total_written = 0;
            while total_written < data.len() {
                let n = file
                    .seek_write(&data[total_written..], offset + total_written as u64)
                    .map_err(|e| StorageError::WriteError {
                        offset: offset + total_written as u64,
                        message: e.to_string(),
                    })?;
                if n == 0 {
                    return Err(StorageError::WriteError {
                        offset: offset + total_written as u64,
                        message: "Zero bytes written (disk full or write interrupted)".to_string(),
                    });
                }
                total_written += n;
            }
        }

        #[cfg(not(any(unix, windows)))]
        {
            use std::io::{Seek, SeekFrom, Write};
            let mut file = self.file.write().await;
            file.seek(SeekFrom::Start(offset)).map_err(|e| {
                StorageError::WriteError {
                    offset,
                    message: e.to_string(),
                }
            })?;
            file.write_all(data).map_err(|e| {
                StorageError::WriteError {
                    offset,
                    message: e.to_string(),
                }
            })?;
        }

        Ok(())
    }

    /// Flushes OS in-memory file buffers to disk (`sync_all`).
    pub async fn sync(&self) -> Result<(), StorageError> {
        let file = self.file.read().await;
        file.sync_all()
            .map_err(|e| StorageError::Io(format!("Failed to flush buffers: {}", e)))?;
        Ok(())
    }

    /// Returns current file metadata length in bytes.
    pub async fn current_size(&self) -> Result<u64, StorageError> {
        let file = self.file.read().await;
        let metadata = file
            .metadata()
            .map_err(|e| StorageError::Io(format!("Failed to read metadata: {}", e)))?;
        Ok(metadata.len())
    }

    /// Returns reference to the destination path.
    pub fn destination_path(&self) -> &Path {
        &self.destination_path
    }

    /// Resolves the default download directory:
    /// `~/Downloads/HyperFetch` (or `%USERPROFILE%\Downloads\HyperFetch` on Windows),
    /// plus optional category subfolder: `Videos`, `Music`, `Archives`, `Documents`, `Programs`, `Others`.
    pub fn get_default_download_dir(category: Option<&str>) -> PathBuf {
        let base = dirs::download_dir()
            .or_else(|| dirs::home_dir().map(|h| h.join("Downloads")))
            .unwrap_or_else(|| PathBuf::from("Downloads"))
            .join("HyperFetch");

        match category {
            Some(cat) if !cat.trim().is_empty() => {
                let cat_trimmed = cat.trim();
                let lower = cat_trimmed.to_lowercase();
                let cat_clean = match lower.as_str() {
                    "videos" | "video" => "Videos",
                    "music" | "audio" => "Music",
                    "archives" | "archive" => "Archives",
                    "documents" | "document" | "docs" => "Documents",
                    "programs" | "program" | "apps" | "software" => "Programs",
                    "others" | "other" => "Others",
                    _ => {
                        let path = Path::new(cat_trimmed);
                        let safe_name = path.file_name().and_then(|s| s.to_str()).unwrap_or("Others");
                        if safe_name.is_empty() || safe_name == "." || safe_name == ".." {
                            "Others"
                        } else {
                            safe_name
                        }
                    }
                };
                base.join(cat_clean)
            }
            _ => base,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_file_allocation() {
        let temp_dir = tempfile::tempdir().expect("Failed to create tempdir");
        let file_path = temp_dir.path().join("alloc_test.bin");
        let writer = FileWriter::new(&file_path).expect("Failed to create FileWriter");

        assert_eq!(writer.current_size().await.expect("current_size failed"), 0);

        let target_size = 1024 * 512; // 512 KB
        writer
            .allocate(target_size)
            .await
            .expect("allocate failed");

        assert_eq!(
            writer.current_size().await.expect("current_size failed"),
            target_size
        );

        let metadata = std::fs::metadata(&file_path).expect("metadata failed");
        assert_eq!(metadata.len(), target_size);
    }

    #[tokio::test]
    async fn test_concurrent_chunk_writes() {
        let temp_dir = tempfile::tempdir().expect("Failed to create tempdir");
        let file_path = temp_dir.path().join("concurrent_test.bin");
        let writer = FileWriter::new(&file_path).expect("Failed to create FileWriter");

        let total_size = 30u64;
        writer
            .allocate(total_size)
            .await
            .expect("allocate failed");

        // Chunks at non-overlapping offsets:
        // Chunk 0: offset 0, len 10 -> "0123456789"
        // Chunk 1: offset 10, len 10 -> "ABCDEFGHIJ"
        // Chunk 2: offset 20, len 10 -> "!@#$%^&*()"
        let chunk0 = b"0123456789".to_vec();
        let chunk1 = b"ABCDEFGHIJ".to_vec();
        let chunk2 = b"!@#$%^&*()".to_vec();

        let w0 = writer.clone();
        let c0 = chunk0.clone();
        let t0 = tokio::spawn(async move {
            w0.write_at(&c0, 0).await.expect("chunk 0 write failed");
        });

        let w1 = writer.clone();
        let c1 = chunk1.clone();
        let t1 = tokio::spawn(async move {
            w1.write_at(&c1, 10).await.expect("chunk 1 write failed");
        });

        let w2 = writer.clone();
        let c2 = chunk2.clone();
        let t2 = tokio::spawn(async move {
            w2.write_at(&c2, 20).await.expect("chunk 2 write failed");
        });

        let (r0, r1, r2) = tokio::join!(t0, t1, t2);
        r0.expect("task 0 panicked");
        r1.expect("task 1 panicked");
        r2.expect("task 2 panicked");

        writer.sync().await.expect("sync failed");

        let content = std::fs::read(&file_path).expect("Failed to read file");
        let mut expected = Vec::new();
        expected.extend_from_slice(&chunk0);
        expected.extend_from_slice(&chunk1);
        expected.extend_from_slice(&chunk2);

        assert_eq!(content, expected);
    }

    #[test]
    fn test_default_download_dir() {
        let base = FileWriter::get_default_download_dir(None);
        assert!(
            base.ends_with("Downloads/HyperFetch")
                || base.ends_with(r"Downloads\HyperFetch")
                || base.ends_with("HyperFetch")
        );

        let videos = FileWriter::get_default_download_dir(Some("Videos"));
        assert_eq!(videos, base.join("Videos"));

        let videos_lower = FileWriter::get_default_download_dir(Some("videos"));
        assert_eq!(videos_lower, base.join("Videos"));

        let music = FileWriter::get_default_download_dir(Some("Music"));
        assert_eq!(music, base.join("Music"));

        let audio = FileWriter::get_default_download_dir(Some("audio"));
        assert_eq!(audio, base.join("Music"));

        let archives = FileWriter::get_default_download_dir(Some("Archives"));
        assert_eq!(archives, base.join("Archives"));

        let documents = FileWriter::get_default_download_dir(Some("Documents"));
        assert_eq!(documents, base.join("Documents"));

        let programs = FileWriter::get_default_download_dir(Some("Programs"));
        assert_eq!(programs, base.join("Programs"));

        let others = FileWriter::get_default_download_dir(Some("Others"));
        assert_eq!(others, base.join("Others"));

        let custom = FileWriter::get_default_download_dir(Some("ISO"));
        assert_eq!(custom, base.join("ISO"));
    }

    #[tokio::test]
    async fn test_nested_directory_creation() {
        let temp_dir = tempfile::tempdir().expect("Failed to create tempdir");
        let nested_path = temp_dir
            .path()
            .join("subdir")
            .join("deep")
            .join("nested")
            .join("target.bin");

        let writer = FileWriter::new(&nested_path).expect("Failed to create FileWriter");
        assert!(nested_path.exists());
        assert_eq!(writer.destination_path(), nested_path.as_path());
    }

    #[tokio::test]
    async fn test_empty_slice_write() {
        let temp_dir = tempfile::tempdir().expect("Failed to create tempdir");
        let file_path = temp_dir.path().join("empty_test.bin");
        let writer = FileWriter::new(&file_path).expect("Failed to create FileWriter");

        writer.write_at(&[], 100).await.expect("Empty write should succeed");
        assert_eq!(writer.current_size().await.expect("current_size failed"), 0);
    }
}
