# HyperFetch Lifecycle, Overlay, and Menu Resilience Implementation Plan

> **For Orchestrator:** REQUIRED SUB-SKILL: Use subagent delegation (`invoke_subagent` with `Model: "flash"`, `Workspace: "inherit"`) for all file modifications.

**Goal:** Implement lifecycle audit fixes, overlay resilience, menu dismiss stability, and bump version to 1.2.2.3 (Build 25).

**Architecture:**
- **macOS FloatingHUDController**: Register global mouse click monitor (`NSEvent.addGlobalMonitorForEvents`) and `NSApplication.didResignActiveNotification` observer to automatically dismiss the floating HUD panel on external clicks or app deactivation. Clean up monitors and observers in `dismiss()` and `deinit`.
- **Desktop ContextMenu (React / Tauri)**: Register `blur` and capture-phase `scroll` event listeners to dismiss context menus immediately when window focus is lost or scrolling occurs outside the menu.
- **macOS HyperFetchApp AppDelegate**: Register a global mouse click monitor in `applicationDidFinishLaunching` to immediately invoke `NSMenu.cancelTracking()` when clicking external windows, preventing dangling active menus.
- **macOS MainWindow Toolbar**: Asynchronously dispatch batch action button handlers via `DispatchQueue.main.async` to prevent blocking AppKit menu tracking teardown during state mutations.
- **macOS DownloadListView Drag-and-Drop Overlay**: Add `.contentShape(Rectangle())` and `.onTapGesture { isDropTargeted = false }` to the drag-drop overlay so abandoned drag sessions can be dismissed on tap.
- **Version Bump**: Bump version to 1.2.2.3 (Build 25) cleanly with no brackets around build numbers across all 11 project manifests, documentation, and app bundles.

**Tech Stack:** Swift 6, AppKit, SwiftUI, TypeScript, React, Rust, Tauri 2.

---

## Phase 1: Floating HUD Lifecycle & Outside Click Dismissal
- Add `clickEventMonitor` and `deactivationObserver` to `FloatingHUDController`.
- In `show(...)`:
  - Register global click monitor for `.leftMouseDown` and `.rightMouseDown`; dismiss if click location falls outside HUD frame.
  - Register deactivation observer for `NSApplication.didResignActiveNotification` to dismiss HUD.
- In `dismiss()` and `deinit`:
  - Unregister click monitor and notification observer cleanly.

## Phase 2: Web Context Menu Focus & Scroll Dismissal
- In `desktop/src/components/ContextMenu.tsx`:
  - Add `handleBlur` and `handleScroll` event handlers.
  - Listen for `blur` and capture-phase `scroll` on `window`.
  - Clean up event listeners on unmount.

## Phase 3: Global Menu Tracking & Toolbar Action Dispatch
- In `Sources/HyperFetchApp/App/HyperFetchApp.swift`:
  - Register global click monitor in `applicationDidFinishLaunching` to call `NSMenu.cancelTracking()`.
- In `Sources/HyperFetchApp/Views/MainWindow.swift`:
  - Wrap toolbar batch action closures in `DispatchQueue.main.async`.

## Phase 4: Drag & Drop Overlay Tap-to-Dismiss Safeguard
- In `Sources/HyperFetchApp/Views/DownloadListView.swift`:
  - Add `.contentShape(Rectangle())` and `.onTapGesture { isDropTargeted = false }` to `dragDropTargetOverlay`.

## Phase 5: Cross-Platform Version Bump to 1.2.2.3 (Build 25)
- Update 11 files with no brackets around build numbers:
  1. `Sources/HyperFetchApp/Info.plist`: CFBundleShortVersionString -> 1.2.2.3, CFBundleVersion -> 25
  2. `Sources/HyperFetchApp/System/AppVersionManager.swift`: currentVersion -> 1.2.2.3, buildNumber -> 25
  3. `desktop/package.json`: version -> 1.2.2.3
  4. `desktop/src-tauri/Cargo.toml`: version -> 1.2.2.3
  5. `desktop/src-tauri/Cargo.lock`: update desktop package version -> 1.2.2.3
  6. `desktop/src-tauri/tauri.conf.json`: version -> 1.2.2.3
  7. `desktop/src-tauri/src/updater.rs`: CURRENT_APP_VERSION -> 1.2.2.3
  8. `desktop/src/components/SettingsModal.tsx`: Version 1.2.2.3
  9. `extensions/chrome/manifest.json`: version -> 1.2.2.3
  10. `docs/index.html`: replace 1.2.2.2 with 1.2.2.3
  11. `README.md`: replace 1.2.2.2 with 1.2.2.3

## Phase 6: Verification & Regression Testing
- Execute `swift test` to confirm all 147 tests pass.
- Verify git diff across all 11 modified files.
