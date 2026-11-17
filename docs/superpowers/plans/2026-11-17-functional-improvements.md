# HyperFetch Functional Improvability Master Implementation Plan

> **For Orchestrator:** REQUIRED SUB-SKILL: Use subagent delegation (`invoke_subagent` with `Model: "flash"`, `Workspace: "inherit"`) for all file modifications.

**Goal:** Implement priority functional improvements and resolve UX, reliability, parity, and extension gaps identified in the review.

**Architecture:** 
- Swift/macOS: Integrate SHA-256 verification via CryptoKit into `DownloadEngine`, add pre-flight disk capacity checks, wire bridge token authentication, add task chunk overrides and queue move actions, and support Quiet Hours speed restoration and auto-open.
- Rust/Windows: Fix `resume_all()` concurrency cap, add connect timeouts, write state atomically on the same drive, make chunk count configurable, and port Quiet Hours scheduling.
- Chrome Extension: Add live download queue display in the popup, domain allow/block filters, configurable minimum file size, and bridge token header authorization.

**Tech Stack:** Swift 6, SwiftUI, CryptoKit, Rust, Tauri 2, Reqwest, Tokio, Chrome Extension MV3.

---

## Phase 1: File Integrity & Core Storage Reliability (Swift & Rust)
- Task 1.1: SHA-256 Checksum Verification Pipeline (Swift)
- Task 1.2: Pre-Flight Disk Capacity Verification (Swift & Rust)
- Task 1.3: Same-Drive Atomic State Writes & Flush on Exit (Rust & Swift)

## Phase 2: Windows Engine Parity & Network Reliability (Rust)
- Task 2.1: Enforce Concurrency Limit in Windows `resume_all()`
- Task 2.2: Add HTTP Connect Timeout & Socket Safeguards (Rust)
- Task 2.3: Configurable Dynamic Chunk Count on Windows
- Task 2.4: Port Bandwidth Scheduling (Quiet Hours) to Windows Engine

## Phase 3: macOS UI & State Refinements (Swift)
- Task 3.1: Add Per-Task Chunk Count Override in AddDownloadSheet
- Task 3.2: Queue Reordering Controls in UI
- Task 3.3: Quiet Hours State Restoration & Auto-Open on Completion
- Task 3.4: LocalhostBridge Shutdown & Stop Safety

## Phase 4: Security & Chrome Companion Extension Enhancements
- Task 4.1: Bridge Token Authentication Support
- Task 4.2: Live Download Queue Telemetry in Chrome Extension Popup
- Task 4.3: Domain Allow/Block Rules & Configurable Minimum File Size

## Phase 5: Verification & Full Regression Testing
- Task 5.1: Swift test suite verification
- Task 5.2: Rust cargo check verification
- Task 5.3: Chrome extension syntax & manifest verification
