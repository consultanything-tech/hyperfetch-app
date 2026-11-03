import Testing
import Foundation
@testable import DownloadKit

// MARK: - Mock URL Protocol

final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data?)

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handlers: [String: Handler] = [:]
    nonisolated(unsafe) private static var recordedRequests: [URLRequest] = []

    static func reset() {
        lock.withLock {
            handlers.removeAll()
            recordedRequests.removeAll()
        }
    }

    static func register(url: URL, handler: @escaping Handler) {
        lock.withLock {
            handlers[url.absoluteString] = handler
        }
    }

    static func requests() -> [URLRequest] {
        lock.withLock { recordedRequests }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard let url = request.url?.absoluteString else { return false }
        return lock.withLock { handlers[url] != nil }
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        MockURLProtocol.lock.withLock {
            MockURLProtocol.recordedRequests.append(request)
        }

        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let handler: Handler? = MockURLProtocol.lock.withLock {
            MockURLProtocol.handlers[url.absoluteString]
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

// MARK: - HTTPRangeProbe Tests

@Suite("HTTPRangeProbe Tests", .serialized)
struct HTTPRangeProbeTests {

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    // MARK: - Case A: Server supports HEAD + Accept-Ranges

    @Test("Case A: Server supports HEAD + Accept-Ranges with Content-Length and Content-Disposition")
    func testServerSupportsHEADAndRanges() async throws {
        MockURLProtocol.reset()
        let testURL = URL(string: "https://cdn.example.com/files/archive-v1.zip")!
        let session = makeSession()

        MockURLProtocol.register(url: testURL) { request in
            #expect(request.httpMethod == "HEAD")
            let response = HTTPURLResponse(
                url: testURL,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Content-Length": "104857600", // 100 MB
                    "Accept-Ranges": "bytes",
                    "Content-Disposition": "attachment; filename=\"custom-archive.zip\"",
                    "ETag": "\"etag-12345\"",
                    "Last-Modified": "Wed, 21 Oct 2025 07:28:00 GMT"
                ]
            )!
            return (response, nil)
        }

        let probe = HTTPRangeProbe(session: session)
        let result = try await probe.probe(url: testURL)

        #expect(result.totalBytes == 104_857_600)
        #expect(result.supportsRange == true)
        #expect(result.filename == "custom-archive.zip")
        #expect(result.etag == "\"etag-12345\"")
        #expect(result.lastModified == "Wed, 21 Oct 2025 07:28:00 GMT")
        #expect(result.finalURL == testURL)

        // Only 1 HEAD request should be performed
        let requests = MockURLProtocol.requests()
        #expect(requests.count == 1)
        #expect(requests.first?.httpMethod == "HEAD")
    }

    // MARK: - Case B: Server rejects HEAD with 405, fallback to GET Range responds 206

    @Test("Case B: Server rejects HEAD with 405, responds 206 to GET Range bytes=0-0")
    func testServerRejectsHEADWith405FallbackToGET206() async throws {
        MockURLProtocol.reset()
        let testURL = URL(string: "https://api.example.com/download/file")!
        let session = makeSession()

        MockURLProtocol.register(url: testURL) { request in
            if request.httpMethod == "HEAD" {
                let response = HTTPURLResponse(
                    url: testURL,
                    statusCode: 405,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Allow": "GET"]
                )!
                return (response, nil)
            } else if request.httpMethod == "GET" {
                #expect(request.value(forHTTPHeaderField: "Range") == "bytes=0-0")
                let response = HTTPURLResponse(
                    url: testURL,
                    statusCode: 206,
                    httpVersion: "HTTP/1.1",
                    headerFields: [
                        "Content-Range": "bytes 0-0/52428800",
                        "Content-Length": "1",
                        "Content-Disposition": "attachment; filename=\"video.mp4\"",
                        "ETag": "\"vid-etag-99\""
                    ]
                )!
                return (response, Data([0x00]))
            } else {
                fatalError("Unexpected method \(request.httpMethod ?? "")")
            }
        }

        let probe = HTTPRangeProbe(session: session)
        let result = try await probe.probe(url: testURL)

        #expect(result.totalBytes == 52_428_800)
        #expect(result.supportsRange == true)
        #expect(result.filename == "video.mp4")
        #expect(result.etag == "\"vid-etag-99\"")
        #expect(result.finalURL == testURL)

        let requests = MockURLProtocol.requests()
        #expect(requests.count == 2)
        #expect(requests[0].httpMethod == "HEAD")
        #expect(requests[1].httpMethod == "GET")
        #expect(requests[1].value(forHTTPHeaderField: "Range") == "bytes=0-0")
    }

    // MARK: - Case C: Server returns 200 OK without Accept-Ranges (chunking not supported)

    @Test("Case C: Server returns 200 OK without Accept-Ranges (stream only)")
    func testServerDoesNotSupportRangesStreamOnly() async throws {
        MockURLProtocol.reset()
        let testURL = URL(string: "https://stream.example.com/live/data.bin")!
        let session = makeSession()

        MockURLProtocol.register(url: testURL) { request in
            if request.httpMethod == "HEAD" {
                // HEAD returns 200, but without Accept-Ranges
                let response = HTTPURLResponse(
                    url: testURL,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: [
                        "Content-Length": "8192"
                    ]
                )!
                return (response, nil)
            } else if request.httpMethod == "GET" {
                // Server ignores Range header and returns 200 OK
                let response = HTTPURLResponse(
                    url: testURL,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: [
                        "Content-Length": "8192"
                    ]
                )!
                return (response, Data(repeating: 0xAB, count: 8192))
            } else {
                fatalError("Unexpected method \(request.httpMethod ?? "")")
            }
        }

        let probe = HTTPRangeProbe(session: session)
        let result = try await probe.probe(url: testURL)

        #expect(result.totalBytes == 8192)
        #expect(result.supportsRange == false)
        #expect(result.filename == "data.bin")

        let requests = MockURLProtocol.requests()
        #expect(requests.count == 2)
        #expect(requests[0].httpMethod == "HEAD")
        #expect(requests[1].httpMethod == "GET")
    }

    // MARK: - Case D: Filename parsing

    @Test("Case D: Filename parsing variants (RFC 5987, standard quoted, fallback, sanitized)")
    func testFilenameParsingVariants() async throws {
        MockURLProtocol.reset()
        let session = makeSession()

        // 1. RFC 5987 UTF-8 encoded filename
        let url1 = URL(string: "https://example.com/rfc5987")!
        MockURLProtocol.register(url: url1) { _ in
            let resp = HTTPURLResponse(
                url: url1,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Accept-Ranges": "bytes",
                    "Content-Length": "100",
                    "Content-Disposition": "attachment; filename*=UTF-8''%e2%82%ac%20rates%20%26%20charges.pdf"
                ]
            )!
            return (resp, nil)
        }

        let probe = HTTPRangeProbe(session: session)
        let res1 = try await probe.probe(url: url1)
        #expect(res1.filename == "€ rates & charges.pdf")

        // 2. RFC 5987 takes precedence over standard filename
        let url2 = URL(string: "https://example.com/precedence")!
        MockURLProtocol.register(url: url2) { _ in
            let resp = HTTPURLResponse(
                url: url2,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Accept-Ranges": "bytes",
                    "Content-Length": "100",
                    "Content-Disposition": "attachment; filename=\"fallback.zip\"; filename*=UTF-8''primary_utf8.zip"
                ]
            )!
            return (resp, nil)
        }
        let res2 = try await probe.probe(url: url2)
        #expect(res2.filename == "primary_utf8.zip")

        // 3. Standard quoted filename with spaces and unescaping
        let url3 = URL(string: "https://example.com/quoted")!
        MockURLProtocol.register(url: url3) { _ in
            let resp = HTTPURLResponse(
                url: url3,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Accept-Ranges": "bytes",
                    "Content-Length": "100",
                    "Content-Disposition": "attachment; filename=\"Quarterly Report 2026.docx\""
                ]
            )!
            return (resp, nil)
        }
        let res3 = try await probe.probe(url: url3)
        #expect(res3.filename == "Quarterly Report 2026.docx")

        // 4. URL path fallback with query parameters stripped
        let url4 = URL(string: "https://example.com/dist/setup-v2.1.dmg?token=secret123&expire=999")!
        MockURLProtocol.register(url: url4) { _ in
            let resp = HTTPURLResponse(
                url: url4,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Accept-Ranges": "bytes",
                    "Content-Length": "100"
                ]
            )!
            return (resp, nil)
        }
        let res4 = try await probe.probe(url: url4)
        #expect(res4.filename == "setup-v2.1.dmg")

        // 5. URL path fallback with percent-encoding
        let url5 = URL(string: "https://example.com/files/My%20App%20Installer.pkg")!
        MockURLProtocol.register(url: url5) { _ in
            let resp = HTTPURLResponse(
                url: url5,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Accept-Ranges": "bytes",
                    "Content-Length": "100"
                ]
            )!
            return (resp, nil)
        }
        let res5 = try await probe.probe(url: url5)
        #expect(res5.filename == "My App Installer.pkg")

        // 6. Path traversal sanitization in Content-Disposition
        let url6 = URL(string: "https://example.com/traversal")!
        MockURLProtocol.register(url: url6) { _ in
            let resp = HTTPURLResponse(
                url: url6,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Accept-Ranges": "bytes",
                    "Content-Length": "100",
                    "Content-Disposition": "attachment; filename=\"../../../../etc/passwd.zip\""
                ]
            )!
            return (resp, nil)
        }
        let res6 = try await probe.probe(url: url6)
        #expect(res6.filename == "passwd.zip")

        // 7. Root URL or empty path falls back to "download"
        let url7 = URL(string: "https://example.com/")!
        MockURLProtocol.register(url: url7) { _ in
            let resp = HTTPURLResponse(
                url: url7,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Accept-Ranges": "bytes",
                    "Content-Length": "100"
                ]
            )!
            return (resp, nil)
        }
        let res7 = try await probe.probe(url: url7)
        #expect(res7.filename == "download")

        // 8. Content-Disposition inline with no filename falls back to URL
        let url8 = URL(string: "https://example.com/assets/presentation.key")!
        MockURLProtocol.register(url: url8) { _ in
            let resp = HTTPURLResponse(
                url: url8,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Accept-Ranges": "bytes",
                    "Content-Length": "500",
                    "Content-Disposition": "inline"
                ]
            )!
            return (resp, nil)
        }
        let res8 = try await probe.probe(url: url8)
        #expect(res8.filename == "presentation.key")
    }

    // MARK: - Case E: Error handling on HTTP 404 / 500

    @Test("Case E: Error handling on HTTP 404 Not Found")
    func testHTTP404Error() async throws {
        MockURLProtocol.reset()
        let notFoundURL = URL(string: "https://example.com/missing-file.zip")!
        let session = makeSession()

        MockURLProtocol.register(url: notFoundURL) { _ in
            let resp = HTTPURLResponse(
                url: notFoundURL,
                statusCode: 404,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            return (resp, nil)
        }

        let probe = HTTPRangeProbe(session: session)
        await #expect(throws: ProbeError.self) {
            try await probe.probe(url: notFoundURL)
        }

        do {
            _ = try await probe.probe(url: notFoundURL)
        } catch let ProbeError.httpError(statusCode, url) {
            #expect(statusCode == 404)
            #expect(url == notFoundURL)
        } catch {
            Issue.record("Expected ProbeError.httpError, got \(error)")
        }
    }

    @Test("Case E: Error handling on HTTP 500 Internal Server Error")
    func testHTTP500Error() async throws {
        MockURLProtocol.reset()
        let serverErrorURL = URL(string: "https://example.com/broken-endpoint")!
        let session = makeSession()

        MockURLProtocol.register(url: serverErrorURL) { _ in
            let resp = HTTPURLResponse(
                url: serverErrorURL,
                statusCode: 500,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            return (resp, nil)
        }

        let probe = HTTPRangeProbe(session: session)
        await #expect(throws: ProbeError.self) {
            try await probe.probe(url: serverErrorURL)
        }
    }

    // MARK: - Additional Cases: 501 Not Implemented, Invalid scheme, 416 Empty File

    @Test("HEAD 501 Not Implemented falls back to GET Range 206")
    func testHEAD501FallbackToGET() async throws {
        MockURLProtocol.reset()
        let testURL = URL(string: "https://example.com/resource")!
        let session = makeSession()

        MockURLProtocol.register(url: testURL) { req in
            if req.httpMethod == "HEAD" {
                let resp = HTTPURLResponse(
                    url: testURL,
                    statusCode: 501,
                    httpVersion: "HTTP/1.1",
                    headerFields: nil
                )!
                return (resp, nil)
            } else {
                let resp = HTTPURLResponse(
                    url: testURL,
                    statusCode: 206,
                    httpVersion: "HTTP/1.1",
                    headerFields: [
                        "Content-Range": "bytes 0-0/1000",
                        "Content-Disposition": "attachment; filename=\"res.bin\""
                    ]
                )!
                return (resp, Data([0x01]))
            }
        }

        let probe = HTTPRangeProbe(session: session)
        let result = try await probe.probe(url: testURL)
        #expect(result.supportsRange == true)
        #expect(result.totalBytes == 1000)
        #expect(result.filename == "res.bin")
    }

    @Test("Invalid URL Scheme throws invalidURL")
    func testInvalidURLScheme() async throws {
        let probe = HTTPRangeProbe()
        let ftpURL = URL(string: "ftp://files.example.com/data.tar")!

        await #expect(throws: ProbeError.self) {
            try await probe.probe(url: ftpURL)
        }

        do {
            _ = try await probe.probe(url: ftpURL)
        } catch let ProbeError.invalidURL(url) {
            #expect(url == ftpURL)
        } catch {
            Issue.record("Expected ProbeError.invalidURL, got \(error)")
        }
    }

    @Test("HEAD 200 without Accept-Ranges falls back to GET Range 206")
    func testHEAD200WithoutAcceptRangesFallsBackToGET206() async throws {
        MockURLProtocol.reset()
        let testURL = URL(string: "https://example.com/unadvertised-range")!
        let session = makeSession()

        MockURLProtocol.register(url: testURL) { req in
            if req.httpMethod == "HEAD" {
                let resp = HTTPURLResponse(
                    url: testURL,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Length": "12345"]
                )!
                return (resp, nil)
            } else {
                let resp = HTTPURLResponse(
                    url: testURL,
                    statusCode: 206,
                    httpVersion: "HTTP/1.1",
                    headerFields: [
                        "Content-Range": "bytes 0-0/12345",
                        "Content-Disposition": "attachment; filename=\"data.bin\""
                    ]
                )!
                return (resp, Data([0xFF]))
            }
        }

        let probe = HTTPRangeProbe(session: session)
        let result = try await probe.probe(url: testURL)
        #expect(result.supportsRange == true)
        #expect(result.totalBytes == 12345)
        #expect(result.filename == "data.bin")
    }

    @Test("Server returns 416 for 0-byte file with Content-Range bytes */0")
    func testZeroByteFileOn416() async throws {
        MockURLProtocol.reset()
        let testURL = URL(string: "https://example.com/empty-file.txt")!
        let session = makeSession()

        MockURLProtocol.register(url: testURL) { req in
            if req.httpMethod == "HEAD" {
                let resp = HTTPURLResponse(
                    url: testURL,
                    statusCode: 405,
                    httpVersion: "HTTP/1.1",
                    headerFields: nil
                )!
                return (resp, nil)
            } else {
                let resp = HTTPURLResponse(
                    url: testURL,
                    statusCode: 416,
                    httpVersion: "HTTP/1.1",
                    headerFields: [
                        "Content-Range": "bytes */0"
                    ]
                )!
                return (resp, nil)
            }
        }

        let probe = HTTPRangeProbe(session: session)
        let result = try await probe.probe(url: testURL)
        #expect(result.supportsRange == true)
        #expect(result.totalBytes == 0)
        #expect(result.filename == "empty-file.txt")
    }

    @Test("Indeterminate stream size with Content-Range bytes 0-0/* returns -1")
    func testIndeterminateStreamSize() async throws {
        MockURLProtocol.reset()
        let testURL = URL(string: "https://example.com/stream.m3u8")!
        let session = makeSession()

        MockURLProtocol.register(url: testURL) { req in
            if req.httpMethod == "HEAD" {
                let resp = HTTPURLResponse(
                    url: testURL,
                    statusCode: 405,
                    httpVersion: "HTTP/1.1",
                    headerFields: nil
                )!
                return (resp, nil)
            } else {
                let resp = HTTPURLResponse(
                    url: testURL,
                    statusCode: 206,
                    httpVersion: "HTTP/1.1",
                    headerFields: [
                        "Content-Range": "bytes 0-0/*"
                    ]
                )!
                return (resp, Data([0x00]))
            }
        }

        let probe = HTTPRangeProbe(session: session)
        let result = try await probe.probe(url: testURL)
        #expect(result.supportsRange == true)
        #expect(result.totalBytes == -1)
    }

    @Test("Network failure throws networkError")
    func testNetworkFailureThrowsNetworkError() async throws {
        MockURLProtocol.reset()
        let testURL = URL(string: "https://example.com/offline")!
        let session = makeSession()

        MockURLProtocol.register(url: testURL) { _ in
            throw URLError(.notConnectedToInternet)
        }

        let probe = HTTPRangeProbe(session: session)
        await #expect(throws: ProbeError.self) {
            try await probe.probe(url: testURL)
        }
    }

    @Test("ProbeError description messages")
    func testProbeErrorDescriptions() {
        let sampleURL = URL(string: "https://example.com/test")!
        #expect(ProbeError.invalidURL(sampleURL).errorDescription?.contains("Invalid or unsupported") == true)
        #expect(ProbeError.invalidResponse.errorDescription?.contains("invalid or non-HTTP") == true)
        #expect(ProbeError.httpError(statusCode: 404, url: sampleURL).errorDescription?.contains("HTTP error 404") == true)
        #expect(ProbeError.networkError("timeout").errorDescription?.contains("Network failure") == true)
        #expect(ProbeError.cancelled.errorDescription?.contains("cancelled") == true)
    }

    // MARK: - Headers and Cookies Verification

    @Test("Headers and cookies are attached to probe requests and default browser User-Agent is used")
    func testHeadersAndCookiesAttached() async throws {
        MockURLProtocol.reset()
        let testURL = URL(string: "https://authenticated.example.com/file.zip")!
        let session = makeSession()

        MockURLProtocol.register(url: testURL) { request in
            #expect(request.value(forHTTPHeaderField: "Cookie") == "session_token=secret123")
            #expect(request.value(forHTTPHeaderField: "Referer") == "https://authenticated.example.com/dashboard")
            #expect(request.value(forHTTPHeaderField: "User-Agent") == HTTPRangeProbe.defaultUserAgent)

            let response = HTTPURLResponse(
                url: testURL,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Content-Length": "2048",
                    "Accept-Ranges": "bytes",
                    "Content-Disposition": "attachment; filename=\"file.zip\""
                ]
            )!
            return (response, nil)
        }

        let probe = HTTPRangeProbe(session: session)
        let headers = [
            "Cookie": "session_token=secret123",
            "Referer": "https://authenticated.example.com/dashboard"
        ]
        let result = try await probe.probe(url: testURL, headers: headers)
        #expect(result.supportsRange == true)
        #expect(result.totalBytes == 2048)
        #expect(result.filename == "file.zip")
    }

    @Test("HEAD 401 falls back to GET Range with cookies and succeeds")
    func testHead401FallsBackToGetWithCookies() async throws {
        MockURLProtocol.reset()
        let testURL = URL(string: "https://docs.google.com/document/u/0/export?format=pdf")!
        let session = makeSession()

        MockURLProtocol.register(url: testURL) { request in
            if request.httpMethod == "HEAD" {
                // Google Docs export rejects HEAD with 401
                let response = HTTPURLResponse(
                    url: testURL,
                    statusCode: 401,
                    httpVersion: "HTTP/1.1",
                    headerFields: nil
                )!
                return (response, nil)
            } else {
                #expect(request.httpMethod == "GET")
                #expect(request.value(forHTTPHeaderField: "Cookie") == "SID=valid_cookie")
                #expect(request.value(forHTTPHeaderField: "Range") == "bytes=0-0")
                let response = HTTPURLResponse(
                    url: testURL,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: [
                        "Content-Length": "524288",
                        "Content-Disposition": "attachment; filename=\"Document.pdf\""
                    ]
                )!
                return (response, Data([0x25, 0x50, 0x44, 0x46]))
            }
        }

        let probe = HTTPRangeProbe(session: session)
        let headers = [
            "Cookie": "SID=valid_cookie",
            "User-Agent": "CustomAgent/1.0"
        ]
        let result = try await probe.probe(url: testURL, headers: headers)
        #expect(result.supportsRange == false)
        #expect(result.totalBytes == 524288)
        #expect(result.filename == "Document.pdf")
    }

    @Test("HEAD returns 500 (like Google Chat attachments), falls back to GET Range 206")
    func testHead500FallsBackToGetRange206() async throws {
        MockURLProtocol.reset()
        let testURL = URL(string: "https://chat.usercontent.google.com/download/attachment.zip")!
        let session = makeSession()

        MockURLProtocol.register(url: testURL) { request in
            if request.httpMethod == "HEAD" {
                let response = HTTPURLResponse(
                    url: testURL,
                    statusCode: 500,
                    httpVersion: "HTTP/1.1",
                    headerFields: nil
                )!
                return (response, nil)
            } else if request.httpMethod == "GET" && request.value(forHTTPHeaderField: "Range") != nil {
                let response = HTTPURLResponse(
                    url: testURL,
                    statusCode: 206,
                    httpVersion: "HTTP/1.1",
                    headerFields: [
                        "Content-Range": "bytes 0-0/10485760",
                        "Content-Disposition": "attachment; filename=\"report.pdf\"",
                        "ETag": "\"etag-attachment\""
                    ]
                )!
                return (response, Data([0x25]))
            } else {
                fatalError("Unexpected request")
            }
        }

        let probe = HTTPRangeProbe(session: session)
        let result = try await probe.probe(url: testURL)

        #expect(result.supportsRange == true)
        #expect(result.totalBytes == 10_485_760)
        #expect(result.filename == "report.pdf")
        #expect(result.etag == "\"etag-attachment\"")
    }

    @Test("HEAD and GET Range both return 500, falls back to plain GET 200")
    func testHeadAndGetRange500FallsBackToPlainGet200() async throws {
        MockURLProtocol.reset()
        let testURL = URL(string: "https://example.com/reports_financial_profit_loss1.php")!
        let session = makeSession()

        MockURLProtocol.register(url: testURL) { request in
            if request.httpMethod == "HEAD" {
                let response = HTTPURLResponse(url: testURL, statusCode: 500, httpVersion: "HTTP/1.1", headerFields: nil)!
                return (response, nil)
            } else if request.httpMethod == "GET" && request.value(forHTTPHeaderField: "Range") != nil {
                let response = HTTPURLResponse(url: testURL, statusCode: 500, httpVersion: "HTTP/1.1", headerFields: nil)!
                return (response, nil)
            } else if request.httpMethod == "GET" && request.value(forHTTPHeaderField: "Range") == nil {
                let response = HTTPURLResponse(
                    url: testURL,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: [
                        "Content-Length": "2048",
                        "Content-Disposition": "attachment; filename=\"profit_loss.xlsx\""
                    ]
                )!
                return (response, Data(repeating: 0x50, count: 2048))
            } else {
                fatalError("Unexpected request")
            }
        }

        let probe = HTTPRangeProbe(session: session)
        let result = try await probe.probe(url: testURL)

        #expect(result.supportsRange == false)
        #expect(result.totalBytes == 2048)
        #expect(result.filename == "profit_loss.xlsx")
    }

    @Test("HTTPRangeProbe redirect delegate preserves Cookie, User-Agent, and Referer across cross-domain redirects")
    func testHTTPProbeRedirectDelegatePreservesHeaders() async throws {
        let delegate = HTTPProbeRedirectDelegate()

        let originalURL = URL(string: "https://chat.google.com/doc")!
        var originalRequest = URLRequest(url: originalURL)
        originalRequest.setValue("session_id=abc123", forHTTPHeaderField: "Cookie")
        originalRequest.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        originalRequest.setValue("https://chat.google.com/", forHTTPHeaderField: "Referer")

        let session = URLSession(configuration: .ephemeral)
        let task = session.dataTask(with: originalRequest)

        let redirectURL = URL(string: "https://chat.usercontent.google.com/doc")!
        let redirectResponse = HTTPURLResponse(
            url: redirectURL,
            statusCode: 302,
            httpVersion: "HTTP/1.1",
            headerFields: ["Location": redirectURL.absoluteString]
        )!

        let newRequest = URLRequest(url: redirectURL)

        await withCheckedContinuation { continuation in
            delegate.urlSession(
                session,
                task: task,
                willPerformHTTPRedirection: redirectResponse,
                newRequest: newRequest
            ) { resultRequest in
                #expect(resultRequest?.value(forHTTPHeaderField: "Cookie") == "session_id=abc123")
                #expect(resultRequest?.value(forHTTPHeaderField: "User-Agent") == "Mozilla/5.0")
                #expect(resultRequest?.value(forHTTPHeaderField: "Referer") == "https://chat.google.com/")
                continuation.resume()
            }
        }
    }
}
