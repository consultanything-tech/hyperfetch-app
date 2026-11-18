//
//  AppState.swift
//  HyperFetchApp
//

import AppKit
import Foundation
import OSLog
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
    case support = "Support"

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

/// Presentation style for the download tasks list.
public enum DownloadListViewMode: String, CaseIterable, Identifiable, Sendable {
    case comfortable = "Comfortable" // Default card view
    case compact = "Compact"         // High-density compact row view

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .comfortable: return "rectangle.grid.1x2"
        case .compact: return "list.bullet"
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
        }
    }
    @Published public var searchText: String = "" {
        didSet { _cachedFilteredTasks = nil }
    }
    @Published public var speedLimitPreset: SpeedLimitPreset = .unlimited
    @Published public var selectedSettingsTab: SettingsTab = .general
    public var openSettingsHandler: (@MainActor () -> Void)?
    @Published public var isBridgeRunning: Bool = false
    @Published public var bridgeListeningPort: UInt16 = LocalhostBridge.defaultPreferredPort
    @Published public var isAddSheetPresented: Bool = false
    public var isAddDownloadSheetPresented: Bool {
        get { isAddSheetPresented }
        set { isAddSheetPresented = newValue }
    }
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
    @Published public var viewMode: DownloadListViewMode {
        didSet {
            UserDefaults.standard.set(viewMode.rawValue, forKey: Self.viewModeKey)
        }
    }

    var _cachedFilteredTasks: [DownloadTaskModel]?
    var lastPauseTimestamps: [UUID: ContinuousClock.Instant] = [:]
    let pauseClock = ContinuousClock()

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

    /// Shared instance reference for lifecycle hooks and synchronous flushes.
    public private(set) static weak var shared: AppState?

    private static let defaultDownloadDirectoryKey = "com.hyperfetch.defaultDownloadDirectory"
    private static let defaultChunkCountKey = "com.hyperfetch.defaultChunkCount"
    private static let sortOptionKey = "com.hyperfetch.sortOption"
    private static let appearanceModeKey = "com.hyperfetch.appearanceMode"
    private static let viewModeKey = "com.hyperfetch.viewMode"
    private static let maxConcurrentDownloadsKey = "com.hyperfetch.maxConcurrentDownloads"
    private static let speedLimitPresetKey = "com.hyperfetch.speedLimitPreset"
    private static let autoCaptureClipboardKey = "com.hyperfetch.autoCaptureClipboard"
    private static let autoStartCapturedDownloadsKey = "com.hyperfetch.autoStartCapturedDownloads"
    private static let bringToFrontOnCaptureKey = "com.hyperfetch.bringToFrontOnCapture"
    private static let playCompletionSoundKey = "com.hyperfetch.playCompletionSound"
    private static let completionSoundNameKey = "com.hyperfetch.completionSoundName"
    private static let showCompletionNotificationKey = "com.hyperfetch.showCompletionNotification"
    static let allTimeDownloadedBytesKey = "allTimeDownloadedBytes"
    static let allTimeCompletedCountKey = "allTimeCompletedCount"
    private static let autoRevealOnCompletionKey = "autoRevealOnCompletion"
    private static let isBandwidthScheduleEnabledKey = "isBandwidthScheduleEnabled"
    private static let scheduleStartHourKey = "scheduleStartHour"
    private static let scheduleEndHourKey = "scheduleEndHour"

    @Published public var allTimeDownloadedBytes: Int64
    @Published public var allTimeCompletedCount: Int
    @Published public var autoRevealOnCompletion: Bool {
        didSet { UserDefaults.standard.set(autoRevealOnCompletion, forKey: Self.autoRevealOnCompletionKey) }
    }
    @Published public var isBandwidthScheduleEnabled: Bool {
        didSet { UserDefaults.standard.set(isBandwidthScheduleEnabled, forKey: Self.isBandwidthScheduleEnabledKey) }
    }
    @Published public var scheduleStartHour: Int {
        didSet { UserDefaults.standard.set(scheduleStartHour, forKey: Self.scheduleStartHourKey) }
    }
    @Published public var scheduleEndHour: Int {
        didSet { UserDefaults.standard.set(scheduleEndHour, forKey: Self.scheduleEndHourKey) }
    }
    @AppStorage("autoOpenOnCompletion") public var autoOpenOnCompletion: Bool = false
    var preScheduleSpeedLimit: SpeedLimitPreset? = nil

    public static let availableCompletionSounds = ["Glass", "Hero", "Ping", "Pop", "Purr", "Tink", "Mute"]

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

    /// Sound effect name to play upon completion (from macOS System Sounds).
    @Published public var completionSoundName: String {
        didSet {
            UserDefaults.standard.set(completionSoundName, forKey: Self.completionSoundNameKey)
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
            return DownloadTaskModel.defaultBaseDirectory
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
    public let launchAtLoginController: LaunchAtLoginController

    /// Whether HyperFetch automatically launches on system login.
    @Published public var launchAtLogin: Bool

    /// System status of the Launch at Login registration.
    @Published public var launchAtLoginStatus: LaunchAtLoginStatus

    @Published public var speedHistory: [Double] = Array(repeating: 0.0, count: 8)
    @Published private(set) public var cachedActiveSocketCount: Int = 0
    @Published private(set) public var cachedAllocatedMemoryMB: Int = 48
    @Published private(set) public var cachedTotalDownloadedTodayBytes: Int64 = 0
    var updatesTask: Task<Void, Never>?
    var speedSamplerTask: Task<Void, Never>?
    var previouslyCompletedTaskIds: Set<UUID> = []
    nonisolated(unsafe) var themeObserver: (any NSObjectProtocol)?
    let logger = Logger(subsystem: "com.hyperfetch.app", category: "AppState")

    public init(
        queueManager: QueueManager? = nil,
        localhostBridge: LocalhostBridge? = nil,
        clipboardMonitor: ClipboardMonitor? = nil,
        launchAtLoginController: LaunchAtLoginController? = nil
    ) {
        let lalc = launchAtLoginController ?? LaunchAtLoginController()
        lalc.sync(defaultIfUnset: true)
        self.launchAtLoginController = lalc
        self.launchAtLogin = lalc.isEnabledInPreferences
        self.launchAtLoginStatus = lalc.status
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

        self.completionSoundName = UserDefaults.standard.string(forKey: Self.completionSoundNameKey) ?? "Pop"

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

        if let savedViewMode = UserDefaults.standard.string(forKey: Self.viewModeKey),
           let mode = DownloadListViewMode(rawValue: savedViewMode) {
            self.viewMode = mode
        } else {
            self.viewMode = .comfortable
        }

        self.allTimeDownloadedBytes = (UserDefaults.standard.object(forKey: Self.allTimeDownloadedBytesKey) as? NSNumber)?.int64Value ?? 0
        self.allTimeCompletedCount = UserDefaults.standard.integer(forKey: Self.allTimeCompletedCountKey)
        self.autoRevealOnCompletion = UserDefaults.standard.bool(forKey: Self.autoRevealOnCompletionKey)
        self.isBandwidthScheduleEnabled = UserDefaults.standard.bool(forKey: Self.isBandwidthScheduleEnabledKey)
        self.scheduleStartHour = UserDefaults.standard.object(forKey: Self.scheduleStartHourKey) as? Int ?? 9
        self.scheduleEndHour = UserDefaults.standard.object(forKey: Self.scheduleEndHourKey) as? Int ?? 18

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

        Self.shared = self

        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.flushSync()
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.flushSync()
        }

        // Start listening to the QueueManager stream
        startListeningToQueue()

        self.cachedActiveSocketCount = self.computeActiveSocketCount()
        self.cachedAllocatedMemoryMB = self.computeAllocatedMemoryMB()
        self.cachedTotalDownloadedTodayBytes = self.computeTotalDownloadedTodayBytes()

        speedSamplerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self else { return }
                let current = self.totalDownloadSpeed
                self.speedHistory.removeFirst()
                self.speedHistory.append(current)

                if self.isBandwidthScheduleEnabled {
                    let currentHour = Calendar.current.component(.hour, from: Date())
                    let inSchedule: Bool
                    if self.scheduleStartHour <= self.scheduleEndHour {
                        inSchedule = currentHour >= self.scheduleStartHour && currentHour < self.scheduleEndHour
                    } else {
                        // Crosses midnight, e.g. 22:00 to 06:00
                        inSchedule = currentHour >= self.scheduleStartHour || currentHour < self.scheduleEndHour
                    }
                    if inSchedule {
                        if self.preScheduleSpeedLimit == nil {
                            self.preScheduleSpeedLimit = self.speedLimitPreset
                        }
                        if self.speedLimitPreset == .unlimited {
                            self.setSpeedLimitPreset(.normal)
                        }
                    } else {
                        if let previous = self.preScheduleSpeedLimit {
                            self.setSpeedLimitPreset(previous)
                            self.preScheduleSpeedLimit = nil
                        }
                    }
                } else if let previous = self.preScheduleSpeedLimit {
                    self.setSpeedLimitPreset(previous)
                    self.preScheduleSpeedLimit = nil
                }

                self.cachedActiveSocketCount = self.computeActiveSocketCount()
                self.cachedAllocatedMemoryMB = self.computeAllocatedMemoryMB()
                self.cachedTotalDownloadedTodayBytes = self.computeTotalDownloadedTodayBytes()
            }
        }

        // Setup background bridges and clipboard monitoring
        setupLocalhostBridge()
        setupClipboardMonitor()
        DispatchQueue.main.async { [weak self] in
            self?.applyAppearance()
        }

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
        speedSamplerTask?.cancel()
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

        guard let app = NSApp else { return }
        app.appearance = targetAppearance
        for window in app.windows {
            window.appearance = targetAppearance
            window.invalidateShadow()
            window.viewsNeedDisplay = true
            window.contentView?.needsDisplay = true
        }
    }

    // MARK: - Computed Properties & Filtering

    /// Restarts a download task cleanly from byte 0.
    public func restartTask(id: UUID) {
        guard let task = tasks.first(where: { $0.id == id }) else { return }
        let url = task.url
        let filename = task.filename
        let headers = task.headers
        let chunkCount = task.preferredChunkCount
        remove(id: id, deleteFile: true)
        addTask(url: url, filename: filename, headers: headers, chunkCount: chunkCount, autoStart: true)
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

    /// Aggregate progress fraction across all active downloads (0.0 to 1.0).
    public var aggregateProgress: Double {
        let active = tasks.filter { $0.status == .downloading || $0.status == .probing }
        guard !active.isEmpty else { return 0.0 }
        let total = active.reduce(Int64(0)) { $0 + max(0, $1.totalBytes) }
        let downloaded = active.reduce(Int64(0)) { $0 + $1.downloadedBytes }
        guard total > 0 else { return 0.0 }
        return min(1.0, max(0.0, Double(downloaded) / Double(total)))
    }

    /// Whether there are any completed tasks in the queue.
    public var hasCompletedTasks: Bool {
        tasks.contains { $0.status == .completed }
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
    public var activeSocketCount: Int { cachedActiveSocketCount }

    private func computeActiveSocketCount() -> Int {
        let activeChunks = tasks.filter { $0.status == .downloading }.reduce(0) { sum, task in
            let active = task.chunks.filter { $0.status == .downloading }.count
            return sum + (active > 0 ? active : (task.status == .downloading ? 1 : 0))
        }
        return activeChunks
    }

    /// Current resident application memory usage in megabytes.
    public var allocatedMemoryMB: Int { cachedAllocatedMemoryMB }

    private func computeAllocatedMemoryMB() -> Int {
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

    public var availableDiskSpaceString: String {
        do {
            let values = try defaultDownloadDirectoryURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
            if let capacity = values.volumeAvailableCapacityForImportantUsage ?? values.volumeAvailableCapacity.map({ Int64($0) }) {
                return "\(Self.formatBytes(capacity)) free"
            }
        } catch {}
        return "Available"
    }

    public func refreshStatus() {
        refreshBridgeStatus()
        objectWillChange.send()
    }

    /// Total bytes downloaded today across all completed and active tasks.
    public var totalDownloadedTodayBytes: Int64 { cachedTotalDownloadedTodayBytes }

    private func computeTotalDownloadedTodayBytes() -> Int64 {
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

    /// Synchronously flushes state persistence to disk on app termination or background transition.
    nonisolated public func flushSync() {
        queueManager.flushSync()
    }

    /// Adds a new download task.
    public func addTask(
        url: URL,
        destinationURL: URL? = nil,
        filename: String? = nil,
        headers: [String: String] = [:],
        chunkCount: Int? = nil,
        expectedChecksum: String? = nil,
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
                    preferredChunkCount: chunkCount ?? self.defaultChunkCount,
                    expectedChecksum: expectedChecksum,
                    autoStart: autoStart
                )
                self.selectedTaskId = newTask.id
                if self.sidebarSelection != .status(.all) && self.sidebarSelection != .status(.active) {
                    self.sidebarSelection = .status(.active)
                }
            } catch {
                logger.error("Failed to add task: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Pauses an active or queued download task.
    public func pause(id: UUID) {
        lastPauseTimestamps[id] = pauseClock.now
        if let idx = tasks.firstIndex(where: { $0.id == id }) {
            tasks[idx].status = .paused
            tasks[idx].bytesPerSecond = 0.0
        }
        Task {
            await queueManager.pauseTask(id: id)
        }
    }

    /// Resumes a paused or failed download task.
    public func resume(id: UUID) {
        if let timestamp = lastPauseTimestamps[id], pauseClock.now - timestamp < .milliseconds(600) {
            return
        }
        if let idx = tasks.firstIndex(where: { $0.id == id }) {
            tasks[idx].status = tasks[idx].totalBytes > 0 ? .downloading : .probing
        }
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

    // MARK: - Queue Reordering Actions

    public func moveTaskUp(id: UUID) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }), idx > 0 else { return }
        Task {
            await queueManager.moveTask(id: id, toIndex: idx - 1)
        }
    }

    public func moveTaskDown(id: UUID) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }), idx < tasks.count - 1 else { return }
        Task {
            await queueManager.moveTask(id: id, toIndex: idx + 1)
        }
    }

    public func moveTaskToTop(id: UUID) {
        Task {
            await queueManager.moveTask(id: id, toIndex: 0)
        }
    }

    public func moveTaskToBottom(id: UUID) {
        Task {
            await queueManager.moveTask(id: id, toIndex: tasks.count - 1)
        }
    }

    /// Previews the currently selected completion chime sound.
    public func playTestSound() {
        guard completionSoundName != "Mute" else { return }
        NSSound(named: completionSoundName)?.play()
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

    /// Toggles pause / resume for a task with the given ID.
    public func togglePause(id: UUID) {
        guard let task = tasks.first(where: { $0.id == id }) else { return }
        switch task.status {
        case .downloading, .probing:
            pause(id: id)
        case .paused, .idle, .failed:
            if let timestamp = lastPauseTimestamps[id], pauseClock.now - timestamp < .milliseconds(600) {
                return
            }
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
        for i in 0..<tasks.count {
            if tasks[i].status == .downloading || tasks[i].status == .probing || tasks[i].status == .idle {
                tasks[i].status = .paused
                tasks[i].bytesPerSecond = 0.0
            }
        }
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

    /// Convenience setter for download speed limit preset.
    public func setSpeedLimitPreset(_ preset: SpeedLimitPreset) {
        setSpeedLimit(preset: preset)
    }

    // MARK: - Launch at Login Management

    /// Toggles Launch at Login and updates system registration and stored preference.
    public func setLaunchAtLogin(_ enabled: Bool) {
        self.launchAtLogin = enabled
        self.launchAtLoginStatus = launchAtLoginController.setLaunchAtLogin(enabled: enabled)
    }

    /// Opens the macOS System Settings app directly to Login Items & Extensions.
    public func openLoginItemsSettings() {
        launchAtLoginController.openSystemSettings()
    }

    // MARK: - System Helpers

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
}
