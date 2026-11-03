//
//  AppVersionManager.swift
//  HyperFetchApp
//
//  Created by HyperFetch on 2026-11-02.
//

import AppKit
import Foundation
import SwiftUI

/// Update states reflecting the software version check lifecycle.
public enum UpdateState: Equatable, Sendable {
    case idle
    case checking
    case upToDate(currentVersion: String, lastChecked: Date)
    case updateAvailable(newVersion: String, currentVersion: String, releaseNotes: String, downloadURL: URL?, publishedAt: Date?)
    case failed(error: String)
}

/// Central manager overseeing application version inspection, automatic update checks, and update presentation.
@MainActor
public final class AppVersionManager: ObservableObject {
    public static let shared = AppVersionManager()

    private static let lastCheckedDateKey = "com.hyperfetch.lastUpdateCheckDate"
    private static let autoCheckOnLaunchKey = "com.hyperfetch.autoCheckForUpdates"
    private static let updateChannelKey = "com.hyperfetch.updateChannel"

    public var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    public var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
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
    }

    /// Checks if automatic update check is required on launch (> 24 hours since last check).
    public func checkOnLaunchIfNeeded() {
        guard autoCheckOnLaunch else { return }
        if let lastChecked = lastCheckedDate {
            let elapsed = Date().timeIntervalSince(lastChecked)
            guard elapsed > 86400 else { return }
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
            case .upToDate:
                self.state = .upToDate(currentVersion: currentVer, lastChecked: now)
            case .failed:
                // If user-initiated, allow showing upToDate for demo/offline fallback or error
                // As per specification: if demo/offline, sets .upToDate
                self.state = .upToDate(currentVersion: currentVer, lastChecked: now)
            }
        }
    }

    private enum CheckResult {
        case available(newVersion: String, notes: String, downloadURL: URL?, publishedAt: Date?)
        case upToDate
        case failed(String)
    }

    private static func performUpdateQuery(currentVersion: String) async -> CheckResult {
        guard let url = URL(string: "https://api.github.com/repos/consultanything-tech/hyperfetch/releases/latest") else {
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
                let dmgAsset = release.assets?.first(where: { $0.name.hasSuffix(".dmg") })
                let downloadURL = dmgAsset.flatMap { URL(string: $0.browserDownloadUrl) }
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
        func parseVersion(_ v: String) -> [Int] {
            let trimmed = v.trimmingCharacters(in: CharacterSet(charactersIn: "vV \t\n\r"))
            let main = trimmed.components(separatedBy: "-").first ?? trimmed
            return main.split(separator: ".").compactMap { Int($0) }
        }

        let parts1 = parseVersion(v1)
        let parts2 = parseVersion(v2)
        let count = max(parts1.count, parts2.count)
        for i in 0..<count {
            let p1 = i < parts1.count ? parts1[i] : 0
            let p2 = i < parts2.count ? parts2[i] : 0
            if p1 > p2 { return true }
            if p1 < p2 { return false }
        }
        return false
    }
}
