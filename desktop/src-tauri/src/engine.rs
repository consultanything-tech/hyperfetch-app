use crate::downloader::{
    calculate_chunks, download_task_content, fallback_filename_from_url, probe_url,
    sanitize_filename, DownloaderError,
};
use crate::models::{AllTimeStats, DownloadCategory, DownloadState, DownloadTask};
use crate::storage::{FileWriter, StorageError};
use reqwest::Client;
use std::collections::{HashMap, VecDeque};
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::{Duration, Instant};
use thiserror::Error;
use tokio::sync::{broadcast, mpsc, RwLock};

/// Errors that can occur within the Download Engine.
#[derive(Debug, Error)]
pub enum EngineError {
    #[error("Task not found: {0}")]
    TaskNotFound(String),

    #[error("Downloader error: {0}")]
    Downloader(#[from] DownloaderError),

    #[error("Storage error: {0}")]
    Storage(#[from] StorageError),

    #[error("I/O error: {0}")]
    Io(#[from] std::io::Error),

    #[error("Serialization error: {0}")]
    Serialization(#[from] serde_json::Error),

    #[error("Engine error: {0}")]
    Other(String),
}

/// Rolling speed calculator based on a sliding time window.
#[derive(Debug)]
pub struct SpeedTracker {
    window: VecDeque<(Instant, u64)>,
    window_duration: Duration,
}

impl SpeedTracker {
    pub fn new(window_duration: Duration) -> Self {
        Self {
            window: VecDeque::new(),
            window_duration,
        }
    }

    pub fn record(&mut self, bytes: u64) {
        if bytes == 0 {
            return;
        }
        let now = Instant::now();
        self.window.push_back((now, bytes));
        self.prune(now);
        while self.window.len() > 500 {
            self.window.pop_front();
        }
    }

    pub fn current_speed(&mut self) -> u64 {
        let now = Instant::now();
        self.prune(now);
        if self.window.is_empty() {
            return 0;
        }
        let total_bytes: u64 = self.window.iter().map(|(_, b)| *b).sum();
        let (first_time, _) = self.window.front().unwrap();
        let elapsed = now.duration_since(*first_time).as_secs_f64();
        if elapsed > 0.05 {
            (total_bytes as f64 / elapsed) as u64
        } else {
            total_bytes
        }
    }

    fn prune(&mut self, now: Instant) {
        while let Some((time, _)) = self.window.front() {
            if now.duration_since(*time) > self.window_duration {
                self.window.pop_front();
            } else {
                break;
            }
        }
    }
}

/// Central coordinator for download tasks, state persistence, rolling speed tracking,
/// and concurrent chunk workers.
#[derive(Clone)]
pub struct DownloadEngine {
    pub tasks: Arc<RwLock<Vec<DownloadTask>>>,
    pub cancellation_handles: Arc<RwLock<HashMap<String, broadcast::Sender<()>>>>,
    pub client: Client,
    pub state_file: PathBuf,
    pub all_time_stats: Arc<RwLock<AllTimeStats>>,
}

impl DownloadEngine {
    /// Returns default persistence location: `~/.config/hyperfetch/tasks.json`
    pub fn default_state_path() -> PathBuf {
        dirs::config_dir()
            .or_else(|| dirs::home_dir().map(|h| h.join(".config")))
            .unwrap_or_else(|| PathBuf::from("."))
            .join("hyperfetch")
            .join("tasks.json")
    }

    /// Derives the stats persistence path (`stats.json`) sibling to the task state file.
    pub fn stats_file_path(state_file: &Path) -> PathBuf {
        state_file.with_file_name("stats.json")
    }

    /// Reads all-time statistics from disk if available, otherwise returning defaults.
    pub fn load_stats_from_disk(path: &Path) -> AllTimeStats {
        if !path.exists() {
            return AllTimeStats::default();
        }
        let data = match std::fs::read_to_string(path) {
            Ok(d) => d,
            Err(_) => return AllTimeStats::default(),
        };
        serde_json::from_str(&data).unwrap_or_default()
    }

    /// Persists all-time statistics to disk atomically.
    pub async fn save_stats_to_disk(&self, stats: &AllTimeStats) -> Result<(), EngineError> {
        let stats_path = Self::stats_file_path(&self.state_file);
        let json = serde_json::to_string_pretty(stats)?;

        if let Some(parent) = stats_path.parent() {
            if !parent.as_os_str().is_empty() {
                std::fs::create_dir_all(parent)?;
            }
        }

        let tmp_file = stats_path.with_extension("tmp");
        std::fs::write(&tmp_file, json)?;
        std::fs::rename(&tmp_file, &stats_path)?;
        Ok(())
    }

    /// Returns a snapshot of the current all-time statistics.
    pub async fn get_all_time_stats(&self) -> AllTimeStats {
        self.all_time_stats.read().await.clone()
    }

    /// Creates a new `DownloadEngine` using default state persistence path.
    pub fn new() -> Self {
        Self::with_state_path(Self::default_state_path())
    }

    /// Creates a new `DownloadEngine` pointing to a specific state file.
    pub fn with_state_path(state_path: impl Into<PathBuf>) -> Self {
        let state_file = state_path.into();
        let loaded_tasks = Self::load_tasks_from_disk(&state_file);
        let stats_file = Self::stats_file_path(&state_file);
        let loaded_stats = Self::load_stats_from_disk(&stats_file);

        let client = Client::builder()
            .tcp_keepalive(Duration::from_secs(30))
            .build()
            .unwrap_or_else(|_| Client::new());

        Self {
            tasks: Arc::new(RwLock::new(loaded_tasks)),
            cancellation_handles: Arc::new(RwLock::new(HashMap::new())),
            client,
            state_file,
            all_time_stats: Arc::new(RwLock::new(loaded_stats)),
        }
    }

    /// Reads tasks from disk, automatically converting any previously active downloads into `Paused`.
    fn load_tasks_from_disk(path: &Path) -> Vec<DownloadTask> {
        if !path.exists() {
            return Vec::new();
        }
        let data = match std::fs::read_to_string(path) {
            Ok(d) => d,
            Err(_) => return Vec::new(),
        };

        let mut tasks: Vec<DownloadTask> = serde_json::from_str(&data).unwrap_or_default();
        for task in &mut tasks {
            if task.status == DownloadState::Downloading
                || task.status == DownloadState::Connecting
            {
                task.status = DownloadState::Paused;
                task.speed = 0;
                task.eta = 0;
            }
        }
        tasks
    }

    /// Atomically persists the current task list to disk as JSON.
    pub async fn save_state(&self) -> Result<(), EngineError> {
        let tasks = self.tasks.read().await.clone();
        let json = serde_json::to_string_pretty(&tasks)?;

        if let Some(parent) = self.state_file.parent() {
            if !parent.as_os_str().is_empty() {
                std::fs::create_dir_all(parent)?;
            }
        }

        let tmp_file = self.state_file.with_extension("tmp");
        std::fs::write(&tmp_file, json)?;
        std::fs::rename(&tmp_file, &self.state_file)?;
        Ok(())
    }

    /// Adds a new download task.
    pub async fn add_download(
        &self,
        url: String,
        filename: Option<String>,
        destination: Option<String>,
        auto_start: bool,
        headers: Option<HashMap<String, String>>,
    ) -> Result<DownloadTask, EngineError> {
        {
            let tasks_lock = self.tasks.read().await;
            if let Some(existing) = tasks_lock.iter().find(|t| {
                t.url == url
                    && t.status != DownloadState::Completed
                    && t.status != DownloadState::Failed
                    && t.status != DownloadState::Cancelled
            }) {
                let existing_task = existing.clone();
                drop(tasks_lock);
                if auto_start && existing_task.status == DownloadState::Paused {
                    let _ = self.resume_download(&existing_task.id).await;
                }
                return Ok(existing_task);
            }
        }

        let resolved_name = filename
            .filter(|f| !f.trim().is_empty())
            .map(|f| sanitize_filename(&f))
            .unwrap_or_else(|| fallback_filename_from_url(&url));

        let category = DownloadCategory::from_filename(&resolved_name);

        let destination_path = if let Some(dest) = destination {
            let p = PathBuf::from(dest);
            if p.is_dir()
                || p.to_string_lossy().ends_with('/')
                || p.to_string_lossy().ends_with('\\')
            {
                p.join(&resolved_name).to_string_lossy().to_string()
            } else {
                p.to_string_lossy().to_string()
            }
        } else {
            let dir = FileWriter::get_default_download_dir(Some(category.folder_name()));
            dir.join(&resolved_name).to_string_lossy().to_string()
        };

        let id = uuid::Uuid::new_v4().to_string();
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();

        let task = DownloadTask {
            id: id.clone(),
            url,
            filename: resolved_name,
            destination_path,
            total_bytes: 0,
            downloaded_bytes: 0,
            status: DownloadState::Pending,
            category,
            speed: 0,
            eta: 0,
            resumable: false,
            error: None,
            chunks: Vec::new(),
            created_at: now,
            completed_at: None,
            headers,
            etag: None,
            last_modified: None,
        };

        {
            let mut tasks_lock = self.tasks.write().await;
            tasks_lock.push(task.clone());
        }

        self.save_state().await?;

        if auto_start {
            self.start_or_resume(&id).await?;
        }

        Ok(task)
    }

    /// Resumes a paused download task (delegates to start_or_resume).
    pub async fn resume_download(&self, id: &str) -> Result<(), EngineError> {
        self.start_or_resume(id).await
    }

    /// Starts or resumes downloading a task by its ID.
    pub async fn start_or_resume(&self, id: &str) -> Result<(), EngineError> {
        let mut task = {
            let mut tasks = self.tasks.write().await;
            let t = tasks
                .iter_mut()
                .find(|t| t.id == id)
                .ok_or_else(|| EngineError::TaskNotFound(id.to_string()))?;

            if t.status == DownloadState::Downloading || t.status == DownloadState::Connecting {
                return Ok(());
            }
            if t.status == DownloadState::Completed {
                return Ok(());
            }

            t.status = DownloadState::Connecting;
            t.error = None;
            t.clone()
        };

        self.save_state().await?;

        let (cancel_tx, _cancel_rx) = broadcast::channel::<()>(4);
        {
            let mut handles = self.cancellation_handles.write().await;
            handles.insert(id.to_string(), cancel_tx.clone());
        }

        let engine = self.clone();
        let task_id = id.to_string();

        tokio::spawn(async move {
            let run_res = engine.run_download(&mut task, cancel_tx).await;

            {
                let mut handles = engine.cancellation_handles.write().await;
                handles.remove(&task_id);
            }

            let mut completed_task_bytes: Option<u64> = None;
            let mut tasks = engine.tasks.write().await;
            if let Some(t) = tasks.iter_mut().find(|t| t.id == task_id) {
                t.speed = 0;
                t.eta = 0;
                match run_res {
                    Ok(()) => {
                        t.status = DownloadState::Completed;
                        let now = std::time::SystemTime::now()
                            .duration_since(std::time::UNIX_EPOCH)
                            .unwrap_or_default()
                            .as_secs();
                        t.completed_at = Some(now);
                        if t.total_bytes > 0 {
                            t.downloaded_bytes = t.total_bytes;
                        }
                        for c in &mut t.chunks {
                            c.completed = true;
                            c.downloaded_bytes = c.total_bytes;
                        }
                        t.error = None;

                        let task_bytes = if t.total_bytes > 0 {
                            t.total_bytes
                        } else {
                            t.downloaded_bytes
                        };
                        completed_task_bytes = Some(task_bytes);
                    }
                    Err(DownloaderError::Cancelled) => {
                        if t.status != DownloadState::Cancelled {
                            t.status = DownloadState::Paused;
                        }
                    }
                    Err(e) => {
                        t.status = DownloadState::Failed;
                        t.error = Some(e.to_string());
                    }
                }
            }
            drop(tasks);

            if let Some(task_bytes) = completed_task_bytes {
                let mut stats = engine.all_time_stats.write().await;
                stats.total_downloaded_bytes += task_bytes;
                stats.total_completed_count += 1;
                let _ = engine.save_stats_to_disk(&stats).await;
            }

            let _ = engine.save_state().await;
        });

        Ok(())
    }

    /// Internal execution loop for downloading a task.
    async fn run_download(
        &self,
        task: &mut DownloadTask,
        cancel_tx: broadcast::Sender<()>,
    ) -> Result<(), DownloaderError> {
        // Step 1: Probe remote resource if total size is unknown or chunks not setup
        if task.total_bytes == 0 || task.chunks.is_empty() {
            match probe_url(&self.client, &task.url, task.headers.as_ref()).await {
                Ok(probe_result) => {
                    if let (Some(old_etag), Some(new_etag)) = (&task.etag, &probe_result.etag) {
                        if old_etag != new_etag {
                            task.downloaded_bytes = 0;
                            task.chunks.clear();
                        }
                    }
                    task.etag = probe_result.etag;
                    task.last_modified = probe_result.last_modified;

                    if let Some(len) = probe_result.content_length {
                        task.total_bytes = len;
                    }
                    task.resumable = probe_result.accept_ranges;

                    // If a suggested filename was found from Content-Disposition, update
                    if let Some(sug) = probe_result.suggested_filename {
                        if task.filename == "download" || !task.filename.contains('.') {
                            task.filename = sug.clone();
                            task.category = DownloadCategory::from_filename(&sug);
                            let def_dir = FileWriter::get_default_download_dir(Some(
                                task.category.folder_name(),
                            ));
                            task.destination_path =
                                def_dir.join(&sug).to_string_lossy().to_string();
                        }
                    }

                    // Sync updated metadata into state
                    {
                        let mut tasks = self.tasks.write().await;
                        if let Some(t) = tasks.iter_mut().find(|t| t.id == task.id) {
                            t.total_bytes = task.total_bytes;
                            t.resumable = task.resumable;
                            t.filename = task.filename.clone();
                            t.category = task.category;
                            t.destination_path = task.destination_path.clone();
                            t.etag = task.etag.clone();
                            t.last_modified = task.last_modified.clone();
                            t.downloaded_bytes = task.downloaded_bytes;
                            t.chunks = task.chunks.clone();
                        }
                    }
                }
                Err(DownloaderError::Cancelled) => return Err(DownloaderError::Cancelled),
                Err(err) => {
                    // Fall back to direct single-stream download
                    eprintln!(
                        "[DownloadEngine] Probe warning for {}: {}. Falling back to single-stream.",
                        task.url, err
                    );
                    task.resumable = false;
                }
            }
        }

        // Step 2: Setup chunks if not yet configured
        if task.chunks.is_empty() {
            if task.resumable && task.total_bytes > 0 {
                task.chunks = calculate_chunks(task.total_bytes, 8);
            } else {
                task.chunks = vec![crate::models::Chunk::new(
                    0,
                    0,
                    if task.total_bytes > 0 {
                        task.total_bytes - 1
                    } else {
                        0
                    },
                )];
            }

            {
                let mut tasks = self.tasks.write().await;
                if let Some(t) = tasks.iter_mut().find(|t| t.id == task.id) {
                    t.chunks = task.chunks.clone();
                }
            }
        }

        // Step 3: Pre-allocate file if size is known and resumable
        let writer = FileWriter::new(&task.destination_path)?;
        if task.resumable && task.total_bytes > 0 {
            if let Err(e) = writer.allocate(task.total_bytes).await {
                let err_msg = format!("Insufficient disk space: pre-allocation failed for {} bytes ({})", task.total_bytes, e);
                return Err(DownloaderError::Io(err_msg));
            }
        }

        // Step 4: Transition to Downloading
        {
            let mut tasks = self.tasks.write().await;
            if let Some(t) = tasks.iter_mut().find(|t| t.id == task.id) {
                t.status = DownloadState::Downloading;
            }
        }
        let _ = self.save_state().await;

        // Step 5: Start rolling speed & ETA tracking loop (500ms intervals)
        let (progress_tx, mut progress_rx) = mpsc::channel::<u64>(2000);
        let task_id_clone = task.id.clone();
        let tasks_ref = Arc::clone(&self.tasks);
        let mut speed_tracker = SpeedTracker::new(Duration::from_secs(2));

        let monitor_handle = tokio::spawn(async move {
            let mut interval = tokio::time::interval(Duration::from_millis(500));
            // First tick finishes immediately, consume it
            interval.tick().await;

            loop {
                tokio::select! {
                    maybe_bytes = progress_rx.recv() => {
                        match maybe_bytes {
                            Some(bytes) => {
                                speed_tracker.record(bytes);
                            }
                            None => break, // Channel closed
                        }
                    }
                    _ = interval.tick() => {
                        let speed = speed_tracker.current_speed();
                        let mut tasks_lock = tasks_ref.write().await;
                        if let Some(t) = tasks_lock.iter_mut().find(|t| t.id == task_id_clone) {
                            if t.status == DownloadState::Downloading {
                                t.speed = speed;
                                let remaining = t.total_bytes.saturating_sub(t.downloaded_bytes);
                                t.eta = if speed > 0 && remaining > 0 {
                                    remaining / speed
                                } else {
                                    0
                                };
                            }
                        }
                    }
                }
            }
        });

        // Step 6: Download content (with automatic HTTP 200 single-stream fallback)
        let download_result = download_task_content(
            &self.client,
            &task.url,
            &mut task.chunks,
            &writer,
            task.total_bytes,
            &mut task.resumable,
            task.headers.as_ref(),
            &cancel_tx,
            &progress_tx,
        )
        .await;

        // Stop progress monitor
        drop(progress_tx);
        let _ = monitor_handle.await;

        // Update downloaded_bytes and chunk progress into state
        let total_chunk_downloaded: u64 = task.chunks.iter().map(|c| c.downloaded_bytes).sum();
        task.downloaded_bytes = total_chunk_downloaded;

        {
            let mut tasks = self.tasks.write().await;
            if let Some(t) = tasks.iter_mut().find(|t| t.id == task.id) {
                t.chunks = task.chunks.clone();
                t.downloaded_bytes = task.downloaded_bytes;
                t.resumable = task.resumable;
            }
        }

        download_result
    }

    /// Pauses an active download task.
    pub async fn pause(&self, id: &str) -> Result<(), EngineError> {
        {
            let handles = self.cancellation_handles.read().await;
            if let Some(sender) = handles.get(id) {
                let _ = sender.send(());
            }
        }

        {
            let mut tasks = self.tasks.write().await;
            let task = tasks
                .iter_mut()
                .find(|t| t.id == id)
                .ok_or_else(|| EngineError::TaskNotFound(id.to_string()))?;

            task.status = DownloadState::Paused;
            task.speed = 0;
            task.eta = 0;
        }

        self.save_state().await?;
        Ok(())
    }

    /// Cancels a download task.
    pub async fn cancel(&self, id: &str) -> Result<(), EngineError> {
        {
            let handles = self.cancellation_handles.read().await;
            if let Some(sender) = handles.get(id) {
                let _ = sender.send(());
            }
        }

        {
            let mut tasks = self.tasks.write().await;
            let task = tasks
                .iter_mut()
                .find(|t| t.id == id)
                .ok_or_else(|| EngineError::TaskNotFound(id.to_string()))?;

            task.status = DownloadState::Cancelled;
            task.speed = 0;
            task.eta = 0;
        }

        self.save_state().await?;
        Ok(())
    }

    /// Deletes a download task and optionally its downloaded file.
    pub async fn delete(&self, id: &str, delete_file: bool) -> Result<(), EngineError> {
        let dest_path = {
            let handles = self.cancellation_handles.read().await;
            if let Some(sender) = handles.get(id) {
                let _ = sender.send(());
            }
            drop(handles);

            let mut tasks = self.tasks.write().await;
            let pos = tasks
                .iter()
                .position(|t| t.id == id)
                .ok_or_else(|| EngineError::TaskNotFound(id.to_string()))?;

            let removed = tasks.remove(pos);
            removed.destination_path
        };

        {
            let mut handles = self.cancellation_handles.write().await;
            handles.remove(id);
        }

        if delete_file {
            let p = PathBuf::from(dest_path);
            if p.exists() {
                let _ = std::fs::remove_file(p);
            }
        }

        self.save_state().await?;
        Ok(())
    }

    /// Returns a list of all managed download tasks.
    pub async fn get_tasks(&self) -> Vec<DownloadTask> {
        self.tasks.read().await.clone()
    }

    /// Returns a single download task by ID.
    pub async fn get_task(&self, id: &str) -> Option<DownloadTask> {
        self.tasks.read().await.iter().find(|t| t.id == id).cloned()
    }

    /// Pauses all currently active downloading/connecting tasks.
    pub async fn pause_all(&self) -> Result<(), EngineError> {
        let active_ids: Vec<String> = {
            let tasks = self.tasks.read().await;
            tasks
                .iter()
                .filter(|t| {
                    t.status == DownloadState::Downloading
                        || t.status == DownloadState::Connecting
                })
                .map(|t| t.id.clone())
                .collect()
        };
        for id in active_ids {
            let _ = self.pause(&id).await;
        }
        Ok(())
    }

    /// Resumes all paused, pending, or failed download tasks.
    pub async fn resume_all(&self) -> Result<(), EngineError> {
        let resumable_ids: Vec<String> = {
            let tasks = self.tasks.read().await;
            tasks
                .iter()
                .filter(|t| {
                    t.status == DownloadState::Paused
                        || t.status == DownloadState::Pending
                        || t.status == DownloadState::Failed
                })
                .map(|t| t.id.clone())
                .collect()
        };
        for id in resumable_ids {
            let _ = self.start_or_resume(&id).await;
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_engine_add_and_get_tasks() {
        let temp_dir = tempfile::tempdir().unwrap();
        let state_file = temp_dir.path().join("tasks.json");
        let engine = DownloadEngine::with_state_path(state_file);

        let task = engine
            .add_download(
                "https://example.com/files/sample.zip".to_string(),
                Some("custom.zip".to_string()),
                Some(temp_dir.path().to_string_lossy().to_string()),
                false,
                None,
            )
            .await
            .unwrap();

        assert_eq!(task.filename, "custom.zip");
        assert_eq!(task.category, DownloadCategory::Archives);
        assert_eq!(task.status, DownloadState::Pending);

        let tasks = engine.get_tasks().await;
        assert_eq!(tasks.len(), 1);
        assert_eq!(tasks[0].id, task.id);

        let retrieved = engine.get_task(&task.id).await;
        assert!(retrieved.is_some());
        assert_eq!(retrieved.unwrap().id, task.id);
    }

    #[tokio::test]
    async fn test_engine_state_persistence_and_auto_recover() {
        let temp_dir = tempfile::tempdir().unwrap();
        let state_file = temp_dir.path().join("tasks.json");
        let engine1 = DownloadEngine::with_state_path(&state_file);

        let task = engine1
            .add_download(
                "https://example.com/movie.mp4".to_string(),
                None,
                Some(temp_dir.path().to_string_lossy().to_string()),
                false,
                None,
            )
            .await
            .unwrap();

        // Simulate that the task was in Downloading state when the app closed
        {
            let mut tasks = engine1.tasks.write().await;
            tasks[0].status = DownloadState::Downloading;
            tasks[0].speed = 100_000;
        }
        engine1.save_state().await.unwrap();

        // Create engine2 from the same state file
        let engine2 = DownloadEngine::with_state_path(&state_file);
        let restored_tasks = engine2.get_tasks().await;
        assert_eq!(restored_tasks.len(), 1);
        assert_eq!(restored_tasks[0].id, task.id);
        // Downloading state should have automatically recovered to Paused
        assert_eq!(restored_tasks[0].status, DownloadState::Paused);
        assert_eq!(restored_tasks[0].speed, 0);
    }

    #[tokio::test]
    async fn test_engine_pause_and_cancel() {
        let temp_dir = tempfile::tempdir().unwrap();
        let state_file = temp_dir.path().join("tasks.json");
        let engine = DownloadEngine::with_state_path(state_file);

        let task = engine
            .add_download(
                "https://example.com/test.iso".to_string(),
                None,
                None,
                false,
                None,
            )
            .await
            .unwrap();

        engine.pause(&task.id).await.unwrap();
        let paused = engine.get_task(&task.id).await.unwrap();
        assert_eq!(paused.status, DownloadState::Paused);

        engine.cancel(&task.id).await.unwrap();
        let cancelled = engine.get_task(&task.id).await.unwrap();
        assert_eq!(cancelled.status, DownloadState::Cancelled);
    }

    #[tokio::test]
    async fn test_engine_delete_with_file() {
        let temp_dir = tempfile::tempdir().unwrap();
        let file_path = temp_dir.path().join("test_delete.txt");
        std::fs::write(&file_path, b"Hello delete").unwrap();
        assert!(file_path.exists());

        let state_file = temp_dir.path().join("tasks.json");
        let engine = DownloadEngine::with_state_path(state_file);

        let task = engine
            .add_download(
                "https://example.com/test_delete.txt".to_string(),
                Some("test_delete.txt".to_string()),
                Some(file_path.to_string_lossy().to_string()),
                false,
                None,
            )
            .await
            .unwrap();

        assert_eq!(engine.get_tasks().await.len(), 1);

        engine.delete(&task.id, true).await.unwrap();
        assert_eq!(engine.get_tasks().await.len(), 0);
        assert!(!file_path.exists());
    }

    #[tokio::test]
    async fn test_speed_tracker() {
        let mut tracker = SpeedTracker::new(Duration::from_secs(1));
        assert_eq!(tracker.current_speed(), 0);

        tracker.record(500);
        tokio::time::sleep(Duration::from_millis(60)).await;
        tracker.record(500);

        let speed = tracker.current_speed();
        assert!(speed > 0);
    }

    #[test]
    fn test_speed_tracker_window_cap() {
        let mut tracker = SpeedTracker::new(Duration::from_secs(60));
        for _ in 0..1000 {
            tracker.record(10);
        }
        assert_eq!(tracker.window.len(), 500);
    }

    #[tokio::test]
    async fn test_engine_end_to_end_download() {
        use axum::http::header::{CONTENT_LENGTH, CONTENT_RANGE, RANGE};
        use axum::http::{HeaderMap, StatusCode};
        use axum::response::IntoResponse;
        use axum::routing::get;
        use axum::Router;

        let test_data: Vec<u8> = (0..20_000).map(|i| (i % 256) as u8).collect();
        let payload_len = test_data.len();
        let data_clone = test_data.clone();

        let app = Router::new().route(
            "/engine_download.bin",
            get(move |headers: HeaderMap| {
                let d = data_clone.clone();
                async move {
                    if let Some(range_header) = headers.get(RANGE).and_then(|v| v.to_str().ok()) {
                        if let Some(range_str) = range_header.strip_prefix("bytes=") {
                            let parts: Vec<&str> = range_str.split('-').collect();
                            let start: usize = parts[0].parse().unwrap_or(0);
                            let end: usize = if parts.len() > 1 && !parts[1].is_empty() {
                                parts[1].parse().unwrap_or(payload_len - 1)
                            } else {
                                payload_len - 1
                            };
                            let end = end.min(payload_len - 1);
                            let slice = d[start..=end].to_vec();
                            return (
                                StatusCode::PARTIAL_CONTENT,
                                [
                                    (
                                        CONTENT_RANGE,
                                        format!("bytes {}-{}/{}", start, end, payload_len),
                                    ),
                                    (CONTENT_LENGTH, slice.len().to_string()),
                                ],
                                slice,
                            )
                                .into_response();
                        }
                    }
                    (StatusCode::OK, [(CONTENT_LENGTH, payload_len.to_string())], d).into_response()
                }
            }),
        );

        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        tokio::spawn(async move {
            axum::serve(listener, app).await.unwrap();
        });

        let temp_dir = tempfile::tempdir().unwrap();
        let state_file = temp_dir.path().join("tasks.json");
        let dest_file = temp_dir.path().join("engine_download.bin");

        let engine = DownloadEngine::with_state_path(state_file);
        let url = format!("http://{}/engine_download.bin", addr);

        let task = engine
            .add_download(
                url,
                Some("engine_download.bin".to_string()),
                Some(dest_file.to_string_lossy().to_string()),
                true,
                None,
            )
            .await
            .unwrap();

        // Wait for download to complete
        for _ in 0..50 {
            tokio::time::sleep(Duration::from_millis(100)).await;
            if let Some(t) = engine.get_task(&task.id).await {
                if t.status == DownloadState::Completed {
                    break;
                }
            }
        }

        let completed = engine.get_task(&task.id).await.unwrap();
        assert_eq!(completed.status, DownloadState::Completed);
        assert_eq!(completed.downloaded_bytes, payload_len as u64);
        assert!(dest_file.exists());
        let disk_bytes = std::fs::read(&dest_file).unwrap();
        assert_eq!(disk_bytes, test_data);
    }

    #[tokio::test]
    async fn test_engine_etag_change_resets_chunks() {
        use crate::models::Chunk;
        use axum::http::header::{ACCEPT_RANGES, CONTENT_LENGTH, ETAG};
        use axum::http::StatusCode;
        use axum::response::IntoResponse;
        use axum::routing::head;
        use axum::Router;

        let app = Router::new().route(
            "/etag_test.bin",
            head(|| async {
                (
                    StatusCode::OK,
                    [
                        (ACCEPT_RANGES, "bytes"),
                        (CONTENT_LENGTH, "5000"),
                        (ETAG, "\"v2-etag\""),
                    ],
                    "",
                )
                    .into_response()
            }),
        );

        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        tokio::spawn(async move {
            axum::serve(listener, app).await.unwrap();
        });

        let temp_dir = tempfile::tempdir().unwrap();
        let state_file = temp_dir.path().join("tasks.json");
        let dest_file = temp_dir.path().join("etag_test.bin");

        let engine = DownloadEngine::with_state_path(state_file);
        let url = format!("http://{}/etag_test.bin", addr);

        // Add task without auto_start
        let task = engine
            .add_download(
                url,
                Some("etag_test.bin".to_string()),
                Some(dest_file.to_string_lossy().to_string()),
                false,
                None,
            )
            .await
            .unwrap();

        // Simulate existing task state with old etag and partially downloaded chunks
        {
            let mut tasks = engine.tasks.write().await;
            if let Some(t) = tasks.iter_mut().find(|t| t.id == task.id) {
                t.etag = Some("\"v1-etag\"".to_string());
                t.downloaded_bytes = 2500;
                t.chunks = vec![Chunk::new(0, 0, 4999)];
            }
        }

        let (cancel_tx, _) = broadcast::channel(1);
        let mut task_clone = engine.get_task(&task.id).await.unwrap();
        task_clone.total_bytes = 0;
        let _ = engine.run_download(&mut task_clone, cancel_tx).await;

        let updated = engine.get_task(&task.id).await.unwrap();
        assert_eq!(updated.etag.as_deref(), Some("\"v2-etag\""));
        assert_eq!(updated.downloaded_bytes, 0);
        assert!(updated.chunks.iter().all(|c| c.downloaded_bytes == 0));
    }

    #[tokio::test]
    async fn test_engine_duplicate_url_returns_existing_task() {
        let temp_dir = tempfile::tempdir().unwrap();
        let state_file = temp_dir.path().join("tasks.json");
        let engine = DownloadEngine::with_state_path(state_file);

        let url = "https://example.com/files/duplicate.zip".to_string();
        let task1 = engine
            .add_download(
                url.clone(),
                Some("duplicate.zip".to_string()),
                Some(temp_dir.path().to_string_lossy().to_string()),
                false,
                None,
            )
            .await
            .unwrap();

        assert_eq!(task1.status, DownloadState::Pending);

        // Adding duplicate URL with auto_start = false returns the existing task without increasing task count
        let task2 = engine
            .add_download(
                url.clone(),
                Some("duplicate.zip".to_string()),
                Some(temp_dir.path().to_string_lossy().to_string()),
                false,
                None,
            )
            .await
            .unwrap();

        assert_eq!(task2.id, task1.id);
        let tasks = engine.get_tasks().await;
        assert_eq!(tasks.len(), 1);

        // Pause task and add with auto_start = true: returns existing task
        engine.pause(&task1.id).await.unwrap();
        let paused_task = engine.get_task(&task1.id).await.unwrap();
        assert_eq!(paused_task.status, DownloadState::Paused);

        let task3 = engine
            .add_download(
                url.clone(),
                None,
                None,
                false,
                None,
            )
            .await
            .unwrap();

        assert_eq!(task3.id, task1.id);
        let tasks_after = engine.get_tasks().await;
        assert_eq!(tasks_after.len(), 1);
    }

    #[tokio::test]
    async fn test_engine_all_time_stats_tracking_and_persistence() {
        let temp_dir = tempfile::tempdir().unwrap();
        let state_file = temp_dir.path().join("tasks.json");

        let engine = DownloadEngine::with_state_path(&state_file);
        let initial_stats = engine.get_all_time_stats().await;
        assert_eq!(initial_stats.total_downloaded_bytes, 0);
        assert_eq!(initial_stats.total_completed_count, 0);

        // Update stats and save to disk
        {
            let mut stats = engine.all_time_stats.write().await;
            stats.total_downloaded_bytes += 4096;
            stats.total_completed_count += 2;
            engine.save_stats_to_disk(&stats).await.unwrap();
        }

        let updated_stats = engine.get_all_time_stats().await;
        assert_eq!(updated_stats.total_downloaded_bytes, 4096);
        assert_eq!(updated_stats.total_completed_count, 2);

        // Verify stats.json file exists on disk
        let stats_file = DownloadEngine::stats_file_path(&state_file);
        assert!(stats_file.exists());

        // Recreate engine pointing to the same state file and assert persistence
        let restored_engine = DownloadEngine::with_state_path(&state_file);
        let restored_stats = restored_engine.get_all_time_stats().await;
        assert_eq!(restored_stats.total_downloaded_bytes, 4096);
        assert_eq!(restored_stats.total_completed_count, 2);
    }
}
