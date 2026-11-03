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
