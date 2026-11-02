//
//  ClipboardMonitor.swift
//  HyperFetchApp
//
//  Created by HyperFetch on 2026-11-02.
//

import AppKit
import Foundation

/// Periodically monitors the macOS system pasteboard for copied download links
/// and emits detection events when a matching URL is found.
@MainActor
public final class ClipboardMonitor: ObservableObject {
    public static let shared = ClipboardMonitor()

    public typealias DetectionHandler = @MainActor (_ url: URL, _ filename: String) -> Void

    /// Handler invoked whenever a downloadable file URL is newly copied to the clipboard.
    public var onDetected: DetectionHandler?

    /// Whether clipboard monitoring is currently running.
    @Published public private(set) var isRunning: Bool = false

    /// Standard set of recognized downloadable file extensions.
    public static let downloadableExtensions: Set<String> = [
        "zip", "dmg", "pkg", "iso", "tar", "gz", "tgz", "7z", "rar",
        "mp4", "mkv", "avi", "mov", "mp3", "wav", "flac",
        "pdf", "exe", "msi", "bin", "app", "xip", "deb", "rpm"
    ]

    private var monitorTask: Task<Void, Never>?
    private var lastChangeCount: Int = -1
    private var recentDetections: [(url: String, timestamp: Date)] = []
    private let maxRecentHistory = 10
    private let duplicateSuppressionInterval: TimeInterval = 60 // 60 seconds

    public init(onDetected: DetectionHandler? = nil) {
        self.onDetected = onDetected
    }

    deinit {
        monitorTask?.cancel()
    }

    /// Starts monitoring the pasteboard with the given check interval.
    public func start(interval: TimeInterval = 0.5) {
        guard !isRunning else { return }
        isRunning = true
        lastChangeCount = NSPasteboard.general.changeCount

        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard let self, self.isRunning else { break }
                self.checkClipboard()
            }
        }
    }

    /// Stops monitoring the pasteboard.
    public func stop() {
        isRunning = false
        monitorTask?.cancel()
        monitorTask = nil
    }

    /// Checks the pasteboard immediately if the change count has increased.
    public func checkClipboard() {
        let currentCount = NSPasteboard.general.changeCount
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        guard let text = NSPasteboard.general.string(forType: .string) else { return }

        if let (url, filename) = Self.extractDownloadableURL(from: text) {
            handleDetectedURL(url, filename: filename)
        }
    }

    /// Evaluates whether a raw string represents an HTTP/HTTPS URL with a downloadable file extension.
    public static func extractDownloadableURL(from string: String) -> (url: URL, filename: String)? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              let host = url.host,
              !host.isEmpty else {
            return nil
        }

        let path = url.path
        guard !path.isEmpty && path != "/" else { return nil }

        let lastComponent = (path as NSString).lastPathComponent
        let ext = (lastComponent as NSString).pathExtension.lowercased()

        guard !ext.isEmpty, downloadableExtensions.contains(ext) else {
            return nil
        }

        let filename = lastComponent.isEmpty ? "download.\(ext)" : lastComponent
        return (url, filename)
    }

    private func handleDetectedURL(_ url: URL, filename: String) {
        let urlString = url.absoluteString
        let now = Date()

        // Clean up entries older than the suppression window
        recentDetections.removeAll { now.timeIntervalSince($0.timestamp) > duplicateSuppressionInterval }

        // Check if recently detected
        if recentDetections.contains(where: { $0.url == urlString }) {
            return
        }

        // Record detection
        recentDetections.append((url: urlString, timestamp: now))
        if recentDetections.count > maxRecentHistory {
            recentDetections.removeFirst(recentDetections.count - maxRecentHistory)
        }

        // Trigger detection handler
        onDetected?(url, filename)
    }
}
