//
//  AppState.swift
//  HyperFetchApp
//

import AppKit
import Foundation
import SwiftUI
import DownloadKit

/// Filter option for download lifecycle status.
public enum StatusFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "All Downloads"
    case active = "Downloading"
    case completed = "Completed"
    case paused = "Paused"
    case failed = "Failed"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .all:
            return "tray.full"
        case .active:
            return "arrow.down.circle.fill"
        case .completed:
            return "checkmark.circle.fill"
        case .paused:
            return "pause.circle.fill"
        case .failed:
            return "exclamationmark.circle.fill"
        }
    }
}

/// Unified navigation item representing a selectable sidebar destination.
public enum SidebarItem: Hashable, Identifiable, Sendable {
    case status(StatusFilter)
    case category(DownloadCategory)

    public var id: String {
        switch self {
        case .status(let filter):
            return "status_\(filter.rawValue)"
        case .category(let category):
            return "category_\(category.rawValue)"
        }
    }
}

/// Bandwidth throttling preset.
public enum SpeedLimitPreset: String, CaseIterable, Identifiable, Sendable {
    case unlimited = "Unlimited"
    case fast = "Fast (10 MB/s)"
    case normal = "Normal (2 MB/s)"
    case snail = "Snail (500 KB/s)"

    public var id: String { rawValue }

    public var bytesPerSecond: Int64 {
        switch self {
        case .unlimited:
            return 0
        case .fast:
            return 10 * 1024 * 1024
        case .normal:
            return 2 * 1024 * 1024
        case .snail:
            return 500 * 1024
        }
    }
}

/// Central application state managing download tasks, user selections, and system integrations.
@MainActor
public final class AppState: ObservableObject {
    @Published public var tasks: [DownloadTaskModel] = []
    @Published public var sidebarSelection: SidebarItem? = .status(.all)
    @Published public var searchText: String = ""
    @Published public var speedLimitPreset: SpeedLimitPreset = .unlimited
    @Published public var isAddSheetPresented: Bool = false
    @Published public var selectedTaskId: UUID? = nil
    @Published public var taskPendingDeletion: DownloadTaskModel? = nil
    @Published public var showDeleteConfirmation: Bool = false

    /// Backward compatibility accessors for statusFilter and selectedCategory
    public var statusFilter: StatusFilter {
        get {
            if case .status(let filter) = sidebarSelection {
                return filter
            }
            return .all
        }
        set {
            sidebarSelection = .status(newValue)
        }
    }

    public var selectedCategory: DownloadCategory? {
        get {
            if case .category(let category) = sidebarSelection {
                return category
            }
            return nil
        }
        set {
            if let newValue {
                sidebarSelection = .category(newValue)
            } else {
                sidebarSelection = .status(.all)
            }
        }
    }

    /// Whether HyperFetch automatically monitors the macOS pasteboard for copied file links.
    @Published public var autoCaptureClipboard: Bool = true {
        didSet {
            if autoCaptureClipboard {
                clipboardMonitor.start()
            } else {
                clipboardMonitor.stop()
            }
        }
    }

    /// When true, captured downloads start immediately without showing the Floating Quick-Add HUD.
    @Published public var autoStartCapturedDownloads: Bool = false

    /// Prefilled URL when presenting AddDownloadSheet via HUD customize or external call.
    @Published public var prefilledURL: String = ""

    /// Prefilled filename when presenting AddDownloadSheet.
    @Published public var prefilledFilename: String = ""

    public let queueManager: QueueManager
    public let notificationManager = NotificationManager.shared
    public let localhostBridge: LocalhostBridge
    public let clipboardMonitor: ClipboardMonitor

    private var updatesTask: Task<Void, Never>?
    private var previouslyCompletedTaskIds: Set<UUID> = []

    public init(
        queueManager: QueueManager? = nil,
        localhostBridge: LocalhostBridge? = nil,
        clipboardMonitor: ClipboardMonitor? = nil
    ) {
        let qm = queueManager ?? QueueManager(
            statePersister: JSONStatePersister(),
            rateLimiter: TokenBucketRateLimiter(bytesPerSecond: 0),
            maxConcurrentDownloads: 4
        )
        self.queueManager = qm
        self.localhostBridge = localhostBridge ?? LocalhostBridge()
        self.clipboardMonitor = clipboardMonitor ?? ClipboardMonitor.shared

        notificationManager.requestAuthorization()

        // Initialize with sample demo tasks if queue is empty
        if self.tasks.isEmpty {
            self.tasks = Self.sampleTasks
            self.selectedTaskId = self.tasks.first?.id
        }

        // Start listening to the QueueManager stream
        startListeningToQueue()

        // Setup background bridges and clipboard monitoring
        setupLocalhostBridge()
        setupClipboardMonitor()
    }

    deinit {
        updatesTask?.cancel()
        localhostBridge.stop()
        let monitor = clipboardMonitor
        Task { @MainActor in
            monitor.stop()
        }
    }

    // MARK: - Computed Properties

    /// Retrieves the currently selected task, if any.
    public var selectedTask: DownloadTaskModel? {
        guard let selectedTaskId else { return nil }
        return tasks.first(where: { $0.id == selectedTaskId })
    }

    /// Tasks filtered by the current sidebar selection (status filter or category) and search query.
    public var filteredTasks: [DownloadTaskModel] {
        tasks.filter { task in
            // 1. Sidebar Selection (Status or Category)
            switch sidebarSelection {
            case .status(let filter):
                let matchesStatus: Bool
                switch filter {
                case .all:
                    matchesStatus = true
                case .active:
                    matchesStatus = (task.status == .downloading || task.status == .probing || task.status == .idle)
                case .completed:
                    matchesStatus = (task.status == .completed)
                case .paused:
                    matchesStatus = (task.status == .paused)
                case .failed:
                    if case .failed = task.status {
                        matchesStatus = true
                    } else {
                        matchesStatus = false
                    }
                }
                guard matchesStatus else { return false }

            case .category(let category):
                if category != .all {
                    guard task.category == category else { return false }
                }

            case nil:
                break
            }

            // 2. Search Query
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !query.isEmpty {
                let matchesName = task.filename.localizedCaseInsensitiveContains(query)
                let matchesURL = task.url.absoluteString.localizedCaseInsensitiveContains(query)
                guard matchesName || matchesURL else { return false }
            }

            return true
        }
    }

    /// Total active download speed in bytes per second.
    public var totalDownloadSpeed: Double {
        tasks.reduce(0.0) { sum, task in
            if task.status == .downloading {
                return sum + task.bytesPerSecond
            }
            return sum
        }
    }

    /// Formatted representation of the aggregate download speed (e.g., "3.2 MB/s").
    public var formattedTotalSpeed: String {
        Self.formatSpeed(totalDownloadSpeed)
    }

    /// Count of currently active (downloading or probing) tasks.
    public var activeDownloadCount: Int {
        tasks.filter { $0.status == .downloading || $0.status == .probing }.count
    }

    /// Count of completed tasks.
    public var completedDownloadCount: Int {
        tasks.filter { $0.status == .completed }.count
    }

    /// Count of paused tasks.
    public var pausedDownloadCount: Int {
        tasks.filter { $0.status == .paused }.count
    }

    /// Returns the task count for a given status filter.
    public func count(for filter: StatusFilter) -> Int {
        switch filter {
        case .all:
            return tasks.count
        case .active:
            return activeDownloadCount
        case .completed:
            return completedDownloadCount
        case .paused:
            return pausedDownloadCount
        case .failed:
            return tasks.filter { if case .failed = $0.status { true } else { false } }.count
        }
    }

    /// Returns the task count for a given category.
    public func count(for category: DownloadCategory) -> Int {
        if category == .all {
            return tasks.count
        }
        return tasks.filter { $0.category == category }.count
    }

    // MARK: - Queue Actions

    /// Adds a new download task.
    public func addTask(
        url: URL,
        destinationURL: URL? = nil,
        filename: String? = nil,
        autoStart: Bool = true
    ) {
        Task {
            do {
                let newTask = try await queueManager.addTask(
                    url: url,
                    destinationURL: destinationURL,
                    filename: filename,
                    autoStart: autoStart
                )
                self.selectedTaskId = newTask.id
            } catch {
                print("Failed to add task: \(error.localizedDescription)")
            }
        }
    }

    /// Pauses an active or queued download task.
    public func pause(id: UUID) {
        Task {
            await queueManager.pauseTask(id: id)
        }
    }

    /// Resumes a paused or failed download task.
    public func resume(id: UUID) {
        Task {
            try? await queueManager.resumeTask(id: id)
        }
    }

    /// Cancels a download task.
    public func cancel(id: UUID) {
        Task {
            await queueManager.cancelTask(id: id)
        }
    }

    /// Removes a task from the list and optionally deletes its file from disk.
    public func remove(id: UUID, deleteFile: Bool = false) {
        if selectedTaskId == id {
            selectedTaskId = nil
        }
        Task {
            try? await queueManager.removeTask(id: id, deleteFile: deleteFile)
        }
    }

    /// Prompts the delete confirmation sheet/dialog for the given or selected task.
    public func promptDelete(task: DownloadTaskModel? = nil) {
        let target = task ?? selectedTask
        guard let target else { return }
        self.taskPendingDeletion = target
        self.showDeleteConfirmation = true
    }

    /// Toggles pause / resume for the currently selected task.
    public func togglePauseSelected() {
        guard let selectedTask else { return }
        switch selectedTask.status {
        case .downloading, .probing:
            pause(id: selectedTask.id)
        case .paused, .idle, .failed:
            resume(id: selectedTask.id)
        case .completed:
            break
        }
    }

    /// Opens the completed file for the currently selected task.
    public func openSelectedFile() {
        guard let selectedTask, selectedTask.status == .completed else { return }
        openFile(task: selectedTask)
    }

    /// Reveals the currently selected task's destination in Finder.
    public func revealSelectedInFinder() {
        guard let selectedTask else { return }
        openInFinder(task: selectedTask)
    }

    /// Pauses all downloads.
    public func pauseAll() {
        Task {
            await queueManager.pauseAll()
        }
    }

    /// Resumes all paused downloads.
    public func resumeAll() {
        Task {
            try? await queueManager.resumeAll()
        }
    }

    /// Updates the global download speed limit preset.
    public func setSpeedLimit(preset: SpeedLimitPreset) {
        self.speedLimitPreset = preset
        Task {
            await queueManager.setSpeedLimit(preset.bytesPerSecond)
        }
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

    /// Opens the downloaded file with its default application.
    public func openFile(task: DownloadTaskModel) {
        let url = task.destinationURL
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.open(url)
        }
    }

    /// Copies the task's source URL to the system clipboard.
    public func copyDownloadLink(task: DownloadTaskModel) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(task.url.absoluteString, forType: .string)
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

    // MARK: - Download Catching & Integration

    /// Presents the Add Download sheet pre-filled with the specified URL and optional filename.
    public func presentAddSheet(url: String = "", filename: String = "") {
        self.prefilledURL = url
        self.prefilledFilename = filename
        self.isAddSheetPresented = true
    }

    private func setupLocalhostBridge() {
        localhostBridge.onDownloadRequested = { [weak self] url, filename, autoStart in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.handleIncomingDownload(
                    url: url,
                    filename: filename,
                    autoStart: autoStart || self.autoStartCapturedDownloads
                )
            }
        }

        Task {
            do {
                _ = try await localhostBridge.start()
            } catch {
                print("LocalhostBridge failed to start: \(error.localizedDescription)")
            }
        }
    }

    private func setupClipboardMonitor() {
        clipboardMonitor.onDetected = { [weak self] url, filename in
            guard let self, self.autoCaptureClipboard else { return }
            self.handleClipboardDetected(url: url, filename: filename)
        }

        if autoCaptureClipboard {
            clipboardMonitor.start()
        }
    }

    private func handleClipboardDetected(url: URL, filename: String) {
        if autoStartCapturedDownloads {
            addTask(url: url, filename: filename, autoStart: true)
        } else {
            FloatingHUDController.shared.show(url: url, filename: filename, appState: self)
        }
    }

    /// Handles an incoming download from localhost bridge, clipboard, or custom URL scheme.
    public func handleIncomingDownload(url: URL, filename: String?, autoStart: Bool) {
        if autoStart || autoStartCapturedDownloads {
            addTask(url: url, filename: filename, autoStart: true)
        } else {
            let name = filename ?? (url.path as NSString).lastPathComponent
            FloatingHUDController.shared.show(url: url, filename: name.isEmpty ? "download" : name, appState: self)
        }
    }

    /// Handles external URLs opened via the custom hyperfetch:// scheme.
    public func handleIncomingURLScheme(_ url: URL) {
        guard url.scheme?.lowercased() == "hyperfetch" else { return }

        // Format 1: hyperfetch://open (brings app forward)
        let host = url.host?.lowercased()
        if host == "open" || url.path == "/open" {
            NSApp.activate(ignoringOtherApps: true)
            for window in NSApp.windows where window.canBecomeMain {
                window.makeKeyAndOrderFront(nil)
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
                let autoStart = components.queryItems?.first(where: { $0.name.lowercased() == "autostart" })?.value.map { $0.lowercased() != "false" && $0 != "0" } ?? true

                handleIncomingDownload(url: targetURL, filename: filename, autoStart: autoStart)
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
                let filename = (targetURL.path as NSString).lastPathComponent
                handleIncomingDownload(url: targetURL, filename: filename.isEmpty ? nil : filename, autoStart: true)
            }
        }
    }

    // MARK: - Formatters

    /// Formats transfer speed into readable strings.
    public static func formatSpeed(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond > 0 else { return "0 B/s" }
        if bytesPerSecond >= 1024 * 1024 * 1024 {
            return String(format: "%.1f GB/s", bytesPerSecond / (1024 * 1024 * 1024))
        } else if bytesPerSecond >= 1024 * 1024 {
            return String(format: "%.1f MB/s", bytesPerSecond / (1024 * 1024))
        } else if bytesPerSecond >= 1024 {
            return String(format: "%.1f KB/s", bytesPerSecond / 1024)
        } else {
            return String(format: "%.0f B/s", bytesPerSecond)
        }
    }

    /// Formats byte counts into localized file size strings.
    public static func formatBytes(_ bytes: Int64) -> String {
        guard bytes >= 0 else { return "Unknown size" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// Calculates remaining time formatted as human-readable string.
    public static func formatETA(remainingBytes: Int64, bytesPerSecond: Double) -> String {
        guard remainingBytes > 0, bytesPerSecond > 100 else { return "--" }
        let seconds = Double(remainingBytes) / bytesPerSecond
        if seconds >= 3600 {
            let hours = Int(seconds) / 3600
            let minutes = (Int(seconds) % 3600) / 60
            return "\(hours)h \(minutes)m remaining"
        } else if seconds >= 60 {
            let minutes = Int(seconds) / 60
            let secs = Int(seconds) % 60
            return "\(minutes)m \(secs)s remaining"
        } else {
            return "\(Int(seconds))s remaining"
        }
    }

    // MARK: - Private Queue Observation

    private func startListeningToQueue() {
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

    private func handleQueueUpdate(_ updatedTasks: [DownloadTaskModel], isInitialLoad: Bool) {
        // If queue is empty on initial load, preserve or initialize sample demo tasks
        if updatedTasks.isEmpty {
            if self.tasks.isEmpty {
                self.tasks = Self.sampleTasks
                self.selectedTaskId = self.tasks.first?.id
            }
            if isInitialLoad {
                return
            }
        }

        // Detect newly completed tasks to trigger notifications
        if !isInitialLoad {
            for task in updatedTasks {
                if task.status == .completed && !previouslyCompletedTaskIds.contains(task.id) {
                    notificationManager.sendDownloadCompletedNotification(task: task)
                }
            }
        }

        // Track completed IDs
        self.previouslyCompletedTaskIds = Set(
            updatedTasks.filter { $0.status == .completed }.map(\.id)
        )

        self.tasks = updatedTasks

        if selectedTaskId == nil || !updatedTasks.contains(where: { $0.id == self.selectedTaskId }) {
            self.selectedTaskId = updatedTasks.first?.id
        }

        // Update Dock icon badge
        DockTileController.updateBadge(activeCount: self.activeDownloadCount)
    }

    // MARK: - Sample Demo Tasks

    /// Sample demo tasks populated when launching HyperFetch with an empty queue.
    public static var sampleTasks: [DownloadTaskModel] {
        let chunkCount = 8
        let totalSize: Int64 = 3_435_973_836 // 3.2 GB
        let chunkSize = totalSize / Int64(chunkCount)
        var chunks: [Chunk] = []
        var downloadedBytes: Int64 = 0

        for i in 0..<chunkCount {
            let start = Int64(i) * chunkSize
            let end = (i == chunkCount - 1) ? totalSize - 1 : (start + chunkSize - 1)
            let length = end - start + 1
            let (status, bytes): (ChunkStatus, Int64) = {
                switch i {
                case 0...2:
                    return (.completed, length)
                case 3:
                    let b = Int64(Double(length) * 0.75)
                    return (.downloading, b)
                case 4:
                    let b = Int64(Double(length) * 0.50)
                    return (.downloading, b)
                case 5:
                    let b = Int64(Double(length) * 0.20)
                    return (.downloading, b)
                default:
                    return (.pending, 0)
                }
            }()
            downloadedBytes += bytes
            chunks.append(Chunk(
                id: UUID(),
                index: i,
                startOffset: start,
                endOffset: end,
                bytesDownloaded: bytes,
                status: status
            ))
        }

        let task1 = DownloadTaskModel(
            id: UUID(),
            url: URL(string: "https://download.developer.apple.com/Developer_Tools/Xcode_16.2/Xcode_16.2.xip")!,
            filename: "Xcode_16.2_Release.xip",
            totalBytes: totalSize,
            downloadedBytes: downloadedBytes,
            status: .downloading,
            chunks: chunks,
            supportsRange: true,
            createdAt: Date().addingTimeInterval(-1200),
            category: .applications,
            bytesPerSecond: 18_420_000
        )

        let task2 = DownloadTaskModel(
            id: UUID(),
            url: URL(string: "https://swcdn.apple.com/content/downloads/macOS_Sequoia_15.3.pkg")!,
            filename: "macOS_Sequoia_15.3_Installer.pkg",
            totalBytes: 14_520_000_000,
            downloadedBytes: 14_520_000_000,
            status: .completed,
            chunks: [
                Chunk(index: 0, startOffset: 0, endOffset: 3_630_000_000 - 1, bytesDownloaded: 3_630_000_000, status: .completed),
                Chunk(index: 1, startOffset: 3_630_000_000, endOffset: 7_260_000_000 - 1, bytesDownloaded: 3_630_000_000, status: .completed),
                Chunk(index: 2, startOffset: 7_260_000_000, endOffset: 10_890_000_000 - 1, bytesDownloaded: 3_630_000_000, status: .completed),
                Chunk(index: 3, startOffset: 10_890_000_000, endOffset: 14_520_000_000 - 1, bytesDownloaded: 3_630_000_000, status: .completed)
            ],
            supportsRange: true,
            createdAt: Date().addingTimeInterval(-86400),
            completedAt: Date().addingTimeInterval(-3600),
            category: .applications,
            bytesPerSecond: 0
        )

        let task3 = DownloadTaskModel(
            id: UUID(),
            url: URL(string: "https://releases.ubuntu.com/24.04/ubuntu-24.04-desktop-amd64.iso")!,
            filename: "ubuntu-24.04-desktop-amd64.iso",
            totalBytes: 6_291_456_000,
            downloadedBytes: 2_516_582_400,
            status: .paused,
            chunks: [
                Chunk(index: 0, startOffset: 0, endOffset: 1_572_864_000 - 1, bytesDownloaded: 1_572_864_000, status: .completed),
                Chunk(index: 1, startOffset: 1_572_864_000, endOffset: 3_145_728_000 - 1, bytesDownloaded: 943_718_400, status: .pending),
                Chunk(index: 2, startOffset: 3_145_728_000, endOffset: 4_718_592_000 - 1, bytesDownloaded: 0, status: .pending),
                Chunk(index: 3, startOffset: 4_718_592_000, endOffset: 6_291_456_000 - 1, bytesDownloaded: 0, status: .pending)
            ],
            supportsRange: true,
            createdAt: Date().addingTimeInterval(-3600),
            category: .archives,
            bytesPerSecond: 0
        )

        return [task1, task2, task3]
    }
}
