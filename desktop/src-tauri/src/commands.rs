use crate::downloader::{probe_url, ProbeResult};
use crate::engine::DownloadEngine;
use crate::models::DownloadTask;
use crate::storage::FileWriter;
use std::collections::HashMap;
use std::path::Path;
use std::sync::Arc;
use tauri::State;

/// Managed state containing the shared DownloadEngine.
pub struct AppState {
    pub engine: Arc<DownloadEngine>,
}

#[tauri::command]
pub async fn get_downloads(state: State<'_, AppState>) -> Result<Vec<DownloadTask>, String> {
    Ok(state.engine.get_tasks().await)
}

#[tauri::command]
pub async fn add_download(
    state: State<'_, AppState>,
    url: String,
    filename: Option<String>,
    destination: Option<String>,
    auto_start: bool,
    headers: Option<HashMap<String, String>>,
) -> Result<DownloadTask, String> {
    state
        .engine
        .add_download(url, filename, destination, auto_start, headers)
        .await
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn pause_download(state: State<'_, AppState>, id: String) -> Result<(), String> {
    state.engine.pause(&id).await.map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn resume_download(state: State<'_, AppState>, id: String) -> Result<(), String> {
    state
        .engine
        .start_or_resume(&id)
        .await
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn cancel_download(state: State<'_, AppState>, id: String) -> Result<(), String> {
    state.engine.cancel(&id).await.map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn delete_download(
    state: State<'_, AppState>,
    id: String,
    delete_file: bool,
) -> Result<(), String> {
    state
        .engine
        .delete(&id, delete_file)
        .await
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn pause_all(state: State<'_, AppState>) -> Result<(), String> {
    state.engine.pause_all().await.map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn resume_all(state: State<'_, AppState>) -> Result<(), String> {
    state.engine.resume_all().await.map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn probe_url_info(url: String) -> Result<ProbeResult, String> {
    let client = reqwest::Client::builder()
        .tcp_keepalive(std::time::Duration::from_secs(30))
        .build()
        .unwrap_or_else(|_| reqwest::Client::new());
    probe_url(&client, &url, None)
        .await
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn open_file(path: String) -> Result<(), String> {
    let p = Path::new(&path);
    if !p.exists() {
        return Err(format!("File does not exist: {}", path));
    }

    #[cfg(target_os = "macos")]
    {
        std::process::Command::new("open")
            .arg(&path)
            .spawn()
            .map_err(|e| format!("Failed to open file: {}", e))?;
    }
    #[cfg(target_os = "windows")]
    {
        std::process::Command::new("cmd")
            .args(["/c", "start", "", &path])
            .spawn()
            .map_err(|e| format!("Failed to open file: {}", e))?;
    }
    #[cfg(target_os = "linux")]
    {
        std::process::Command::new("xdg-open")
            .arg(&path)
            .spawn()
            .map_err(|e| format!("Failed to open file: {}", e))?;
    }
    Ok(())
}

#[tauri::command]
pub async fn open_containing_folder(path: String) -> Result<(), String> {
    let p = Path::new(&path);

    #[cfg(target_os = "macos")]
    {
        if p.exists() {
            std::process::Command::new("open")
                .args(["-R", &path])
                .spawn()
                .map_err(|e| format!("Failed to reveal file: {}", e))?;
        } else if let Some(parent) = p.parent() {
            if parent.exists() {
                std::process::Command::new("open")
                    .arg(parent)
                    .spawn()
                    .map_err(|e| format!("Failed to open directory: {}", e))?;
            } else {
                return Err(format!("Directory does not exist: {}", parent.display()));
            }
        } else {
            return Err("Invalid path".to_string());
        }
    }
    #[cfg(target_os = "windows")]
    {
        if p.exists() {
            std::process::Command::new("explorer")
                .args([format!("/select,{}", path)])
                .spawn()
                .map_err(|e| format!("Failed to reveal file: {}", e))?;
        } else if let Some(parent) = p.parent() {
            if parent.exists() {
                std::process::Command::new("explorer")
                    .arg(parent)
                    .spawn()
                    .map_err(|e| format!("Failed to open directory: {}", e))?;
            } else {
                return Err(format!("Directory does not exist: {}", parent.display()));
            }
        } else {
            return Err("Invalid path".to_string());
        }
    }
    #[cfg(target_os = "linux")]
    {
        let dir = if p.is_dir() {
            p
        } else {
            p.parent().unwrap_or(p)
        };
        if dir.exists() {
            std::process::Command::new("xdg-open")
                .arg(dir)
                .spawn()
                .map_err(|e| format!("Failed to open directory: {}", e))?;
        } else {
            return Err(format!("Directory does not exist: {}", dir.display()));
        }
    }
    Ok(())
}

#[tauri::command]
pub fn get_default_download_dir(category: Option<String>) -> String {
    FileWriter::get_default_download_dir(category.as_deref())
        .to_string_lossy()
        .to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_get_default_download_dir_categories() {
        let base_dir = get_default_download_dir(None);
        assert!(base_dir.ends_with("HyperFetch"));

        let videos_dir = get_default_download_dir(Some("videos".to_string()));
        assert!(videos_dir.ends_with("Videos"));

        let music_dir = get_default_download_dir(Some("Music".to_string()));
        assert!(music_dir.ends_with("Music"));

        let archives_dir = get_default_download_dir(Some("archives".to_string()));
        assert!(archives_dir.ends_with("Archives"));

        let docs_dir = get_default_download_dir(Some("documents".to_string()));
        assert!(docs_dir.ends_with("Documents"));
    }

    #[tokio::test]
    async fn test_probe_url_info_invalid() {
        let res = probe_url_info("not-a-valid-url".to_string()).await;
        assert!(res.is_err());
    }
}

