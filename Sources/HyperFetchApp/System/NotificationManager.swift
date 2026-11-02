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

        UNUserNotificationCenter.current().setNotificationCategories([completedCategory])
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

    // MARK: - UNUserNotificationCenterDelegate

    /// Delivers notifications as banners even when the app is active in the foreground.
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    /// Handles clicks on notifications or the "Show in Finder" action button.
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let path = userInfo["destinationPath"] as? String {
            let fileURL = URL(fileURLWithPath: path)
            DispatchQueue.main.async {
                NSWorkspace.shared.activateFileViewerSelecting([fileURL])
            }
        }
        completionHandler()
    }
}
