//
//  main.swift
//  HyperFetchNativeHost
//
//  Chrome Native Messaging Host for HyperFetch.
//  Listens on stdio for launch requests from Chromium extensions
//  and starts the HyperFetch desktop application.
//

import AppKit
import Foundation

/// Launches the HyperFetch GUI application bundle.
func launchHyperFetchApp() {
    var appURL: URL?

    let arg0 = CommandLine.arguments[0]
    let execURL = URL(fileURLWithPath: arg0).resolvingSymlinksInPath()
    let candidate = execURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    if candidate.pathExtension == "app" && FileManager.default.fileExists(atPath: candidate.path) {
        appURL = candidate
    } else {
        let defaultApp = URL(fileURLWithPath: "/Applications/HyperFetch.app")
        if FileManager.default.fileExists(atPath: defaultApp.path) {
            appURL = defaultApp
        } else if let bundleURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.hyperfetch.app") {
            appURL = bundleURL
        }
    }

    guard let targetURL = appURL else {
        fputs("[hyperfetch-host] Could not locate HyperFetch.app bundle\n", stderr)
        return
    }

    let config = NSWorkspace.OpenConfiguration()
    config.activates = false
    config.addsToRecentItems = false

    let semaphore = DispatchSemaphore(value: 0)
    NSWorkspace.shared.openApplication(at: targetURL, configuration: config) { app, error in
        if let error = error {
            fputs("[hyperfetch-host] openApplication failed: \(error.localizedDescription)\n", stderr)
        } else {
            fputs("[hyperfetch-host] HyperFetch launched successfully\n", stderr)
        }
        semaphore.signal()
    }
    _ = semaphore.wait(timeout: .now() + 2.0)
}

/// Reads a message according to the Chrome Native Messaging protocol:
/// 4 bytes little-endian length, followed by that many bytes of JSON payload.
func readNativeMessage() -> Data? {
    var length: UInt32 = 0
    let bytesRead = withUnsafeMutableBytes(of: &length) { ptr in
        read(STDIN_FILENO, ptr.baseAddress, 4)
    }
    if bytesRead <= 0 {
        return nil
    }

    let messageLength = Int(length)
    guard messageLength > 0, messageLength <= 10 * 1024 * 1024 else {
        return nil
    }

    var buffer = [UInt8](repeating: 0, count: messageLength)
    var totalRead = 0
    while totalRead < messageLength {
        let r = buffer.withUnsafeMutableBytes { ptr in
            read(STDIN_FILENO, ptr.baseAddress! + totalRead, messageLength - totalRead)
        }
        if r <= 0 {
            return nil
        }
        totalRead += r
    }

    return Data(buffer)
}

/// Writes a JSON response according to the Chrome Native Messaging protocol:
/// 4 bytes little-endian length, followed by the UTF-8 JSON payload.
func sendNativeResponse(_ jsonString: String) {
    guard let responseData = jsonString.data(using: .utf8) else { return }
    var length = UInt32(responseData.count)

    _ = withUnsafeBytes(of: &length) { ptr in
        write(STDOUT_FILENO, ptr.baseAddress, 4)
    }
    _ = responseData.withUnsafeBytes { ptr in
        write(STDOUT_FILENO, ptr.baseAddress, ptr.count)
    }
    fflush(stdout)
}

func main() {
    // Process incoming message(s) until stdin closes (EOF)
    while true {
        guard let _ = readNativeMessage() else {
            break
        }

        launchHyperFetchApp()

        let responseJSON = "{\"status\":\"ok\",\"launched\":true}"
        sendNativeResponse(responseJSON)
    }
}

main()
