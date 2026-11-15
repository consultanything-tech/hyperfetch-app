//
//  NotificationManager.swift
//  HyperFetchApp
//

import AppKit
import Foundation
import UserNotifications
import DownloadKit

/// Manages system notifications for download completion and events.
public final class NotificationManager: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    public static let shared = NotificationManager()

    public static let actionShowInFinder = "SHOW_IN_FINDER"
    public static let categoryDownloadCompleted = "DOWNLOAD_COMPLETED"

    public static let categoryUpdateAvailable = "UPDATE_AVAILABLE"
    public static let categoryUpdateReady = "UPDATE_READY"
    public static let actionRestartNow = "RESTART_NOW"
    public static let actionViewUpdate = "VIEW_UPDATE"
    public static let actionOpenBrowser = "OPEN_BROWSER"

    private override init() {
        super.init()
        setupNotificationCategories()
        UNUserNotificationCenter.current().delegate = self
    }

    /// Configures custom notification categories and action buttons.
    private func setupNotificationCategories() {
        let showInFinderAction = UNNotificationAction(
            identifier: Self.actionShowInFinder,
            title: "Show in Finder",
            options: [.foreground]
        )

        let completedCategory = UNNotificationCategory(
            identifier: Self.categoryDownloadCompleted,
            actions: [showInFinderAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        let viewUpdateAction = UNNotificationAction(
            identifier: Self.actionViewUpdate,
            title: "View Update",
            options: [.foreground]
        )

        let openBrowserAction = UNNotificationAction(
            identifier: Self.actionOpenBrowser,
            title: "Open in Browser",
            options: [.foreground]
        )

        let updateAvailableCategory = UNNotificationCategory(
            identifier: Self.categoryUpdateAvailable,
            actions: [viewUpdateAction, openBrowserAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        let restartNowAction = UNNotificationAction(
            identifier: Self.actionRestartNow,
            title: "Restart & Launch",
            options: [.foreground]
        )

        let updateReadyCategory = UNNotificationCategory(
            identifier: Self.categoryUpdateReady,
            actions: [restartNowAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        UNUserNotificationCenter.current().setNotificationCategories([
            completedCategory,
            updateAvailableCategory,
            updateReadyCategory
        ])
    }

    /// Requests user authorization for delivering alerts, sounds, and badges.
    public func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { granted, error in
            if let error {
                print("Notification permission error: \(error.localizedDescription)")
            }
        }
    }

    /// Retrieves current notification authorization status.
    public func getAuthorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    /// Schedules a notification when a download completes.
    public func sendDownloadCompletedNotification(task: DownloadTaskModel, playSound: Bool = true) {
        let content = UNMutableNotificationContent()
        content.title = "Download Complete"
        content.subtitle = task.filename
        content.body = "Successfully downloaded to \(task.destinationURL.lastPathComponent)"
        content.sound = playSound ? .default : nil
        content.categoryIdentifier = Self.categoryDownloadCompleted
        content.userInfo = ["destinationPath": task.destinationURL.path]

        let request = UNNotificationRequest(
            identifier: "complete-\(task.id.uuidString)",
            content: content,
            trigger: nil // deliver immediately
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("Failed to schedule completion notification: \(error.localizedDescription)")
            }
        }
    }

    /// Schedules a notification when a new version of HyperFetch is available.
    public func sendUpdateAvailableNotification(
        version: String,
        releaseNotes: String,
        releaseURL: URL?,
        canAutoDownload: Bool
    ) {
        let content = UNMutableNotificationContent()
        content.title = "HyperFetch Update Available"
        content.subtitle = "Version \(version)"
        content.body = releaseNotes.isEmpty ? "A new version of HyperFetch is available to install." : releaseNotes
        content.sound = .default
        content.categoryIdentifier = Self.categoryUpdateAvailable
        content.userInfo = [
            "version": version,
            "releaseURL": releaseURL?.absoluteString ?? ""
        ]

        let request = UNNotificationRequest(
            identifier: "update-available-\(version)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("Failed to schedule update available notification: \(error.localizedDescription)")
            }
        }
    }

    /// Schedules a notification when a downloaded update is verified and ready to install.
    public func sendUpdateReadyNotification(version: String) {
        let content = UNMutableNotificationContent()
        content.title = "HyperFetch Update Ready"
        content.subtitle = "Version \(version)"
        content.body = "The update has been downloaded. Click to restart and update."
        content.sound = .default
        content.categoryIdentifier = Self.categoryUpdateReady
        content.userInfo = [
            "version": version,
            "isReady": true
        ]

        let request = UNNotificationRequest(
            identifier: "update-ready-\(version)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("Failed to schedule update ready notification: \(error.localizedDescription)")
            }
        }
    }

    /// Schedules a notification when an automatic update download fails, providing manual browser download fallback.
    public func sendUpdateDownloadFailedNotification(version: String, fallbackURL: URL?) {
        let content = UNMutableNotificationContent()
        content.title = "HyperFetch Update Available"
        content.subtitle = "Version \(version)"
        content.body = "Automatic download could not complete. Click to download manually from GitHub."
        content.sound = .default
        content.categoryIdentifier = Self.categoryUpdateAvailable
        content.userInfo = [
            "version": version,
            "releaseURL": fallbackURL?.absoluteString ?? "",
            "isFailed": true
        ]

        let request = UNNotificationRequest(
            identifier: "update-failed-\(version)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("Failed to schedule update failed notification: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Delivers notifications as banners even when the app is active in the foreground.
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    /// Handles clicks on notifications or custom action buttons.
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let actionId = response.actionIdentifier
        let isFailedFallback = userInfo["isFailed"] as? Bool == true

        if let path = userInfo["destinationPath"] as? String {
            let fileURL = URL(fileURLWithPath: path)
            DispatchQueue.main.async {
                NSWorkspace.shared.activateFileViewerSelecting([fileURL])
            }
        } else if actionId == Self.actionOpenBrowser || (isFailedFallback && actionId == UNNotificationDefaultActionIdentifier) {
            if let urlStr = userInfo["releaseURL"] as? String, let url = URL(string: urlStr) {
                DispatchQueue.main.async {
                    NSWorkspace.shared.open(url)
                }
            }
        } else if actionId == Self.actionRestartNow {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: NSNotification.Name("HyperFetchRelaunchRequested"), object: nil)
            }
        } else if actionId == Self.actionViewUpdate || actionId == UNNotificationDefaultActionIdentifier {
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
                NotificationCenter.default.post(name: NSNotification.Name("HyperFetchShowUpdateSheet"), object: nil)
            }
        }

        completionHandler()
    }
}
