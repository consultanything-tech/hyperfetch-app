//
//  NativeHostManager.swift
//  DownloadKit
//
//  Manages registration and manifest generation for the Chromium
//  Native Messaging Host used by HyperFetch.
//

import Foundation

public final class NativeHostManager: Sendable {
    public static let hostName = "com.hyperfetch.native"
    public static let manifestFileName = "com.hyperfetch.native.json"
    public static let extensionId = "chhljomijnngbgaglihlgjdbebebfijl"
    public static let defaultExecutablePath = "/Applications/HyperFetch.app/Contents/MacOS/hyperfetch-host"

    /// Browser directories under ~/Library/Application Support/
    public static let browserRelativePaths: [String] = [
        "Google/Chrome",
        "Chromium",
        "BraveSoftware/Brave-Browser",
        "Microsoft Edge",
        "Arc/User Data",
        "Vivaldi"
    ]

    /// Generates the Native Messaging Host manifest JSON for Chromium-based browsers.
    public static func generateManifest(executablePath: String = defaultExecutablePath) -> String {
        return """
        {
          "name": "\(hostName)",
          "description": "HyperFetch Native Messaging Host",
          "path": "\(executablePath)",
          "type": "stdio",
          "allowed_origins": [
            "chrome-extension://\(extensionId)/"
          ]
        }
        """
    }

    /// Registers the Native Messaging Host manifest in all installed browser NativeMessagingHosts directories.
    ///
    /// - Parameters:
    ///   - executablePath: Path to the hyperfetch-host binary (defaults to auto-detected path or default path).
    ///   - baseDirectory: Optional base directory to search for browser subfolders (defaults to ~/Library/Application Support).
    ///   - fileManager: The file manager to perform directory checks and writes with.
    /// - Returns: Array of file URLs where manifests were successfully written.
    @discardableResult
    public static func registerManifests(
        executablePath: String? = nil,
        baseDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) -> [URL] {
        let appSupport: URL
        if let baseDirectory {
            appSupport = baseDirectory
        } else if let standardDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            appSupport = standardDir
        } else {
            appSupport = URL(fileURLWithPath: ("~/Library/Application Support" as NSString).expandingTildeInPath)
        }

        let resolvedPath: String
        if let explicit = executablePath, !explicit.isEmpty {
            resolvedPath = explicit
        } else {
            let bundleHost = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/hyperfetch-host")
            if fileManager.fileExists(atPath: bundleHost.path) {
                resolvedPath = bundleHost.path
            } else {
                resolvedPath = defaultExecutablePath
            }
        }

        let manifestContent = generateManifest(executablePath: resolvedPath)
        var writtenURLs: [URL] = []

        for relPath in browserRelativePaths {
            let browserDir = appSupport.appendingPathComponent(relPath)
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: browserDir.path, isDirectory: &isDir), isDir.boolValue {
                let hostsDir = browserDir.appendingPathComponent("NativeMessagingHosts")
                do {
                    if !fileManager.fileExists(atPath: hostsDir.path) {
                        try fileManager.createDirectory(at: hostsDir, withIntermediateDirectories: true)
                    }
                    let manifestURL = hostsDir.appendingPathComponent(manifestFileName)
                    try manifestContent.write(to: manifestURL, atomically: true, encoding: .utf8)
                    writtenURLs.append(manifestURL)
                } catch {
                    // Non-fatal error writing manifest to this specific browser directory
                }
            }
        }

        return writtenURLs
    }
}
