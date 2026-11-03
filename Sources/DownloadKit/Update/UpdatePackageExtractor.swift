//
//  UpdatePackageExtractor.swift
//  DownloadKit
//
//  Created by HyperFetch on 2026-11-03.
//

import Foundation

/// Handles decompression, volume mounting, verification, and staging of HyperFetch update packages.
public enum UpdatePackageExtractor {
    public enum ExtractionError: LocalizedError, Equatable {
        case archiveNotFound(String)
        case extractionFailed(String)
        case verificationFailed(String)

        public var errorDescription: String? {
            switch self {
            case .archiveNotFound(let msg): return msg
            case .extractionFailed(let msg): return msg
            case .verificationFailed(let msg): return msg
            }
        }
    }

    /// Extracts an update archive (.zip or .dmg) into an isolated temporary staging directory,
    /// verifies the bundle integrity, and returns the URL to the staged `HyperFetch.app`.
    @discardableResult
    public static func extractAndVerify(
        archiveURL: URL,
        newVersion: String,
        cleanArchiveAfterExtraction: Bool = true
    ) throws -> URL {
        guard FileManager.default.fileExists(atPath: archiveURL.path) else {
            throw ExtractionError.archiveNotFound("Archive not found at \(archiveURL.path)")
        }

        let stagingDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("HyperFetchUpdate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)

        let isDMG = archiveURL.pathExtension.lowercased() == "dmg"
        var stagedAppURL = stagingDir.appendingPathComponent("HyperFetch.app")

        if isDMG {
            try extractDMG(archiveURL: archiveURL, stagingDir: stagingDir, stagedAppURL: stagedAppURL)
        } else {
            try extractZIP(archiveURL: archiveURL, stagingDir: stagingDir)
        }

        // Check if stagedAppURL exists directly or inside an extracted subfolder
        if !FileManager.default.fileExists(atPath: stagedAppURL.path) {
            if let contents = try? FileManager.default.contentsOfDirectory(at: stagingDir, includingPropertiesForKeys: nil),
               let appItem = contents.first(where: { $0.pathExtension == "app" }) {
                stagedAppURL = appItem
            }
        }

        guard FileManager.default.fileExists(atPath: stagedAppURL.path) else {
            throw ExtractionError.verificationFailed("No .app bundle found in extracted package.")
        }

        // Verify that Contents/MacOS/HyperFetch exists
        let executableURL = stagedAppURL.appendingPathComponent("Contents/MacOS/HyperFetch")
        guard FileManager.default.fileExists(atPath: executableURL.path) else {
            throw ExtractionError.verificationFailed("App bundle verification failed: missing Contents/MacOS/HyperFetch.")
        }

        if cleanArchiveAfterExtraction {
            try? FileManager.default.removeItem(at: archiveURL)
        }

        return stagedAppURL
    }

    private static func extractZIP(archiveURL: URL, stagingDir: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archiveURL.path, stagingDir.path]

        let errPipe = Pipe()
        process.standardError = errPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = errPipe.fileHandleForReading.readDataToEndOfFile()
            let err = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw ExtractionError.extractionFailed("Failed to extract ZIP archive: \(err)")
        }
    }

    private static func extractDMG(archiveURL: URL, stagingDir: URL, stagedAppURL: URL) throws {
        let attachProcess = Process()
        attachProcess.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        attachProcess.arguments = ["attach", archiveURL.path, "-nobrowse", "-readonly", "-plist"]

        let outPipe = Pipe()
        let errPipe = Pipe()
        attachProcess.standardOutput = outPipe
        attachProcess.standardError = errPipe

        try attachProcess.run()
        attachProcess.waitUntilExit()

        guard attachProcess.terminationStatus == 0 else {
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let err = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw ExtractionError.extractionFailed("Failed to mount DMG: \(err)")
        }

        let plistData = outPipe.fileHandleForReading.readDataToEndOfFile()
        var mountPoint: String?

        if let plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any],
           let entities = plist["system-entities"] as? [[String: Any]] {
            for entity in entities {
                if let mp = entity["mount-point"] as? String, !mp.isEmpty {
                    mountPoint = mp
                    break
                }
            }
        }

        // Fallback string search for /Volumes/
        if mountPoint == nil {
            let outputText = String(data: plistData, encoding: .utf8) ?? ""
            for line in outputText.components(separatedBy: .newlines) {
                if let range = line.range(of: "/Volumes/") {
                    mountPoint = String(line[range.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    break
                }
            }
        }

        guard let mountPath = mountPoint, FileManager.default.fileExists(atPath: mountPath) else {
            throw ExtractionError.extractionFailed("Could not determine mount point for DMG.")
        }

        defer {
            let detachProcess = Process()
            detachProcess.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            detachProcess.arguments = ["detach", mountPath, "-force"]
            try? detachProcess.run()
            detachProcess.waitUntilExit()
        }

        let mountURL = URL(fileURLWithPath: mountPath)
        let sourceAppURL: URL
        let candidate = mountURL.appendingPathComponent("HyperFetch.app")
        if FileManager.default.fileExists(atPath: candidate.path) {
            sourceAppURL = candidate
        } else if let items = try? FileManager.default.contentsOfDirectory(at: mountURL, includingPropertiesForKeys: nil),
                  let firstApp = items.first(where: { $0.pathExtension == "app" }) {
            sourceAppURL = firstApp
        } else {
            throw ExtractionError.verificationFailed("HyperFetch.app was not found on mounted DMG volume.")
        }

        let copyProcess = Process()
        copyProcess.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        copyProcess.arguments = [sourceAppURL.path, stagedAppURL.path]

        let copyErrPipe = Pipe()
        copyProcess.standardError = copyErrPipe

        try copyProcess.run()
        copyProcess.waitUntilExit()

        guard copyProcess.terminationStatus == 0 else {
            let copyErrData = copyErrPipe.fileHandleForReading.readDataToEndOfFile()
            let copyErr = String(data: copyErrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw ExtractionError.extractionFailed("Failed to copy app bundle from DMG to staging directory: \(copyErr)")
        }
    }
}
