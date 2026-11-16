import Testing
import Foundation
@testable import DownloadKit

// MARK: - Isolated Mock URL Protocol for Engine Tests

final class EngineMockURLProtocol: URLProtocol, @unchecked Sendable {
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
        request
    }

    override func startLoading() {
        EngineMockURLProtocol.lock.withLock {
            EngineMockURLProtocol.recordedRequests.append(request)
        }

        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let handler: Handler? = EngineMockURLProtocol.lock.withLock {
            EngineMockURLProtocol.handlers[url.absoluteString]
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

@Suite("DownloadEngine Tests", .serialized)
struct DownloadEngineTests {

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [EngineMockURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func createTempDir() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("HyperFetchTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }

    // MARK: - Test 1: 4-Chunk Concurrent Download

    @Test("4-chunk concurrent download completes and file on disk matches expected payload")
    func testConcurrentFourChunkDownload() async throws {
        EngineMockURLProtocol.reset()
        let session = makeSession()
        let tempDir = try createTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let testURL = URL(string: "https://engine.example.com/files/dataset.bin")!
        let totalSize = 512 * 1024 // 512 KB
        // Create known patterned data
        let expectedData = Data((0..<totalSize).map { UInt8(($0 * 31 + 7) & 0xFF) })

        EngineMockURLProtocol.register(url: testURL) { request in
            if request.httpMethod == "HEAD" {
                let response = HTTPURLResponse(
                    url: testURL,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: [
                        "Content-Length": "\(totalSize)",
                        "Accept-Ranges": "bytes",
                        "Content-Disposition": "attachment; filename=\"dataset.bin\""
                    ]
                )!
                return (response, nil)
            } else if request.httpMethod == "GET" {
                if let rangeHeader = request.value(forHTTPHeaderField: "Range") {
                    let cleaned = rangeHeader.replacingOccurrences(of: "bytes=", with: "")
                    let parts = cleaned.split(separator: "-").map { String($0) }
                    guard parts.count == 2,
                          let start = Int(parts[0]),
                          let end = Int(parts[1]),
                          start <= end,
                          end < totalSize else {
                        let resp = HTTPURLResponse(url: testURL, statusCode: 416, httpVersion: "HTTP/1.1", headerFields: nil)!
                        return (resp, nil)
                    }

                    let chunkData = expectedData.subdata(in: start..<(end + 1))
                    let response = HTTPURLResponse(
                        url: testURL,
                        statusCode: 206,
                        httpVersion: "HTTP/1.1",
                        headerFields: [
                            "Content-Range": "bytes \(start)-\(end)/\(totalSize)",
                            "Content-Length": "\(chunkData.count)",
                            "Content-Type": "application/octet-stream"
                        ]
                    )!
                    return (response, chunkData)
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
            fatalError("Unexpected HTTP method \(request.httpMethod ?? "")")
        }

        let destinationURL = tempDir.appendingPathComponent("dataset.bin")
        let task = DownloadTaskModel(
            url: testURL,
            destinationURL: destinationURL
        )

        let engine = DownloadEngine(
            session: session,
            defaultChunkCount: 4,
            minChunkSize: 128 * 1024 // 128 KB chunks -> 512 KB / 128 KB = 4 chunks
        )

        let completedTask = try await engine.startDownload(task: task)

        #expect(completedTask.status == .completed)
        #expect(completedTask.completedAt != nil)
        #expect(completedTask.downloadedBytes == Int64(totalSize))
        #expect(completedTask.progress == 1.0)
        #expect(completedTask.chunks.count == 4)

        for chunk in completedTask.chunks {
            #expect(chunk.status == .completed)
            #expect(chunk.bytesDownloaded == chunk.expectedLength)
        }

        // Verify file content matches byte-for-byte
        let diskData = try Data(contentsOf: destinationURL)
        #expect(diskData.count == totalSize)
        #expect(diskData == expectedData)

        // Verify that 4 Range GET requests were recorded
        let requests = EngineMockURLProtocol.requests()
        let rangeRequests = requests.filter { $0.httpMethod == "GET" && $0.value(forHTTPHeaderField: "Range") != nil }
        #expect(rangeRequests.count == 4)
    }

    // MARK: - Test 2: Single-Stream Non-Range Download

    @Test("Single-stream non-range download streams directly to disk")
    func testSingleStreamNonRangeDownload() async throws {
        EngineMockURLProtocol.reset()
        let session = makeSession()
        let tempDir = try createTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let testURL = URL(string: "https://engine.example.com/stream/feed.dat")!
        let totalSize = 64 * 1024 // 64 KB
        let expectedData = Data((0..<totalSize).map { UInt8($0 & 0xFF) })

        EngineMockURLProtocol.register(url: testURL) { request in
            if request.httpMethod == "HEAD" {
                // Server returns 200 without Accept-Ranges
                let response = HTTPURLResponse(
                    url: testURL,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: [
                        "Content-Length": "\(totalSize)",
                        "Content-Disposition": "attachment; filename=\"feed.dat\""
                    ]
                )!
                return (response, nil)
            } else if request.httpMethod == "GET" {
                let response = HTTPURLResponse(
                    url: testURL,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: [
                        "Content-Length": "\(totalSize)"
                    ]
                )!
                return (response, expectedData)
            }
            fatalError("Unexpected HTTP method \(request.httpMethod ?? "")")
        }

        let destinationURL = tempDir.appendingPathComponent("feed.dat")
        let task = DownloadTaskModel(
            url: testURL,
            destinationURL: destinationURL
        )

        let engine = DownloadEngine(session: session)
        let completedTask = try await engine.startDownload(task: task)

        #expect(completedTask.status == .completed)
        #expect(completedTask.completedAt != nil)
        #expect(completedTask.downloadedBytes == Int64(totalSize))
        #expect(completedTask.progress == 1.0)
        #expect(completedTask.supportsRange == false)

        let diskData = try Data(contentsOf: destinationURL)
        #expect(diskData == expectedData)
    }

    // MARK: - Test 3: Monotonically Increasing Progress Updates

    @Test("Progress updates increase monotonically up to 1.0")
    func testProgressUpdatesMonotonicallyIncrease() async throws {
        EngineMockURLProtocol.reset()
        let session = makeSession()
        let tempDir = try createTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let testURL = URL(string: "https://engine.example.com/files/progress-test.zip")!
        let totalSize = 256 * 1024 // 256 KB
        let expectedData = Data(repeating: 0xEE, count: totalSize)

        EngineMockURLProtocol.register(url: testURL) { request in
            if request.httpMethod == "HEAD" {
                let response = HTTPURLResponse(
                    url: testURL,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: [
                        "Content-Length": "\(totalSize)",
                        "Accept-Ranges": "bytes",
                        "Content-Disposition": "attachment; filename=\"progress-test.zip\""
                    ]
                )!
                return (response, nil)
            } else {
                guard let rangeHeader = request.value(forHTTPHeaderField: "Range") else {
                    let resp = HTTPURLResponse(url: testURL, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
                    return (resp, expectedData)
                }
                let cleaned = rangeHeader.replacingOccurrences(of: "bytes=", with: "")
                let parts = cleaned.split(separator: "-").map { String($0) }
                let start = Int(parts[0])!
                let end = Int(parts[1])!
                let chunk = expectedData.subdata(in: start..<(end + 1))
                let response = HTTPURLResponse(
                    url: testURL,
                    statusCode: 206,
                    httpVersion: "HTTP/1.1",
                    headerFields: [
                        "Content-Range": "bytes \(start)-\(end)/\(totalSize)",
                        "Content-Length": "\(chunk.count)"
                    ]
                )!
                return (response, chunk)
            }
        }

        let destinationURL = tempDir.appendingPathComponent("progress-test.zip")
        let task = DownloadTaskModel(url: testURL, destinationURL: destinationURL)

        final class ProgressCollector: @unchecked Sendable {
            private let lock = NSLock()
            private var progressValues: [Double] = []
            private var downloadedBytesValues: [Int64] = []

            func record(_ task: DownloadTaskModel) {
                lock.withLock {
                    progressValues.append(task.progress)
                    downloadedBytesValues.append(task.downloadedBytes)
                }
            }

            var progress: [Double] { lock.withLock { progressValues } }
            var downloadedBytes: [Int64] { lock.withLock { downloadedBytesValues } }
        }

        let collector = ProgressCollector()
        let engine = DownloadEngine(
            session: session,
            defaultChunkCount: 2,
            minChunkSize: 128 * 1024
        )

        let completed = try await engine.startDownload(task: task) { snapshot in
            collector.record(snapshot)
        }

        #expect(completed.status == .completed)

        let progressList = collector.progress
        #expect(!progressList.isEmpty)

        // Verify monotonic progression
        var previousProgress: Double = 0.0
        for p in progressList {
            #expect(p >= previousProgress)
            #expect(p <= 1.0)
            previousProgress = p
        }

        // Final progress must reach 1.0
        #expect(progressList.last == 1.0)
    }

    // MARK: - Test 4: Error Handling on HTTP 500

    @Test("Server returns 500 during chunk download, task transitions to failed or throws")
    func testHTTP500DuringDownloadThrowsAndMarksFailed() async throws {
        EngineMockURLProtocol.reset()
        let session = makeSession()
        let tempDir = try createTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let testURL = URL(string: "https://engine.example.com/files/failing.bin")!
        let totalSize = 256 * 1024

        EngineMockURLProtocol.register(url: testURL) { request in
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
                // Fail any GET Range request with 500 Internal Server Error
                let response = HTTPURLResponse(
                    url: testURL,
                    statusCode: 500,
                    httpVersion: "HTTP/1.1",
                    headerFields: nil
                )!
                return (response, nil)
            }
        }

        let destinationURL = tempDir.appendingPathComponent("failing.bin")
        let task = DownloadTaskModel(url: testURL, destinationURL: destinationURL)

        let engine = DownloadEngine(session: session)

        await #expect(throws: (any Error).self) {
            _ = try await engine.startDownload(task: task)
        }

        if let recordedTask = await engine.task(for: task.id) {
            switch recordedTask.status {
            case .failed(let reason):
                #expect(!reason.isEmpty)
            default:
                Issue.record("Expected task status to be .failed, got \(recordedTask.status)")
            }
        }
    }

    // MARK: - Test 5: Pause and Resume Download

    @Test("Pause and resume download preserves downloaded chunks and finishes correctly")
    func testPauseAndResumeDownload() async throws {
        EngineMockURLProtocol.reset()
        let session = makeSession()
        let tempDir = try createTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let testURL = URL(string: "https://engine.example.com/files/resumable.bin")!
        let totalSize = 256 * 1024 // 256 KB
        let expectedData = Data((0..<totalSize).map { UInt8(($0 * 17) & 0xFF) })

        EngineMockURLProtocol.register(url: testURL) { request in
            if request.httpMethod == "HEAD" {
                let response = HTTPURLResponse(
                    url: testURL,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: [
                        "Content-Length": "\(totalSize)",
                        "Accept-Ranges": "bytes",
                        "Content-Disposition": "attachment; filename=\"resumable.bin\""
                    ]
                )!
                return (response, nil)
            } else {
                let rangeHeader = request.value(forHTTPHeaderField: "Range")!
                let cleaned = rangeHeader.replacingOccurrences(of: "bytes=", with: "")
                let parts = cleaned.split(separator: "-").map { String($0) }
                let start = Int(parts[0])!
                let end = Int(parts[1])!
                let chunkData = expectedData.subdata(in: start..<(end + 1))
                let response = HTTPURLResponse(
                    url: testURL,
                    statusCode: 206,
                    httpVersion: "HTTP/1.1",
                    headerFields: [
                        "Content-Range": "bytes \(start)-\(end)/\(totalSize)",
                        "Content-Length": "\(chunkData.count)"
                    ]
                )!
                return (response, chunkData)
            }
        }

        let destinationURL = tempDir.appendingPathComponent("resumable.bin")
        let task = DownloadTaskModel(
            url: testURL,
            destinationURL: destinationURL
        )

        let engine = DownloadEngine(
            session: session,
            defaultChunkCount: 2,
            minChunkSize: 128 * 1024
        )

        // Simulate a task that is cancelled midway
        let downloadTaskHandle = Task {
            try await engine.startDownload(task: task)
        }

        // Cancel the task
        downloadTaskHandle.cancel()

        _ = try? await downloadTaskHandle.value

        // Retrieve the task state from engine
        guard let pausedTask = await engine.task(for: task.id) else {
            Issue.record("Expected task to be stored in engine")
            return
        }

        // Now resume the download using the paused task
        let resumedTask = try await engine.startDownload(task: pausedTask)

        #expect(resumedTask.status == .completed)
        #expect(resumedTask.progress == 1.0)
        #expect(resumedTask.downloadedBytes == Int64(totalSize))

        let diskData = try Data(contentsOf: destinationURL)
        #expect(diskData == expectedData)
    }

    // MARK: - Test 6: ChunkDownloader Unit Test

    @Test("ChunkDownloader downloads byte range and writes to exact offset")
    func testChunkDownloaderDirect() async throws {
        EngineMockURLProtocol.reset()
        let session = makeSession()
        let tempDir = try createTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let testURL = URL(string: "https://engine.example.com/files/chunk-unit.dat")!
        let totalSize = 1000
        let expectedData = Data((0..<totalSize).map { UInt8($0 % 256) })

        EngineMockURLProtocol.register(url: testURL) { request in
            let range = request.value(forHTTPHeaderField: "Range")!
            #expect(range == "bytes=200-599")
            let subdata = expectedData.subdata(in: 200..<600)
            let response = HTTPURLResponse(
                url: testURL,
                statusCode: 206,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Content-Range": "bytes 200-599/1000",
                    "Content-Length": "400"
                ]
            )!
            return (response, subdata)
        }

        let destinationURL = tempDir.appendingPathComponent("chunk-unit.dat")
        let writer = FileWriter(destinationURL: destinationURL)
        try await writer.allocate(totalBytes: Int64(totalSize))

        var chunk = Chunk(index: 0, startOffset: 200, endOffset: 599)
        let downloader = ChunkDownloader(session: session)

        final class DeltaTracker: @unchecked Sendable {
            private let lock = NSLock()
            private var total: Int64 = 0
            func add(_ val: Int64) {
                lock.withLock { total += val }
            }
            var count: Int64 {
                lock.withLock { total }
            }
        }
        let tracker = DeltaTracker()

        try await downloader.download(chunk: &chunk, from: testURL, to: writer) { delta in
            tracker.add(delta)
        }

        #expect(chunk.status == .completed)
        #expect(chunk.bytesDownloaded == 400)
        #expect(tracker.count == 400)

        try await writer.sync()
        await writer.close()

        let diskData = try Data(contentsOf: destinationURL)
        #expect(diskData.subdata(in: 200..<600) == expectedData.subdata(in: 200..<600))
    }

    // MARK: - Test 7: Preferred Chunk Count Acceleration

    @Test("DownloadEngine respects preferredChunkCount of 8 over defaultChunkCount of 4")
    func testPreferredChunkCountEight() async throws {
        EngineMockURLProtocol.reset()
        let session = makeSession()
        let tempDir = try createTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let testURL = URL(string: "https://engine.example.com/files/turbo.bin")!
        let totalSize = 512 * 1024 // 512 KB
        let expectedData = Data((0..<totalSize).map { UInt8(($0 * 17 + 3) & 0xFF) })

        EngineMockURLProtocol.register(url: testURL) { request in
            if request.httpMethod == "HEAD" {
                let response = HTTPURLResponse(
                    url: testURL,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: [
                        "Content-Length": "\(totalSize)",
                        "Accept-Ranges": "bytes",
                        "Content-Disposition": "attachment; filename=\"turbo.bin\""
                    ]
                )!
                return (response, nil)
            } else if request.httpMethod == "GET" {
                if let rangeHeader = request.value(forHTTPHeaderField: "Range") {
                    let cleaned = rangeHeader.replacingOccurrences(of: "bytes=", with: "")
                    let parts = cleaned.split(separator: "-").map { String($0) }
                    guard parts.count == 2,
                          let start = Int(parts[0]),
                          let end = Int(parts[1]),
                          start <= end,
                          end < totalSize else {
                        let resp = HTTPURLResponse(url: testURL, statusCode: 416, httpVersion: "HTTP/1.1", headerFields: nil)!
                        return (resp, nil)
                    }

                    let chunkData = expectedData.subdata(in: start..<(end + 1))
                    let response = HTTPURLResponse(
                        url: testURL,
                        statusCode: 206,
                        httpVersion: "HTTP/1.1",
                        headerFields: [
                            "Content-Range": "bytes \(start)-\(end)/\(totalSize)",
                            "Content-Length": "\(chunkData.count)",
                            "Content-Type": "application/octet-stream"
                        ]
                    )!
                    return (response, chunkData)
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
            fatalError("Unexpected HTTP method \(request.httpMethod ?? "")")
        }

        let destinationURL = tempDir.appendingPathComponent("turbo.bin")
        let task = DownloadTaskModel(
            url: testURL,
            destinationURL: destinationURL,
            preferredChunkCount: 8
        )

        let engine = DownloadEngine(
            session: session,
            defaultChunkCount: 4,
            minChunkSize: 64 * 1024 // 512 KB / 64 KB = 8 chunks capacity
        )

        let completedTask = try await engine.startDownload(task: task)

        #expect(completedTask.status == .completed)
        #expect(completedTask.chunks.count == 8)
        #expect(completedTask.downloadedBytes == Int64(totalSize))

        for chunk in completedTask.chunks {
            #expect(chunk.status == .completed)
            #expect(chunk.bytesDownloaded == chunk.expectedLength)
        }

        let diskData = try Data(contentsOf: destinationURL)
        #expect(diskData == expectedData)
    }

    // MARK: - Test 8: Probe Failure Fallback to Single Stream

    @Test("DownloadEngine falls back to single-stream download when probing fails")
    func testProbeFailureFallsBackToSingleStreamDownload() async throws {
        EngineMockURLProtocol.reset()
        let session = makeSession()
        let tempDir = try createTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let testURL = URL(string: "https://engine.example.com/dynamic_report.php")!
        let totalSize = 1024
        let expectedData = Data(repeating: 0x42, count: totalSize)

        struct FailingProbe: HTTPProbing {
            func probe(url: URL, headers: [String: String]) async throws -> ProbeResult {
                throw ProbeError.httpError(statusCode: 500, url: url)
            }
        }

        EngineMockURLProtocol.register(url: testURL) { request in
            #expect(request.httpMethod == "GET")
            // No Range header in direct single stream
            #expect(request.value(forHTTPHeaderField: "Range") == nil)
            let response = HTTPURLResponse(
                url: testURL,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Content-Length": "\(totalSize)"
                ]
            )!
            return (response, expectedData)
        }

        let destinationURL = tempDir.appendingPathComponent("report.pdf")
        let task = DownloadTaskModel(
            url: testURL,
            destinationURL: destinationURL
        )

        let engine = DownloadEngine(
            session: session,
            probe: FailingProbe()
        )

        let completedTask = try await engine.startDownload(task: task)

        #expect(completedTask.status == .completed)
        #expect(completedTask.supportsRange == false)
        #expect(completedTask.downloadedBytes == Int64(totalSize))
        #expect(completedTask.chunks.count == 1)
        #expect(completedTask.chunks[0].endOffset == -1)

        let diskData = try Data(contentsOf: destinationURL)
        #expect(diskData == expectedData)
    }

    // MARK: - Test 9: ChunkDownloader Redirect Delegate

    @Test("ChunkDownloader redirect delegate preserves Cookie, User-Agent, and Referer headers across redirects")
    func testChunkDownloaderRedirectDelegatePreservesHeaders() async throws {
        let (_, continuation) = AsyncThrowingStream<Data, Error>.makeStream()
        defer { continuation.finish() }

        let delegate = DataTaskStreamDelegate(continuation: continuation) { _ in }

        let originalURL = URL(string: "https://chat.google.com/download/file")!
        var originalRequest = URLRequest(url: originalURL)
        originalRequest.setValue("SID=secret_cookie; HSID=auth", forHTTPHeaderField: "Cookie")
        originalRequest.setValue("Mozilla/5.0 HyperFetch", forHTTPHeaderField: "User-Agent")
        originalRequest.setValue("https://chat.google.com/", forHTTPHeaderField: "Referer")
        originalRequest.setValue("custom-val", forHTTPHeaderField: "X-Custom-Header")

        let session = URLSession(configuration: .ephemeral)
        let task = session.dataTask(with: originalRequest)

        let redirectURL = URL(string: "https://chat.usercontent.google.com/download/file")!
        let redirectResponse = HTTPURLResponse(
            url: redirectURL,
            statusCode: 302,
            httpVersion: "HTTP/1.1",
            headerFields: ["Location": redirectURL.absoluteString]
        )!

        // URLSession default behavior strips Cookie header on cross-domain redirect:
        let newRequest = URLRequest(url: redirectURL)

        await withCheckedContinuation { continuation in
            delegate.urlSession(
                session,
                task: task,
                willPerformHTTPRedirection: redirectResponse,
                newRequest: newRequest
            ) { resultRequest in
                #expect(resultRequest?.value(forHTTPHeaderField: "Cookie") == "SID=secret_cookie; HSID=auth")
                #expect(resultRequest?.value(forHTTPHeaderField: "User-Agent") == "Mozilla/5.0 HyperFetch")
                #expect(resultRequest?.value(forHTTPHeaderField: "Referer") == "https://chat.google.com/")
                #expect(resultRequest?.value(forHTTPHeaderField: "X-Custom-Header") == "custom-val")
                continuation.resume()
            }
        }
    }

    // MARK: - Test 10: Probe Filename and Category Rerouting

    @Test("DownloadEngine probe discovering filename updates category and destinationURL appropriately")
    func testProbeUpdatesCategoryAndDestinationURL() async throws {
        struct FilenameProbe: HTTPProbing {
            let discoveredFilename: String
            func probe(url: URL, headers: [String: String]) async throws -> ProbeResult {
                ProbeResult(
                    totalBytes: 500,
                    supportsRange: true,
                    filename: discoveredFilename,
                    finalURL: url
                )
            }
        }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [EngineMockURLProtocol.self]
        let session = URLSession(configuration: config)

        let testURL = URL(string: "https://engine.example.com/download?id=123")!
        let chunkData = Data(repeating: 0x55, count: 500)

        EngineMockURLProtocol.register(url: testURL) { _ in
            let response = HTTPURLResponse(
                url: testURL,
                statusCode: 206,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Content-Range": "bytes 0-499/500",
                    "Content-Length": "500"
                ]
            )!
            return (response, chunkData)
        }

        // Case A: Task created with default HyperFetch base directory
        let defaultTask = DownloadTaskModel(
            url: testURL,
            filename: "download"
        )
        #expect(defaultTask.category == .other)

        let engine = DownloadEngine(
            session: session,
            probe: FilenameProbe(discoveredFilename: "video.mp4")
        )

        let updatedTask = try await engine.startDownload(task: defaultTask)
        #expect(updatedTask.filename == "video.mp4")
        #expect(updatedTask.category == .video)
        let expectedVideoDest = DownloadTaskModel.defaultDestinationURL(for: "video.mp4", category: .video)
        #expect(updatedTask.destinationURL == expectedVideoDest)

        // Case B: Task created with custom external directory
        let customDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let customTask = DownloadTaskModel(
            url: testURL,
            filename: "tempfile",
            destinationURL: customDir.appendingPathComponent("tempfile")
        )
        let engine2 = DownloadEngine(
            session: session,
            probe: FilenameProbe(discoveredFilename: "archive.zip")
        )
        let updatedTask2 = try await engine2.startDownload(task: customTask)
        #expect(updatedTask2.filename == "archive.zip")
        #expect(updatedTask2.category == .archives)
        #expect(updatedTask2.destinationURL == customDir.appendingPathComponent("archive.zip"))
    }

    // MARK: - Test: Single-Stream Fallback when Server Returns 200 for Range Requests

    @Test("DownloadEngine seamlessly falls back to single-stream when server returns 200 OK for range request")
    func testDownloadEngineFallsBackToSingleStreamWhenServerReturns200ForRange() async throws {
        EngineMockURLProtocol.reset()
        let session = makeSession()
        let tempDir = try createTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let testURL = URL(string: "https://engine.example.com/files/Doc5959234250.zip")!
        let totalSize = 1_000_000 // 1,000,000 bytes
        let expectedData = Data((0..<totalSize).map { UInt8(($0 * 17 + 5) & 0xFF) })

        EngineMockURLProtocol.register(url: testURL) { request in
            if request.httpMethod == "HEAD" {
                let response = HTTPURLResponse(
                    url: testURL,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: [
                        "Content-Length": "\(totalSize)",
                        "Accept-Ranges": "bytes",
                        "Content-Disposition": "attachment; filename=\"Doc5959234250.zip\""
                    ]
                )!
                return (response, nil)
            } else if request.httpMethod == "GET" {
                // Backend dynamic servlet ignores Range headers and returns HTTP 200 with full payload
                let response = HTTPURLResponse(
                    url: testURL,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: [
                        "Content-Length": "\(totalSize)",
                        "Content-Type": "application/zip"
                    ]
                )!
                return (response, expectedData)
            }
            fatalError("Unexpected HTTP method \(request.httpMethod ?? "")")
        }

        let destinationURL = tempDir.appendingPathComponent("Doc5959234250.zip")
        let task = DownloadTaskModel(
            url: testURL,
            destinationURL: destinationURL
        )

        let engine = DownloadEngine(
            session: session,
            defaultChunkCount: 4,
            minChunkSize: 128 * 1024
        )

        let completedTask = try await engine.startDownload(task: task)

        #expect(completedTask.status == .completed)
        #expect(completedTask.completedAt != nil)
        #expect(completedTask.downloadedBytes == Int64(totalSize))
        #expect(completedTask.progress == 1.0)
        #expect(completedTask.supportsRange == false)

        let diskData = try Data(contentsOf: destinationURL)
        #expect(diskData.count == totalSize)
        #expect(diskData == expectedData)
    }

    // MARK: - Test: Rate-Limit (429) Fallback to Single Stream

    @Test("DownloadEngine seamlessly falls back to single-stream when server rate limits multi-chunk with HTTP 429")
    func testDownloadEngineFallsBackToSingleStreamWhenServerRateLimitsWith429() async throws {
        EngineMockURLProtocol.reset()
        let session = makeSession()
        let tempDir = try createTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let testURL = URL(string: "https://engine.example.com/files/rate_limited_video.mp4")!
        let totalSize = 1_000_000 // 1,000,000 bytes
        let expectedData = Data((0..<totalSize).map { UInt8(($0 * 31 + 7) & 0xFF) })

        EngineMockURLProtocol.register(url: testURL) { request in
            if request.httpMethod == "HEAD" {
                let response = HTTPURLResponse(
                    url: testURL,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: [
                        "Content-Length": "\(totalSize)",
                        "Accept-Ranges": "bytes",
                        "Content-Disposition": "attachment; filename=\"rate_limited_video.mp4\""
                    ]
                )!
                return (response, nil)
            } else if request.httpMethod == "GET" {
                // If request includes Range header, simulate server rejecting concurrent chunk requests with HTTP 429 Too Many Requests
                if let rangeHeader = request.value(forHTTPHeaderField: "Range"), !rangeHeader.isEmpty {
                    let response = HTTPURLResponse(
                        url: testURL,
                        statusCode: 429,
                        httpVersion: "HTTP/1.1",
                        headerFields: [
                            "Content-Type": "text/plain",
                            "Retry-After": "1"
                        ]
                    )!
                    let errorBody = Data("Too Many Requests: Concurrency limit exceeded".utf8)
                    return (response, errorBody)
                } else {
                    // Direct single-stream GET request without Range header succeeds with 200 OK
                    let response = HTTPURLResponse(
                        url: testURL,
                        statusCode: 200,
                        httpVersion: "HTTP/1.1",
                        headerFields: [
                            "Content-Length": "\(totalSize)",
                            "Content-Type": "video/mp4"
                        ]
                    )!
                    return (response, expectedData)
                }
            }
            fatalError("Unexpected HTTP method \(request.httpMethod ?? "")")
        }

        let destinationURL = tempDir.appendingPathComponent("rate_limited_video.mp4")
        let task = DownloadTaskModel(
            url: testURL,
            destinationURL: destinationURL
        )

        let engine = DownloadEngine(
            session: session,
            defaultChunkCount: 4,
            minChunkSize: 128 * 1024,
            rateLimitBackoffDuration: .milliseconds(10)
        )

        let completedTask = try await engine.startDownload(task: task)

        #expect(completedTask.status == .completed)
        #expect(completedTask.completedAt != nil)
        #expect(completedTask.downloadedBytes == Int64(totalSize))
        #expect(completedTask.progress == 1.0)
        #expect(completedTask.supportsRange == false)

        let diskData = try Data(contentsOf: destinationURL)
        #expect(diskData.count == totalSize)
        #expect(diskData == expectedData)
    }

    @Test("DownloadEngine surfaces failure when server returns HTTP 403 for chunk request")
    func testDownloadEngineSurfacesFailureOn403() async throws {
        EngineMockURLProtocol.reset()
        let session = makeSession()
        let tempDir = try createTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let testURL = URL(string: "https://engine.example.com/files/forbidden_chunk_video.mp4")!
        let totalSize = 500_000

        EngineMockURLProtocol.register(url: testURL) { request in
            if request.httpMethod == "HEAD" {
                let response = HTTPURLResponse(
                    url: testURL,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: [
                        "Content-Length": "\(totalSize)",
                        "Accept-Ranges": "bytes",
                        "Content-Disposition": "attachment; filename=\"forbidden_chunk_video.mp4\""
                    ]
                )!
                return (response, nil)
            } else if request.httpMethod == "GET" {
                if let rangeHeader = request.value(forHTTPHeaderField: "Range"), !rangeHeader.isEmpty {
                    // Simulate server rejecting concurrent chunk requests with HTTP 403 Forbidden
                    let response = HTTPURLResponse(
                        url: testURL,
                        statusCode: 403,
                        httpVersion: "HTTP/1.1",
                        headerFields: [
                            "Content-Type": "text/html"
                        ]
                    )!
                    let errorBody = Data("<html><body>403 Forbidden</body></html>".utf8)
                    return (response, errorBody)
                } else {
                    let response = HTTPURLResponse(
                        url: testURL,
                        statusCode: 200,
                        httpVersion: "HTTP/1.1",
                        headerFields: [
                            "Content-Length": "\(totalSize)",
                            "Content-Type": "video/mp4"
                        ]
                    )!
                    return (response, Data(count: totalSize))
                }
            }
            fatalError("Unexpected HTTP method \(request.httpMethod ?? "")")
        }

        let destinationURL = tempDir.appendingPathComponent("forbidden_chunk_video.mp4")
        let task = DownloadTaskModel(
            url: testURL,
            destinationURL: destinationURL
        )

        let engine = DownloadEngine(
            session: session,
            defaultChunkCount: 4,
            minChunkSize: 64 * 1024,
            rateLimitBackoffDuration: .milliseconds(10)
        )

        await #expect(throws: (any Error).self) {
            _ = try await engine.startDownload(task: task)
        }

        if let recordedTask = await engine.task(for: task.id) {
            switch recordedTask.status {
            case .failed(let reason):
                #expect(!reason.isEmpty)
            default:
                Issue.record("Expected task status to be .failed, got \(recordedTask.status)")
            }
        }
    }

    // MARK: - Error Classification Tests

    @Test("isRangeNotSupportedError returns true only for 416 and 501")
    func testErrorClassification_rangeErrors() async throws {
        let engine = DownloadEngine()
        let err416 = ChunkDownloadError.httpError(statusCode: 416)
        #expect(await engine.exposedIsRangeNotSupportedError(err416) == true)
        let err501 = ChunkDownloadError.httpError(statusCode: 501)
        #expect(await engine.exposedIsRangeNotSupportedError(err501) == true)
        let err403 = ChunkDownloadError.httpError(statusCode: 403)
        #expect(await engine.exposedIsRangeNotSupportedError(err403) == false)
        let err503 = ChunkDownloadError.httpError(statusCode: 503)
        #expect(await engine.exposedIsRangeNotSupportedError(err503) == false)
        let err429 = ChunkDownloadError.httpError(statusCode: 429)
        #expect(await engine.exposedIsRangeNotSupportedError(err429) == false)
    }

    @Test("isRateLimitError returns true for 429 and 503")
    func testErrorClassification_rateLimitErrors() async throws {
        let engine = DownloadEngine()
        let err429 = ChunkDownloadError.httpError(statusCode: 429)
        #expect(await engine.exposedIsRateLimitError(err429) == true)
        let err503 = ChunkDownloadError.httpError(statusCode: 503)
        #expect(await engine.exposedIsRateLimitError(err503) == true)
        let err403 = ChunkDownloadError.httpError(statusCode: 403)
        #expect(await engine.exposedIsRateLimitError(err403) == false)
    }
}
