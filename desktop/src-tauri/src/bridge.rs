use crate::downloader::sanitize_filename;
use crate::engine::DownloadEngine;
use axum::{
    body::Bytes,
    extract::{DefaultBodyLimit, Query, Request, State},
    http::{
        header::{self, HeaderMap, HeaderName, HeaderValue},
        Method, StatusCode,
    },
    middleware::{self, Next},
    response::{IntoResponse, Response},
    routing::get,
    Json, Router,
};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::atomic::{AtomicU16, Ordering};
use std::sync::{Arc, RwLock};

pub const DEFAULT_PREFERRED_PORT: u16 = 31415;
pub const DEFAULT_FALLBACK_PORT: u16 = 31416;
pub const BRIDGE_VERSION: &str = env!("CARGO_PKG_VERSION");
pub const APP_NAME: &str = "HyperFetch";

/// Deserializes optional boolean values from either standard JSON booleans or string equivalents.
fn deserialize_optional_bool<'de, D>(deserializer: D) -> Result<Option<bool>, D::Error>
where
    D: serde::Deserializer<'de>,
{
    #[derive(Deserialize)]
    #[serde(untagged)]
    enum BoolOrString {
        Bool(bool),
        Str(String),
    }

    match Option::<BoolOrString>::deserialize(deserializer)? {
        Some(BoolOrString::Bool(b)) => Ok(Some(b)),
        Some(BoolOrString::Str(s)) => {
            let lower = s.trim().to_lowercase();
            Ok(Some(lower != "false" && lower != "0"))
        }
        None => Ok(None),
    }
}

/// Structured download request payload for POST /add or POST /download.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DownloadPayload {
    pub url: String,
    #[serde(default)]
    pub filename: Option<String>,
    #[serde(
        default,
        alias = "autoStart",
        alias = "auto_start",
        deserialize_with = "deserialize_optional_bool"
    )]
    pub auto_start: Option<bool>,
    #[serde(default)]
    pub headers: Option<HashMap<String, String>>,
    #[serde(default, alias = "preferredChunkCount", alias = "preferred_chunk_count")]
    pub preferred_chunk_count: Option<usize>,
    #[serde(default, alias = "expectedChecksum", alias = "expected_checksum", alias = "checksum", alias = "sha256")]
    pub expected_checksum: Option<String>,
}

/// Query parameters for GET /add or GET /download.
#[derive(Debug, Default, Deserialize)]
pub struct AddQueryParams {
    pub url: Option<String>,
    pub filename: Option<String>,
    #[serde(
        default,
        alias = "autoStart",
        alias = "auto_start",
        deserialize_with = "deserialize_optional_bool"
    )]
    pub auto_start: Option<bool>,
    pub headers: Option<String>,
    pub token: Option<String>,
    #[serde(default, alias = "preferredChunkCount", alias = "preferred_chunk_count")]
    pub preferred_chunk_count: Option<usize>,
    #[serde(default, alias = "expectedChecksum", alias = "expected_checksum", alias = "checksum", alias = "sha256")]
    pub expected_checksum: Option<String>,
}

/// Payload/Query for /sheet endpoint.
#[derive(Debug, Default, Deserialize)]
pub struct SheetPayload {
    pub url: Option<String>,
    pub filename: Option<String>,
}

/// Payload/Query for /theme endpoint.
#[derive(Debug, Default, Deserialize)]
pub struct ThemePayload {
    pub mode: Option<String>,
}

/// Configuration options for the LocalhostBridge.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BridgeConfig {
    pub preferred_port: u16,
    pub fallback_port: u16,
    pub bridge_token: Option<String>,
}

impl Default for BridgeConfig {
    fn default() -> Self {
        Self {
            preferred_port: DEFAULT_PREFERRED_PORT,
            fallback_port: DEFAULT_FALLBACK_PORT,
            bridge_token: None,
        }
    }
}

pub type SheetCallback = Arc<dyn Fn(Option<String>, Option<String>) + Send + Sync + 'static>;
pub type ThemeCallback = Arc<dyn Fn(String) + Send + Sync + 'static>;

/// Shared state accessible by Axum route handlers and middleware.
#[derive(Clone)]
pub struct BridgeState {
    pub engine: Arc<DownloadEngine>,
    pub config: BridgeConfig,
    pub bound_port: Arc<AtomicU16>,
    pub on_sheet_requested: Option<SheetCallback>,
    pub on_theme_requested: Option<ThemeCallback>,
}

impl BridgeState {
    pub fn current_port(&self) -> u16 {
        let p = self.bound_port.load(Ordering::SeqCst);
        if p > 0 {
            p
        } else {
            self.config.preferred_port
        }
    }
}

/// Errors originating from the localhost bridge.
#[derive(Debug, thiserror::Error)]
pub enum BridgeError {
    #[error("Port binding failed for ports: {0:?}")]
    PortBindingFailed(Vec<u16>),

    #[error("Bridge is already running on port {0}")]
    AlreadyRunning(u16),

    #[error("I/O error: {0}")]
    Io(#[from] std::io::Error),

    #[error("Engine error: {0}")]
    Engine(#[from] crate::engine::EngineError),

    #[error("Other error: {0}")]
    Other(String),
}

// ============================================================================
// Security Helpers & VAPT Hardening
// ============================================================================

/// Validates whether the incoming Host header represents a safe loopback address.
/// Prevents DNS rebinding attacks where external hostnames resolve to 127.0.0.1.
pub fn is_authorized_host(raw_host: &str) -> bool {
    let host = raw_host.trim().to_lowercase();
    if host.is_empty() {
        return false;
    }
    if host == "127.0.0.1" || host == "localhost" {
        return true;
    }
    if let Some((hostname, port_str)) = host.split_once(':') {
        if (hostname == "127.0.0.1" || hostname == "localhost") && port_str.parse::<u16>().is_ok() {
            return true;
        }
    }
    false
}

/// Checks whether the raw origin represents a recognized browser extension scheme.
pub fn is_extension_origin(raw_origin: &str) -> bool {
    let lower = raw_origin.trim().to_lowercase();
    lower.starts_with("chrome-extension://")
        || lower.starts_with("moz-extension://")
        || lower.starts_with("safari-web-extension://")
}

/// Validates whether an incoming Origin header belongs to an authorized browser extension or local origin.
/// Blocks cross-origin access from external web domains (e.g. https://evil.com).
pub fn is_authorized_origin(raw_origin: &str) -> bool {
    let lower = raw_origin.trim().to_lowercase();
    if lower.is_empty() || lower == "null" {
        return false;
    }
    if is_extension_origin(&lower) {
        return true;
    }
    for prefix in [
        "http://127.0.0.1",
        "http://localhost",
        "https://127.0.0.1",
        "https://localhost",
    ] {
        if lower == prefix
            || lower.starts_with(&format!("{}:", prefix))
            || lower.starts_with(&format!("{}/", prefix))
        {
            return true;
        }
    }
    false
}

/// Validates whether a download URL string is well-formed with an allowed http/https scheme.
pub fn is_valid_download_url(url_str: &str) -> bool {
    let trimmed = url_str.trim();
    if trimmed.is_empty() {
        return false;
    }
    if let Ok(parsed) = reqwest::Url::parse(trimmed) {
        let scheme = parsed.scheme().to_lowercase();
        return scheme == "http" || scheme == "https";
    }
    false
}

/// Sanitizes a requested filename against path traversal (../, slashes, null bytes).
/// Returns None if the input collapses to empty or pure traversal sequence.
pub fn sanitize_requested_filename(raw: &str) -> Option<String> {
    let sanitized = sanitize_filename(raw);
    if sanitized.is_empty() || sanitized == "download" || sanitized == "." || sanitized == ".." {
        None
    } else {
        Some(sanitized)
    }
}

/// Validates client identification and shared secret token authentication (CWE-346).
fn is_authorized_client(
    config: &BridgeConfig,
    headers: &HeaderMap,
    method: &Method,
    origin: Option<&str>,
    uri: &axum::http::Uri,
) -> bool {
    // 1. Shared secret token enforcement if configured
    if let Some(required_token) = &config.bridge_token {
        if !required_token.is_empty() {
            if let Some(token_header) = headers.get("x-hyperfetch-token").and_then(|v| v.to_str().ok()) {
                if token_header == required_token {
                    return true;
                }
            }
            if let Some(auth_header) = headers.get(header::AUTHORIZATION).and_then(|v| v.to_str().ok()) {
                let trimmed = auth_header.strip_prefix("Bearer ").unwrap_or(auth_header).trim();
                if trimmed == required_token {
                    return true;
                }
            }
            if let Some(query) = uri.query() {
                for pair in query.split('&') {
                    if let Some((k, v)) = pair.split_once('=') {
                        if k == "token" && v == required_token {
                            return true;
                        }
                    }
                }
            }
            return false;
        }
    }

    // 2. Client identification check
    let has_client_header = headers
        .get("x-hyperfetch-client")
        .and_then(|v| v.to_str().ok())
        .map(|v| v.eq_ignore_ascii_case("extension"))
        .unwrap_or(false);

    let has_auth = headers.contains_key(header::AUTHORIZATION)
        || headers.contains_key("x-hyperfetch-token");

    if has_client_header || has_auth {
        return true;
    }

    // 3. Requests with Origin: chrome-extension://... MUST provide client identification
    if let Some(origin_str) = origin {
        if is_extension_origin(origin_str) {
            return false;
        }
    }

    // 4. State-modifying POST requests MUST provide client identification
    if method == Method::POST {
        return false;
    }

    // Non-POST requests without extension origin (e.g. GET /status from local CLI or browser probe)
    true
}

/// Applies required VAPT security headers and conditional CORS headers to every response.
pub fn apply_security_headers(headers: &mut HeaderMap, allowed_origin: Option<&str>) {
    headers.insert(
        HeaderName::from_static("content-security-policy"),
        HeaderValue::from_static("default-src 'none'"),
    );
    headers.insert(
        HeaderName::from_static("x-frame-options"),
        HeaderValue::from_static("DENY"),
    );
    headers.insert(
        HeaderName::from_static("x-content-type-options"),
        HeaderValue::from_static("nosniff"),
    );
    headers.insert(
        HeaderName::from_static("referrer-policy"),
        HeaderValue::from_static("no-referrer"),
    );
    headers.insert(
        HeaderName::from_static("cache-control"),
        HeaderValue::from_static("no-store, no-cache, must-revalidate"),
    );

    if let Some(origin) = allowed_origin {
        if let Ok(val) = HeaderValue::from_str(origin) {
            headers.insert(header::ACCESS_CONTROL_ALLOW_ORIGIN, val);
            headers.insert(header::VARY, HeaderValue::from_static("Origin"));
            headers.insert(
                header::ACCESS_CONTROL_ALLOW_METHODS,
                HeaderValue::from_static("GET, POST, OPTIONS"),
            );
            headers.insert(
                header::ACCESS_CONTROL_ALLOW_HEADERS,
                HeaderValue::from_static(
                    "Content-Type, Authorization, X-Requested-With, X-HyperFetch-Client, X-HyperFetch-Token",
                ),
            );
        }
    }
}

fn json_response<T: Serialize>(status: StatusCode, data: T) -> Response {
    let mut resp = (status, Json(data)).into_response();
    resp.headers_mut().insert(
        header::CONTENT_TYPE,
        HeaderValue::from_static("application/json; charset=utf-8"),
    );
    resp
}

fn error_response(status: StatusCode, message: &str) -> Response {
    json_response(
        status,
        serde_json::json!({
            "status": "error",
            "message": message,
        }),
    )
}

// ============================================================================
// Axum Middleware
// ============================================================================

/// VAPT Security & Origin verification middleware.
async fn vapt_security_middleware(
    State(state): State<BridgeState>,
    req: Request,
    next: Next,
) -> Response {
    // 1. Host Header Validation (DNS Rebinding Defense)
    let host_valid = match req.headers().get(header::HOST).and_then(|v| v.to_str().ok()) {
        Some(host_str) => is_authorized_host(host_str),
        None => false,
    };

    if !host_valid {
        let mut resp = error_response(
            StatusCode::FORBIDDEN,
            "Invalid or unauthorized Host header",
        );
        apply_security_headers(resp.headers_mut(), None);
        return resp;
    }

    // 2. Origin & Referer Validation (Safe CORS & CSRF Defense)
    let raw_origin = req
        .headers()
        .get(header::ORIGIN)
        .and_then(|v| v.to_str().ok())
        .map(|s| s.to_string());

    let raw_referer = req
        .headers()
        .get(header::REFERER)
        .and_then(|v| v.to_str().ok())
        .map(|s| s.to_string());

    let allowed_origin = if let Some(origin) = &raw_origin {
        if !is_authorized_origin(origin) {
            let mut resp = error_response(
                StatusCode::FORBIDDEN,
                "Cross-origin access from external web origin prohibited",
            );
            apply_security_headers(resp.headers_mut(), None);
            return resp;
        }
        Some(origin.clone())
    } else if let Some(referer) = &raw_referer {
        if !is_authorized_origin(referer) {
            let mut resp = error_response(
                StatusCode::FORBIDDEN,
                "Cross-origin access from external web origin prohibited",
            );
            apply_security_headers(resp.headers_mut(), None);
            return resp;
        }
        None
    } else {
        None
    };

    if let Some(sec_fetch) = req.headers().get("sec-fetch-site").and_then(|v| v.to_str().ok()) {
        if sec_fetch.eq_ignore_ascii_case("cross-site") && allowed_origin.is_none() {
            let mut resp = error_response(
                StatusCode::FORBIDDEN,
                "Cross-origin access from external web origin prohibited",
            );
            apply_security_headers(resp.headers_mut(), None);
            return resp;
        }
    }

    // 3. Handle CORS Preflight OPTIONS
    if req.method() == Method::OPTIONS {
        if let Some(origin) = &allowed_origin {
            let mut resp = StatusCode::NO_CONTENT.into_response();
            apply_security_headers(resp.headers_mut(), Some(origin));
            resp.headers_mut().insert(
                header::ACCESS_CONTROL_MAX_AGE,
                HeaderValue::from_static("86400"),
            );
            return resp;
        } else {
            let mut resp = error_response(
                StatusCode::FORBIDDEN,
                "Cross-origin access from external web origin prohibited",
            );
            apply_security_headers(resp.headers_mut(), None);
            return resp;
        }
    }

    // 4. Client Identification & Shared Secret Authentication (CWE-346)
    if !is_authorized_client(&state.config, req.headers(), req.method(), allowed_origin.as_deref(), req.uri()) {
        let mut resp = error_response(
            StatusCode::FORBIDDEN,
            "Client authentication required: missing or invalid client token or header",
        );
        apply_security_headers(resp.headers_mut(), allowed_origin.as_deref());
        return resp;
    }

    // 5. Execute downstream handlers and inject security/CORS headers
    let mut resp = next.run(req).await;
    apply_security_headers(resp.headers_mut(), allowed_origin.as_deref());
    resp
}

// ============================================================================
// Endpoint Route Handlers
// ============================================================================

/// GET /status, GET /, GET /health
async fn status_handler(State(state): State<BridgeState>) -> Response {
    let port = state.current_port();
    json_response(
        StatusCode::OK,
        serde_json::json!({
            "status": "ok",
            "app": APP_NAME,
            "version": BRIDGE_VERSION,
            "port": port,
        }),
    )
}

/// POST /add, POST /download
async fn post_add_handler(
    State(state): State<BridgeState>,
    payload_res: Result<Json<DownloadPayload>, axum::extract::rejection::JsonRejection>,
) -> Response {
    let Json(payload) = match payload_res {
        Ok(p) => p,
        Err(_) => {
            return error_response(
                StatusCode::BAD_REQUEST,
                "Missing or invalid 'url' parameter (must be http/https)",
            );
        }
    };

    if !is_valid_download_url(&payload.url) {
        return error_response(
            StatusCode::BAD_REQUEST,
            "Missing or invalid 'url' parameter (must be http/https)",
        );
    }

    let sanitized_filename = payload.filename.as_deref().and_then(sanitize_requested_filename);
    let auto_start = payload.auto_start.unwrap_or(true);

    match state
        .engine
        .add_download(
            payload.url.clone(),
            sanitized_filename,
            None,
            auto_start,
            payload.headers,
            payload.preferred_chunk_count,
            payload.expected_checksum,
        )
        .await
    {
        Ok(task) => json_response(
            StatusCode::OK,
            serde_json::json!({
                "status": "ok",
                "message": "Download added to HyperFetch",
                "url": task.url,
                "filename": task.filename,
                "id": task.id,
            }),
        ),
        Err(e) => error_response(
            StatusCode::INTERNAL_SERVER_ERROR,
            &format!("Failed to add download: {e}"),
        ),
    }
}

/// GET /add, GET /download
async fn get_add_handler(
    State(state): State<BridgeState>,
    Query(params): Query<AddQueryParams>,
) -> Response {
    let url_str = match &params.url {
        Some(u) if is_valid_download_url(u) => u.clone(),
        _ => {
            return error_response(
                StatusCode::BAD_REQUEST,
                "Missing or invalid 'url' query parameter",
            );
        }
    };

    let sanitized_filename = params.filename.as_deref().and_then(sanitize_requested_filename);
    let auto_start = params.auto_start.unwrap_or(true);

    let parsed_headers = params
        .headers
        .as_deref()
        .and_then(|h| serde_json::from_str::<HashMap<String, String>>(h).ok());

    match state
        .engine
        .add_download(
            url_str,
            sanitized_filename,
            None,
            auto_start,
            parsed_headers,
            params.preferred_chunk_count,
            params.expected_checksum,
        )
        .await
    {
        Ok(task) => json_response(
            StatusCode::OK,
            serde_json::json!({
                "status": "ok",
                "message": "Download added to HyperFetch",
                "url": task.url,
                "filename": task.filename,
                "id": task.id,
            }),
        ),
        Err(e) => error_response(
            StatusCode::INTERNAL_SERVER_ERROR,
            &format!("Failed to add download: {e}"),
        ),
    }
}

/// GET /sheet
async fn get_sheet_handler(
    State(state): State<BridgeState>,
    Query(params): Query<SheetPayload>,
) -> Response {
    if let Some(cb) = &state.on_sheet_requested {
        cb(params.url, params.filename);
    }
    json_response(
        StatusCode::OK,
        serde_json::json!({
            "status": "ok",
            "message": "Sheet requested",
        }),
    )
}

/// POST /sheet
async fn post_sheet_handler(
    State(state): State<BridgeState>,
    Query(query): Query<SheetPayload>,
    bytes: Bytes,
) -> Response {
    let body_payload: Option<SheetPayload> = if !bytes.is_empty() {
        serde_json::from_slice(&bytes).ok()
    } else {
        None
    };
    let (url, filename) = match body_payload {
        Some(b) => (b.url.or(query.url), b.filename.or(query.filename)),
        None => (query.url, query.filename),
    };

    if let Some(cb) = &state.on_sheet_requested {
        cb(url, filename);
    }
    json_response(
        StatusCode::OK,
        serde_json::json!({
            "status": "ok",
            "message": "Sheet requested",
        }),
    )
}

/// GET /theme
async fn get_theme_handler(
    State(state): State<BridgeState>,
    Query(query): Query<ThemePayload>,
) -> Response {
    let mode = query
        .mode
        .filter(|m| !m.trim().is_empty())
        .unwrap_or_else(|| "dark".to_string());

    if let Some(cb) = &state.on_theme_requested {
        cb(mode.clone());
    }
    json_response(
        StatusCode::OK,
        serde_json::json!({
            "status": "ok",
            "theme": mode,
        }),
    )
}

/// POST /theme
async fn post_theme_handler(
    State(state): State<BridgeState>,
    Query(query): Query<ThemePayload>,
    bytes: Bytes,
) -> Response {
    let body_payload: Option<ThemePayload> = if !bytes.is_empty() {
        serde_json::from_slice(&bytes).ok()
    } else {
        None
    };
    let mode = body_payload
        .and_then(|b| b.mode)
        .or(query.mode)
        .filter(|m| !m.trim().is_empty())
        .unwrap_or_else(|| "dark".to_string());

    if let Some(cb) = &state.on_theme_requested {
        cb(mode.clone());
    }
    json_response(
        StatusCode::OK,
        serde_json::json!({
            "status": "ok",
            "theme": mode,
        }),
    )
}

/// GET /transfers and GET /queue handler
async fn get_transfers_handler(State(state): State<BridgeState>) -> Response {
    let tasks = state.engine.get_tasks().await;
    json_response(
        StatusCode::OK,
        serde_json::json!({
            "status": "ok",
            "transfers": tasks,
        }),
    )
}

/// 404 Fallback
async fn not_found_handler(req: Request) -> Response {
    error_response(
        StatusCode::NOT_FOUND,
        &format!("Route not found: {}", req.uri().path()),
    )
}

/// Constructs the full Axum router configured with VAPT middleware and endpoints.
pub fn create_router(state: BridgeState) -> Router {
    Router::new()
        .route("/", get(status_handler))
        .route("/status", get(status_handler))
        .route("/health", get(status_handler))
        .route("/add", get(get_add_handler).post(post_add_handler))
        .route("/download", get(get_add_handler).post(post_add_handler))
        .route("/sheet", get(get_sheet_handler).post(post_sheet_handler))
        .route("/theme", get(get_theme_handler).post(post_theme_handler))
        .route("/transfers", get(get_transfers_handler))
        .route("/queue", get(get_transfers_handler))
        .fallback(not_found_handler)
        .layer(middleware::from_fn_with_state(
            state.clone(),
            vapt_security_middleware,
        ))
        .layer(DefaultBodyLimit::max(1024 * 1024))
        .with_state(state)
}

// ============================================================================
// LocalhostBridge Server Implementation
// ============================================================================

/// Embedded HTTP bridge listening on loopback (127.0.0.1) with dynamic port binding.
pub struct LocalhostBridge {
    pub engine: Arc<DownloadEngine>,
    pub config: BridgeConfig,
    bound_port: Arc<AtomicU16>,
    shutdown_tx: tokio::sync::broadcast::Sender<()>,
    on_sheet_requested: Arc<RwLock<Option<SheetCallback>>>,
    on_theme_requested: Arc<RwLock<Option<ThemeCallback>>>,
}

impl LocalhostBridge {
    /// Creates a new LocalhostBridge instance with the given engine and configuration.
    pub fn new(engine: Arc<DownloadEngine>, config: BridgeConfig) -> Self {
        let (shutdown_tx, _) = tokio::sync::broadcast::channel(16);
        Self {
            engine,
            config,
            bound_port: Arc::new(AtomicU16::new(0)),
            shutdown_tx,
            on_sheet_requested: Arc::new(RwLock::new(None)),
            on_theme_requested: Arc::new(RwLock::new(None)),
        }
    }

    /// Sets the UI sheet presentation request callback.
    pub fn set_on_sheet_requested<F>(&self, cb: F)
    where
        F: Fn(Option<String>, Option<String>) + Send + Sync + 'static,
    {
        if let Ok(mut lock) = self.on_sheet_requested.write() {
            *lock = Some(Arc::new(cb));
        }
    }

    /// Sets the appearance/theme change request callback.
    pub fn set_on_theme_requested<F>(&self, cb: F)
    where
        F: Fn(String) + Send + Sync + 'static,
    {
        if let Ok(mut lock) = self.on_theme_requested.write() {
            *lock = Some(Arc::new(cb));
        }
    }

    /// Whether the bridge server is currently running and bound to a port.
    pub fn is_running(&self) -> bool {
        self.bound_port.load(Ordering::SeqCst) > 0
    }

    /// Returns the currently active listening port, or None if stopped.
    pub fn listening_port(&self) -> Option<u16> {
        let port = self.bound_port.load(Ordering::SeqCst);
        if port > 0 {
            Some(port)
        } else {
            None
        }
    }

    /// Stops the server and cancels all active connections gracefully.
    pub fn stop(&self) {
        let _ = self.shutdown_tx.send(());
        self.bound_port.store(0, Ordering::SeqCst);
    }

    /// Starts the localhost bridge, attempting the preferred port first and falling back if occupied.
    /// Returns the bound port and the background task join handle.
    pub async fn start(&self) -> Result<(u16, tokio::task::JoinHandle<()>), BridgeError> {
        let current = self.bound_port.load(Ordering::SeqCst);
        if current > 0 {
            return Err(BridgeError::AlreadyRunning(current));
        }

        let ports_to_try = [self.config.preferred_port, self.config.fallback_port];
        let mut bound_listener = None;

        for &port in &ports_to_try {
            let addr = format!("127.0.0.1:{}", port);
            match tokio::net::TcpListener::bind(&addr).await {
                Ok(listener) => {
                    bound_listener = Some(listener);
                    break;
                }
                Err(_) => {
                    continue;
                }
            }
        }

        let listener = bound_listener.ok_or_else(|| {
            BridgeError::PortBindingFailed(vec![
                self.config.preferred_port,
                self.config.fallback_port,
            ])
        })?;

        let actual_port = listener.local_addr()?.port();
        self.bound_port.store(actual_port, Ordering::SeqCst);

        let sheet_cb = self
            .on_sheet_requested
            .read()
            .ok()
            .and_then(|l| l.clone());
        let theme_cb = self
            .on_theme_requested
            .read()
            .ok()
            .and_then(|l| l.clone());

        let state = BridgeState {
            engine: self.engine.clone(),
            config: self.config.clone(),
            bound_port: self.bound_port.clone(),
            on_sheet_requested: sheet_cb,
            on_theme_requested: theme_cb,
        };

        let app = create_router(state);
        let mut shutdown_rx = self.shutdown_tx.subscribe();

        let handle = tokio::spawn(async move {
            let serve = axum::serve(listener, app);
            let _ = serve
                .with_graceful_shutdown(async move {
                    let _ = shutdown_rx.recv().await;
                })
                .await;
        });

        Ok((actual_port, handle))
    }
}

// ============================================================================
// Unit and Integration Tests
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::AtomicBool;

    fn create_test_engine() -> (Arc<DownloadEngine>, tempfile::TempDir) {
        let temp_dir = tempfile::tempdir().expect("Failed to create tempdir");
        let state_path = temp_dir.path().join("tasks.json");
        let engine = Arc::new(DownloadEngine::with_state_path(state_path));
        (engine, temp_dir)
    }

    #[tokio::test]
    async fn test_get_status_returns_200_with_security_headers_and_correct_json() {
        let (engine, _td) = create_test_engine();
        let config = BridgeConfig {
            preferred_port: 0, // bind ephemeral port
            fallback_port: 0,
            bridge_token: None,
        };
        let bridge = LocalhostBridge::new(engine, config);
        let (port, handle) = bridge.start().await.expect("Bridge failed to start");
        assert!(port > 0);
        assert!(bridge.is_running());
        assert_eq!(bridge.listening_port(), Some(port));

        let client = reqwest::Client::new();
        let resp = client
            .get(format!("http://127.0.0.1:{}/status", port))
            .send()
            .await
            .expect("GET /status request failed");

        assert_eq!(resp.status(), StatusCode::OK);

        // Security headers check
        let headers = resp.headers();
        assert_eq!(
            headers.get("content-security-policy").unwrap(),
            "default-src 'none'"
        );
        assert_eq!(headers.get("x-frame-options").unwrap(), "DENY");
        assert_eq!(headers.get("x-content-type-options").unwrap(), "nosniff");
        assert_eq!(headers.get("referrer-policy").unwrap(), "no-referrer");
        assert_eq!(
            headers.get("cache-control").unwrap(),
            "no-store, no-cache, must-revalidate"
        );

        // JSON payload check
        let json: serde_json::Value = resp.json().await.expect("Failed to parse json");
        assert_eq!(json["status"], "ok");
        assert_eq!(json["app"], "HyperFetch");
        assert_eq!(json["version"], BRIDGE_VERSION);
        assert_eq!(json["port"], port);

        bridge.stop();
        let _ = handle.await;
        assert!(!bridge.is_running());
    }

    #[tokio::test]
    async fn test_post_download_adds_task_to_engine_and_returns_200() {
        let (engine, _td) = create_test_engine();
        let config = BridgeConfig {
            preferred_port: 0,
            fallback_port: 0,
            bridge_token: None,
        };
        let bridge = LocalhostBridge::new(engine.clone(), config);
        let (port, handle) = bridge.start().await.expect("Bridge start failed");

        let client = reqwest::Client::new();
        let payload = serde_json::json!({
            "url": "https://example.com/downloads/installer.dmg",
            "filename": "custom_installer.dmg",
            "autoStart": false,
            "headers": {
                "User-Agent": "HyperFetch-Test/1.0"
            }
        });

        let resp = client
            .post(format!("http://127.0.0.1:{}/download", port))
            .header("X-HyperFetch-Client", "extension")
            .json(&payload)
            .send()
            .await
            .expect("POST /download failed");

        assert_eq!(resp.status(), StatusCode::OK);
        let json: serde_json::Value = resp.json().await.expect("Failed to parse json");
        assert_eq!(json["status"], "ok");
        assert_eq!(json["message"], "Download added to HyperFetch");
        assert_eq!(json["url"], "https://example.com/downloads/installer.dmg");
        assert_eq!(json["filename"], "custom_installer.dmg");
        let task_id = json["id"].as_str().expect("Expected task id string");
        assert!(!task_id.is_empty());

        // Verify task exists in engine
        let tasks = engine.tasks.read().await;
        assert_eq!(tasks.len(), 1);
        assert_eq!(tasks[0].id, task_id);
        assert_eq!(tasks[0].filename, "custom_installer.dmg");

        // Verify GET /transfers and GET /queue return the task
        for path in ["/transfers", "/queue"] {
            let resp = client
                .get(format!("http://127.0.0.1:{}{}", port, path))
                .header("X-HyperFetch-Client", "extension")
                .send()
                .await
                .expect("GET transfers failed");
            assert_eq!(resp.status(), StatusCode::OK);
            let json: serde_json::Value = resp.json().await.expect("Failed to parse json");
            assert_eq!(json["status"], "ok");
            let transfers = json["transfers"].as_array().expect("transfers should be array");
            assert_eq!(transfers.len(), 1);
            assert_eq!(transfers[0]["filename"], "custom_installer.dmg");
        }

        bridge.stop();
        let _ = handle.await;
    }

    #[tokio::test]
    async fn test_invalid_url_returns_400() {
        let (engine, _td) = create_test_engine();
        let config = BridgeConfig {
            preferred_port: 0,
            fallback_port: 0,
            bridge_token: None,
        };
        let bridge = LocalhostBridge::new(engine, config);
        let (port, handle) = bridge.start().await.expect("Bridge start failed");

        let client = reqwest::Client::new();

        // 1. Invalid scheme (ftp)
        let resp = client
            .post(format!("http://127.0.0.1:{}/add", port))
            .header("X-HyperFetch-Client", "extension")
            .json(&serde_json::json!({
                "url": "ftp://example.com/file.zip"
            }))
            .send()
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::BAD_REQUEST);

        // 2. Missing url
        let resp = client
            .post(format!("http://127.0.0.1:{}/add", port))
            .header("X-HyperFetch-Client", "extension")
            .json(&serde_json::json!({
                "filename": "no_url.zip"
            }))
            .send()
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::BAD_REQUEST);

        // 3. GET /add with missing url query
        let resp = client
            .get(format!("http://127.0.0.1:{}/add", port))
            .send()
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::BAD_REQUEST);

        bridge.stop();
        let _ = handle.await;
    }

    #[tokio::test]
    async fn test_path_traversal_filename_is_sanitized() {
        let (engine, _td) = create_test_engine();
        let config = BridgeConfig {
            preferred_port: 0,
            fallback_port: 0,
            bridge_token: None,
        };
        let bridge = LocalhostBridge::new(engine.clone(), config);
        let (port, handle) = bridge.start().await.expect("Bridge start failed");

        let client = reqwest::Client::new();

        // Traversal sequence ../../../var/root/.bashrc should be sanitized to .bashrc
        let payload = serde_json::json!({
            "url": "https://example.com/test.dmg",
            "filename": "../../../var/root/.bashrc",
            "autoStart": false
        });

        let resp = client
            .post(format!("http://127.0.0.1:{}/add", port))
            .header("X-HyperFetch-Client", "extension")
            .json(&payload)
            .send()
            .await
            .unwrap();

        assert_eq!(resp.status(), StatusCode::OK);
        let json: serde_json::Value = resp.json().await.unwrap();
        assert_eq!(json["filename"], ".bashrc");

        // Pure traversal ../../ should resolve safely to fallback filename from URL
        let payload2 = serde_json::json!({
            "url": "https://example.com/releases/myapp.zip",
            "filename": "../../",
            "autoStart": false
        });

        let resp2 = client
            .post(format!("http://127.0.0.1:{}/add", port))
            .header("X-HyperFetch-Client", "extension")
            .json(&payload2)
            .send()
            .await
            .unwrap();

        assert_eq!(resp2.status(), StatusCode::OK);
        let json2: serde_json::Value = resp2.json().await.unwrap();
        assert_eq!(json2["filename"], "myapp.zip");

        // Verify task stored in engine does not contain path traversal
        let tasks = engine.tasks.read().await;
        assert!(tasks.iter().all(|t| !t.filename.contains('/')));
        assert!(tasks.iter().all(|t| !t.filename.contains('\\')));
        assert!(tasks.iter().all(|t| !t.destination_path.contains("..")));

        bridge.stop();
        let _ = handle.await;
    }

    #[tokio::test]
    async fn test_cors_and_security_headers_present_in_response() {
        let (engine, _td) = create_test_engine();
        let config = BridgeConfig {
            preferred_port: 0,
            fallback_port: 0,
            bridge_token: None,
        };
        let bridge = LocalhostBridge::new(engine, config);
        let (port, handle) = bridge.start().await.expect("Bridge start failed");

        let client = reqwest::Client::new();
        let origin = "chrome-extension://abcdefghijklmnop";

        // Authorized extension origin
        let resp = client
            .get(format!("http://127.0.0.1:{}/status", port))
            .header("Origin", origin)
            .header("X-HyperFetch-Client", "extension")
            .send()
            .await
            .unwrap();

        assert_eq!(resp.status(), StatusCode::OK);
        let h = resp.headers();
        assert_eq!(h.get("access-control-allow-origin").unwrap(), origin);
        assert_eq!(h.get("vary").unwrap(), "Origin");
        assert_eq!(h.get("content-security-policy").unwrap(), "default-src 'none'");
        assert_eq!(h.get("x-frame-options").unwrap(), "DENY");

        // OPTIONS preflight check
        let opt_resp = client
            .request(Method::OPTIONS, format!("http://127.0.0.1:{}/add", port))
            .header("Origin", origin)
            .send()
            .await
            .unwrap();

        assert_eq!(opt_resp.status(), StatusCode::NO_CONTENT);
        let opt_h = opt_resp.headers();
        assert_eq!(opt_h.get("access-control-allow-origin").unwrap(), origin);
        assert_eq!(opt_h.get("access-control-max-age").unwrap(), "86400");
        assert_eq!(opt_h.get("content-security-policy").unwrap(), "default-src 'none'");

        // Unauthorized external origin (e.g. https://evil.com) -> 403 Forbidden without CORS
        let evil_resp = client
            .get(format!("http://127.0.0.1:{}/status", port))
            .header("Origin", "https://evil.com")
            .send()
            .await
            .unwrap();

        assert_eq!(evil_resp.status(), StatusCode::FORBIDDEN);
        assert!(evil_resp.headers().get("access-control-allow-origin").is_none());
        assert_eq!(
            evil_resp.headers().get("content-security-policy").unwrap(),
            "default-src 'none'"
        );

        bridge.stop();
        let _ = handle.await;
    }

    #[tokio::test]
    async fn test_port_fallback_triggers_when_preferred_port_occupied() {
        let (engine1, _td1) = create_test_engine();

        // 1. Pick a temporary listener to hold a port
        let blocker = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let occupied_port = blocker.local_addr().unwrap().port();

        // 2. Pick a second listener to determine a valid fallback port
        let fallback_listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let fallback_port = fallback_listener.local_addr().unwrap().port();
        drop(fallback_listener); // Free fallback port so bridge can bind it

        let config = BridgeConfig {
            preferred_port: occupied_port,
            fallback_port,
            bridge_token: None,
        };

        let bridge = LocalhostBridge::new(engine1, config);
        let (bound_port, handle) = bridge.start().await.expect("Fallback start failed");

        assert_eq!(bound_port, fallback_port);
        assert!(bridge.is_running());
        assert_eq!(bridge.listening_port(), Some(fallback_port));

        bridge.stop();
        let _ = handle.await;
        drop(blocker);
    }

    #[tokio::test]
    async fn test_shared_secret_bridge_token_authentication() {
        let (engine, _td) = create_test_engine();
        let secret_token = "secret_hyperfetch_token_42".to_string();
        let config = BridgeConfig {
            preferred_port: 0,
            fallback_port: 0,
            bridge_token: Some(secret_token.clone()),
        };
        let bridge = LocalhostBridge::new(engine, config);
        let (port, handle) = bridge.start().await.expect("Bridge start failed");

        let client = reqwest::Client::new();

        // 1. Missing token -> 403
        let r1 = client
            .get(format!("http://127.0.0.1:{}/status", port))
            .send()
            .await
            .unwrap();
        assert_eq!(r1.status(), StatusCode::FORBIDDEN);

        // 2. Wrong token -> 403
        let r2 = client
            .get(format!("http://127.0.0.1:{}/status", port))
            .header("X-HyperFetch-Token", "wrong_token")
            .send()
            .await
            .unwrap();
        assert_eq!(r2.status(), StatusCode::FORBIDDEN);

        // 3. Valid X-HyperFetch-Token -> 200
        let r3 = client
            .get(format!("http://127.0.0.1:{}/status", port))
            .header("X-HyperFetch-Token", &secret_token)
            .send()
            .await
            .unwrap();
        assert_eq!(r3.status(), StatusCode::OK);

        // 4. Valid Authorization: Bearer token -> 200
        let r4 = client
            .get(format!("http://127.0.0.1:{}/status", port))
            .header("Authorization", format!("Bearer {}", secret_token))
            .send()
            .await
            .unwrap();
        assert_eq!(r4.status(), StatusCode::OK);

        // 5. Valid query token parameter -> 200
        let r5 = client
            .get(format!("http://127.0.0.1:{}/status?token={}", port, secret_token))
            .send()
            .await
            .unwrap();
        assert_eq!(r5.status(), StatusCode::OK);

        bridge.stop();
        let _ = handle.await;
    }

    #[tokio::test]
    async fn test_sheet_and_theme_callbacks() {
        let (engine, _td) = create_test_engine();
        let config = BridgeConfig {
            preferred_port: 0,
            fallback_port: 0,
            bridge_token: None,
        };
        let bridge = LocalhostBridge::new(engine, config);

        let sheet_called = Arc::new(AtomicBool::new(false));
        let sheet_called_clone = sheet_called.clone();
        bridge.set_on_sheet_requested(move |url, filename| {
            if url == Some("https://example.com/doc.pdf".to_string())
                && filename == Some("doc.pdf".to_string())
            {
                sheet_called_clone.store(true, Ordering::SeqCst);
            }
        });

        let theme_received = Arc::new(RwLock::new(String::new()));
        let theme_received_clone = theme_received.clone();
        bridge.set_on_theme_requested(move |mode| {
            if let Ok(mut lock) = theme_received_clone.write() {
                *lock = mode;
            }
        });

        let (port, handle) = bridge.start().await.expect("Bridge start failed");
        let client = reqwest::Client::new();

        // Trigger GET /sheet
        let resp_sheet = client
            .get(format!(
                "http://127.0.0.1:{}/sheet?url=https://example.com/doc.pdf&filename=doc.pdf",
                port
            ))
            .send()
            .await
            .unwrap();
        assert_eq!(resp_sheet.status(), StatusCode::OK);
        assert!(sheet_called.load(Ordering::SeqCst));

        // Trigger POST /theme
        let resp_theme = client
            .post(format!("http://127.0.0.1:{}/theme?mode=light", port))
            .header("X-HyperFetch-Client", "extension")
            .send()
            .await
            .unwrap();
        assert_eq!(resp_theme.status(), StatusCode::OK);
        assert_eq!(*theme_received.read().unwrap(), "light");

        bridge.stop();
        let _ = handle.await;
    }

    #[test]
    fn test_security_helper_unit_validation() {
        // Host checks
        assert!(is_authorized_host("127.0.0.1"));
        assert!(is_authorized_host("localhost"));
        assert!(is_authorized_host("127.0.0.1:31415"));
        assert!(is_authorized_host("localhost:8080"));
        assert!(is_authorized_host("LOCALHOST:31415"));
        assert!(!is_authorized_host("evil.com"));
        assert!(!is_authorized_host("attacker.com:31415"));
        assert!(!is_authorized_host("127.0.0.1.evil.com"));
        assert!(!is_authorized_host("localhost.attacker.com"));
        assert!(!is_authorized_host(""));
        assert!(!is_authorized_host("127.0.0.1:invalidPort"));

        // Origin checks
        assert!(is_authorized_origin("chrome-extension://abcdefghijklmnop"));
        assert!(is_authorized_origin("moz-extension://fedcba9876543210"));
        assert!(is_authorized_origin("safari-web-extension://12345678-1234"));
        assert!(is_authorized_origin("http://127.0.0.1"));
        assert!(is_authorized_origin("http://127.0.0.1:3000"));
        assert!(is_authorized_origin("http://localhost"));
        assert!(is_authorized_origin("http://localhost:5173"));
        assert!(is_authorized_origin("https://127.0.0.1:8443"));
        assert!(is_authorized_origin("https://localhost:8443"));

        // Malicious origins
        assert!(!is_authorized_origin("https://evil.com"));
        assert!(!is_authorized_origin("http://malicious.org"));
        assert!(!is_authorized_origin("http://localhost.evil.com"));
        assert!(!is_authorized_origin("http://127.0.0.1.attacker.com"));
        assert!(!is_authorized_origin("null"));
        assert!(!is_authorized_origin(""));

        // Path traversal sanitization
        assert_eq!(
            sanitize_requested_filename("../../../var/root/.bashrc"),
            Some(".bashrc".to_string())
        );
        assert_eq!(sanitize_requested_filename("../../"), None);
        assert_eq!(sanitize_requested_filename(".."), None);
        assert_eq!(sanitize_requested_filename(""), None);
        assert_eq!(
            sanitize_requested_filename("archive\0.zip"),
            Some("archive.zip".to_string())
        );
        assert_eq!(
            sanitize_requested_filename("nested/folder/doc.pdf"),
            Some("doc.pdf".to_string())
        );
        assert_eq!(
            sanitize_requested_filename("nested\\folder\\doc.pdf"),
            Some("doc.pdf".to_string())
        );
    }
}
