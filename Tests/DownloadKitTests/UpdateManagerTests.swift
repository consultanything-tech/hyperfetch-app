//
//  UpdateManagerTests.swift
//  DownloadKitTests
//
//  Created by HyperFetch on 2026-11-03.
//

import Testing
import Foundation
@testable import DownloadKit

@Suite("Auto-Update Manager & Extractor Tests")
struct UpdateManagerTests {

    // MARK: - UpdateState Tests

    @Test("UpdateState equality and case behavior")
    func testUpdateStateEquality() {
        let now = Date()
        let fileURL = URL(fileURLWithPath: "/tmp/HyperFetch.app")

        #expect(UpdateState.idle == UpdateState.idle)
        #expect(UpdateState.checking == UpdateState.checking)
        #expect(UpdateState.installing == UpdateState.installing)

        #expect(
            UpdateState.upToDate(currentVersion: "1.0.0", lastChecked: now) ==
            UpdateState.upToDate(currentVersion: "1.0.0", lastChecked: now)
        )
        #expect(
            UpdateState.upToDate(currentVersion: "1.0.0", lastChecked: now) !=
            UpdateState.upToDate(currentVersion: "1.0.1", lastChecked: now)
        )

        let updateURL = URL(string: "https://github.com/consultanything-tech/hyperfetch-app/releases/download/v1.1.0/HyperFetch.zip")
        #expect(
            UpdateState.updateAvailable(
                newVersion: "1.1.0",
                currentVersion: "1.0.0",
                releaseNotes: "Bug fixes",
                downloadURL: updateURL,
                publishedAt: now
            ) ==
            UpdateState.updateAvailable(
                newVersion: "1.1.0",
                currentVersion: "1.0.0",
                releaseNotes: "Bug fixes",
                downloadURL: updateURL,
                publishedAt: now
            )
        )

        #expect(
            UpdateState.downloading(newVersion: "1.1.0", progress: 0.5, bytesDownloaded: 500, totalBytes: 1000) ==
            UpdateState.downloading(newVersion: "1.1.0", progress: 0.5, bytesDownloaded: 500, totalBytes: 1000)
        )
        #expect(
            UpdateState.downloading(newVersion: "1.1.0", progress: 0.5, bytesDownloaded: 500, totalBytes: 1000) !=
            UpdateState.downloading(newVersion: "1.1.0", progress: 0.6, bytesDownloaded: 600, totalBytes: 1000)
        )

        #expect(UpdateState.extracting(newVersion: "1.1.0") == UpdateState.extracting(newVersion: "1.1.0"))
        #expect(UpdateState.extracting(newVersion: "1.1.0") != UpdateState.extracting(newVersion: "1.2.0"))

        #expect(
            UpdateState.readyToInstall(newVersion: "1.1.0", stagedAppURL: fileURL) ==
            UpdateState.readyToInstall(newVersion: "1.1.0", stagedAppURL: fileURL)
        )

        #expect(UpdateState.failed(error: "Network error") == UpdateState.failed(error: "Network error"))
        #expect(UpdateState.failed(error: "Network error") != UpdateState.failed(error: "Disk full"))
    }

    // MARK: - VersionComparator Tests

    @Test("VersionComparator parses and compares semver strings accurately")
    func testVersionComparator() {
        // Newer versions
        #expect(VersionComparator.isVersion("1.0.1", newerThan: "1.0.0"))
        #expect(VersionComparator.isVersion("1.1.0", newerThan: "1.0.9"))
        #expect(VersionComparator.isVersion("2.0.0", newerThan: "1.99.99"))
        #expect(VersionComparator.isVersion("1.0.0.1", newerThan: "1.0.0"))

        // Prefix handling ('v' and 'V')
        #expect(VersionComparator.isVersion("v1.2.0", newerThan: "1.1.9"))
        #expect(VersionComparator.isVersion("V2.0.0", newerThan: "v1.9.9"))

        // Suffix / Pre-release handling
        #expect(VersionComparator.isVersion("1.2.0-beta", newerThan: "1.1.0"))
        #expect(VersionComparator.isVersion("1.2.0-rc1", newerThan: "1.1.5"))

        // Equal or older versions
        #expect(!VersionComparator.isVersion("1.0.0", newerThan: "1.0.0"))
        #expect(!VersionComparator.isVersion("v1.0.0", newerThan: "1.0.0"))
        #expect(!VersionComparator.isVersion("0.9.9", newerThan: "1.0.0"))
        #expect(!VersionComparator.isVersion("1.0.0", newerThan: "1.0.1"))
        #expect(!VersionComparator.isVersion("1.1.0", newerThan: "2.0.0"))
    }

    // MARK: - UpdatePackageExtractor Tests

    @Test("UpdatePackageExtractor successfully extracts and verifies valid ZIP app bundle")
    func testExtractAndVerifyValidZip() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("TestAutoUpdate_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create mock HyperFetch.app structure
        let mockApp = tempDir.appendingPathComponent("HyperFetch.app")
        let macosDir = mockApp.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macosDir, withIntermediateDirectories: true)

        let mockExecutable = macosDir.appendingPathComponent("HyperFetch")
        let dummyPayload = "#!/bin/sh\necho HyperFetch\n"
        try dummyPayload.write(to: mockExecutable, atomically: true, encoding: .utf8)

        // Make executable
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: mockExecutable.path)

        // Zip it using /usr/bin/ditto
        let zipURL = tempDir.appendingPathComponent("HyperFetch.zip")
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-c", "-k", "--keepParent", mockApp.path, zipURL.path]
        try ditto.run()
        ditto.waitUntilExit()
        #expect(ditto.terminationStatus == 0)

        // Remove the source mockApp so we test true extraction
        try FileManager.default.removeItem(at: mockApp)

        // Extract and verify
        let stagedAppURL = try UpdatePackageExtractor.extractAndVerify(
            archiveURL: zipURL,
            newVersion: "1.2.0",
            cleanArchiveAfterExtraction: false
        )

        #expect(FileManager.default.fileExists(atPath: stagedAppURL.path))
        #expect(stagedAppURL.lastPathComponent == "HyperFetch.app")

        let stagedExec = stagedAppURL.appendingPathComponent("Contents/MacOS/HyperFetch")
        #expect(FileManager.default.fileExists(atPath: stagedExec.path))

        // Cleanup staged app folder
        try? FileManager.default.removeItem(at: stagedAppURL.deletingLastPathComponent())
    }

    @Test("UpdatePackageExtractor throws when archive is missing")
    func testExtractMissingArchive() {
        let missingURL = URL(fileURLWithPath: "/tmp/non_existent_archive_\(UUID().uuidString).zip")
        #expect(throws: UpdatePackageExtractor.ExtractionError.self) {
            try UpdatePackageExtractor.extractAndVerify(archiveURL: missingURL, newVersion: "1.0.0")
        }
    }

    @Test("UpdatePackageExtractor throws verificationFailed when app bundle lacks executable")
    func testExtractCorruptAppBundle() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("TestCorruptUpdate_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create mock App without Contents/MacOS/HyperFetch
        let mockApp = tempDir.appendingPathComponent("HyperFetch.app")
        let resourcesDir = mockApp.appendingPathComponent("Contents/Resources")
        try FileManager.default.createDirectory(at: resourcesDir, withIntermediateDirectories: true)

        let zipURL = tempDir.appendingPathComponent("HyperFetch.zip")
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-c", "-k", "--keepParent", mockApp.path, zipURL.path]
        try ditto.run()
        ditto.waitUntilExit()

        try FileManager.default.removeItem(at: mockApp)

        #expect(throws: UpdatePackageExtractor.ExtractionError.self) {
            try UpdatePackageExtractor.extractAndVerify(
                archiveURL: zipURL,
                newVersion: "1.2.0",
                cleanArchiveAfterExtraction: false
            )
        }
    }
}
