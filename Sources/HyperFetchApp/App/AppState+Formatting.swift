//
//  AppState+Formatting.swift
//  HyperFetchApp
//

import Foundation

@MainActor
extension AppState {
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
}
