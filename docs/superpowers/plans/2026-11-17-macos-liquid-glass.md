# macOS Liquid Glass & System Settings Synchronization Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Transform HyperFetch macOS interface into an authentic Liquid Glass design that inherits system-wide macOS settings (Dark/Light appearance, Reduce Transparency, Wallpaper Tinting, Window Active/Inactive states, and Golden Gate appearance slider) via native NSVisualEffectView and SwiftUI materials.

**Architecture:** Configure `NSWindow` with full-size content and transparent chrome; bridge `NSVisualEffectView` with `.behindWindow` and `.withinWindow` blending modes; update design system tokens in `Theme.swift` to use adaptive translucent materials and specular gradient highlights; apply across main window canvas, sidebar, queue cards, and inspectors with full accessibility fallback.

**Tech Stack:** Swift 5.9+, AppKit (`NSVisualEffectView`, `NSWindow`), SwiftUI (`Material`, `@Environment(\.accessibilityReduceTransparency)`).

---

### Task 1: Configure Window-Level Chrome & Transparency in `MainWindowDelegate.swift`

**Files:**
- Modify: `Sources/HyperFetchApp/System/MainWindowDelegate.swift`

**Step 1:** In `configure(window: NSWindow)`, insert `.fullSizeContentView` into `window.styleMask`, set `window.titlebarAppearsTransparent = true`, `window.titleVisibility = .hidden`, `window.isOpaque = false`, and `window.backgroundColor = .clear`.
**Step 2:** Ensure window reopen and frame restoration maintain the clear backing color and transparency.
**Step 3:** Commit: `git commit -m "feat(macos): configure transparent NSWindow chrome and full-size content view"`

---

### Task 2: Build `VisualEffectBlur` Bridge & Liquid Glass Tokens in `Theme.swift`

**Files:**
- Modify: `Sources/HyperFetchApp/Views/Theme.swift`

**Step 1:** Create `VisualEffectBlur: NSViewRepresentable` with configurable `material`, `blendingMode`, and `state = .followsWindowActiveState`.
**Step 2:** Create `LiquidGlassStyle: ViewModifier` featuring:
  - Wallpaper blur diffusion via `VisualEffectBlur` / `.ultraThinMaterial`
  - Specular edge lighting via `LinearGradient` stroke border (bright at top, soft at bottom)
  - Full `@Environment(\.accessibilityReduceTransparency)` fallback to solid `NSColor.windowBackgroundColor`
**Step 3:** Update `Theme.canvasBackground` to `.clear`, and update `Theme.cardBackground`, `Theme.cardActive`, `Theme.cardBorder` to adaptive translucent color definitions.
**Step 4:** Commit: `git commit -m "feat(macos): add VisualEffectBlur bridge and LiquidGlass tokens with accessibility fallback"`

---

### Task 3: Apply Behind-Window Blur to Root Window & Split View in `MainWindow.swift`

**Files:**
- Modify: `Sources/HyperFetchApp/Views/MainWindow.swift`

**Step 1:** Replace `.background(Theme.canvasBackground)` on the root `NavigationSplitView` with a background layer using `VisualEffectBlur(material: .underWindowBackground, blendingMode: .behindWindow)`.
**Step 2:** Ensure split view columns and detail inspector use transparent / blurred backgrounds allowing wallpaper refraction to flow seamlessly across the window.
**Step 3:** Commit: `git commit -m "feat(macos): apply behind-window glass material to MainWindow canvas and split view"`

---

### Task 4: Modernize Download Queue Rows & Floating Bars with Liquid Glass

**Files:**
- Modify: `Sources/HyperFetchApp/Views/DownloadRowView.swift`
- Modify: `Sources/HyperFetchApp/Views/CompactDownloadRowView.swift`
- Modify: `Sources/HyperFetchApp/Views/DownloadListView.swift`

**Step 1:** In `DownloadListView.swift`, make scrollview content background hidden (`.scrollContentBackground(.hidden)`) and wrap bottom status telemetry with `.withinWindow` material blur.
**Step 2:** In `DownloadRowView.swift` and `CompactDownloadRowView.swift`, replace flat card fills with translucent liquid glass backgrounds and specular highlights, while keeping active selection distinct.
**Step 3:** Commit: `git commit -m "feat(macos): apply liquid glass styling to download cards and queue status bar"`

---

### Task 5: Verification & Build Packaging

**Files:**
- Test: Build project using `swift build`
- Run: `swift test`
- Package: `scripts/package_dmg.sh`

**Step 1:** Run `swift build` and resolve any compiler warnings or type mismatches.
**Step 2:** Run `swift test` to verify all engine and model test suites pass.
**Step 3:** Run `scripts/package_dmg.sh` to package the updated DMG.
**Step 4:** Commit and document in walkthrough artifact.
