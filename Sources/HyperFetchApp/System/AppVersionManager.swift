//
//  AppVersionManager.swift
//  HyperFetchApp
//
//  Created by HyperFetch on 2026-11-02.
//

import AppKit
import Foundation
import SwiftUI
import DownloadKit

/// Update states reflecting the software version check, auto-download, extraction, and in-place replacement lifecycle.
public typealias UpdateState = DownloadKit.UpdateState

/// Central manager overseeing application version inspection, automatic update checks, and update presentation.
@MainActor
public final class AppVersionManager: ObservableObject {
    public static let shared = AppVersionManager()

    private static let lastCheckedDateKey = "com.hyperfetch.lastUpdateCheckDate"
    private static let autoCheckOnLaunchKey = "com.hyperfetch.autoCheckForUpdates"
    private static let updateChannelKey = "com.hyperfetch.updateChannel"

    public static let autoDownloadUpdatesKey = "HyperFetch_AutoDownloadUpdates"
    public static let notifyOnUpdateAvailableKey = "HyperFetch_NotifyOnUpdateAvailable"

    public var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.1.1"
    }

    public var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "16"
    }

    public var fullVersionString: String {
        "v\(currentVersion) (Build \(buildNumber))"
    }

    @Published public var lastCheckedDate: Date? {
        didSet {
            UserDefaults.standard.set(lastCheckedDate, forKey: Self.lastCheckedDateKey)
        }
    }

    @Published public var autoCheckOnLaunch: Bool {
        didSet {
            UserDefaults.standard.set(autoCheckOnLaunch, forKey: Self.autoCheckOnLaunchKey)
        }
    }

    @Published public var updateChannel: String {
        didSet {
            UserDefaults.standard.set(updateChannel, forKey: Self.updateChannelKey)
        }
    }

    @Published public var autoDownloadUpdates: Bool {
        didSet {
            UserDefaults.standard.set(autoDownloadUpdates, forKey: Self.autoDownloadUpdatesKey)
        }
    }

    @Published public var notifyOnUpdateAvailable: Bool {
        didSet {
            UserDefaults.standard.set(notifyOnUpdateAvailable, forKey: Self.notifyOnUpdateAvailableKey)
        }
    }

    @Published public var isBannerDismissedForVersion: String? = nil
    @Published public var isUpdateSheetPresented: Bool = false
    @Published public var isAboutSheetPresented: Bool = false
    @Published public var state: UpdateState = .idle

    public var formattedLastCheckedDate: String {
        guard let lastCheckedDate else { return "Never" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: lastCheckedDate)
    }

    private var activeCheckTask: Task<Void, Never>?
    private var downloadTask: URLSessionDownloadTask?
    private var activeSession: URLSession?
    private var periodicCheckTimer: Timer?

    public init() {
        if let savedDate = UserDefaults.standard.object(forKey: Self.lastCheckedDateKey) as? Date {
            self.lastCheckedDate = savedDate
        } else {
            self.lastCheckedDate = nil
        }

        if UserDefaults.standard.object(forKey: Self.autoCheckOnLaunchKey) != nil {
            self.autoCheckOnLaunch = UserDefaults.standard.bool(forKey: Self.autoCheckOnLaunchKey)
        } else {
            self.autoCheckOnLaunch = true
        }

        if let savedChannel = UserDefaults.standard.string(forKey: Self.updateChannelKey), !savedChannel.isEmpty {
            self.updateChannel = savedChannel
        } else {
            self.updateChannel = "Stable"
        }

        if UserDefaults.standard.object(forKey: Self.autoDownloadUpdatesKey) != nil {
            self.autoDownloadUpdates = UserDefaults.standard.bool(forKey: Self.autoDownloadUpdatesKey)
        } else {
            self.autoDownloadUpdates = true
        }

        if UserDefaults.standard.object(forKey: Self.notifyOnUpdateAvailableKey) != nil {
            self.notifyOnUpdateAvailable = UserDefaults.standard.bool(forKey: Self.notifyOnUpdateAvailableKey)
        } else {
            self.notifyOnUpdateAvailable = true
        }

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("HyperFetchShowUpdateSheet"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isUpdateSheetPresented = true
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("HyperFetchRelaunchRequested"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if case .readyToInstall(_, let stagedAppURL) = self.state {
                    self.installAndRelaunch(stagedAppURL: stagedAppURL)
                }
            }
        }

        periodicCheckTimer = Timer.scheduledTimer(withTimeInterval: 14400, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkOnLaunchIfNeeded()
            }
        }
    }

    /// Checks if automatic update check is required on launch (> 15 minutes since last check).
    public func checkOnLaunchIfNeeded() {
        guard autoCheckOnLaunch else { return }
        if let lastChecked = lastCheckedDate {
            let elapsed = Date().timeIntervalSince(lastChecked)
            guard elapsed > 900 else { return }
        }
        checkForUpdates(userInitiated: false)
    }

    /// Initiates a software update check, querying latest GitHub releases or manifest.
    public func checkForUpdates(userInitiated: Bool = true) {
        activeCheckTask?.cancel()

        state = .checking
        if userInitiated {
            isUpdateSheetPresented = true
        }

        let currentVer = self.currentVersion

        activeCheckTask = Task { [weak self] in
            // Subtle brief pause so user can see checking animation if user-initiated
            if userInitiated {
                try? await Task.sleep(nanoseconds: 600_000_000)
            }

            guard !Task.isCancelled else { return }

            let result = await Self.performUpdateQuery(currentVersion: currentVer)

            guard !Task.isCancelled, let self else { return }

            let now = Date()
            self.lastCheckedDate = now

            switch result {
            case .available(let newVersion, let notes, let downloadURL, let pubDate):
                self.state = .updateAvailable(
                    newVersion: newVersion,
                    currentVersion: currentVer,
                    releaseNotes: notes,
                    downloadURL: downloadURL,
                    publishedAt: pubDate
                )
                if userInitiated {
                    self.isUpdateSheetPresented = true
                } else {
                    if self.autoDownloadUpdates, let url = downloadURL, url.lastPathComponent.lowercased().hasSuffix(".zip") {
                        self.downloadAndInstallUpdate(from: url, newVersion: newVersion, isSilent: true)
                    } else if self.notifyOnUpdateAvailable {
                        NotificationManager.shared.sendUpdateAvailableNotification(
                            version: newVersion,
                            releaseNotes: notes,
                            releaseURL: downloadURL,
                            canAutoDownload: self.autoDownloadUpdates
                        )
                    }
                }
            case .upToDate:
                self.state = .upToDate(currentVersion: currentVer, lastChecked: now)
            case .failed:
                // If user-initiated, allow showing upToDate for demo/offline fallback or error
                self.state = .upToDate(currentVersion: currentVer, lastChecked: now)
            }
        }
    }

    /// Downloads and automatically extracts/verifies the update package.
    public func downloadAndInstallUpdate(from url: URL, newVersion: String, isSilent: Bool = false) {
        state = .downloading(newVersion: newVersion, progress: 0.0, bytesDownloaded: 0, totalBytes: 0)
        if !isSilent {
            isUpdateSheetPresented = true
        }

        Task { [weak self] in
            guard let self else { return }
            do {
                let localArchiveURL: URL

                if url.isFileURL {
                    let tempDir = FileManager.default.temporaryDirectory
                    let dest = tempDir.appendingPathComponent("\(UUID().uuidString)_\(url.lastPathComponent)")
                    try FileManager.default.copyItem(at: url, to: dest)
                    localArchiveURL = dest
                } else {
                    localArchiveURL = try await self.performDownload(from: url, newVersion: newVersion)
                }

                await MainActor.run {
                    self.state = .extracting(newVersion: newVersion)
                }

                let stagedApp = try await Task.detached {
                    try UpdatePackageExtractor.extractAndVerify(
                        archiveURL: localArchiveURL,
                        newVersion: newVersion
                    )
                }.value

                await MainActor.run {
                    self.state = .readyToInstall(newVersion: newVersion, stagedAppURL: stagedApp)
                    if isSilent {
                        NotificationManager.shared.sendUpdateReadyNotification(version: newVersion)
                    }
                }
            } catch {
                await MainActor.run {
                    self.state = .failed(error: error.localizedDescription)
                    if isSilent {
                        NotificationManager.shared.sendUpdateDownloadFailedNotification(version: newVersion, fallbackURL: url)
                    }
                }
            }
        }
    }

    /// Replaces the currently running application with the verified staged update bundle and restarts.
    public func installAndRelaunch(stagedAppURL: URL) {
        state = .installing

        let targetAppURL: URL
        if Bundle.main.bundleURL.pathExtension == "app" {
            targetAppURL = Bundle.main.bundleURL
        } else {
            targetAppURL = URL(fileURLWithPath: "/Applications/HyperFetch.app")
        }

        let currentPID = ProcessInfo.processInfo.processIdentifier
        let stagingFolderURL = stagedAppURL.deletingLastPathComponent()
        let updaterScriptURL = FileManager.default.temporaryDirectory.appendingPathComponent("hyperfetch_relaunch_\(UUID().uuidString).sh")

        let script = """
        #!/bin/bash
        LOG="/tmp/hyperfetch_updater.log"
        echo "=== HyperFetch Updater Starting ($(date)) ===" > "$LOG"
        echo "Target: \(targetAppURL.path)" >> "$LOG"
        echo "Staged: \(stagedAppURL.path)" >> "$LOG"

        # Wait for process to exit
        for i in $(seq 1 50); do
            if ! kill -0 \(currentPID) 2>/dev/null; then
                break
            fi
            sleep 0.1
        done

        if kill -0 \(currentPID) 2>/dev/null; then
            kill -9 \(currentPID) 2>/dev/null
            sleep 0.2
        fi

        # Attempt direct replacement
        rm -rf "\(targetAppURL.path)" >> "$LOG" 2>&1
        /usr/bin/ditto "\(stagedAppURL.path)" "\(targetAppURL.path)" >> "$LOG" 2>&1

        # If target app bundle does not exist or copy failed, fallback to elevated prompt
        if [ ! -d "\(targetAppURL.path)" ]; then
            echo "Direct replacement failed; attempting elevated prompt via osascript..." >> "$LOG"
            /usr/bin/osascript -e 'do shell script "rm -rf \\"\(targetAppURL.path)\\" && /usr/bin/ditto \\"\(stagedAppURL.path)\\" \\"\(targetAppURL.path)\\"" with administrator privileges' >> "$LOG" 2>&1
        fi

        # Clean staging
        rm -rf "\(stagingFolderURL.path)" >> "$LOG" 2>&1
        rm -f "\(updaterScriptURL.path)" >> "$LOG" 2>&1

        echo "Launching updated app..." >> "$LOG"
        /usr/bin/open "\(targetAppURL.path)" >> "$LOG" 2>&1
        """

        do {
            try script.write(to: updaterScriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: updaterScriptURL.path)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [updaterScriptURL.path]
            try process.run()
        } catch {
            print("[AppVersionManager] Failed to launch updater script: \(error)")
        }

        // Dismiss modal sheet
        isUpdateSheetPresented = false

        // Unconditionally terminate the process so the updater script executes immediately
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NSApp.terminate(nil)
            exit(0)
        }
    }

    /// Cancels active download task if running.
    public func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        activeSession?.invalidateAndCancel()
        activeSession = nil
        state = .idle
    }

    // MARK: - Private Download Engine

    private func performDownload(from url: URL, newVersion: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let tracker = UpdateDownloadDelegate(
                onProgress: { [weak self] progress, downloaded, total in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        if case .downloading = self.state {
                            self.state = .downloading(
                                newVersion: newVersion,
                                progress: progress,
                                bytesDownloaded: downloaded,
                                totalBytes: total
                            )
                        }
                    }
                },
                continuation: continuation
            )

            let session = URLSession(configuration: .default, delegate: tracker, delegateQueue: nil)
            self.activeSession = session

            var request = URLRequest(url: url)
            request.setValue("HyperFetch/\(self.currentVersion)", forHTTPHeaderField: "User-Agent")

            let task = session.downloadTask(with: request)
            self.downloadTask = task
            task.resume()
        }
    }

    private enum CheckResult {
        case available(newVersion: String, notes: String, downloadURL: URL?, publishedAt: Date?)
        case upToDate
        case failed(String)
    }

    private static func performUpdateQuery(currentVersion: String) async -> CheckResult {
        guard let url = URL(string: "https://api.github.com/repos/consultanything-tech/hyperfetch-app/releases/latest") else {
            return .upToDate
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5.0
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("HyperFetch/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .upToDate
            }

            guard httpResponse.statusCode == 200 else {
                // If 404 or repository not yet public/created, treat gracefully as up-to-date
                return .upToDate
            }

            struct GHRelease: Decodable {
                let tagName: String
                let name: String?
                let body: String?
                let htmlUrl: String?
                let publishedAt: String?
                let assets: [GHAsset]?

                enum CodingKeys: String, CodingKey {
                    case tagName = "tag_name"
                    case name
                    case body
                    case htmlUrl = "html_url"
                    case publishedAt = "published_at"
                    case assets
                }
            }

            struct GHAsset: Decodable {
                let name: String
                let browserDownloadUrl: String

                enum CodingKeys: String, CodingKey {
                    case name
                    case browserDownloadUrl = "browser_download_url"
                }
            }

            let release = try JSONDecoder().decode(GHRelease.self, from: data)
            let releaseVersion = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV \t\n\r"))

            if isVersion(releaseVersion, newerThan: currentVersion) {
                // Prefer HyperFetch application .zip asset, excluding companion extension packages
                let appZipAsset = release.assets?.first(where: {
                    let name = $0.name.lowercased()
                    return name.hasSuffix(".zip") && (name == "hyperfetch.zip" || !name.contains("extension"))
                })
                let dmgAsset = release.assets?.first(where: {
                    let name = $0.name.lowercased()
                    return name.hasSuffix(".dmg") && !name.contains("extension")
                })
                let targetAsset = appZipAsset ?? dmgAsset

                let downloadURL = targetAsset.flatMap { URL(string: $0.browserDownloadUrl) }
                    ?? release.htmlUrl.flatMap { URL(string: $0) }

                let notes = release.body?.trimmingCharacters(in: .whitespacesAndNewlines)
                    ?? "A new version of HyperFetch is available with performance improvements and bug fixes."

                let date: Date? = {
                    guard let publishedAt = release.publishedAt else { return nil }
                    let iso = ISO8601DateFormatter()
                    return iso.date(from: publishedAt)
                }()

                return .available(
                    newVersion: releaseVersion,
                    notes: notes,
                    downloadURL: downloadURL,
                    publishedAt: date
                )
            } else {
                return .upToDate
            }
        } catch {
            // Offline / timeout / demo graceful fallback
            return .upToDate
        }
    }

    /// Semantic version comparison returning true if `v1` is strictly greater than `v2`.
    public static func isVersion(_ v1: String, newerThan v2: String) -> Bool {
        VersionComparator.isVersion(v1, newerThan: v2)
    }
}

// MARK: - Download Progress Tracker Delegate

private final class UpdateDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let onProgress: @Sendable (Double, Int64, Int64) -> Void
    private var continuation: CheckedContinuation<URL, Error>?
    private var isCompleted = false
    private let lock = NSLock()

    init(
        onProgress: @escaping @Sendable (Double, Int64, Int64) -> Void,
        continuation: CheckedContinuation<URL, Error>
    ) {
        self.onProgress = onProgress
        self.continuation = continuation
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let expected = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : max(totalBytesWritten, 1)
        let progress = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0.0
        onProgress(min(1.0, max(0.0, progress)), totalBytesWritten, expected)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        lock.lock()
        defer { lock.unlock() }
        guard !isCompleted else { return }
        isCompleted = true

        let origName = downloadTask.originalRequest?.url?.lastPathComponent ?? "HyperFetchUpdate.zip"
        let safeName = origName.isEmpty ? "HyperFetchUpdate.zip" : origName
        let tempDir = FileManager.default.temporaryDirectory
        let destination = tempDir.appendingPathComponent("\(UUID().uuidString)_\(safeName)")

        do {
            try FileManager.default.moveItem(at: location, to: destination)
            continuation?.resume(returning: destination)
        } catch {
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            lock.lock()
            defer { lock.unlock() }
            guard !isCompleted else { return }
            isCompleted = true
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }
}
