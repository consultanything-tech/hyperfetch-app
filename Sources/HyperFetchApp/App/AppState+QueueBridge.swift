//
//  AppState+QueueBridge.swift
//  HyperFetchApp
//

import AppKit
import Foundation
import OSLog
import DownloadKit

@MainActor
extension AppState {
    // MARK: - Queue Listening & Lifecycle

    func startListeningToQueue() {
        updatesTask = Task { [weak self] in
            guard let self else { return }

            // Restore existing persisted tasks
            if let restored = try? await self.queueManager.restoreTasks() {
                self.handleQueueUpdate(restored, isInitialLoad: true)
            }

            for await updatedList in await self.queueManager.queueUpdates {
                self.handleQueueUpdate(updatedList, isInitialLoad: false)
            }
        }
    }

    func handleQueueUpdate(_ updatedTasks: [DownloadTaskModel], isInitialLoad: Bool) {
        var tasksToProcess = updatedTasks
        for i in 0..<tasksToProcess.count {
            let taskId = tasksToProcess[i].id
            if let timestamp = lastPauseTimestamps[taskId], pauseClock.now - timestamp < .milliseconds(600) {
                if tasksToProcess[i].status != .paused {
                    tasksToProcess[i].status = .paused
                    tasksToProcess[i].bytesPerSecond = 0.0
                }
            }
        }

        // Detect newly completed tasks to trigger notifications and audio alerts
        if !isInitialLoad {
            for task in tasksToProcess {
                if task.status == .completed && !previouslyCompletedTaskIds.contains(task.id) {
                    let bytes = task.totalBytes > 0 ? task.totalBytes : task.downloadedBytes
                    self.allTimeDownloadedBytes += bytes
                    self.allTimeCompletedCount += 1
                    UserDefaults.standard.set(self.allTimeDownloadedBytes, forKey: Self.allTimeDownloadedBytesKey)
                    UserDefaults.standard.set(self.allTimeCompletedCount, forKey: Self.allTimeCompletedCountKey)

                    if autoRevealOnCompletion {
                        NSWorkspace.shared.activateFileViewerSelecting([task.destinationURL])
                    }

                    if autoOpenOnCompletion {
                        openFile(task)
                    }

                    if showCompletionNotification {
                        notificationManager.sendDownloadCompletedNotification(task: task, playSound: false)
                    }
                    if playCompletionSound && completionSoundName != "Mute" {
                        NSSound(named: completionSoundName)?.play()
                    }
                }
            }
        }

        // Track completed IDs
        self.previouslyCompletedTaskIds = Set(
            tasksToProcess.filter { $0.status == .completed }.map(\.id)
        )

        if tasksToProcess.isEmpty {
            self.tasks = []
            self.selectedTaskIDs = []
            DockTileController.update(activeCount: 0, progress: 0.0)
            return
        }

        self.tasks = tasksToProcess

        // Maintain selection validity
        let validIds = Set(tasksToProcess.map(\.id))
        let previouslyHadSelection = !selectedTaskIDs.isEmpty
        selectedTaskIDs.formIntersection(validIds)
        if (isInitialLoad || previouslyHadSelection), selectedTaskIDs.isEmpty, let firstId = tasksToProcess.first?.id {
            selectedTaskIDs = [firstId]
        }

        // Update Dock icon badge and progress overlay
        DockTileController.update(activeCount: self.activeDownloadCount, progress: aggregateProgress)
    }

    // MARK: - Localhost Bridge

    public func setupLocalhostBridge() {
        // Register native messaging host manifests for Chromium browsers
        NativeHostManager.registerManifests()

        localhostBridge.onDownloadRequested = { [weak self] url, filename, autoStart, headers in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.handleIncomingDownload(
                    url: url,
                    filename: filename,
                    headers: headers ?? [:],
                    autoStart: autoStart || self.autoStartCapturedDownloads
                )
            }
        }

        localhostBridge.onSheetRequested = { [weak self] url, filename in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.bringToFront()
                self.presentAddSheet(url: url ?? "", filename: filename ?? "")
            }
        }

        localhostBridge.onAppearanceChangeRequested = { [weak self] mode in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if mode.lowercased() == "dark" {
                    self.appearanceMode = .dark
                } else if mode.lowercased() == "light" {
                    self.appearanceMode = .light
                } else {
                    self.appearanceMode = .system
                }
            }
        }

        localhostBridge.onTransfersRequested = { [weak self] in
            guard let self else { return [] }
            struct TransfersBox: @unchecked Sendable {
                let items: [[String: Any]]
            }
            let extract: @MainActor () -> TransfersBox = {
                TransfersBox(items: self.tasks.map { task in
                    [
                        "id": task.id.uuidString,
                        "filename": task.filename,
                        "total_bytes": task.totalBytes,
                        "downloaded_bytes": task.downloadedBytes,
                        "speed": Int64(task.bytesPerSecond),
                        "eta": Int64(task.eta),
                        "status": task.status.displayName.lowercased(),
                        "progress": task.progress
                    ]
                })
            }
            if Thread.isMainThread {
                return MainActor.assumeIsolated {
                    extract()
                }.items
            } else {
                return DispatchQueue.main.sync {
                    extract()
                }.items
            }
        }

        Task {
            do {
                let port = try await localhostBridge.start()
                await MainActor.run {
                    self.isBridgeRunning = true
                    self.bridgeListeningPort = port
                }
            } catch {
                logger.error("LocalhostBridge failed to start: \(error.localizedDescription, privacy: .public)")
                await MainActor.run {
                    self.isBridgeRunning = self.localhostBridge.isRunning
                    self.bridgeListeningPort = self.localhostBridge.listeningPort ?? self.localhostBridge.preferredPort
                }
            }
        }
    }

    /// Starts or configures the localhost bridge.
    public func startLocalhostBridge() {
        setupLocalhostBridge()
    }

    /// Stops the localhost bridge server.
    public func stopLocalhostBridge() {
        localhostBridge.stop()
        self.isBridgeRunning = false
    }

    /// Restarts the localhost bridge if stopped or offline.
    public func restartLocalhostBridge() {
        stopLocalhostBridge()
        setupLocalhostBridge()
    }

    /// Refreshes bridge status indicators from the active listener.
    public func refreshBridgeStatus() {
        self.isBridgeRunning = localhostBridge.isRunning
        if let port = localhostBridge.listeningPort {
            self.bridgeListeningPort = port
        }
    }

    // MARK: - Clipboard Monitor

    func setupClipboardMonitor() {
        clipboardMonitor.onDetected = { [weak self] url, filename in
            guard let self, self.autoCaptureClipboard else { return }
            self.handleClipboardDetected(url: url, filename: filename)
        }

        if autoCaptureClipboard {
            clipboardMonitor.start()
        }
    }

    func handleClipboardDetected(url: URL, filename: String) {
        if autoStartCapturedDownloads {
            if bringToFrontOnCapture {
                bringToFront()
                NSSound(named: "Pop")?.play()
            }
            addTask(url: url, filename: filename, autoStart: true)
        } else {
            FloatingHUDController.shared.show(url: url, filename: filename, appState: self)
        }
    }

    /// Handles an incoming download from localhost bridge, clipboard, or custom URL scheme.
    public func handleIncomingDownload(url: URL, filename: String?, headers: [String: String] = [:], autoStart: Bool) {
        if bringToFrontOnCapture {
            bringToFront()
            NSSound(named: "Pop")?.play()
        }

        let safeFilename = filename.map { FilenameResolver.sanitize($0) }

        if autoStart || autoStartCapturedDownloads {
            if sidebarSelection != .status(.all) && sidebarSelection != .status(.active) {
                sidebarSelection = .status(.active)
            }
            addTask(url: url, filename: safeFilename, headers: headers, autoStart: true)
        } else {
            let name = safeFilename ?? (url.path as NSString).lastPathComponent
            FloatingHUDController.shared.show(url: url, filename: name.isEmpty ? "download" : name, appState: self)
        }
    }

    // MARK: - URL Scheme Handling

    /// Presents the Add Download sheet pre-filled with the specified URL and optional filename.
    public func presentAddSheet(url: String = "", filename: String = "") {
        self.prefilledURL = url
        self.prefilledFilename = filename
        self.isAddSheetPresented = true
    }

    /// Handles external URLs opened via the custom hyperfetch:// scheme.
    public func handleIncomingURLScheme(_ url: URL) {
        bringToFront()

        guard url.scheme?.lowercased() == "hyperfetch" else { return }

        // Format 1: hyperfetch://open (brings app forward)
        let host = url.host?.lowercased()
        if host == "open" || url.path == "/open" {
            return
        }

        // Format: hyperfetch://settings?tab=general
        if host == "settings" || url.path == "/settings" {
            let tabString = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name.lowercased() == "tab" })?.value
            let tab = tabString.flatMap { SettingsTab(rawValue: $0.capitalized) } ?? .general
            openSettingsWindow(tab: tab)
            return
        }

        // Format: hyperfetch://appearance?mode=dark|light|system
        if host == "appearance" || url.path == "/appearance" {
            if let modeString = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name.lowercased() == "mode" })?.value {
                if modeString.lowercased() == "dark" {
                    appearanceMode = .dark
                } else if modeString.lowercased() == "light" {
                    appearanceMode = .light
                } else {
                    appearanceMode = .system
                }
            }
            return
        }

        // Format 2: hyperfetch://add?url=... or hyperfetch://download?url=...
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            if let targetURLString = components.queryItems?.first(where: { $0.name.lowercased() == "url" })?.value,
               let targetURL = URL(string: targetURLString),
               let targetScheme = targetURL.scheme?.lowercased(),
               (targetScheme == "http" || targetScheme == "https") {
                let filename = components.queryItems?.first(where: { $0.name.lowercased() == "filename" })?.value
                let safeFilename = filename.map { FilenameResolver.sanitize($0) } ?? ""
                presentAddSheet(url: targetURL.absoluteString, filename: safeFilename)
                return
            } else if components.queryItems?.contains(where: { $0.name.lowercased() == "url" }) == true || host == "add" || host == "download" {
                return
            }
        }

        // Format 3: hyperfetch://https://example.com/file.dmg
        let raw = url.absoluteString
        let prefix = "hyperfetch://"
        if raw.lowercased().hasPrefix(prefix) {
            let remainder = String(raw.dropFirst(prefix.count))
            let normalized = (remainder.hasPrefix("http://") || remainder.hasPrefix("https://")) ? remainder : "https://\(remainder)"
            if let targetURL = URL(string: normalized),
               let targetScheme = targetURL.scheme?.lowercased(),
               (targetScheme == "http" || targetScheme == "https") {
                let rawName = (targetURL.path as NSString).lastPathComponent
                let safeFilename = FilenameResolver.sanitize(rawName)
                presentAddSheet(url: targetURL.absoluteString, filename: safeFilename)
            }
        }
    }

    /// Convenience alias for handleIncomingURLScheme.
    public func handleURLScheme(_ url: URL) {
        handleIncomingURLScheme(url)
    }

    /// Convenience alias for handling incoming URLs.
    public func handleIncomingURL(_ url: URL) {
        handleIncomingURLScheme(url)
    }

    // MARK: - System & Finder Helpers

    /// Reveals the downloaded file in macOS Finder.
    public func openInFinder(task: DownloadTaskModel) {
        let url = task.destinationURL
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            // Open containing directory if file doesn't exist yet
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
    }

    /// Convenience alias to show file in Finder.
    public func showInFinder(_ task: DownloadTaskModel) {
        openInFinder(task: task)
    }

    /// Opens the downloaded file with its default application.
    public func openFile(task: DownloadTaskModel) {
        let url = task.destinationURL
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.open(url)
        }
    }

    /// Convenience overload to open a downloaded file.
    public func openFile(_ task: DownloadTaskModel) {
        openFile(task: task)
    }

    /// Copies the task's source URL to the system clipboard.
    public func copyDownloadLink(task: DownloadTaskModel) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(task.url.absoluteString, forType: .string)
    }

    /// Copies the local destination file path of a task to the macOS pasteboard.
    public func copyFilePath(task: DownloadTaskModel) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(task.destinationURL.path, forType: .string)
    }

    /// Reveals or previews a completed task file in Finder.
    public func quickLookFile(task: DownloadTaskModel) {
        NSWorkspace.shared.activateFileViewerSelecting([task.destinationURL])
    }

    /// Inspects the macOS system pasteboard for a valid HTTP/HTTPS URL.
    public func getValidURLFromClipboard() -> URL? {
        guard let text = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty,
              let url = URL(string: text),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              let host = url.host,
              !host.isEmpty else {
            return nil
        }
        return url
    }
}
