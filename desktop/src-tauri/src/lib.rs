pub mod bridge;
pub mod commands;
pub mod downloader;
pub mod engine;
pub mod models;
pub mod native_host;
pub mod storage;
pub mod updater;

use bridge::{BridgeConfig, LocalhostBridge};
pub use commands::AppState;
use engine::DownloadEngine;
use models::DownloadState;
use std::sync::Arc;
use tauri::menu::{Menu, MenuItem, PredefinedMenuItem};
use tauri::tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent};
use tauri::window::{ProgressBarState, ProgressBarStatus};
use tauri::{Emitter, Manager};

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let engine = Arc::new(DownloadEngine::new());

    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .manage(AppState {
            engine: engine.clone(),
        })
        .setup({
            let engine = engine.clone();
            move |app| {
                let handle = app.handle().clone();

                // Setup and start Localhost HTTP Bridge
                let bridge_config = BridgeConfig::default();
                let bridge = Arc::new(LocalhostBridge::new(engine.clone(), bridge_config));

                let handle_sheet = handle.clone();
                bridge.set_on_sheet_requested(move |url, filename| {
                    let payload = serde_json::json!({
                        "url": url,
                        "filename": filename,
                    });
                    let _ = handle_sheet.emit("open-add-sheet", payload);
                });

                let handle_theme = handle.clone();
                bridge.set_on_theme_requested(move |theme| {
                    let _ = handle_theme.emit("set-theme", theme);
                });

                let bridge_runner = bridge.clone();
                tauri::async_runtime::spawn(async move {
                    if let Err(e) = bridge_runner.start().await {
                        eprintln!("[LocalhostBridge] Failed to start: {}", e);
                    }
                });

                // System Tray Setup
                let show_item =
                    MenuItem::with_id(app, "show", "Show HyperFetch", true, None::<&str>)?;
                let add_item =
                    MenuItem::with_id(app, "add", "Add Download...", true, None::<&str>)?;
                let pause_all_item =
                    MenuItem::with_id(app, "pause_all", "Pause All", true, None::<&str>)?;
                let resume_all_item =
                    MenuItem::with_id(app, "resume_all", "Resume All", true, None::<&str>)?;
                let separator = PredefinedMenuItem::separator(app)?;
                let quit_item =
                    MenuItem::with_id(app, "quit", "Quit HyperFetch", true, None::<&str>)?;

                let tray_menu = Menu::with_items(
                    app,
                    &[
                        &show_item,
                        &add_item,
                        &pause_all_item,
                        &resume_all_item,
                        &separator,
                        &quit_item,
                    ],
                )?;

                let tray_icon = app.default_window_icon().cloned();
                let mut tray_builder = TrayIconBuilder::with_id("main-tray")
                    .tooltip("HyperFetch - Fast Multi-Threaded Download Manager")
                    .menu(&tray_menu)
                    .show_menu_on_left_click(false)
                    .on_menu_event({
                        let engine = engine.clone();
                        move |app_handle, event| {
                            match event.id().as_ref() {
                                "show" => {
                                    if let Some(window) = app_handle.get_webview_window("main") {
                                        let _ = window.show();
                                        let _ = window.unminimize();
                                        let _ = window.set_focus();
                                    }
                                }
                                "add" => {
                                    if let Some(window) = app_handle.get_webview_window("main") {
                                        let _ = window.show();
                                        let _ = window.unminimize();
                                        let _ = window.set_focus();
                                    }
                                    let _ = app_handle.emit("open-add-sheet", serde_json::json!({}));
                                }
                                "pause_all" => {
                                    let engine = engine.clone();
                                    tauri::async_runtime::spawn(async move {
                                        let _ = engine.pause_all().await;
                                    });
                                }
                                "resume_all" => {
                                    let engine = engine.clone();
                                    tauri::async_runtime::spawn(async move {
                                        let _ = engine.resume_all().await;
                                    });
                                }
                                "quit" => {
                                    app_handle.exit(0);
                                }
                                _ => {}
                            }
                        }
                    })
                    .on_tray_icon_event(|tray, event| {
                        if let TrayIconEvent::Click {
                            button: MouseButton::Left,
                            button_state: MouseButtonState::Up,
                            ..
                        } = event
                        {
                            let app_handle = tray.app_handle();
                            if let Some(window) = app_handle.get_webview_window("main") {
                                let _ = window.show();
                                let _ = window.unminimize();
                                let _ = window.set_focus();
                            }
                        }
                    });

                if let Some(icon) = tray_icon {
                    tray_builder = tray_builder.icon(icon);
                }

                if let Err(e) = tray_builder.build(app) {
                    eprintln!("[SystemTray] Failed to initialize tray icon: {}", e);
                }

                // 500ms background poller that emits download-progress event and updates taskbar progress
                let handle_poll = handle.clone();
                let engine_poll = engine.clone();
                tauri::async_runtime::spawn(async move {
                    let mut interval = tokio::time::interval(std::time::Duration::from_millis(500));
                    let mut had_active_prev = false;

                    loop {
                        interval.tick().await;
                        let tasks = engine_poll.get_tasks().await;
                        let mut total_bytes: u64 = 0;
                        let mut downloaded_bytes: u64 = 0;
                        let mut active_count = 0;

                        for t in &tasks {
                            if t.status == DownloadState::Downloading
                                || t.status == DownloadState::Connecting
                            {
                                active_count += 1;
                                downloaded_bytes += t.downloaded_bytes;
                                total_bytes += t.total_bytes;
                            }
                        }

                        if active_count > 0 {
                            had_active_prev = true;
                            let _ = handle_poll.emit("download-progress", &tasks);

                            #[cfg(desktop)]
                            if let Some(window) = handle_poll.get_webview_window("main") {
                                if total_bytes > 0 && downloaded_bytes <= total_bytes {
                                    let pct = ((downloaded_bytes as f64 / total_bytes as f64)
                                        * 100.0)
                                        .round()
                                        as u64;
                                    let _ = window.set_progress_bar(ProgressBarState {
                                        status: Some(ProgressBarStatus::Normal),
                                        progress: Some(pct.min(100)),
                                    });
                                } else {
                                    let _ = window.set_progress_bar(ProgressBarState {
                                        status: Some(ProgressBarStatus::Indeterminate),
                                        progress: None,
                                    });
                                }
                            }
                        } else if had_active_prev {
                            had_active_prev = false;
                            let _ = handle_poll.emit("download-progress", &tasks);

                            #[cfg(desktop)]
                            if let Some(window) = handle_poll.get_webview_window("main") {
                                let _ = window.set_progress_bar(ProgressBarState {
                                    status: Some(ProgressBarStatus::None),
                                    progress: None,
                                });
                            }
                        }
                    }
                });

                Ok(())
            }
        })
        .invoke_handler(tauri::generate_handler![
            commands::get_downloads,
            commands::add_download,
            commands::pause_download,
            commands::resume_download,
            commands::cancel_download,
            commands::delete_download,
            commands::pause_all,
            commands::resume_all,
            commands::reorder_task,
            commands::probe_url_info,
            commands::open_file,
            commands::open_containing_folder,
            commands::get_default_download_dir,
            commands::get_all_time_stats,
            commands::get_max_concurrent_downloads,
            commands::set_max_concurrent_downloads,
            commands::get_quiet_hours_config,
            commands::set_quiet_hours_config,
            updater::check_for_updates,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
