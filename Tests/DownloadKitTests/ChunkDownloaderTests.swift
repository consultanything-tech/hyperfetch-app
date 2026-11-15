import Testing
import Foundation
@testable import DownloadKit

final class ChunkTestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Int

    init(_ initial: Int = 0) {
        self.value = initial
    }

    func increment() -> Int {
        lock.withLock {
            value += 1
            return value
        }
    }

    var current: Int {
        lock.withLock { value }
    }
}

// MARK: - Isolated Mock URL Protocol for ChunkDownloader Tests

final class ChunkMockURLProtocol: URLProtocol, @unchecked Sendable {
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
        ChunkMockURLProtocol.lock.withLock {
            ChunkMockURLProtocol.recordedRequests.append(request)
        }

        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let handler: Handler? = ChunkMockURLProtocol.lock.withLock {
            ChunkMockURLProtocol.handlers[url.absoluteString]
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

@Suite("ChunkDownloader Tests", .serialized)
struct ChunkDownloaderTests {
    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ChunkMockURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func createTempDir() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("HyperFetch_ChunkDownloaderTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }

    @Test("ChunkDownloader suppresses Accept-Language by default and preserves custom Accept-Language when provided")
    func testChunkDownloaderAcceptLanguage() async throws {
        ChunkMockURLProtocol.reset()
        let session = makeSession()
        let tempDir = try createTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let testURL = URL(string: "https://engine.example.com/files/chunk-lang.dat")!
        let totalSize = 100
        let data = Data(repeating: 0x41, count: totalSize)

        // 1. Default: Accept-Language is suppressed to ""
        ChunkMockURLProtocol.register(url: testURL) { request in
            #expect(request.value(forHTTPHeaderField: "Accept-Language") == "")
            #expect(request.value(forHTTPHeaderField: "User-Agent") == HTTPRangeProbe.defaultUserAgent)
            let response = HTTPURLResponse(
                url: testURL,
                statusCode: 206,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Content-Range": "bytes 0-99/100",
                    "Content-Length": "100"
                ]
            )!
            return (response, data)
        }

        let destinationURL = tempDir.appendingPathComponent("chunk-lang-1.dat")
        let writer = FileWriter(destinationURL: destinationURL)
        try await writer.allocate(totalBytes: Int64(totalSize))

        var chunk = Chunk(index: 0, startOffset: 0, endOffset: 99)
        let downloader = ChunkDownloader(session: session)

        try await downloader.download(chunk: &chunk, from: testURL, to: writer) { _ in }
        #expect(chunk.status == .completed)
        #expect(chunk.bytesDownloaded == 100)

        // 2. Custom Accept-Language provided
        ChunkMockURLProtocol.reset()
        ChunkMockURLProtocol.register(url: testURL) { request in
            #expect(request.value(forHTTPHeaderField: "Accept-Language") == "en-US,en;q=0.5")
            let response = HTTPURLResponse(
                url: testURL,
                statusCode: 206,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Content-Range": "bytes 0-99/100",
                    "Content-Length": "100"
                ]
            )!
            return (response, data)
        }

        let destinationURL2 = tempDir.appendingPathComponent("chunk-lang-2.dat")
        let writer2 = FileWriter(destinationURL: destinationURL2)
        try await writer2.allocate(totalBytes: Int64(totalSize))

        var chunk2 = Chunk(index: 0, startOffset: 0, endOffset: 99)
        try await downloader.download(chunk: &chunk2, from: testURL, to: writer2, headers: ["Accept-Language": "en-US,en;q=0.5"]) { _ in }
        #expect(chunk2.status == .completed)
        #expect(chunk2.bytesDownloaded == 100)
    }

    @Test("ChunkDownloader automatically retries on transient URLError networkConnectionLost and resumes from offset")
    func testChunkDownloaderTransientNetworkErrorRetry() async throws {
        ChunkMockURLProtocol.reset()
        let session = makeSession()
        let tempDir = try createTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let testURL = URL(string: "https://engine.example.com/files/chunk-retry-transient.dat")!
        let totalSize = 100
        let data = Data(repeating: 0x42, count: totalSize)

        let counter = ChunkTestCounter()

        ChunkMockURLProtocol.register(url: testURL) { request in
            let currentAttempt = counter.increment()

            if currentAttempt == 1 {
                throw URLError(.networkConnectionLost)
            } else {
                let response = HTTPURLResponse(
                    url: testURL,
                    statusCode: 206,
                    httpVersion: "HTTP/1.1",
                    headerFields: [
                        "Content-Range": "bytes 0-99/100",
                        "Content-Length": "100"
                    ]
                )!
                return (response, data)
            }
        }

        let destinationURL = tempDir.appendingPathComponent("chunk-transient.dat")
        let writer = FileWriter(destinationURL: destinationURL)
        try await writer.allocate(totalBytes: Int64(totalSize))

        var chunk = Chunk(index: 0, startOffset: 0, endOffset: 99)
        let downloader = ChunkDownloader(session: session)

        try await downloader.download(chunk: &chunk, from: testURL, to: writer) { _ in }
        #expect(chunk.status == .completed)
        #expect(chunk.bytesDownloaded == 100)
        #expect(counter.current == 2)
    }

    @Test("ChunkDownloader automatically retries on unexpected EOF and resumes from current offset")
    func testChunkDownloaderUnexpectedEOFRetry() async throws {
        ChunkMockURLProtocol.reset()
        let session = makeSession()
        let tempDir = try createTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let testURL = URL(string: "https://engine.example.com/files/chunk-retry-eof.dat")!
        let part1 = Data(repeating: 0x41, count: 40)
        let part2 = Data(repeating: 0x42, count: 60)

        let counter = ChunkTestCounter()

        ChunkMockURLProtocol.register(url: testURL) { request in
            let currentAttempt = counter.increment()

            if currentAttempt == 1 {
                #expect(request.value(forHTTPHeaderField: "Range") == "bytes=0-99")
                let response = HTTPURLResponse(
                    url: testURL,
                    statusCode: 206,
                    httpVersion: "HTTP/1.1",
                    headerFields: [
                        "Content-Range": "bytes 0-99/100",
                        "Content-Length": "100"
                    ]
                )!
                return (response, part1)
            } else {
                #expect(request.value(forHTTPHeaderField: "Range") == "bytes=40-99")
                let response = HTTPURLResponse(
                    url: testURL,
                    statusCode: 206,
                    httpVersion: "HTTP/1.1",
                    headerFields: [
                        "Content-Range": "bytes 40-99/100",
                        "Content-Length": "60"
                    ]
                )!
                return (response, part2)
            }
        }

        let destinationURL = tempDir.appendingPathComponent("chunk-eof.dat")
        let writer = FileWriter(destinationURL: destinationURL)
        try await writer.allocate(totalBytes: 100)

        var chunk = Chunk(index: 0, startOffset: 0, endOffset: 99)
        let downloader = ChunkDownloader(session: session)

        try await downloader.download(chunk: &chunk, from: testURL, to: writer) { _ in }
        #expect(chunk.status == .completed)
        #expect(chunk.bytesDownloaded == 100)
        #expect(counter.current == 2)
    }
}
