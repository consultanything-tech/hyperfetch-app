# HyperFetch UI/UX Overhaul & Cross-Platform Parity Plan

> **For Orchestrator:** REQUIRED SUB-SKILL: Use subagent delegation (`invoke_subagent` with `Model: "flash"`, `Workspace: "inherit"`) for all file modifications.

**Goal:** Elevate HyperFetch UI/UX across all surfaces by aligning macOS with native macOS Sequoia patterns (vibrancy materials, integer typography, native commands) and bringing Windows into complete feature and interaction parity with macOS (Inspector side pane, desktop selection semantics, right-click context menus, and live sparkline telemetry).

**Architecture:**
- **macOS App**: Adopt native SwiftUI material vibrancy (`.ultraThinMaterial`), standard integer point typography, native `.commands` menu bar integration, unified selection toolbar, and full accessibility labels.
- **Windows App**: Implement Inspector side pane (`TaskDetailInspector`), row-click selection with `Ctrl+Click` / `Shift+Click` contiguous range selection, custom right-click context menu, live rolling sparkline telemetry, and Windows 11 `Segoe UI Variable` typography.
- **Chrome Extension & Motion**: Adaptive polling backoff, `:focus-visible` styling, and universal `prefers-reduced-motion` accommodations.

**Tech Stack:** Swift 6, SwiftUI, React 19, Tailwind CSS, Lucide icons, Tauri 2, Chrome Extension MV3.

---

## Phase 1: macOS Native Sequoia Design & HIG Alignment
- Task 1.1: Update `Theme.swift`, `SidebarView.swift`, and `DownloadListView.swift` to use native macOS vibrancy materials (`.ultraThinMaterial`, dynamic system colors) and integrate selection batch actions cleanly into the toolbar.
- Task 1.2: Standardize fractional font sizes (`13.5pt`, `11.5pt`, `9.5pt`) to integer typography scale across `MainWindow.swift`, `DownloadRowView.swift`, and `CompactDownloadRowView.swift`.
- Task 1.3: Replace zero-opacity hidden button shortcuts in `MainWindow.swift` with standard SwiftUI `.commands` and `.onKeyPress`.
- Task 1.4: Centralize category colors and symbols on `DownloadCategory` and add full accessibility labels and values to download row checkboxes and progress bars.
- Task 1.5: Add `@Environment(\.accessibilityReduceMotion)` checks in `ChunkVisualizer.swift`.

## Phase 2: Windows Desktop Parity with macOS App
- Task 2.1: Build `TaskDetailInspector.tsx` side panel mirroring macOS `taskDetailView` (chunk grid, segmented range stream bar, metadata, checksum state, action buttons), and remove in-row accordion expansion.
- Task 2.2: Implement desktop row selection semantics (`click` selects, `Ctrl+Click` toggles, `Shift+Click` range selects) in `App.tsx` and `DownloadRow.tsx`.
- Task 2.3: Implement custom desktop right-click context menu on download rows (Pause/Resume, Reveal in Explorer, Copy Link, Queue Position reordering, Delete).
- Task 2.4: Wire live rolling network speed history to the sidebar sparklines in `Sidebar.tsx`.
- Task 2.5: Align terminology ("Video & Media", "Audio & Music", "Applications & Disk") and update font stack to `'Segoe UI Variable Text', 'Segoe UI', system-ui`.

## Phase 3: Chrome Extension Polish & Global Reduced Motion
- Task 3.1: Add `:focus-visible` styling and accessible button labels in `popup.html` / `popup.css`.
- Task 3.2: Implement adaptive polling backoff (1.5s active transfers, 5s idle) in `popup.js`.
- Task 3.3: Add `@media (prefers-reduced-motion: reduce)` rules across `index.css` and `popup.css`.

## Phase 4: Verification & Regression Testing
- Task 4.1: `swift test` and `swift build` on macOS.
- Task 4.2: `cargo test` and `pnpm build` in `desktop/`.
- Task 4.3: End-to-end verification and documentation update in `walkthrough.md`.
