import Testing
import Foundation
import Network
@testable import DownloadKit

private final class SecurityTestMockURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data?)

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handlers: [String: Handler] = [:]

    static func reset() {
        lock.withLock {
            handlers.removeAll()
        }
    }

    static func register(url: URL, handler: @escaping Handler) {
        lock.withLock {
            handlers[url.absoluteString] = handler
        }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard let url = request.url?.absoluteString else { return false }
        return lock.withLock { handlers[url] != nil }
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let handler: Handler? = SecurityTestMockURLProtocol.lock.withLock {
            SecurityTestMockURLProtocol.handlers[url.absoluteString]
        }

        guard let handler = handler else {
            let error = URLError(.badServerResponse)
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if let data = data {
                client?.urlProtocol(self, didLoad: data)
            }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

@Suite("Security Tests", .serialized)
struct SecurityTests {

    // MARK: - Filename Sanitization & Path Traversal

    @Test("FilenameResolver.sanitize prevents path traversal and cleans unsafe inputs")
    func testFilenameResolverSanitization() {
        // Traversal sequences to leaf filename
        #expect(FilenameResolver.sanitize("../../.zshrc") == ".zshrc")
        #expect(FilenameResolver.sanitize("/etc/passwd") == "passwd")
        #expect(FilenameResolver.sanitize("foo/bar/baz.zip") == "baz.zip")
        #expect(FilenameResolver.sanitize("..\\..\\payload") == "payload")
        #expect(FilenameResolver.sanitize("nested\\folder\\doc.pdf") == "doc.pdf")

        // Dangerous or empty filenames should become empty string
        #expect(FilenameResolver.sanitize("") == "")
        #expect(FilenameResolver.sanitize(".") == "")
        #expect(FilenameResolver.sanitize("..") == "")
        #expect(FilenameResolver.sanitize("   ") == "")
        #expect(FilenameResolver.sanitize("///") == "")
        #expect(FilenameResolver.sanitize("../../") == "")
        #expect(FilenameResolver.sanitize("..\\..\\") == "")
        #expect(FilenameResolver.sanitize("/root/..") == "")

        // Null byte striping
        #expect(FilenameResolver.sanitize("archive\0.zip") == "archive.zip")
    }

    // MARK: - Destination URL Confinement

    @Test("DownloadTaskModel destination URL confinement prevents traversal out of downloads directory")
    func testDestinationURLConfinement() {
        let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads", isDirectory: true)

        let task = DownloadTaskModel(
            url: URL(string: "https://example.com/exploit")!,
            filename: "../../.zshrc"
        )

        // Filename should be sanitized to leaf
        #expect(task.filename == ".zshrc")

        // Destination URL should be standardized and confined to Downloads folder
        #expect(!task.destinationURL.path.contains(".."))
        let expectedURL = downloadsDir
            .appendingPathComponent("HyperFetch", isDirectory: true)
            .appendingPathComponent("Other", isDirectory: true)
            .appendingPathComponent(".zshrc")
            .standardizedFileURL
        #expect(task.destinationURL == expectedURL)

        // Crucially, destinationURL must not point to ~/.zshrc directly
        let homeDir = URL(fileURLWithPath: NSHomeDirectory())
        let sensitiveTarget = homeDir.appendingPathComponent(".zshrc").standardizedFileURL
        #expect(task.destinationURL != sensitiveTarget)
    }

    @Test("DownloadTaskModel falls back safely when filename is nil, empty, or pure traversal")
    func testDestinationURLFallback() {
        // nil filename falls back to url.lastPathComponent
        let taskFromURL = DownloadTaskModel(
            url: URL(string: "https://example.com/release.dmg")!,
            filename: nil
        )
        #expect(taskFromURL.filename == "release.dmg")

        // ".." sanitizes to empty string, falling back to "download"
        let taskDotDot = DownloadTaskModel(
            url: URL(string: "https://example.com/release.dmg")!,
            filename: ".."
        )
        #expect(taskDotDot.filename == "download")

        // whitespace sanitizes to empty string, URL has no component -> "download"
        let taskPureFallback = DownloadTaskModel(
            url: URL(string: "https://example.com/")!,
            filename: "  "
        )
        #expect(taskPureFallback.filename == "download")
    }

    @Test("Explicit destinationURL is standardized")
    func testExplicitDestinationStandardization() {
        let customDir = URL(fileURLWithPath: "/tmp/custom/../downloads")
        let task = DownloadTaskModel(
            url: URL(string: "https://example.com/test.zip")!,
            destinationURL: customDir.appendingPathComponent("test.zip")
        )
        #expect(!task.destinationURL.path.contains("/tmp/custom/.."))
        #expect(task.destinationURL.path == "/tmp/downloads/test.zip")
    }

    // MARK: - LocalhostBridge Path Sanitization

    @Test("LocalhostBridge sanitizes traversal in POST /add and GET /add requests")
    func testLocalhostBridgeFilenameSanitization() async throws {
        let bridge = LocalhostBridge(preferredPort: 39305, fallbackPort: 39306)

        final class CallbackBox: @unchecked Sendable {
            var url: URL?
            var filename: String?
        }
        let box = CallbackBox()

        bridge.onDownloadRequested = { url, filename, _, _ in
            box.url = url
            box.filename = filename
        }

        let port = try await bridge.start()
        defer { bridge.stop() }

        // Test POST /add with traversal filename
        var postRequest = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/add")!)
        postRequest.httpMethod = "POST"
        postRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        postRequest.setValue("extension", forHTTPHeaderField: "X-HyperFetch-Client")
        let payload1: [String: Any] = [
            "url": "https://example.com/test.dmg",
            "filename": "../../../var/root/.bashrc"
        ]
        postRequest.httpBody = try JSONSerialization.data(withJSONObject: payload1)
        let _ = try await URLSession.shared.data(for: postRequest)

        #expect(box.filename == ".bashrc")

        // Test POST /add with empty/pure traversal filename -> resolves to nil
        let payload2: [String: Any] = [
            "url": "https://example.com/test.dmg",
            "filename": "../../"
        ]
        postRequest.httpBody = try JSONSerialization.data(withJSONObject: payload2)
        let _ = try await URLSession.shared.data(for: postRequest)

        #expect(box.filename == nil)

        // Test GET /add with traversal filename
        let targetURL = "https://example.com/file.bin"
        let encodedTarget = targetURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let getURL1 = URL(string: "http://127.0.0.1:\(port)/add?url=\(encodedTarget)&filename=../../payload.bin")!
        let _ = try await URLSession.shared.data(from: getURL1)

        #expect(box.filename == "payload.bin")

        // Test GET /add with dot-dot only -> resolves to nil
        let getURL2 = URL(string: "http://127.0.0.1:\(port)/add?url=\(encodedTarget)&filename=..")!
        let _ = try await URLSession.shared.data(from: getURL2)

        #expect(box.filename == nil)
    }

    // MARK: - DNS Rebinding & Host Header Defense

    struct RawHTTPResponse: Sendable {
        let statusLine: String
        let headers: [String: String]
        let body: String
    }

    private final class RawHTTPContext: @unchecked Sendable {
        private let lock = NSLock()
        private var hasResumed = false
        private var completion: (@Sendable (Result<RawHTTPResponse, any Error>) -> Void)?

        init(completion: @escaping @Sendable (Result<RawHTTPResponse, any Error>) -> Void) {
            self.completion = completion
        }

        func complete(with result: Result<RawHTTPResponse, any Error>) {
            lock.lock()
            defer { lock.unlock() }
            guard !hasResumed else { return }
            hasResumed = true
            let comp = completion
            completion = nil
            comp?(result)
        }
    }

    private func sendRawHTTP(port: UInt16, request: String) async throws -> RawHTTPResponse {
        let connection = NWConnection(
            host: .ipv4(.loopback),
            port: NWEndpoint.Port(rawValue: port)!,
            using: .tcp
        )
        return try await withCheckedThrowingContinuation { continuation in
            let context = RawHTTPContext { result in
                continuation.resume(with: result)
            }

            connection.stateUpdateHandler = { state in
                if case .failed(let error) = state {
                    context.complete(with: .failure(error))
                }
            }
            connection.start(queue: .global())
            let data = Data(request.utf8)
            connection.send(content: data, completion: .contentProcessed { sendError in
                if let sendError = sendError {
                    context.complete(with: .failure(sendError))
                    return
                }
                connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { responseData, _, _, recvError in
                    if let recvError = recvError {
                        context.complete(with: .failure(recvError))
                    } else if let responseData = responseData, let str = String(data: responseData, encoding: .utf8) {
                        let parts = str.components(separatedBy: "\r\n\r\n")
                        let headerPart = parts.first ?? ""
                        let bodyPart = parts.count > 1 ? parts.dropFirst().joined(separator: "\r\n\r\n") : ""
                        let headerLines = headerPart.components(separatedBy: "\r\n")
                        let statusLine = headerLines.first ?? ""
                        var parsedHeaders: [String: String] = [:]
                        for line in headerLines.dropFirst() {
                            let p = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                            if p.count == 2 {
                                parsedHeaders[p[0].lowercased()] = p[1]
                            }
                        }
                        context.complete(with: .success(RawHTTPResponse(statusLine: statusLine, headers: parsedHeaders, body: bodyPart)))
                    } else {
                        context.complete(with: .success(RawHTTPResponse(statusLine: "", headers: [:], body: "")))
                    }
                    connection.cancel()
                }
            })
        }
    }

    @Test("DNS Rebinding: Host header pointing to external or attacker domain is rejected with 403 Forbidden")
    func testHostHeaderValidation() async throws {
        let bridge = LocalhostBridge(preferredPort: 39315, fallbackPort: 39316)
        let port = try await bridge.start()
        defer { bridge.stop() }

        // Test 1: Host header attacker.com
        let rawAttacker = "GET /status HTTP/1.1\r\nHost: attacker.com\r\nConnection: close\r\n\r\n"
        let res1 = try await sendRawHTTP(port: port, request: rawAttacker)
        #expect(res1.statusLine.contains("403 Forbidden"))
        #expect(res1.body.contains("Invalid or unauthorized Host header"))

        // Test 2: Host header evil.com:31415
        let rawEvil = "GET /status HTTP/1.1\r\nHost: evil.com:\(port)\r\nConnection: close\r\n\r\n"
        let res2 = try await sendRawHTTP(port: port, request: rawEvil)
        #expect(res2.statusLine.contains("403 Forbidden"))

        // Test 3: Missing Host header entirely
        let rawMissing = "GET /status HTTP/1.1\r\nConnection: close\r\n\r\n"
        let res3 = try await sendRawHTTP(port: port, request: rawMissing)
        #expect(res3.statusLine.contains("403 Forbidden"))

        // Test 4: Valid Host 127.0.0.1:<port>
        let rawValidIP = "GET /status HTTP/1.1\r\nHost: 127.0.0.1:\(port)\r\nConnection: close\r\n\r\n"
        let res4 = try await sendRawHTTP(port: port, request: rawValidIP)
        #expect(res4.statusLine.contains("200 OK"))
        #expect(res4.body.contains("\"status\" : \"ok\""))

        // Test 5: Valid Host localhost:<port>
        let rawValidLocalhost = "GET /status HTTP/1.1\r\nHost: localhost:\(port)\r\nConnection: close\r\n\r\n"
        let res5 = try await sendRawHTTP(port: port, request: rawValidLocalhost)
        #expect(res5.statusLine.contains("200 OK"))
    }

    @Test("Host and Origin helper unit validation")
    func testSecurityHelperMethods() {
        let bridge = LocalhostBridge()

        // Host validation
        #expect(bridge.isAuthorizedHost("127.0.0.1") == true)
        #expect(bridge.isAuthorizedHost("localhost") == true)
        #expect(bridge.isAuthorizedHost("127.0.0.1:31415") == true)
        #expect(bridge.isAuthorizedHost("localhost:8080") == true)
        #expect(bridge.isAuthorizedHost("LOCALHOST:31415") == true)
        #expect(bridge.isAuthorizedHost("evil.com") == false)
        #expect(bridge.isAuthorizedHost("attacker.com:31415") == false)
        #expect(bridge.isAuthorizedHost("127.0.0.1.evil.com") == false)
        #expect(bridge.isAuthorizedHost("localhost.attacker.com") == false)
        #expect(bridge.isAuthorizedHost("") == false)
        #expect(bridge.isAuthorizedHost("127.0.0.1:invalidPort") == false)

        // Origin validation
        #expect(bridge.isAuthorizedOrigin("chrome-extension://abcdefghijklmnop") == true)
        #expect(bridge.isAuthorizedOrigin("moz-extension://fedcba9876543210") == true)
        #expect(bridge.isAuthorizedOrigin("safari-web-extension://12345678-1234") == true)
        #expect(bridge.isAuthorizedOrigin("http://127.0.0.1") == true)
        #expect(bridge.isAuthorizedOrigin("http://127.0.0.1:3000") == true)
        #expect(bridge.isAuthorizedOrigin("http://localhost") == true)
        #expect(bridge.isAuthorizedOrigin("http://localhost:5173") == true)
        #expect(bridge.isAuthorizedOrigin("https://127.0.0.1:8443") == true)
        #expect(bridge.isAuthorizedOrigin("https://localhost:8443") == true)

        // Untrusted / Attack vectors
        #expect(bridge.isAuthorizedOrigin("https://evil.com") == false)
        #expect(bridge.isAuthorizedOrigin("http://malicious.org") == false)
        #expect(bridge.isAuthorizedOrigin("http://localhost.evil.com") == false)
        #expect(bridge.isAuthorizedOrigin("http://127.0.0.1.attacker.com") == false)
        #expect(bridge.isAuthorizedOrigin("null") == false)
        #expect(bridge.isAuthorizedOrigin("") == false)
    }

    @Test("Cross-site Referer or Sec-Fetch-Site on GET /add is blocked")
    func testDriveByProtectionViaReferer() async throws {
        let bridge = LocalhostBridge(preferredPort: 39325, fallbackPort: 39326)
        let port = try await bridge.start()
        defer { bridge.stop() }

        // GET /add with external web Referer
        var req1 = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/add?url=https://example.com/file.dmg")!)
        req1.setValue("https://evil.com/page.html", forHTTPHeaderField: "Referer")
        let (_, resp1) = try await URLSession.shared.data(for: req1)
        let httpResp1 = try #require(resp1 as? HTTPURLResponse)
        #expect(httpResp1.statusCode == 403)

        // GET /add with Sec-Fetch-Site: cross-site
        var req2 = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/add?url=https://example.com/file.dmg")!)
        req2.setValue("cross-site", forHTTPHeaderField: "Sec-Fetch-Site")
        let (_, resp2) = try await URLSession.shared.data(for: req2)
        let httpResp2 = try #require(resp2 as? HTTPURLResponse)
        #expect(httpResp2.statusCode == 403)
    }

    // MARK: - Symlink Traversal Defense (CWE-59)

    @Test("FileWriter rejects destination path if it is a symbolic link (CWE-59)")
    func testFileWriterRejectsSymlink() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("symlink_test_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let targetFile = tempDir.appendingPathComponent("target.txt")
        try "sensitive file content".write(to: targetFile, atomically: true, encoding: .utf8)

        let symlinkURL = tempDir.appendingPathComponent("symlink.txt")
        try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: targetFile)

        let writer = FileWriter(destinationURL: symlinkURL)
        do {
            try await writer.allocate(totalBytes: 1024)
            Issue.record("Expected allocate to fail for symlink destination")
        } catch let FileWriteError.fileCreationFailed(message) {
            #expect(message.contains("symbolic link and will not be followed"))
        } catch {
            Issue.record("Unexpected error thrown: \(error)")
        }
    }

    // MARK: - Sensitive Session Credential Purging (CWE-312)

    @Test("DownloadEngine scrubs Cookie and Authorization headers upon task completion (CWE-312)")
    func testCompletedDownloadScrubsSensitiveHeaders() async throws {
        let testURL = URL(string: "https://security.example.com/files/secure_download.bin")!
        let totalSize = 64 * 1024 // 64 KB
        let expectedData = Data((0..<totalSize).map { UInt8($0 & 0xFF) })

        SecurityTestMockURLProtocol.register(url: testURL) { request in
            if request.httpMethod == "HEAD" {
                let response = HTTPURLResponse(
                    url: testURL,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: [
                        "Content-Length": "\(totalSize)",
                        "Accept-Ranges": "bytes"
                    ]
                )!
                return (response, nil)
            } else {
                let response = HTTPURLResponse(
                    url: testURL,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Length": "\(totalSize)"]
                )!
                return (response, expectedData)
            }
        }
        defer {
            SecurityTestMockURLProtocol.reset()
        }

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SecurityTestMockURLProtocol.self]
        let session = URLSession(configuration: config)

        let task = DownloadTaskModel(
            url: testURL,
            destinationURL: tempDir.appendingPathComponent("secure_download.bin"),
            headers: [
                "Cookie": "session_id=secret_cookie_token_12345",
                "cookie": "legacy_cookie=xyz",
                "Authorization": "Bearer super_secret_bearer_token",
                "authorization": "Basic dXNlcjpwYXNz",
                "User-Agent": "HyperFetch/1.0",
                "X-Custom-Header": "KeepThisHeader"
            ]
        )

        let engine = DownloadEngine(
            session: session,
            defaultChunkCount: 1,
            minChunkSize: 64 * 1024
        )

        let completedTask = try await engine.startDownload(task: task)

        #expect(completedTask.status == .completed)
        #expect(completedTask.headers["Cookie"] == nil)
        #expect(completedTask.headers["cookie"] == nil)
        #expect(completedTask.headers["Authorization"] == nil)
        #expect(completedTask.headers["authorization"] == nil)
        #expect(completedTask.headers["User-Agent"] == "HyperFetch/1.0")
        #expect(completedTask.headers["X-Custom-Header"] == "KeepThisHeader")
    }

    // MARK: - Client Identification & Bridge Token Authentication (CWE-346)

    @Test("LocalhostBridge rejects extension origin request lacking X-HyperFetch-Client header with 403 Forbidden")
    func testExtensionOriginRequiresClientHeader() async throws {
        let bridge = LocalhostBridge(preferredPort: 39335, fallbackPort: 39336)
        let port = try await bridge.start()
        defer { bridge.stop() }

        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/status")!)
        req.setValue("chrome-extension://abcdefghijklmnop", forHTTPHeaderField: "Origin")
        // No X-HyperFetch-Client header
        let (data, resp) = try await URLSession.shared.data(for: req)
        let httpResp = try #require(resp as? HTTPURLResponse)
        #expect(httpResp.statusCode == 403)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["status"] as? String == "error")
        #expect((json?["message"] as? String)?.contains("Client authentication required") == true)
    }

    @Test("LocalhostBridge accepts extension origin request with valid X-HyperFetch-Client header")
    func testExtensionOriginWithClientHeaderAccepted() async throws {
        let bridge = LocalhostBridge(preferredPort: 39345, fallbackPort: 39346)
        let port = try await bridge.start()
        defer { bridge.stop() }

        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/status")!)
        req.setValue("chrome-extension://abcdefghijklmnop", forHTTPHeaderField: "Origin")
        req.setValue("extension", forHTTPHeaderField: "X-HyperFetch-Client")
        let (data, resp) = try await URLSession.shared.data(for: req)
        let httpResp = try #require(resp as? HTTPURLResponse)
        #expect(httpResp.statusCode == 200)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["status"] as? String == "ok")
    }

    @Test("LocalhostBridge rejects POST request lacking client identification header")
    func testPostRequestLackingClientHeaderRejected() async throws {
        let bridge = LocalhostBridge(preferredPort: 39355, fallbackPort: 39356)
        let port = try await bridge.start()
        defer { bridge.stop() }

        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/add")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = ["url": "https://example.com/file.dmg"]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (_, resp) = try await URLSession.shared.data(for: req)
        let httpResp = try #require(resp as? HTTPURLResponse)
        #expect(httpResp.statusCode == 403)
    }

    @Test("LocalhostBridge with bridgeToken enforces secret token check")
    func testBridgeTokenAuthentication() async throws {
        let secretToken = "hf_secret_token_98765"
        let bridge = LocalhostBridge(preferredPort: 39365, fallbackPort: 39366, bridgeToken: secretToken)
        let port = try await bridge.start()
        defer { bridge.stop() }

        // Request without token -> 403
        let req1 = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/status")!)
        let (_, resp1) = try await URLSession.shared.data(for: req1)
        let httpResp1 = try #require(resp1 as? HTTPURLResponse)
        #expect(httpResp1.statusCode == 403)

        // Request with wrong token -> 403
        var req2 = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/status")!)
        req2.setValue("wrong_token", forHTTPHeaderField: "X-HyperFetch-Token")
        let (_, resp2) = try await URLSession.shared.data(for: req2)
        let httpResp2 = try #require(resp2 as? HTTPURLResponse)
        #expect(httpResp2.statusCode == 403)

        // Request with correct X-HyperFetch-Token -> 200
        var req3 = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/status")!)
        req3.setValue(secretToken, forHTTPHeaderField: "X-HyperFetch-Token")
        let (data3, resp3) = try await URLSession.shared.data(for: req3)
        let httpResp3 = try #require(resp3 as? HTTPURLResponse)
        #expect(httpResp3.statusCode == 200)
        let json3 = try JSONSerialization.jsonObject(with: data3) as? [String: Any]
        #expect(json3?["status"] as? String == "ok")

        // Request with correct Authorization Bearer token -> 200
        var req4 = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/status")!)
        req4.setValue("Bearer \(secretToken)", forHTTPHeaderField: "Authorization")
        let (data4, resp4) = try await URLSession.shared.data(for: req4)
        let httpResp4 = try #require(resp4 as? HTTPURLResponse)
        #expect(httpResp4.statusCode == 200)
        let json4 = try JSONSerialization.jsonObject(with: data4) as? [String: Any]
        #expect(json4?["status"] as? String == "ok")
    }
}
