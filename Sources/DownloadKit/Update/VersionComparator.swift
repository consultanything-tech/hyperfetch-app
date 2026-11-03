//
//  VersionComparator.swift
//  DownloadKit
//
//  Created by HyperFetch on 2026-11-03.
//

import Foundation

/// Utilities for semantic version parsing and comparison.
public enum VersionComparator {
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
