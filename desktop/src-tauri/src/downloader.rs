use crate::models::Chunk;
use crate::storage::{FileWriter, StorageError};
use futures_util::StreamExt;
use reqwest::header::{
    HeaderMap, ACCEPT_ENCODING, ACCEPT_RANGES, CONTENT_DISPOSITION, CONTENT_LENGTH, CONTENT_RANGE,
    CONTENT_TYPE, ETAG, LAST_MODIFIED, RANGE, USER_AGENT,
};
use reqwest::{Client, StatusCode, Url};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;
use std::time::Duration;
use thiserror::Error;
use tokio::sync::{broadcast, mpsc};

const DEFAULT_USER_AGENT: &str =
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36";
pub const MIN_CHUNK_SIZE: u64 = 1024 * 1024; // 1 MB

/// Errors that can occur during URL probing and file downloading.
#[derive(Debug, Error)]
pub enum DownloaderError {
    #[error("HTTP error {status}: {message}")]
    HttpError { status: u16, message: String },

    #[error("Network error: {0}")]
    Network(String),

    #[error("Storage error: {0}")]
    Storage(#[from] StorageError),

    #[error("I/O error: {0}")]
    Io(String),

    #[error("Operation cancelled")]
    Cancelled,

    #[error("Server returned HTTP 200 instead of 206 for range request")]
    SingleStreamFallbackRequired,

    #[error("Unexpected EOF: expected {expected} bytes, received {received} bytes")]
    UnexpectedEof { expected: u64, received: u64 },

    #[error("Invalid URL: {0}")]
    InvalidUrl(String),

    #[error("Engine error: {0}")]
    Other(String),
}

/// Type alias matching Swift/API naming conventions.
pub type DownloadError = DownloaderError;

impl From<reqwest::Error> for DownloaderError {
    fn from(err: reqwest::Error) -> Self {
        DownloaderError::Network(err.to_string())
    }
}

/// Represents the inspected capabilities and metadata of a remote URL.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ProbeResult {
    pub content_length: Option<u64>,
    pub accept_ranges: bool,
    pub suggested_filename: Option<String>,
    pub mime_type: Option<String>,
    pub is_redirect: bool,
    pub final_url: String,
    pub etag: Option<String>,
    pub last_modified: Option<String>,
}

/// Helper function to perform percent-decoding on a string.
pub fn percent_decode(input: &str) -> String {
    let mut bytes = Vec::new();
    let mut chars = input.bytes();
    while let Some(b) = chars.next() {
        if b == b'%' {
            let h1 = chars.next();
            let h2 = chars.next();
            if let (Some(h1), Some(h2)) = (h1, h2) {
                if let (Some(d1), Some(d2)) = (
                    (h1 as char).to_digit(16),
                    (h2 as char).to_digit(16),
                ) {
                    bytes.push(((d1 << 4) | d2) as u8);
                    continue;
                }
            }
        }
        bytes.push(b);
    }
    String::from_utf8_lossy(&bytes).into_owned()
}

/// Sanitizes a filename to prevent path traversal or invalid characters.
pub fn sanitize_filename(filename: &str) -> String {
    let trimmed = filename.trim();
    let without_nulls: String = trimmed.chars().filter(|c| *c != '\0').collect();
    let normalized = without_nulls.replace('\\', "/");
    let leaf = normalized.rsplit('/').next().unwrap_or("").trim();
    if leaf.is_empty() || leaf == "." || leaf == ".." {
        "download".to_string()
    } else {
        leaf.to_string()
    }
}

/// Extracts fallback filename from a URL path or query parameters.
pub fn fallback_filename_from_url(url_str: &str) -> String {
    if let Ok(parsed) = Url::parse(url_str) {
        // Check query parameters first (e.g. ?file=foo.zip or ?filename=foo.zip)
        for (k, v) in parsed.query_pairs() {
            if k.eq_ignore_ascii_case("filename") || k.eq_ignore_ascii_case("file") {
                let s = sanitize_filename(&v);
                if s != "download" && !s.is_empty() {
                    return s;
                }
            }
        }

        let path = parsed.path();
        let leaf = path.rsplit('/').next().unwrap_or("");
        let decoded = percent_decode(leaf);
        let sanitized = sanitize_filename(&decoded);
        if sanitized != "download" && !sanitized.is_empty() {
            return sanitized;
        }
    }
    "download".to_string()
}

/// Parses Content-Disposition header into a sanitized filename.
/// Supports RFC 5987 / RFC 6266 `filename*=` and standard `filename=`.
pub fn parse_content_disposition(header: &str) -> Option<String> {
    // 1. Try RFC 5987 / 6266: filename*=
    if let Some(pos) = header.to_lowercase().find("filename*=") {
        let after = header[pos + 10..].trim();
        let without_quotes = if after.starts_with('"') {
            after.strip_prefix('"').and_then(|s| s.split('"').next()).unwrap_or("")
        } else {
            after.split(';').next().unwrap_or("").trim()
        };

        // Format is charset'language'encoded-value
        let parts: Vec<&str> = without_quotes.split('\'').collect();
        let raw_val = if parts.len() >= 3 {
            parts[2..].join("'")
        } else {
            without_quotes.to_string()
        };

        let decoded = percent_decode(&raw_val);
        let sanitized = sanitize_filename(&decoded);
        if sanitized != "download" && !sanitized.is_empty() {
            return Some(sanitized);
        }
    }

    // 2. Try standard filename=
    if let Some(pos) = header.to_lowercase().find("filename=") {
        // Ensure it's not filename*=
        if pos == 0 || header.as_bytes()[pos - 1] != b'*' {
            let after = header[pos + 9..].trim();
            let raw_val = if after.starts_with('"') {
                let without_leading = &after[1..];
                let mut unquoted = String::new();
                let mut escaping = false;
                for ch in without_leading.chars() {
                    if escaping {
                        unquoted.push(ch);
                        escaping = false;
                    } else if ch == '\\' {
                        escaping = true;
                    } else if ch == '"' {
                        break;
                    } else {
                        unquoted.push(ch);
                    }
                }
                unquoted
            } else {
                after.split(';').next().unwrap_or("").trim().to_string()
            };

            let sanitized = sanitize_filename(&raw_val);
            if sanitized != "download" && !sanitized.is_empty() {
                return Some(sanitized);
            }
        }
    }

    None
}

/// Parses the total byte length from a `Content-Range` header (e.g. "bytes 0-0/10485760").
pub fn parse_content_range_total(header: &str) -> Option<u64> {
    if let Some(slash_idx) = header.rfind('/') {
        let total_str = header[slash_idx + 1..].trim();
        total_str.parse::<u64>().ok()
    } else {
        None
    }
}

fn apply_custom_headers(
    mut req: reqwest::RequestBuilder,
    headers: Option<&HashMap<String, String>>,
) -> reqwest::RequestBuilder {
    let mut has_ua = false;
    if let Some(h) = headers {
        for (k, v) in h {
            if k.eq_ignore_ascii_case("user-agent") {
                has_ua = true;
            }
            req = req.header(k, v);
        }
    }
    if !has_ua {
        req = req.header(USER_AGENT, DEFAULT_USER_AGENT);
    }
    req.header(ACCEPT_ENCODING, "identity")
}

#[derive(Debug)]
struct RateLimiterState {
    last_refill: std::time::Instant,
    available_tokens: f64,
}

/// Token bucket bandwidth rate limiter for throttling downloads.
#[derive(Debug, Clone)]
pub struct RateLimiter {
    state: Arc<tokio::sync::Mutex<RateLimiterState>>,
    limit_bytes_per_sec: Arc<AtomicU64>,
}

impl RateLimiter {
    pub fn new(limit_bytes_per_sec: u64) -> Self {
        Self {
            state: Arc::new(tokio::sync::Mutex::new(RateLimiterState {
                last_refill: std::time::Instant::now(),
                available_tokens: 0.0,
            })),
            limit_bytes_per_sec: Arc::new(AtomicU64::new(limit_bytes_per_sec)),
        }
    }

    pub fn set_limit(&self, limit: u64) {
        self.limit_bytes_per_sec.store(limit, Ordering::Relaxed);
    }

    pub fn get_limit(&self) -> u64 {
        self.limit_bytes_per_sec.load(Ordering::Relaxed)
    }

    pub async fn throttle(&self, bytes: u64) {
        let limit = self.limit_bytes_per_sec.load(Ordering::Relaxed);
        if limit == 0 || bytes == 0 {
            return;
        }

        let mut state = self.state.lock().await;
        let now = std::time::Instant::now();
        let elapsed = now.duration_since(state.last_refill).as_secs_f64();
        state.last_refill = now;

        let capacity = limit as f64;
        state.available_tokens = (state.available_tokens + elapsed * capacity).min(capacity);

        let needed = bytes as f64;
        if state.available_tokens >= needed {
            state.available_tokens -= needed;
        } else {
            let deficit = needed - state.available_tokens;
            state.available_tokens = 0.0;
            let wait_secs = deficit / capacity;
            drop(state);
            let wait = wait_secs.min(1.0);
            tokio::time::sleep(Duration::from_secs_f64(wait)).await;
        }
    }
}

/// Helper struct for constructing standardized chunk download HTTP clients.
pub struct ChunkDownloader;

impl ChunkDownloader {
    pub fn build_client() -> Client {
        Client::builder()
            .connect_timeout(Duration::from_secs(15))
            .timeout(Duration::from_secs(60))
            .tcp_keepalive(Duration::from_secs(30))
            .build()
            .unwrap_or_else(|_| Client::new())
    }
}

/// Standalone probe helper constructing a standardized HTTP client.
pub async fn probe_download(
    url: &str,
    headers: Option<&HashMap<String, String>>,
) -> Result<ProbeResult, DownloaderError> {
    let client = ChunkDownloader::build_client();
    probe_url(&client, url, headers).await
}

/// Probes a remote URL using HEAD and GET Range 0-0 in parallel to inspect capabilities and metadata.
pub async fn probe_url(
    client: &Client,
    url: &str,
    headers: Option<&HashMap<String, String>>,
) -> Result<ProbeResult, DownloaderError> {
    let _parsed_url = Url::parse(url).map_err(|e| DownloaderError::InvalidUrl(e.to_string()))?;

    let head_fut = apply_custom_headers(client.head(url), headers).send();
    let get_fut = apply_custom_headers(client.get(url), headers)
        .header(RANGE, "bytes=0-0")
        .send();

    let (head_result, get_result) = tokio::join!(head_fut, get_fut);

    let mut head_response_opt = None;

    if let Ok(res) = head_result {
        let status = res.status();
        if status.is_success() {
            let accept_ranges_val = res
                .headers()
                .get(ACCEPT_RANGES)
                .and_then(|v| v.to_str().ok())
                .unwrap_or("");
            let supports_range = accept_ranges_val.to_lowercase().contains("bytes");

            let content_len = res
                .headers()
                .get(CONTENT_LENGTH)
                .and_then(|v| v.to_str().ok())
                .and_then(|s| s.parse::<u64>().ok());

            if supports_range && content_len.is_some() {
                let final_url = res.url().to_string();
                let is_redirect = final_url != url;
                let mime_type = res
                    .headers()
                    .get(CONTENT_TYPE)
                    .and_then(|v| v.to_str().ok())
                    .map(|s| s.split(';').next().unwrap_or(s).trim().to_string());

                let disp_filename = res
                    .headers()
                    .get(CONTENT_DISPOSITION)
                    .and_then(|v| v.to_str().ok())
                    .and_then(parse_content_disposition);

                let suggested_filename = Some(
                    disp_filename.unwrap_or_else(|| fallback_filename_from_url(&final_url)),
                );

                let etag = res
                    .headers()
                    .get(ETAG)
                    .and_then(|v| v.to_str().ok())
                    .map(|s| s.to_string());
                let last_modified = res
                    .headers()
                    .get(LAST_MODIFIED)
                    .and_then(|v| v.to_str().ok())
                    .map(|s| s.to_string());

                return Ok(ProbeResult {
                    content_length: content_len,
                    accept_ranges: true,
                    suggested_filename,
                    mime_type,
                    is_redirect,
                    final_url,
                    etag,
                    last_modified,
                });
            } else {
                // Fall back to GET Range 0-0 to verify range support or content length
                head_response_opt = Some((
                    res.url().to_string(),
                    res.headers().clone(),
                    content_len,
                ));
            }
        }
    }

    // Resolve from get_result (which already ran in parallel)
    let get_res = get_result.map_err(DownloaderError::from)?;

    let final_url = get_res.url().to_string();
    let is_redirect = final_url != url;
    let status = get_res.status();

    let (_head_url, head_headers, head_content_len) = head_response_opt.unwrap_or_else(|| {
        (final_url.clone(), HeaderMap::new(), None)
    });

    let mime_type = get_res
        .headers()
        .get(CONTENT_TYPE)
        .or_else(|| head_headers.get(CONTENT_TYPE))
        .and_then(|v| v.to_str().ok())
        .map(|s| s.split(';').next().unwrap_or(s).trim().to_string());

    let disp_filename = get_res
        .headers()
        .get(CONTENT_DISPOSITION)
        .or_else(|| head_headers.get(CONTENT_DISPOSITION))
        .and_then(|v| v.to_str().ok())
        .and_then(parse_content_disposition);

    let suggested_filename = Some(
        disp_filename.unwrap_or_else(|| fallback_filename_from_url(&final_url)),
    );

    let etag = get_res
        .headers()
        .get(ETAG)
        .or_else(|| head_headers.get(ETAG))
        .and_then(|v| v.to_str().ok())
        .map(|s| s.to_string());

    let last_modified = get_res
        .headers()
        .get(LAST_MODIFIED)
        .or_else(|| head_headers.get(LAST_MODIFIED))
        .and_then(|v| v.to_str().ok())
        .map(|s| s.to_string());

    if status == StatusCode::PARTIAL_CONTENT {
        // 206 Partial Content: Byte-range supported
        let total_bytes = get_res
            .headers()
            .get(CONTENT_RANGE)
            .and_then(|v| v.to_str().ok())
            .and_then(parse_content_range_total)
            .or(head_content_len);

        return Ok(ProbeResult {
            content_length: total_bytes,
            accept_ranges: true,
            suggested_filename,
            mime_type,
            is_redirect,
            final_url,
            etag,
            last_modified,
        });
    } else if status == StatusCode::OK {
        // 200 OK: Server does not honor Range request, single stream only
        let content_len = get_res
            .headers()
            .get(CONTENT_LENGTH)
            .and_then(|v| v.to_str().ok())
            .and_then(|s| s.parse::<u64>().ok())
            .or(head_content_len);

        return Ok(ProbeResult {
            content_length: content_len,
            accept_ranges: false,
            suggested_filename,
            mime_type,
            is_redirect,
            final_url,
            etag,
            last_modified,
        });
    } else if status == StatusCode::RANGE_NOT_SATISFIABLE {
        // 416: Could be an empty 0-byte file
        let total_bytes = get_res
            .headers()
            .get(CONTENT_RANGE)
            .and_then(|v| v.to_str().ok())
            .and_then(parse_content_range_total)
            .or(Some(0));

        return Ok(ProbeResult {
            content_length: total_bytes,
            accept_ranges: true,
            suggested_filename,
            mime_type,
            is_redirect,
            final_url,
            etag,
            last_modified,
        });
    } else if !status.is_success() {
        return Err(DownloaderError::HttpError {
            status: status.as_u16(),
            message: format!("Probe failed with HTTP status {}", status),
        });
    }

    Err(DownloaderError::Other("Unable to probe URL".to_string()))
}

/// Partitions a file of `total_bytes` into 4 to 16 chunks depending on size.
/// If `total_bytes <= 1MB` or `total_bytes == 0`, returns a single chunk.
pub fn calculate_chunks(total_bytes: u64, max_chunks: usize) -> Vec<Chunk> {
    if total_bytes == 0 {
        return vec![Chunk {
            index: 0,
            start_offset: 0,
            end_offset: 0,
            downloaded_bytes: 0,
            total_bytes: 0,
            completed: false,
        }];
    }
    if total_bytes <= MIN_CHUNK_SIZE {
        return vec![Chunk::new(0, 0, total_bytes - 1)];
    }

    let clamped_max = max_chunks.clamp(1, 16);
    let by_size = (total_bytes / MIN_CHUNK_SIZE) as usize;
    let chunk_count = if clamped_max >= 4 {
        by_size.clamp(4, clamped_max)
    } else {
        by_size.clamp(1, clamped_max)
    };

    let base_size = total_bytes / chunk_count as u64;
    let mut chunks = Vec::with_capacity(chunk_count);
    let mut start = 0u64;

    for i in 0..chunk_count {
        let end = if i == chunk_count - 1 {
            total_bytes - 1
        } else {
            start + base_size - 1
        };
        chunks.push(Chunk::new(i, start, end));
        start = end + 1;
    }

    chunks
}

/// Downloads a single chunk using byte-range requests and writes directly to `FileWriter`.
/// If the server unexpectedly returns HTTP 200 instead of HTTP 206 for a range starting > 0,
/// or when multi-chunk splitting was expected, returns `SingleStreamFallbackRequired`.
pub async fn download_chunk_worker(
    client: &Client,
    url: &str,
    chunk: &mut Chunk,
    writer: &FileWriter,
    headers: Option<&HashMap<String, String>>,
    mut cancel_rx: broadcast::Receiver<()>,
    progress_tx: &mpsc::Sender<u64>,
    is_multi_chunk: bool,
    limiter: Option<Arc<RateLimiter>>,
) -> Result<(), DownloaderError> {
    if chunk.completed {
        return Ok(());
    }
    if chunk.total_bytes > 0 && chunk.downloaded_bytes >= chunk.total_bytes {
        chunk.completed = true;
        return Ok(());
    }

    let range_start = chunk.start_offset + chunk.downloaded_bytes;
    let range_end = chunk.end_offset;

    let mut req = apply_custom_headers(client.get(url), headers);
    if range_end >= range_start {
        req = req.header(RANGE, format!("bytes={}-{}", range_start, range_end));
    } else {
        req = req.header(RANGE, format!("bytes={}-", range_start));
    }

    let res = tokio::select! {
        _ = cancel_rx.recv() => return Err(DownloaderError::Cancelled),
        result = req.send() => result.map_err(DownloaderError::from)?,
    };

    let status = res.status();

    if status == StatusCode::OK {
        // HTTP 200 returned instead of 206 Partial Content!
        // If this chunk starts at offset > 0, or is part of a multi-chunk split,
        // we must gracefully abort multi-chunk splitting and fallback to single stream.
        if chunk.start_offset > 0 || is_multi_chunk {
            return Err(DownloaderError::SingleStreamFallbackRequired);
        }
        // Single chunk starting at 0 that received 200: Stream directly
    } else if status != StatusCode::PARTIAL_CONTENT {
        return Err(DownloaderError::HttpError {
            status: status.as_u16(),
            message: format!("Chunk download failed with status {}", status),
        });
    }

    let mut stream = res.bytes_stream();
    let mut current_offset = range_start;

    loop {
        let item = tokio::select! {
            _ = cancel_rx.recv() => return Err(DownloaderError::Cancelled),
            next = stream.next() => next,
        };

        match item {
            Some(Ok(bytes)) => {
                let len = bytes.len() as u64;
                if len > 0 {
                    writer.write_at(&bytes, current_offset).await?;
                    current_offset += len;
                    chunk.downloaded_bytes += len;
                    let _ = progress_tx.send(len).await;
                    if let Some(ref lim) = limiter {
                        lim.throttle(len).await;
                    }
                }
            }
            Some(Err(e)) => return Err(DownloaderError::Network(e.to_string())),
            None => break,
        }
    }

    if chunk.total_bytes > 0 && chunk.downloaded_bytes >= chunk.total_bytes {
        chunk.completed = true;
    } else if chunk.total_bytes == 0 && chunk.downloaded_bytes > 0 {
        chunk.total_bytes = chunk.downloaded_bytes;
        chunk.completed = true;
    }

    Ok(())
}

/// Single-stream direct downloader. Streams the response body starting at offset 0
/// (or resume start_offset) directly into the `FileWriter`.
pub async fn download_single_stream(
    client: &Client,
    url: &str,
    writer: &FileWriter,
    headers: Option<&HashMap<String, String>>,
    start_offset: u64,
    mut cancel_rx: broadcast::Receiver<()>,
    progress_tx: &mpsc::Sender<u64>,
    limiter: Option<Arc<RateLimiter>>,
) -> Result<u64, DownloaderError> {
    let mut req = apply_custom_headers(client.get(url), headers);
    if start_offset > 0 {
        req = req.header(RANGE, format!("bytes={}-", start_offset));
    }

    let res = tokio::select! {
        _ = cancel_rx.recv() => return Err(DownloaderError::Cancelled),
        result = req.send() => result.map_err(DownloaderError::from)?,
    };

    let status = res.status();
    let mut write_offset = if status == StatusCode::PARTIAL_CONTENT {
        start_offset
    } else if status == StatusCode::OK {
        // If server responded with 200, start writing from offset 0
        0
    } else {
        return Err(DownloaderError::HttpError {
            status: status.as_u16(),
            message: format!("Single stream failed with HTTP status {}", status),
        });
    };

    let mut stream = res.bytes_stream();
    let mut total_downloaded = 0u64;

    loop {
        let item = tokio::select! {
            _ = cancel_rx.recv() => return Err(DownloaderError::Cancelled),
            next = stream.next() => next,
        };

        match item {
            Some(Ok(bytes)) => {
                let len = bytes.len() as u64;
                if len > 0 {
                    writer.write_at(&bytes, write_offset).await?;
                    write_offset += len;
                    total_downloaded += len;
                    let _ = progress_tx.send(len).await;
                    if let Some(ref lim) = limiter {
                        lim.throttle(len).await;
                    }
                }
            }
            Some(Err(e)) => return Err(DownloaderError::Network(e.to_string())),
            None => break,
        }
    }

    writer.sync().await?;
    Ok(total_downloaded)
}

/// Orchestrates multi-chunk download with automatic HTTP 200 Single-Stream Fallback.
/// If range requests fail or return 200, it cancels multi-chunk splitting and
/// streams the full body into `FileWriter` at offset 0.
pub async fn download_task_content(
    client: &Client,
    url: &str,
    chunks: &mut Vec<Chunk>,
    writer: &FileWriter,
    total_bytes: u64,
    resumable: &mut bool,
    headers: Option<&HashMap<String, String>>,
    cancel_tx: &broadcast::Sender<()>,
    progress_tx: &mpsc::Sender<u64>,
) -> Result<(), DownloaderError> {
    download_task_content_with_limiter(
        client,
        url,
        chunks,
        writer,
        total_bytes,
        resumable,
        headers,
        cancel_tx,
        progress_tx,
        None,
    )
    .await
}

/// Orchestrates multi-chunk download with optional rate limiter.
pub async fn download_task_content_with_limiter(
    client: &Client,
    url: &str,
    chunks: &mut Vec<Chunk>,
    writer: &FileWriter,
    total_bytes: u64,
    resumable: &mut bool,
    headers: Option<&HashMap<String, String>>,
    cancel_tx: &broadcast::Sender<()>,
    progress_tx: &mpsc::Sender<u64>,
    limiter: Option<Arc<RateLimiter>>,
) -> Result<(), DownloaderError> {
    let should_multi_chunk = *resumable && chunks.len() > 1;

    if should_multi_chunk {
        let is_multi = true;
        let mut tasks = Vec::with_capacity(chunks.len());
        let fallback_needed = Arc::new(AtomicBool::new(false));

        for chunk in chunks.iter_mut() {
            if chunk.completed {
                continue;
            }
            let mut chunk_clone = chunk.clone();
            let client_clone = client.clone();
            let url_clone = url.to_string();
            let writer_clone = writer.clone();
            let headers_clone = headers.cloned();
            let cancel_rx = cancel_tx.subscribe();
            let progress_tx_clone = progress_tx.clone();
            let fallback_flag = Arc::clone(&fallback_needed);
            let limiter_clone = limiter.clone();

            let handle = tokio::spawn(async move {
                let res = download_chunk_worker(
                    &client_clone,
                    &url_clone,
                    &mut chunk_clone,
                    &writer_clone,
                    headers_clone.as_ref(),
                    cancel_rx,
                    &progress_tx_clone,
                    is_multi,
                    limiter_clone,
                )
                .await;

                if let Err(DownloaderError::SingleStreamFallbackRequired) = &res {
                    fallback_flag.store(true, Ordering::SeqCst);
                }

                (chunk_clone, res)
            });

            tasks.push(handle);
        }

        let mut had_fallback = false;
        let mut had_cancel = false;
        let mut general_err = None;

        for handle in tasks {
            match handle.await {
                Ok((updated_chunk, res)) => {
                    // Update chunk in original slice
                    if let Some(orig) = chunks.get_mut(updated_chunk.index) {
                        *orig = updated_chunk;
                    }
                    match res {
                        Ok(()) => {}
                        Err(DownloaderError::SingleStreamFallbackRequired) => {
                            had_fallback = true;
                        }
                        Err(DownloaderError::Cancelled) => {
                            had_cancel = true;
                        }
                        Err(e) => {
                            if general_err.is_none() {
                                general_err = Some(e);
                            }
                        }
                    }
                }
                Err(join_err) => {
                    if general_err.is_none() {
                        general_err = Some(DownloaderError::Other(join_err.to_string()));
                    }
                }
            }
        }

        if had_fallback || fallback_needed.load(Ordering::SeqCst) {
            // CRITICAL FEATURE (HTTP 200 Single-Stream Fallback):
            // Gracefully abort multi-chunk splitting and stream the entire response body directly starting at offset 0
            *resumable = false;
            *chunks = vec![Chunk::new(
                0,
                0,
                if total_bytes > 0 {
                    total_bytes - 1
                } else {
                    0
                },
            )];
            // Reset pre-allocated file size
            let _ = writer.allocate(0).await;

            let downloaded = download_single_stream(
                client,
                url,
                writer,
                headers,
                0,
                cancel_tx.subscribe(),
                progress_tx,
                limiter.clone(),
            )
            .await?;

            chunks[0].downloaded_bytes = downloaded;
            chunks[0].total_bytes = downloaded;
            chunks[0].completed = true;
            return Ok(());
        }

        if had_cancel {
            return Err(DownloaderError::Cancelled);
        }

        if let Some(err) = general_err {
            return Err(err);
        }

        writer.sync().await?;
        return Ok(());
    }

    // Single chunk / stream download
    if chunks.is_empty() {
        chunks.push(Chunk::new(
            0,
            0,
            if total_bytes > 0 {
                total_bytes - 1
            } else {
                0
            },
        ));
    }

    let start_offset = chunks[0].downloaded_bytes;
    let downloaded = download_single_stream(
        client,
        url,
        writer,
        headers,
        start_offset,
        cancel_tx.subscribe(),
        progress_tx,
        limiter,
    )
    .await?;

    chunks[0].downloaded_bytes += downloaded;
    if chunks[0].total_bytes == 0 || chunks[0].downloaded_bytes >= chunks[0].total_bytes {
        chunks[0].completed = true;
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_calculate_chunks() {
        // Zero bytes
        let c0 = calculate_chunks(0, 8);
        assert_eq!(c0.len(), 1);
        assert_eq!(c0[0].start_offset, 0);
        assert_eq!(c0[0].end_offset, 0);
        assert_eq!(c0[0].total_bytes, 0);

        // 500 KB (<= 1MB)
        let c_small = calculate_chunks(500 * 1024, 8);
        assert_eq!(c_small.len(), 1);
        assert_eq!(c_small[0].total_bytes, 500 * 1024);

        // 10 MB with max 8 chunks -> should produce 8 chunks
        let total = 10 * 1024 * 1024;
        let c_multi = calculate_chunks(total, 8);
        assert_eq!(c_multi.len(), 8);

        // Verify contiguous byte range coverage
        assert_eq!(c_multi[0].start_offset, 0);
        assert_eq!(c_multi.last().unwrap().end_offset, total - 1);
        for i in 0..c_multi.len() - 1 {
            assert_eq!(c_multi[i].end_offset + 1, c_multi[i + 1].start_offset);
        }

        let sum_bytes: u64 = c_multi.iter().map(|c| c.total_bytes).sum();
        assert_eq!(sum_bytes, total);
    }

    #[test]
    fn test_parse_content_disposition() {
        // Standard quoted
        let h1 = r#"attachment; filename="archive.zip""#;
        assert_eq!(parse_content_disposition(h1), Some("archive.zip".into()));

        // Standard unquoted
        let h2 = "attachment; filename=document.pdf";
        assert_eq!(parse_content_disposition(h2), Some("document.pdf".into()));

        // RFC 5987 utf-8
        let h3 = "attachment; filename*=UTF-8''my%20presentation.pptx";
        assert_eq!(
            parse_content_disposition(h3),
            Some("my presentation.pptx".into())
        );

        // Both: RFC 5987 should take precedence
        let h4 = r#"attachment; filename="fallback.zip"; filename*=utf-8''real%20deal.zip"#;
        assert_eq!(parse_content_disposition(h4), Some("real deal.zip".into()));

        // Path traversal attempts
        let h5 = r#"attachment; filename="../../etc/passwd""#;
        assert_eq!(parse_content_disposition(h5), Some("passwd".into()));
    }

    #[test]
    fn test_fallback_filename_from_url() {
        assert_eq!(
            fallback_filename_from_url("https://example.com/files/archive.tar.gz?v=1"),
            "archive.tar.gz"
        );
        assert_eq!(
            fallback_filename_from_url("https://example.com/download/setup%20file.exe"),
            "setup file.exe"
        );
        assert_eq!(
            fallback_filename_from_url("https://example.com/api?file=payload.bin"),
            "payload.bin"
        );
        assert_eq!(fallback_filename_from_url("https://example.com/"), "download");
    }

    #[test]
    fn test_parse_content_range_total() {
        assert_eq!(
            parse_content_range_total("bytes 0-1023/10485760"),
            Some(10485760)
        );
        assert_eq!(parse_content_range_total("bytes 0-0/500"), Some(500));
        assert_eq!(parse_content_range_total("bytes 0-0/*"), None);
        assert_eq!(parse_content_range_total("invalid"), None);
    }

    #[tokio::test]
    async fn test_http_200_single_stream_fallback() {
        use axum::http::header::RANGE;
        use axum::http::{HeaderMap, StatusCode};
        use axum::response::IntoResponse;
        use axum::routing::get;
        use axum::Router;

        // A mock server that ignores Range headers and always returns 200 OK with full content
        let test_payload = b"Hello HTTP 200 Single Stream Fallback World! 1234567890".repeat(100);
        let payload_clone = test_payload.clone();

        let app = Router::new().route(
            "/fallback_test",
            get(move |headers: HeaderMap| {
                let p = payload_clone.clone();
                async move {
                    // Even if client sent Range, server ignores it and sends 200 OK!
                    let _ = headers.get(RANGE);
                    (StatusCode::OK, p).into_response()
                }
            }),
        );

        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        tokio::spawn(async move {
            axum::serve(listener, app).await.unwrap();
        });

        let temp_dir = tempfile::tempdir().unwrap();
        let dest_file = temp_dir.path().join("downloaded.bin");
        let writer = FileWriter::new(&dest_file).unwrap();

        let client = Client::new();
        let url = format!("http://{}/fallback_test", addr);

        // Intentionally configure 4 chunks as if range was supported
        let mut chunks = vec![
            Chunk::new(0, 0, 1000),
            Chunk::new(1, 1001, 2000),
            Chunk::new(2, 2001, 3000),
            Chunk::new(3, 3001, test_payload.len() as u64 - 1),
        ];

        let (cancel_tx, _cancel_rx) = broadcast::channel(4);
        let (progress_tx, mut progress_rx) = mpsc::channel(100);
        tokio::spawn(async move {
            while let Some(_) = progress_rx.recv().await {}
        });

        let mut resumable = true;
        let res = download_task_content(
            &client,
            &url,
            &mut chunks,
            &writer,
            test_payload.len() as u64,
            &mut resumable,
            None,
            &cancel_tx,
            &progress_tx,
        )
        .await;

        assert!(res.is_ok(), "download_task_content failed: {:?}", res);
        assert!(!resumable, "resumable should be set to false after 200 fallback");
        assert_eq!(chunks.len(), 1, "chunks should be reset to 1 after fallback");

        let saved = std::fs::read(&dest_file).unwrap();
        assert_eq!(saved.len(), test_payload.len());
        assert_eq!(saved, test_payload);
    }

    #[tokio::test]
    async fn test_multi_chunk_concurrent_download() {
        use axum::http::header::{CONTENT_LENGTH, CONTENT_RANGE, RANGE};
        use axum::http::{HeaderMap, StatusCode};
        use axum::response::IntoResponse;
        use axum::routing::get;
        use axum::Router;

        let test_payload: Vec<u8> = (0..50_000).map(|i| (i % 256) as u8).collect();
        let payload_len = test_payload.len();
        let payload_clone = test_payload.clone();

        let app = Router::new().route(
            "/range_test",
            get(move |headers: HeaderMap| {
                let p = payload_clone.clone();
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
                            let slice = p[start..=end].to_vec();
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
                    (StatusCode::OK, p).into_response()
                }
            }),
        );

        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        tokio::spawn(async move {
            axum::serve(listener, app).await.unwrap();
        });

        let temp_dir = tempfile::tempdir().unwrap();
        let dest_file = temp_dir.path().join("multichunk.bin");
        let writer = FileWriter::new(&dest_file).unwrap();
        writer.allocate(payload_len as u64).await.unwrap();

        let client = Client::new();
        let url = format!("http://{}/range_test", addr);

        let mut chunks = vec![
            Chunk::new(0, 0, 12_499),
            Chunk::new(1, 12_500, 24_999),
            Chunk::new(2, 25_000, 37_499),
            Chunk::new(3, 37_500, payload_len as u64 - 1),
        ];

        let (cancel_tx, _cancel_rx) = broadcast::channel(4);
        let (progress_tx, mut progress_rx) = mpsc::channel(100);
        tokio::spawn(async move {
            while let Some(_) = progress_rx.recv().await {}
        });

        let mut resumable = true;
        let res = download_task_content(
            &client,
            &url,
            &mut chunks,
            &writer,
            payload_len as u64,
            &mut resumable,
            None,
            &cancel_tx,
            &progress_tx,
        )
        .await;

        assert!(res.is_ok(), "multichunk download failed: {:?}", res);
        assert!(resumable);
        assert_eq!(chunks.len(), 4);
        for chunk in &chunks {
            assert!(chunk.completed);
            assert_eq!(chunk.downloaded_bytes, chunk.total_bytes);
        }

        let saved = std::fs::read(&dest_file).unwrap();
        assert_eq!(saved.len(), payload_len);
        assert_eq!(saved, test_payload);
    }

    #[tokio::test]
    async fn test_probe_url_head_405_fallback() {
        use axum::http::header::{CONTENT_DISPOSITION, CONTENT_RANGE};
        use axum::http::StatusCode;
        use axum::response::IntoResponse;
        use axum::routing::get;
        use axum::Router;

        // Server only allows GET, rejects HEAD with 405 Method Not Allowed
        let app = Router::new().route(
            "/probe_test",
            get(|| async {
                (
                    StatusCode::PARTIAL_CONTENT,
                    [
                        (CONTENT_RANGE, "bytes 0-0/10485760"),
                        (CONTENT_DISPOSITION, r#"attachment; filename="data_packet.zip""#),
                    ],
                    "x",
                )
                    .into_response()
            }),
        );

        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        tokio::spawn(async move {
            axum::serve(listener, app).await.unwrap();
        });

        let client = Client::new();
        let url = format!("http://{}/probe_test", addr);

        let probe = probe_url(&client, &url, None).await.unwrap();
        assert_eq!(probe.content_length, Some(10485760));
        assert!(probe.accept_ranges);
        assert_eq!(probe.suggested_filename.as_deref(), Some("data_packet.zip"));
    }

    #[tokio::test]
    async fn test_probe_url_etag_and_last_modified() {
        use axum::http::header::{ACCEPT_RANGES, CONTENT_LENGTH, ETAG, LAST_MODIFIED};
        use axum::http::StatusCode;
        use axum::response::IntoResponse;
        use axum::routing::head;
        use axum::Router;

        let app = Router::new().route(
            "/etag_probe",
            head(|| async {
                (
                    StatusCode::OK,
                    [
                        (ACCEPT_RANGES, "bytes"),
                        (CONTENT_LENGTH, "2048"),
                        (ETAG, "\"test-etag-12345\""),
                        (LAST_MODIFIED, "Fri, 14 Nov 2026 12:00:00 GMT"),
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

        let client = Client::new();
        let url = format!("http://{}/etag_probe", addr);

        let probe = probe_url(&client, &url, None).await.unwrap();
        assert_eq!(probe.content_length, Some(2048));
        assert!(probe.accept_ranges);
        assert_eq!(probe.etag.as_deref(), Some("\"test-etag-12345\""));
        assert_eq!(
            probe.last_modified.as_deref(),
            Some("Fri, 14 Nov 2026 12:00:00 GMT")
        );
    }

    #[tokio::test]
    async fn test_rate_limiter_throttling() {
        let limiter = RateLimiter::new(100_000); // 100 KB/s
        assert_eq!(limiter.get_limit(), 100_000);

        limiter.set_limit(50_000);
        assert_eq!(limiter.get_limit(), 50_000);

        // When limit is 0 (unlimited), throttle returns immediately
        limiter.set_limit(0);
        let start = std::time::Instant::now();
        limiter.throttle(1_000_000).await;
        assert!(start.elapsed().as_millis() < 50);
    }

    #[test]
    fn test_chunk_downloader_client_builder() {
        let client = ChunkDownloader::build_client();
        // Client builds successfully with connect_timeout and timeout configured
        drop(client);
    }
}
