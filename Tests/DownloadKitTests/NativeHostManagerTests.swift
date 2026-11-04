//
//  NativeHostManagerTests.swift
//  DownloadKitTests
//
//  Created by HyperFetch on 2026-11-04.
//

import Testing
import Foundation
@testable import DownloadKit

@Suite("Native Messaging Host Manager Tests")
struct NativeHostManagerTests {

    @Test("Manifest JSON generation contains required fields and valid JSON structure")
    func testGenerateManifestDefault() throws {
        let manifestJSON = NativeHostManager.generateManifest()

        guard let data = manifestJSON.data(using: .utf8) else {
            Issue.record("Manifest string could not be converted to UTF-8 data")
            return
        }

        let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(jsonObject != nil)

        #expect(jsonObject?["name"] as? String == "com.hyperfetch.native")
        #expect(jsonObject?["description"] as? String == "HyperFetch Native Messaging Host")
        #expect(jsonObject?["type"] as? String == "stdio")
        #expect(jsonObject?["path"] as? String == "/Applications/HyperFetch.app/Contents/MacOS/hyperfetch-host")

        let origins = jsonObject?["allowed_origins"] as? [String]
        #expect(origins != nil)
        #expect(origins?.contains("chrome-extension://chhljomijnngbgaglihlgjdbebebfijl/") == true)
    }

    @Test("Manifest JSON generation with custom executable path")
    func testGenerateManifestCustomPath() throws {
        let customPath = "/custom/path/to/hyperfetch-host"
        let manifestJSON = NativeHostManager.generateManifest(executablePath: customPath)

        guard let data = manifestJSON.data(using: .utf8),
              let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            Issue.record("Failed to parse custom manifest JSON")
            return
        }

        #expect(jsonObject["path"] as? String == customPath)
        #expect(jsonObject["name"] as? String == "com.hyperfetch.native")
    }

    @Test("registerManifests writes manifest file to existing browser parent directories")
    func testRegisterManifestsInMockEnvironment() throws {
        let fileManager = FileManager.default
        let tempBase = fileManager.temporaryDirectory.appendingPathComponent("NativeHostTests_\(UUID().uuidString)")
        try fileManager.createDirectory(at: tempBase, withIntermediateDirectories: true)

        defer {
            try? fileManager.removeItem(at: tempBase)
        }

        // Simulate installed Chrome and Brave
        let chromeDir = tempBase.appendingPathComponent("Google/Chrome")
        let braveDir = tempBase.appendingPathComponent("BraveSoftware/Brave-Browser")
        let edgeDir = tempBase.appendingPathComponent("Microsoft Edge")

        try fileManager.createDirectory(at: chromeDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: braveDir, withIntermediateDirectories: true)
        // Edge is deliberately NOT created to verify skipped paths

        let written = NativeHostManager.registerManifests(
            executablePath: "/Test/HyperFetch.app/Contents/MacOS/hyperfetch-host",
            baseDirectory: tempBase,
            fileManager: fileManager
        )

        #expect(written.count == 2)

        let chromeManifest = chromeDir.appendingPathComponent("NativeMessagingHosts/com.hyperfetch.native.json")
        let braveManifest = braveDir.appendingPathComponent("NativeMessagingHosts/com.hyperfetch.native.json")
        let edgeManifest = edgeDir.appendingPathComponent("NativeMessagingHosts/com.hyperfetch.native.json")

        #expect(fileManager.fileExists(atPath: chromeManifest.path))
        #expect(fileManager.fileExists(atPath: braveManifest.path))
        #expect(!fileManager.fileExists(atPath: edgeManifest.path))

        let content = try String(contentsOf: chromeManifest, encoding: .utf8)
        #expect(content.contains("com.hyperfetch.native"))
        #expect(content.contains("/Test/HyperFetch.app/Contents/MacOS/hyperfetch-host"))
        #expect(content.contains("chrome-extension://chhljomijnngbgaglihlgjdbebebfijl/"))
    }

    @Test("registerManifests executes in local user environment")
    func testRegisterLive() {
        let written = NativeHostManager.registerManifests()
        #expect(!written.isEmpty)
        print("Registered native host in live directories: \(written)")
    }
}
