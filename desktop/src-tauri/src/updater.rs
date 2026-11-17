use reqwest::header::{ACCEPT, USER_AGENT};
use serde::{Deserialize, Serialize};
use std::time::Duration;

pub const CURRENT_APP_VERSION: &str = "1.2.2";
pub const GITHUB_REPO: &str = "consultanything-tech/hyperfetch";

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct UpdateCheckResult {
    pub available: bool,
    pub current_version: String,
    pub latest_version: String,
    pub release_notes: Option<String>,
    pub download_url: Option<String>,
    pub asset_name: Option<String>,
    pub published_at: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct GitHubRelease {
    pub tag_name: String,
    pub name: Option<String>,
    pub body: Option<String>,
    pub html_url: Option<String>,
    pub published_at: Option<String>,
    pub assets: Option<Vec<GitHubAsset>>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct GitHubAsset {
    pub name: String,
    pub browser_download_url: String,
    pub size: Option<u64>,
}

/// Semantic version comparison returning true if `remote` is strictly newer than `current`.
pub fn is_newer_version(remote: &str, current: &str) -> bool {
    let parse_parts = |s: &str| -> Vec<u64> {
        let trimmed = s.trim().trim_start_matches(|c: char| c == 'v' || c == 'V');
        let main_ver = trimmed.split('-').next().unwrap_or(trimmed);
        main_ver
            .split('.')
            .map(|part| part.trim().parse::<u64>().unwrap_or(0))
            .collect()
    };

    let remote_parts = parse_parts(remote);
    let current_parts = parse_parts(current);

    let max_len = remote_parts.len().max(current_parts.len());
    for i in 0..max_len {
        let r = remote_parts.get(i).copied().unwrap_or(0);
        let c = current_parts.get(i).copied().unwrap_or(0);
        if r > c {
            return true;
        } else if r < c {
            return false;
        }
    }
    false
}

/// Finds the most appropriate Windows asset from a list of release assets.
/// Priority:
/// 1. `.exe` (NSIS installer or executable)
/// 2. `.msi` (Windows installer package)
/// 3. Windows zip archive (`.zip` containing "win" or "x64")
pub fn find_windows_asset<'a>(assets: &'a [GitHubAsset]) -> Option<&'a GitHubAsset> {
    // 1. Look for .exe installers
    if let Some(exe) = assets.iter().find(|a| {
        let lower = a.name.to_lowercase();
        lower.ends_with(".exe") && !lower.contains("extension")
    }) {
        return Some(exe);
    }

    // 2. Look for .msi installers
    if let Some(msi) = assets.iter().find(|a| {
        let lower = a.name.to_lowercase();
        lower.ends_with(".msi") && !lower.contains("extension")
    }) {
        return Some(msi);
    }

    // 3. Look for windows zip archives
    assets.iter().find(|a| {
        let lower = a.name.to_lowercase();
        lower.ends_with(".zip")
            && (lower.contains("win") || lower.contains("x64") || lower.contains("windows"))
            && !lower.contains("extension")
    })
}

/// Checks GitHub releases API for newer versions of HyperFetch.
pub async fn check_for_updates_impl(
    repo: &str,
    current_ver: &str,
) -> Result<UpdateCheckResult, String> {
    let url = format!("https://api.github.com/repos/{}/releases/latest", repo);
    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(6))
        .build()
        .unwrap_or_else(|_| reqwest::Client::new());

    let response = match client
        .get(&url)
        .header(ACCEPT, "application/vnd.github.v3+json")
        .header(USER_AGENT, format!("HyperFetch/{}", current_ver))
        .send()
        .await
    {
        Ok(res) => res,
        Err(_) => {
            // Graceful fallback on network/DNS error
            return Ok(UpdateCheckResult {
                available: false,
                current_version: current_ver.to_string(),
                latest_version: current_ver.to_string(),
                release_notes: None,
                download_url: None,
                asset_name: None,
                published_at: None,
            });
        }
    };

    if !response.status().is_success() {
        // Graceful fallback for 404 / 403 / unreleased
        return Ok(UpdateCheckResult {
            available: false,
            current_version: current_ver.to_string(),
            latest_version: current_ver.to_string(),
            release_notes: None,
            download_url: None,
            asset_name: None,
            published_at: None,
        });
    }

    let release = match response.json::<GitHubRelease>().await {
        Ok(r) => r,
        Err(_) => {
            return Ok(UpdateCheckResult {
                available: false,
                current_version: current_ver.to_string(),
                latest_version: current_ver.to_string(),
                release_notes: None,
                download_url: None,
                asset_name: None,
                published_at: None,
            });
        }
    };

    let remote_ver_str = release
        .tag_name
        .trim()
        .trim_start_matches(|c: char| c == 'v' || c == 'V')
        .to_string();

    let is_newer = is_newer_version(&remote_ver_str, current_ver);

    let (download_url, asset_name) = if let Some(ref assets) = release.assets {
        if let Some(target_asset) = find_windows_asset(assets) {
            (
                Some(target_asset.browser_download_url.clone()),
                Some(target_asset.name.clone()),
            )
        } else {
            (release.html_url.clone(), None)
        }
    } else {
        (release.html_url.clone(), None)
    };

    Ok(UpdateCheckResult {
        available: is_newer,
        current_version: current_ver.to_string(),
        latest_version: remote_ver_str,
        release_notes: release.body,
        download_url,
        asset_name,
        published_at: release.published_at,
    })
}

#[tauri::command]
pub async fn check_for_updates() -> Result<UpdateCheckResult, String> {
    check_for_updates_impl(GITHUB_REPO, CURRENT_APP_VERSION).await
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_is_newer_version() {
        // Newer versions
        assert!(is_newer_version("1.0.14", "1.0.13"));
        assert!(is_newer_version("v1.0.14", "1.0.13"));
        assert!(is_newer_version("1.1.0", "1.0.13"));
        assert!(is_newer_version("2.0.0", "1.0.13"));
        assert!(is_newer_version("1.0.13.1", "1.0.13"));
        assert!(is_newer_version("v2.0.1", "v1.0.13"));

        // Equal versions
        assert!(!is_newer_version("1.0.13", "1.0.13"));
        assert!(!is_newer_version("v1.0.13", "1.0.13"));
        assert!(!is_newer_version("1.0.13", "v1.0.13"));

        // Older versions
        assert!(!is_newer_version("1.0.12", "1.0.13"));
        assert!(!is_newer_version("0.9.9", "1.0.13"));
        assert!(!is_newer_version("v1.0.1", "1.0.13"));
    }

    #[test]
    fn test_find_windows_asset_priority() {
        let assets = vec![
            GitHubAsset {
                name: "HyperFetch-macOS.dmg".to_string(),
                browser_download_url: "https://example.com/mac.dmg".to_string(),
                size: Some(1000),
            },
            GitHubAsset {
                name: "HyperFetch_1.0.14_x64-setup.exe".to_string(),
                browser_download_url: "https://example.com/win-setup.exe".to_string(),
                size: Some(2000),
            },
            GitHubAsset {
                name: "HyperFetch_1.0.14_x64_en-US.msi".to_string(),
                browser_download_url: "https://example.com/win.msi".to_string(),
                size: Some(3000),
            },
        ];

        let selected = find_windows_asset(&assets).expect("should find exe");
        assert_eq!(selected.name, "HyperFetch_1.0.14_x64-setup.exe");
        assert_eq!(selected.browser_download_url, "https://example.com/win-setup.exe");

        // When only .msi is present
        let msi_assets = vec![
            GitHubAsset {
                name: "HyperFetch-macOS.dmg".to_string(),
                browser_download_url: "https://example.com/mac.dmg".to_string(),
                size: Some(1000),
            },
            GitHubAsset {
                name: "HyperFetch_1.0.14_x64_en-US.msi".to_string(),
                browser_download_url: "https://example.com/win.msi".to_string(),
                size: Some(3000),
            },
        ];
        let selected_msi = find_windows_asset(&msi_assets).expect("should find msi");
        assert_eq!(selected_msi.name, "HyperFetch_1.0.14_x64_en-US.msi");

        // When only zip is present
        let zip_assets = vec![
            GitHubAsset {
                name: "HyperFetch-windows-x64.zip".to_string(),
                browser_download_url: "https://example.com/win-zip.zip".to_string(),
                size: Some(4000),
            },
        ];
        let selected_zip = find_windows_asset(&zip_assets).expect("should find zip");
        assert_eq!(selected_zip.name, "HyperFetch-windows-x64.zip");
    }

    #[test]
    fn test_parse_github_release_json() {
        let json = r#"{
            "tag_name": "v1.0.14",
            "name": "HyperFetch 1.0.14",
            "body": "- Added Windows Taskbar progress\n- Added In-App Updater",
            "html_url": "https://github.com/consultanything-tech/hyperfetch/releases/tag/v1.0.14",
            "published_at": "2026-11-08T12:00:00Z",
            "assets": [
                {
                    "name": "HyperFetch_1.0.14_x64-setup.exe",
                    "browser_download_url": "https://github.com/consultanything-tech/hyperfetch/releases/download/v1.0.14/HyperFetch_1.0.14_x64-setup.exe",
                    "size": 52428800
                }
            ]
        }"#;

        let release: GitHubRelease = serde_json::from_str(json).expect("valid json");
        assert_eq!(release.tag_name, "v1.0.14");
        let remote_ver = release.tag_name.trim_start_matches('v');
        assert!(is_newer_version(remote_ver, "1.0.13"));

        let asset = find_windows_asset(release.assets.as_ref().unwrap()).unwrap();
        assert_eq!(asset.name, "HyperFetch_1.0.14_x64-setup.exe");
    }
}
