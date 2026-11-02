import Testing
import Foundation
import Network
@testable import DownloadKit

@Suite("LocalhostBridge HTTP Server Tests")
struct LocalhostBridgeTests {

    @Test("LocalhostBridge initializes with expected default configuration")
    func testInitialization() {
        let bridge = LocalhostBridge()
        #expect(bridge.preferredPort == 31415)
        #expect(bridge.fallbackPort == 31416)
        #expect(bridge.isRunning == false)
        #expect(bridge.listeningPort == nil)
    }

    @Test("LocalhostBridge starts, binds to loopback, and reports listening port")
    func testStartAndStop() async throws {
        // Use high non-standard test ports to avoid any port conflicts during parallel tests
        let bridge = LocalhostBridge(preferredPort: 39145, fallbackPort: 39146)
        let boundPort = try await bridge.start()
        #expect(boundPort == 39145 || boundPort == 39146)
        #expect(bridge.isRunning == true)
        #expect(bridge.listeningPort == boundPort)

        bridge.stop()
        #expect(bridge.isRunning == false)
        #expect(bridge.listeningPort == nil)
    }

    @Test("OPTIONS request returns 204 No Content with full CORS headers")
    func testOptionsCORSPreflight() async throws {
        let bridge = LocalhostBridge(preferredPort: 39155, fallbackPort: 39156)
        let port = try await bridge.start()
        defer { bridge.stop() }

        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/add")!)
        request.httpMethod = "OPTIONS"
        request.setValue("https://example.com", forHTTPHeaderField: "Origin")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            Issue.record("Expected HTTPURLResponse")
            return
        }

        #expect(httpResponse.statusCode == 204)
        #expect(httpResponse.allHeaderFields["Access-Control-Allow-Origin"] as? String == "*")
        #expect((httpResponse.allHeaderFields["Access-Control-Allow-Methods"] as? String)?.contains("OPTIONS") == true)
        #expect(data.isEmpty)
    }

    @Test("GET /status returns 200 OK with app information")
    func testGetStatus() async throws {
        let bridge = LocalhostBridge(preferredPort: 39165, fallbackPort: 39166)
        let port = try await bridge.start()
        defer { bridge.stop() }

        let request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/status")!)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            Issue.record("Expected HTTPURLResponse")
            return
        }

        #expect(httpResponse.statusCode == 200)
        #expect(httpResponse.value(forHTTPHeaderField: "Content-Type")?.contains("application/json") == true)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["status"] as? String == "ok")
        #expect(json?["app"] as? String == "HyperFetch")
        #expect(json?["version"] as? String == "1.0.0")
        #expect(json?["port"] as? Int == Int(port))
    }

    @Test("POST /add parses JSON payload and executes onDownloadRequested callback")
    func testPostAddDownload() async throws {
        let bridge = LocalhostBridge(preferredPort: 39175, fallbackPort: 39176)

        final class CallbackBox: @unchecked Sendable {
            var url: URL?
            var filename: String?
            var autoStart: Bool?
        }
        let box = CallbackBox()

        bridge.onDownloadRequested = { url, filename, autoStart, _ in
            box.url = url
            box.filename = filename
            box.autoStart = autoStart
        }

        let port = try await bridge.start()
        defer { bridge.stop() }

        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/add")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = [
            "url": "https://example.com/downloads/installer.dmg",
            "filename": "custom_installer.dmg",
            "autoStart": true
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            Issue.record("Expected HTTPURLResponse")
            return
        }

        #expect(httpResponse.statusCode == 200)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["status"] as? String == "ok")

        #expect(box.url?.absoluteString == "https://example.com/downloads/installer.dmg")
        #expect(box.filename == "custom_installer.dmg")
        #expect(box.autoStart == true)
    }

    @Test("POST /add rejects missing or malformed URL with 400 Bad Request")
    func testPostAddInvalid() async throws {
        let bridge = LocalhostBridge(preferredPort: 39185, fallbackPort: 39186)
        let port = try await bridge.start()
        defer { bridge.stop() }

        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/add")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = [
            "filename": "no_url.zip"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            Issue.record("Expected HTTPURLResponse")
            return
        }

        #expect(httpResponse.statusCode == 400)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["status"] as? String == "error")
    }

    @Test("GET /add parses query string parameters correctly")
    func testGetAddDownload() async throws {
        let bridge = LocalhostBridge(preferredPort: 39195, fallbackPort: 39196)

        final class CallbackBox: @unchecked Sendable {
            var url: URL?
            var filename: String?
            var autoStart: Bool?
        }
        let box = CallbackBox()

        bridge.onDownloadRequested = { url, filename, autoStart, _ in
            box.url = url
            box.filename = filename
            box.autoStart = autoStart
        }

        let port = try await bridge.start()
        defer { bridge.stop() }

        let targetURLString = "https://example.com/bigfile.iso"
        let encodedTarget = targetURLString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let getURL = URL(string: "http://127.0.0.1:\(port)/add?url=\(encodedTarget)&filename=my_iso.iso&autoStart=false")!

        let (data, response) = try await URLSession.shared.data(from: getURL)
        guard let httpResponse = response as? HTTPURLResponse else {
            Issue.record("Expected HTTPURLResponse")
            return
        }

        #expect(httpResponse.statusCode == 200)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["status"] as? String == "ok")

        #expect(box.url?.absoluteString == "https://example.com/bigfile.iso")
        #expect(box.filename == "my_iso.iso")
        #expect(box.autoStart == false)
    }

    @Test("Port fallback triggers when preferred port is occupied")
    func testPortFallback() async throws {
        let primaryPort: UInt16 = 39205
        let fallbackPort: UInt16 = 39206

        // Bind the primary port first with an initial bridge
        let blockerBridge = LocalhostBridge(preferredPort: primaryPort, fallbackPort: 39207)
        let blockerPort = try await blockerBridge.start()
        #expect(blockerPort == primaryPort)
        defer { blockerBridge.stop() }

        // Start a second bridge requesting primaryPort, should fallback to fallbackPort
        let secondBridge = LocalhostBridge(preferredPort: primaryPort, fallbackPort: fallbackPort)
        let secondPort = try await secondBridge.start()
        #expect(secondPort == fallbackPort)
        defer { secondBridge.stop() }

        #expect(secondBridge.isRunning)
        #expect(secondBridge.listeningPort == fallbackPort)
    }

    @Test("POST /add parses JSON payload with headers and passes to onDownloadRequested")
    func testPostAddWithHeaders() async throws {
        let bridge = LocalhostBridge(preferredPort: 39215, fallbackPort: 39216)

        final class CallbackBox: @unchecked Sendable {
            var url: URL?
            var filename: String?
            var autoStart: Bool?
            var headers: [String: String]?
        }
        let box = CallbackBox()

        bridge.onDownloadRequested = { url, filename, autoStart, headers in
            box.url = url
            box.filename = filename
            box.autoStart = autoStart
            box.headers = headers
        }

        let port = try await bridge.start()
        defer { bridge.stop() }

        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/add")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = [
            "url": "https://docs.google.com/document/u/0/export?format=pdf",
            "filename": "Proposal.pdf",
            "autoStart": true,
            "headers": [
                "Cookie": "SID=abc123xyz; HSID=def456",
                "User-Agent": "Mozilla/5.0 Chrome/131.0.0.0",
                "Referer": "https://docs.google.com/"
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            Issue.record("Expected HTTPURLResponse")
            return
        }

        #expect(httpResponse.statusCode == 200)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["status"] as? String == "ok")

        #expect(box.url?.absoluteString == "https://docs.google.com/document/u/0/export?format=pdf")
        #expect(box.filename == "Proposal.pdf")
        #expect(box.autoStart == true)
        #expect(box.headers?["Cookie"] == "SID=abc123xyz; HSID=def456")
        #expect(box.headers?["User-Agent"] == "Mozilla/5.0 Chrome/131.0.0.0")
        #expect(box.headers?["Referer"] == "https://docs.google.com/")
    }
}
