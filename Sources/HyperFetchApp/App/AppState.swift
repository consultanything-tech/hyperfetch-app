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

/// Sorting option for the download list.
public enum SortOption: String, CaseIterable, Identifiable, Sendable {
    case dateNewest = "Date Added (Newest)"
    case dateOldest = "Date Added (Oldest)"
    case nameAZ = "Name (A to Z)"
    case nameZA = "Name (Z to A)"
    case sizeLargest = "File Size (Largest)"
    case sizeSmallest = "File Size (Smallest)"
    case progress = "Progress"
    case speed = "Transfer Speed"

    public var id: String { rawValue }
}

/// Active tab in the native Settings window.
public enum SettingsTab: String, CaseIterable, Identifiable, Hashable, Sendable {
    case general = "General"
    case automation = "Automation"
    case browser = "Browser"
    case updates = "Updates"

    public var id: String { rawValue }
}

/// Application color theme appearance setting.
public enum AppearanceMode: String, CaseIterable, Identifiable, Sendable {
    case system = "System"
    case dark = "Dark"
    case light = "Light"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .system: return "circle.righthalf.filled"
        case .dark: return "moon.fill"
        case .light: return "sun.max.fill"
        }
    }
}

/// Central application state managing download tasks, user selections, and system integrations.
@MainActor
public final class AppState: ObservableObject {
    @Published public var tasks: [DownloadTaskModel] = [] {
        didSet { _cachedFilteredTasks = nil }
    }
    @Published public var sidebarSelection: SidebarItem? = .status(.all) {
        didSet {
            _cachedFilteredTasks = nil
            NSLog("🎯 [HyperFetch] sidebarSelection changed to: %@", String(describing: sidebarSelection))
        }
    }
    @Published public var searchText: String = "" {
        didSet { _cachedFilteredTasks = nil }
    }
    @Published public var speedLimitPreset: SpeedLimitPreset = .unlimited
    @Published public var selectedSettingsTab: SettingsTab = .general
    public var openSettingsHandler: (@MainActor () -> Void)?
    @Published public var isBridgeRunning: Bool = false
    @Published public var bridgeListeningPort: UInt16 = 31415
    @Published public var isAddSheetPresented: Bool = false
    @Published public var selectedTaskIDs: Set<UUID> = []
    @Published public var taskPendingDeletion: DownloadTaskModel? = nil
    @Published public var tasksPendingDeletion: [DownloadTaskModel] = []
    @Published public var showDeleteConfirmation: Bool = false
    @Published public var sortOption: SortOption {
        didSet {
            UserDefaults.standard.set(sortOption.rawValue, forKey: Self.sortOptionKey)
            _cachedFilteredTasks = nil
        }
    }
    @Published public var appearanceMode: AppearanceMode {
        didSet {
            UserDefaults.standard.set(appearanceMode.rawValue, forKey: Self.appearanceModeKey)
            applyAppearance()
        }
    }

    private var _cachedFilteredTasks: [DownloadTaskModel]?

    /// Backward compatibility accessor for single-task selection.
    public var selectedTaskId: UUID? {
        get { selectedTaskIDs.first }
        set {
            if let newValue {
                if selectedTaskIDs != [newValue] {
                    selectedTaskIDs = [newValue]
                }
            } else {
                if !selectedTaskIDs.isEmpty {
                    selectedTaskIDs = []
                }
            }
        }
    }

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

    /// Prefilled URL when presenting AddDownloadSheet via HUD customize or external call.
    @Published public var prefilledURL: String = ""

    /// Prefilled filename when presenting AddDownloadSheet.
    @Published public var prefilledFilename: String = ""

    private static let defaultDownloadDirectoryKey = "com.hyperfetch.defaultDownloadDirectory"
    private static let defaultChunkCountKey = "com.hyperfetch.defaultChunkCount"
    private static let sortOptionKey = "com.hyperfetch.sortOption"
    private static let appearanceModeKey = "com.hyperfetch.appearanceMode"
    private static let maxConcurrentDownloadsKey = "com.hyperfetch.maxConcurrentDownloads"
    private static let speedLimitPresetKey = "com.hyperfetch.speedLimitPreset"
    private static let autoCaptureClipboardKey = "com.hyperfetch.autoCaptureClipboard"
    private static let autoStartCapturedDownloadsKey = "com.hyperfetch.autoStartCapturedDownloads"
    private static let bringToFrontOnCaptureKey = "com.hyperfetch.bringToFrontOnCapture"
    private static let playCompletionSoundKey = "com.hyperfetch.playCompletionSound"
    private static let showCompletionNotificationKey = "com.hyperfetch.showCompletionNotification"

    /// Maximum concurrent downloads allowed simultaneously (1 to 8).
    @Published public var maxConcurrentDownloads: Int {
        didSet {
            let clamped = max(1, min(8, maxConcurrentDownloads))
            if clamped != maxConcurrentDownloads {
                maxConcurrentDownloads = clamped
                return
            }
            UserDefaults.standard.set(maxConcurrentDownloads, forKey: Self.maxConcurrentDownloadsKey)
            Task {
                await queueManager.setMaxConcurrentDownloads(maxConcurrentDownloads)
            }
        }
    }

    /// Whether HyperFetch automatically monitors the macOS pasteboard for copied file links.
    @Published public var autoCaptureClipboard: Bool {
        didSet {
            UserDefaults.standard.set(autoCaptureClipboard, forKey: Self.autoCaptureClipboardKey)
            if autoCaptureClipboard {
                clipboardMonitor.start()
            } else {
                clipboardMonitor.stop()
            }
        }
    }

    /// When true, captured downloads start immediately without showing the Floating Quick-Add HUD.
    @Published public var autoStartCapturedDownloads: Bool {
        didSet {
            UserDefaults.standard.set(autoStartCapturedDownloads, forKey: Self.autoStartCapturedDownloadsKey)
        }
    }

    /// Whether HyperFetch automatically activates and brings itself to the foreground when a download is captured.
    @Published public var bringToFrontOnCapture: Bool = true {
        didSet {
            UserDefaults.standard.set(bringToFrontOnCapture, forKey: Self.bringToFrontOnCaptureKey)
        }
    }

    /// Whether to play a sound effect upon download completion.
    @Published public var playCompletionSound: Bool {
        didSet {
            UserDefaults.standard.set(playCompletionSound, forKey: Self.playCompletionSoundKey)
        }
    }

    /// Whether to show a system banner notification upon download completion.
    @Published public var showCompletionNotification: Bool {
        didSet {
            UserDefaults.standard.set(showCompletionNotification, forKey: Self.showCompletionNotificationKey)
        }
    }

    /// Locates the absolute URL of the extensions/chrome directory on disk.
    public var extensionDirectoryURL: URL {
        let fileManager = FileManager.default

        // 1. Check App Bundle Resources (production packaged builds)
        if let resourceURL = Bundle.main.resourceURL?.appendingPathComponent("extensions/chrome"),
           fileManager.fileExists(atPath: resourceURL.path) {
            return resourceURL
        }

        // 2. Check relative to source repo via #filePath (development / debug builds)
        let sourceBase = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // App
            .deletingLastPathComponent() // HyperFetchApp
            .deletingLastPathComponent() // Sources
            .deletingLastPathComponent() // Project root
            .appendingPathComponent("extensions/chrome")
        if fileManager.fileExists(atPath: sourceBase.path) {
            return sourceBase
        }

        // 3. Check current working directory
        let cwdPath = URL(fileURLWithPath: fileManager.currentDirectoryPath).appendingPathComponent("extensions/chrome")
        if fileManager.fileExists(atPath: cwdPath.path) {
            return cwdPath
        }

        // 4. Check sibling to App bundle
        let bundleSibling = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("extensions/chrome")
        if fileManager.fileExists(atPath: bundleSibling.path) {
            return bundleSibling
        }

        return sourceBase
    }

    /// Absolute string path to the Chrome extension directory.
    public var extensionDirectoryPath: String {
        extensionDirectoryURL.path
    }

    /// Default download folder preference persisted via UserDefaults.
    public var defaultDownloadDirectoryURL: URL {
        get {
            if let savedPath = UserDefaults.standard.string(forKey: Self.defaultDownloadDirectoryKey), !savedPath.isEmpty {
                return URL(fileURLWithPath: savedPath)
            }
            return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
        }
        set {
            objectWillChange.send()
            UserDefaults.standard.set(newValue.path, forKey: Self.defaultDownloadDirectoryKey)
        }
    }

    /// Default acceleration chunk count persisted via UserDefaults.
    public var defaultChunkCount: Int {
        get {
            let saved = UserDefaults.standard.integer(forKey: Self.defaultChunkCountKey)
            return saved > 0 ? saved : 4
        }
        set {
            objectWillChange.send()
            UserDefaults.standard.set(newValue, forKey: Self.defaultChunkCountKey)
        }
    }

    public let queueManager: QueueManager
    public let notificationManager = NotificationManager.shared
    public let localhostBridge: LocalhostBridge
    public let clipboardMonitor: ClipboardMonitor

    private var updatesTask: Task<Void, Never>?
    private var previouslyCompletedTaskIds: Set<UUID> = []
    nonisolated(unsafe) private var themeObserver: (any NSObjectProtocol)?

    public init(
        queueManager: QueueManager? = nil,
        localhostBridge: LocalhostBridge? = nil,
        clipboardMonitor: ClipboardMonitor? = nil
    ) {
        let savedMax = UserDefaults.standard.integer(forKey: Self.maxConcurrentDownloadsKey)
        let effectiveMax = savedMax > 0 ? max(1, min(8, savedMax)) : 4
        self.maxConcurrentDownloads = effectiveMax

        let initialSpeed: SpeedLimitPreset
        if let savedSpeed = UserDefaults.standard.string(forKey: Self.speedLimitPresetKey),
           let preset = SpeedLimitPreset(rawValue: savedSpeed) {
            initialSpeed = preset
        } else {
            initialSpeed = .unlimited
        }
        self.speedLimitPreset = initialSpeed

        if UserDefaults.standard.object(forKey: Self.playCompletionSoundKey) == nil {
            self.playCompletionSound = true
        } else {
            self.playCompletionSound = UserDefaults.standard.bool(forKey: Self.playCompletionSoundKey)
        }

        if UserDefaults.standard.object(forKey: Self.showCompletionNotificationKey) == nil {
            self.showCompletionNotification = true
        } else {
            self.showCompletionNotification = UserDefaults.standard.bool(forKey: Self.showCompletionNotificationKey)
        }

        if UserDefaults.standard.object(forKey: Self.autoCaptureClipboardKey) == nil {
            self.autoCaptureClipboard = true
        } else {
            self.autoCaptureClipboard = UserDefaults.standard.bool(forKey: Self.autoCaptureClipboardKey)
        }

        self.autoStartCapturedDownloads = UserDefaults.standard.bool(forKey: Self.autoStartCapturedDownloadsKey)

        if UserDefaults.standard.object(forKey: Self.bringToFrontOnCaptureKey) == nil {
            self.bringToFrontOnCapture = true
        } else {
            self.bringToFrontOnCapture = UserDefaults.standard.bool(forKey: Self.bringToFrontOnCaptureKey)
        }

        if let savedSort = UserDefaults.standard.string(forKey: Self.sortOptionKey),
           let option = SortOption(rawValue: savedSort) {
            self.sortOption = option
        } else {
            self.sortOption = .dateNewest
        }

        if let savedAppearance = UserDefaults.standard.string(forKey: Self.appearanceModeKey),
           let mode = AppearanceMode(rawValue: savedAppearance) {
            self.appearanceMode = mode
        } else {
            self.appearanceMode = .system
        }

        let speedBytes = initialSpeed.bytesPerSecond
        let qm = queueManager ?? QueueManager(
            statePersister: JSONStatePersister(),
            rateLimiter: TokenBucketRateLimiter(bytesPerSecond: speedBytes),
            maxConcurrentDownloads: effectiveMax
        )
        self.queueManager = qm
        self.localhostBridge = localhostBridge ?? LocalhostBridge()
        self.clipboardMonitor = clipboardMonitor ?? ClipboardMonitor.shared

        if queueManager != nil {
            Task { [qm] in
                await qm.setMaxConcurrentDownloads(effectiveMax)
                await qm.setSpeedLimit(speedBytes)
            }
        }

        notificationManager.requestAuthorization()

        // Start listening to the QueueManager stream
        startListeningToQueue()

        // Setup background bridges and clipboard monitoring
        setupLocalhostBridge()
        setupClipboardMonitor()
        applyAppearance()

        HyperFetchServiceProvider.shared.appState = self

        // Observe system theme changes for .system appearance mode
        themeObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.appearanceMode == .system else { return }
                self.objectWillChange.send()
                self.applyAppearance()
            }
        }
    }

    deinit {
        updatesTask?.cancel()
        localhostBridge.stop()
        if let themeObserver {
            DistributedNotificationCenter.default().removeObserver(themeObserver)
        }
        let monitor = clipboardMonitor
        Task { @MainActor in
            monitor.stop()
        }
    }

    // MARK: - Appearance Management

    /// Determines whether the host macOS system interface is currently in Dark Mode.
    public var isSystemDark: Bool {
        if let style = CFPreferencesCopyAppValue("AppleInterfaceStyle" as CFString, kCFPreferencesAnyApplication) as? String {
            return style.caseInsensitiveCompare("dark") == .orderedSame
        }
        return false
    }

    public var preferredColorScheme: ColorScheme? {
        switch appearanceMode {
        case .system:
            return isSystemDark ? .dark : .light
        case .dark:
            return .dark
        case .light:
            return .light
        }
    }

    public func applyAppearance() {
        let targetAppearance: NSAppearance?
        switch appearanceMode {
        case .system:
            targetAppearance = isSystemDark ? NSAppearance(named: .darkAqua) : NSAppearance(named: .aqua)
        case .dark:
            targetAppearance = NSAppearance(named: .darkAqua)
        case .light:
            targetAppearance = NSAppearance(named: .aqua)
        }

        NSApp.appearance = targetAppearance
        for window in NSApp.windows {
            window.appearance = targetAppearance
            window.invalidateShadow()
            window.viewsNeedDisplay = true
            window.contentView?.needsDisplay = true
        }
    }

    // MARK: - Computed Properties

    /// Retrieves the currently selected task, if any.
    public var selectedTask: DownloadTaskModel? {
        guard let selectedTaskId else { return nil }
        return tasks.first(where: { $0.id == selectedTaskId })
    }

    /// Retrieves all currently selected tasks.
    public var selectedTasks: [DownloadTaskModel] {
        tasks.filter { selectedTaskIDs.contains($0.id) }
    }

    // MARK: - Selection Management

    /// Whether any of the selected tasks are currently active (downloading or probing).
    public var hasActiveSelectedTasks: Bool {
        selectedTasks.contains { $0.status == .downloading || $0.status == .probing }
    }

    /// Whether any of the selected tasks can be resumed (paused, idle, or failed).
    public var hasResumableSelectedTasks: Bool {
        selectedTasks.contains { task in
            switch task.status {
            case .paused, .idle, .failed:
                return true
            case .downloading, .probing, .completed:
                return false
            }
        }
    }

    /// Indicates whether all currently filtered tasks are selected.
    public var isAllSelected: Bool {
        !filteredTasks.isEmpty && filteredTasks.allSatisfy { selectedTaskIDs.contains($0.id) }
    }

    /// Indicates whether some, but not all, currently filtered tasks are selected.
    public var isPartiallySelected: Bool {
        !isAllSelected && filteredTasks.contains { selectedTaskIDs.contains($0.id) }
    }

    /// Selects all tasks currently visible under active filters.
    public func selectAll() {
        selectedTaskIDs = Set(filteredTasks.map(\.id))
    }

    /// Deselects all tasks.
    public func deselectAll() {
        selectedTaskIDs = []
    }

    /// Toggles the selection state for a specific task ID.
    public func toggleSelection(id: UUID) {
        if selectedTaskIDs.contains(id) {
            selectedTaskIDs.remove(id)
        } else {
            selectedTaskIDs.insert(id)
        }
    }

    /// Toggles selection between all filtered tasks and none.
    public func toggleSelectAll() {
        if isAllSelected {
            deselectAll()
        } else {
            selectAll()
        }
    }

    /// Tasks filtered by the current sidebar selection (status filter or category), search query, and sort option.
    public var filteredTasks: [DownloadTaskModel] {
        if let cached = _cachedFilteredTasks {
            return cached
        }
        let computed = computeFilteredTasks()
        _cachedFilteredTasks = computed
        return computed
    }

    private func computeFilteredTasks() -> [DownloadTaskModel] {
        let filtered = tasks.filter { task in
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

        return filtered.sorted { a, b in
            switch sortOption {
            case .dateNewest:
                if a.createdAt != b.createdAt {
                    return a.createdAt > b.createdAt
                }
                return a.filename.localizedStandardCompare(b.filename) == .orderedAscending
            case .dateOldest:
                if a.createdAt != b.createdAt {
                    return a.createdAt < b.createdAt
                }
                return a.filename.localizedStandardCompare(b.filename) == .orderedAscending
            case .nameAZ:
                return a.filename.localizedStandardCompare(b.filename) == .orderedAscending
            case .nameZA:
                return a.filename.localizedStandardCompare(b.filename) == .orderedDescending
            case .sizeLargest:
                if a.totalBytes != b.totalBytes {
                    return a.totalBytes > b.totalBytes
                }
                return a.filename.localizedStandardCompare(b.filename) == .orderedAscending
            case .sizeSmallest:
                if a.totalBytes != b.totalBytes {
                    return a.totalBytes < b.totalBytes
                }
                return a.filename.localizedStandardCompare(b.filename) == .orderedAscending
            case .progress:
                if a.progress != b.progress {
                    return a.progress > b.progress
                }
                return a.filename.localizedStandardCompare(b.filename) == .orderedAscending
            case .speed:
                if a.bytesPerSecond != b.bytesPerSecond {
                    return a.bytesPerSecond > b.bytesPerSecond
                }
                return a.filename.localizedStandardCompare(b.filename) == .orderedAscending
            }
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

    /// Count of currently open TCP connections across active chunk streams.
    public var activeSocketCount: Int {
        let activeChunks = tasks.filter { $0.status == .downloading }.reduce(0) { sum, task in
            let active = task.chunks.filter { $0.status == .downloading }.count
            return sum + (active > 0 ? active : (task.status == .downloading ? 1 : 0))
        }
        return activeChunks
    }

    /// Current resident application memory usage in megabytes.
    public var allocatedMemoryMB: Int {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        if kerr == KERN_SUCCESS {
            return max(16, Int(info.resident_size / (1024 * 1024)))
        }
        return 48
    }

    /// Total bytes downloaded today across all completed and active tasks.
    public var totalDownloadedTodayBytes: Int64 {
        let calendar = Calendar.current
        return tasks.reduce(0) { sum, task in
            if let completedAt = task.completedAt, calendar.isDateInToday(completedAt) {
                return sum + task.downloadedBytes
            } else if calendar.isDateInToday(task.createdAt) {
                return sum + task.downloadedBytes
            }
            return sum
        }
    }

    /// Formatted total bytes downloaded today.
    public var formattedTotalDownloadedToday: String {
        Self.formatBytes(totalDownloadedTodayBytes)
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
        headers: [String: String] = [:],
        chunkCount: Int? = nil,
        autoStart: Bool = true
    ) {
        if sidebarSelection != .status(.all) && sidebarSelection != .status(.active) {
            sidebarSelection = .status(.active)
        }
        Task {
            do {
                let newTask = try await queueManager.addTask(
                    url: url,
                    destinationURL: destinationURL,
                    filename: filename,
                    headers: headers,
                    preferredChunkCount: chunkCount,
                    autoStart: autoStart
                )
                self.selectedTaskId = newTask.id
                if self.sidebarSelection != .status(.all) && self.sidebarSelection != .status(.active) {
                    self.sidebarSelection = .status(.active)
                }
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
        selectedTaskIDs.remove(id)
        if selectedTaskIDs.isEmpty, let next = tasks.first(where: { $0.id != id })?.id {
            selectedTaskIDs = [next]
        }
        self.tasks.removeAll(where: { $0.id == id })
        Task {
            try? await queueManager.removeTask(id: id, deleteFile: deleteFile)
        }
    }

    /// Removes all selected tasks from the queue and resets selection.
    public func removeSelected(deleteFile: Bool = false) {
        let targets = selectedTasks
        let targetIDs = Set(targets.map(\.id))
        selectedTaskIDs.removeAll()
        self.tasks.removeAll(where: { targetIDs.contains($0.id) })
        if let first = self.tasks.first?.id {
            self.selectedTaskIDs = [first]
        }
        Task {
            for task in targets {
                try? await queueManager.removeTask(id: task.id, deleteFile: deleteFile)
            }
        }
    }

    /// Pauses all active/probing/idle tasks among the currently selected tasks.
    public func pauseSelected() {
        for task in selectedTasks {
            switch task.status {
            case .downloading, .probing, .idle:
                pause(id: task.id)
            case .paused, .completed, .failed:
                break
            }
        }
    }

    /// Resumes all paused/failed/idle tasks among the currently selected tasks.
    public func resumeSelected() {
        for task in selectedTasks {
            switch task.status {
            case .paused, .failed, .idle:
                resume(id: task.id)
            case .downloading, .probing, .completed:
                break
            }
        }
    }


    /// Prompts the delete confirmation sheet/dialog for the given task, or the selected tasks if none specified.
    public func promptDelete(task: DownloadTaskModel? = nil) {
        if let task {
            self.taskPendingDeletion = task
            self.tasksPendingDeletion = [task]
            self.showDeleteConfirmation = true
        } else {
            promptDeleteSelected()
        }
    }

    /// Sets up delete confirmation for the selected task(s).
    public func promptDeleteSelected() {
        let targets = selectedTasks
        guard !targets.isEmpty else { return }
        self.tasksPendingDeletion = targets
        self.taskPendingDeletion = targets.first
        self.showDeleteConfirmation = true
    }

    /// Toggles pause / resume for a task with the given ID.
    public func togglePause(id: UUID) {
        guard let task = tasks.first(where: { $0.id == id }) else { return }
        switch task.status {
        case .downloading, .probing:
            pause(id: id)
        case .paused, .idle, .failed:
            resume(id: id)
        case .completed:
            break
        }
    }

    /// Toggles pause / resume for the currently selected task(s).
    public func togglePauseSelected() {
        let targets = selectedTasks
        if targets.count > 1 {
            let hasActive = targets.contains { $0.status == .downloading || $0.status == .probing }
            if hasActive {
                pauseSelected()
            } else {
                resumeSelected()
            }
        } else if let single = targets.first ?? selectedTask {
            togglePause(id: single.id)
        }
    }

    /// Opens the completed file(s) for the currently selected task(s).
    public func openSelectedFile() {
        for task in selectedTasks where task.status == .completed {
            openFile(task: task)
        }
    }

    /// Reveals the currently selected task(s) destination in Finder.
    public func revealSelectedInFinder() {
        let targets = selectedTasks
        let urls = targets.map(\.destinationURL)
        if !urls.isEmpty {
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        }
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
        UserDefaults.standard.set(preset.rawValue, forKey: Self.speedLimitPresetKey)
        Task {
            await queueManager.setSpeedLimit(preset.bytesPerSecond)
        }
    }

    // MARK: - System & Finder Helpers

    /// Activates HyperFetch and brings all active application windows to the foreground.
    @MainActor
    public func bringToFront() {
        MainWindowDelegate.shared.reopenMainWindow()
    }

    /// Opens the macOS Settings window and selects the specified tab.
    @MainActor
    public func openSettingsWindow(tab: SettingsTab = .general) {
        self.selectedSettingsTab = tab
        MainWindowDelegate.shared.reopenMainWindow()

        if let openSettingsHandler {
            openSettingsHandler()
            return
        }

        // Fallback 1: Trigger the native Settings menu item if present in NSApp.mainMenu
        if let mainMenu = NSApp.mainMenu {
            for item in mainMenu.items {
                if let submenu = item.submenu {
                    for subitem in submenu.items {
                        if subitem.keyEquivalent == "," && subitem.keyEquivalentModifierMask.contains(.command) {
                            if let action = subitem.action {
                                NSApp.sendAction(action, to: subitem.target, from: subitem)
                                return
                            }
                        }
                    }
                }
            }
        }

        // Fallback 2: Standard selector dispatch
        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

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

    public func setupLocalhostBridge() {
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

        Task {
            do {
                let port = try await localhostBridge.start()
                await MainActor.run {
                    self.isBridgeRunning = true
                    self.bridgeListeningPort = port
                }
            } catch {
                print("LocalhostBridge failed to start: \(error.localizedDescription)")
                await MainActor.run {
                    self.isBridgeRunning = self.localhostBridge.isRunning
                    self.bridgeListeningPort = self.localhostBridge.listeningPort ?? self.localhostBridge.preferredPort
                }
            }
        }
    }

    /// Restarts the localhost bridge if stopped or offline.
    public func restartLocalhostBridge() {
        localhostBridge.stop()
        self.isBridgeRunning = false
        setupLocalhostBridge()
    }

    /// Refreshes bridge status indicators from the active listener.
    public func refreshBridgeStatus() {
        self.isBridgeRunning = localhostBridge.isRunning
        if let port = localhostBridge.listeningPort {
            self.bridgeListeningPort = port
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
        // Detect newly completed tasks to trigger notifications
        if !isInitialLoad && showCompletionNotification {
            for task in updatedTasks {
                if task.status == .completed && !previouslyCompletedTaskIds.contains(task.id) {
                    notificationManager.sendDownloadCompletedNotification(task: task, playSound: playCompletionSound)
                }
            }
        }

        // Track completed IDs
        self.previouslyCompletedTaskIds = Set(
            updatedTasks.filter { $0.status == .completed }.map(\.id)
        )

        if updatedTasks.isEmpty {
            self.tasks = []
            self.selectedTaskIDs = []
            DockTileController.updateBadge(activeCount: 0)
            return
        }

        self.tasks = updatedTasks

        // Maintain selection validity
        let validIds = Set(updatedTasks.map(\.id))
        let previouslyHadSelection = !selectedTaskIDs.isEmpty
        selectedTaskIDs.formIntersection(validIds)
        if (isInitialLoad || previouslyHadSelection), selectedTaskIDs.isEmpty, let firstId = updatedTasks.first?.id {
            selectedTaskIDs = [firstId]
        }

        // Update Dock icon badge
        DockTileController.updateBadge(activeCount: self.activeDownloadCount)
    }
}
