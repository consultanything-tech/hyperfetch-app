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

    @Test("OPTIONS request with authorized extension origin returns 204 No Content with reflected CORS headers")
    func testOptionsCORSPreflight() async throws {
        let bridge = LocalhostBridge(preferredPort: 39155, fallbackPort: 39156)
        let port = try await bridge.start()
        defer { bridge.stop() }

        let extensionOrigin = "chrome-extension://abcdefghijklmnop"
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/add")!)
        request.httpMethod = "OPTIONS"
        request.setValue(extensionOrigin, forHTTPHeaderField: "Origin")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            Issue.record("Expected HTTPURLResponse")
            return
        }

        #expect(httpResponse.statusCode == 204)
        #expect(httpResponse.value(forHTTPHeaderField: "Access-Control-Allow-Origin") == extensionOrigin)
        #expect(httpResponse.value(forHTTPHeaderField: "Vary") == "Origin")
        #expect(httpResponse.value(forHTTPHeaderField: "Access-Control-Allow-Methods")?.contains("OPTIONS") == true)
        #expect(data.isEmpty)
    }

    @Test("OPTIONS request with untrusted origin is rejected with 403 Forbidden")
    func testOptionsCORSPreflightRejectedForExternalOrigin() async throws {
        let bridge = LocalhostBridge(preferredPort: 39157, fallbackPort: 39158)
        let port = try await bridge.start()
        defer { bridge.stop() }

        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/add")!)
        request.httpMethod = "OPTIONS"
        request.setValue("https://evil.com", forHTTPHeaderField: "Origin")

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            Issue.record("Expected HTTPURLResponse")
            return
        }

        #expect(httpResponse.statusCode == 403)
        #expect(httpResponse.value(forHTTPHeaderField: "Access-Control-Allow-Origin") == nil)
    }

    @Test("External origin requests to GET /status and POST /add are rejected with 403 Forbidden")
    func testExternalOriginRejected() async throws {
        let bridge = LocalhostBridge(preferredPort: 39159, fallbackPort: 39160)
        let port = try await bridge.start()
        defer { bridge.stop() }

        // GET /status with untrusted Origin
        var getReq = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/status")!)
        getReq.setValue("https://malicious.com", forHTTPHeaderField: "Origin")
        let (getData, getResp) = try await URLSession.shared.data(for: getReq)
        let getHttp = try #require(getResp as? HTTPURLResponse)
        #expect(getHttp.statusCode == 403)
        #expect(getHttp.value(forHTTPHeaderField: "Access-Control-Allow-Origin") == nil)
        let getJson = try JSONSerialization.jsonObject(with: getData) as? [String: Any]
        #expect(getJson?["status"] as? String == "error")
        #expect((getJson?["message"] as? String)?.contains("Cross-origin access from external web origin prohibited") == true)

        // POST /add with untrusted Origin
        var postReq = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/add")!)
        postReq.httpMethod = "POST"
        postReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        postReq.setValue("https://evil.org", forHTTPHeaderField: "Origin")
        let payload: [String: Any] = ["url": "https://example.com/exploit.dmg"]
        postReq.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (postData, postResp) = try await URLSession.shared.data(for: postReq)
        let postHttp = try #require(postResp as? HTTPURLResponse)
        #expect(postHttp.statusCode == 403)
        #expect(postHttp.value(forHTTPHeaderField: "Access-Control-Allow-Origin") == nil)
        let postJson = try JSONSerialization.jsonObject(with: postData) as? [String: Any]
        #expect(postJson?["status"] as? String == "error")
    }

    @Test("Authorized extension and loopback origins succeed with 200 and reflected CORS header")
    func testAuthorizedOriginsSucceed() async throws {
        let bridge = LocalhostBridge(preferredPort: 39161, fallbackPort: 39162)
        let port = try await bridge.start()
        defer { bridge.stop() }

        let allowedOrigins = [
            "chrome-extension://abcdefghijklmnop",
            "moz-extension://fedcba9876543210",
            "safari-web-extension://12345678-1234-1234-1234-1234567890ab",
            "http://127.0.0.1:3000",
            "http://localhost:5173"
        ]

        for origin in allowedOrigins {
            var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/status")!)
            req.setValue(origin, forHTTPHeaderField: "Origin")
            req.setValue("extension", forHTTPHeaderField: "X-HyperFetch-Client")
            let (_, resp) = try await URLSession.shared.data(for: req)
            let httpResp = try #require(resp as? HTTPURLResponse)
            #expect(httpResp.statusCode == 200)
            #expect(httpResp.value(forHTTPHeaderField: "Access-Control-Allow-Origin") == origin)
            #expect(httpResp.value(forHTTPHeaderField: "Vary") == "Origin")
        }
    }

    @Test("Direct CLI request without Origin header succeeds without CORS headers")
    func testDirectCallWithoutOrigin() async throws {
        let bridge = LocalhostBridge(preferredPort: 39163, fallbackPort: 39164)
        let port = try await bridge.start()
        defer { bridge.stop() }

        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/status")!)
        // Ensure Origin is not set
        req.setValue(nil, forHTTPHeaderField: "Origin")
        let (_, resp) = try await URLSession.shared.data(for: req)
        let httpResp = try #require(resp as? HTTPURLResponse)
        #expect(httpResp.statusCode == 200)
        #expect(httpResp.value(forHTTPHeaderField: "Access-Control-Allow-Origin") == nil)
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
        #expect(json?["version"] as? String == "1.1.1")
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
        request.setValue("extension", forHTTPHeaderField: "X-HyperFetch-Client")
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
        request.setValue("extension", forHTTPHeaderField: "X-HyperFetch-Client")
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
        request.setValue("extension", forHTTPHeaderField: "X-HyperFetch-Client")
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
