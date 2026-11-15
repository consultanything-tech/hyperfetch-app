//
//  UpdateState.swift
//  DownloadKit
//
//  Created by HyperFetch on 2026-11-03.
//

import Foundation

/// Update states reflecting the software version check, auto-download, extraction, and in-place replacement lifecycle.
public enum UpdateState: Equatable, Sendable {
    case idle
    case checking
    case upToDate(currentVersion: String, lastChecked: Date)
    case updateAvailable(newVersion: String, currentVersion: String, releaseNotes: String, downloadURL: URL?, publishedAt: Date?)
    case downloading(newVersion: String, progress: Double, bytesDownloaded: Int64, totalBytes: Int64)
    case extracting(newVersion: String)
    case readyToInstall(newVersion: String, stagedAppURL: URL)
    case installing
    case failed(error: String)
}

/// Preferences and keys for background auto-updates and notifications.
public struct UpdatePreferences: Sendable {
    public static let autoDownloadUpdatesKey = "HyperFetch_AutoDownloadUpdates"
    public static let notifyOnUpdateAvailableKey = "HyperFetch_NotifyOnUpdateAvailable"

    public static func isAutoDownloadUpdatesEnabled(userDefaults: UserDefaults = .standard) -> Bool {
        if userDefaults.object(forKey: autoDownloadUpdatesKey) != nil {
            return userDefaults.bool(forKey: autoDownloadUpdatesKey)
        }
        return true
    }

    public static func isNotifyOnUpdateAvailableEnabled(userDefaults: UserDefaults = .standard) -> Bool {
        if userDefaults.object(forKey: notifyOnUpdateAvailableKey) != nil {
            return userDefaults.bool(forKey: notifyOnUpdateAvailableKey)
        }
        return true
    }

    public static func setAutoDownloadUpdates(_ enabled: Bool, userDefaults: UserDefaults = .standard) {
        userDefaults.set(enabled, forKey: autoDownloadUpdatesKey)
    }

    public static func setNotifyOnUpdateAvailable(_ enabled: Bool, userDefaults: UserDefaults = .standard) {
        userDefaults.set(enabled, forKey: notifyOnUpdateAvailableKey)
    }
}
