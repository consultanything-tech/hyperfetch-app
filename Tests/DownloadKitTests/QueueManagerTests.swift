import Testing
import Foundation
@testable import DownloadKit

// MARK: - Isolated Mock URL Protocol for Queue Tests

final class QueueMockURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data?)

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handlers: [String: Handler] = [:]
    nonisolated(unsafe) private static var activeConnections = 0
    nonisolated(unsafe) private static var maxConcurrentObserved = 0

    static func reset() {
        lock.withLock {
            handlers.removeAll()
            activeConnections = 0
            maxConcurrentObserved = 0
        }
    }

    static func maxConcurrency() -> Int {
        lock.withLock { maxConcurrentObserved }
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

        let handler: Handler? = QueueMockURLProtocol.lock.withLock {
            QueueMockURLProtocol.handlers[url.absoluteString]
        }

        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        QueueMockURLProtocol.lock.withLock {
            QueueMockURLProtocol.activeConnections += 1
            if QueueMockURLProtocol.activeConnections > QueueMockURLProtocol.maxConcurrentObserved {
                QueueMockURLProtocol.maxConcurrentObserved = QueueMockURLProtocol.activeConnections
            }
        }

        defer {
            QueueMockURLProtocol.lock.withLock {
                QueueMockURLProtocol.activeConnections -= 1
            }
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if let data {
                client?.urlProtocol(self, didLoad: data)
            }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

// MARK: - QueueManager Tests Suite

@Suite("QueueManager Tests", .serialized)
struct QueueManagerTests {

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [QueueMockURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func createTempDir() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("HyperFetchQueueTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }

    private func registerMockFile(url: URL, size: Int = 1024, delay: TimeInterval = 0.03) {
        let data = Data((0..<size).map { UInt8($0 & 0xFF) })
        let filename = url.lastPathComponent

        QueueMockURLProtocol.register(url: url) { request in
            if request.httpMethod == "HEAD" {
                let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: [
                        "Content-Length": "\(size)",
                        "Accept-Ranges": "bytes",
                        "Content-Disposition": "attachment; filename=\"\(filename)\""
                    ]
                )!
                return (response, nil)
            } else if request.httpMethod == "GET" {
                if delay > 0 {
                    Thread.sleep(forTimeInterval: delay)
                }

                if let rangeHeader = request.value(forHTTPHeaderField: "Range") {
                    let cleaned = rangeHeader.replacingOccurrences(of: "bytes=", with: "")
                    let parts = cleaned.split(separator: "-").map { String($0) }
                    if parts.count == 2,
                       let start = Int(parts[0]),
                       let end = Int(parts[1]),
                       start <= end,
                       end < size {
                        let chunk = data.subdata(in: start..<(end + 1))
                        let response = HTTPURLResponse(
                            url: url,
                            statusCode: 206,
                            httpVersion: "HTTP/1.1",
                            headerFields: [
                                "Content-Range": "bytes \(start)-\(end)/\(size)",
                                "Content-Length": "\(chunk.count)",
                                "Content-Type": "application/octet-stream"
                            ]
                        )!
                        return (response, chunk)
                    }
                }

                let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: [
                        "Content-Length": "\(size)",
                        "Content-Type": "application/octet-stream"
                    ]
                )!
                return (response, data)
            }
            let resp = HTTPURLResponse(url: url, statusCode: 405, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (resp, nil)
        }
    }

    // MARK: - Test 1: Concurrency Bounds & Auto-Drain

    @Test("Adding tasks respects maxConcurrentDownloads and auto-drains queued tasks")
    func testMaxConcurrentDownloadsAndAutoDrain() async throws {
        QueueMockURLProtocol.reset()
        let session = makeSession()
        let tempDir = try createTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let engine = DownloadEngine(session: session)
        let queueManager = QueueManager(engine: engine, maxConcurrentDownloads: 2)

        let urls = (1...4).map { URL(string: "https://queue.example.com/file\($0).bin")! }
        for url in urls {
            registerMockFile(url: url, size: 2048, delay: 0.04)
        }

        // Add 4 tasks with autoStart = true
        for (idx, url) in urls.enumerated() {
            let dest = tempDir.appendingPathComponent("file\(idx + 1).bin")
            try await queueManager.addTask(url: url, destinationURL: dest, autoStart: true)
        }

        // Concurrency should immediately be capped at 2
        let initialActive = await queueManager.activeCount
        #expect(initialActive == 2)

        let tasksSnapshot = await queueManager.tasks()
        #expect(tasksSnapshot.count == 4)
        // Task 3 and 4 should be queued/idle
        #expect(tasksSnapshot[2].status == .idle)
        #expect(tasksSnapshot[3].status == .idle)

        // Wait for all downloads to finish automatically via auto-drain
        var allCompleted = false
        for _ in 0..<80 {
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms
            let currentTasks = await queueManager.tasks()
            let completedCount = currentTasks.filter { $0.status == .completed }.count
            if completedCount == 4 {
                allCompleted = true
                break
            }
        }

        #expect(allCompleted)
        let finalActive = await queueManager.activeCount
        #expect(finalActive == 0)

        // Verify each file was downloaded and exists on disk
        for idx in 1...4 {
            let fileURL = tempDir.appendingPathComponent("file\(idx).bin")
            #expect(FileManager.default.fileExists(atPath: fileURL.path))
            let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            let fileSize = attrs[.size] as? Int64 ?? 0
            #expect(fileSize == 2048)
        }

        // Verify that max concurrency never exceeded the limit of 2
        #expect(QueueMockURLProtocol.maxConcurrency() <= 2)
    }

    // MARK: - Test 2: Pause All & Resume All

    @Test("pauseAll and resumeAll properly pause active/idle downloads and resume them")
    func testPauseAllAndResumeAll() async throws {
        QueueMockURLProtocol.reset()
        let session = makeSession()
        let tempDir = try createTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let engine = DownloadEngine(session: session)
        let queueManager = QueueManager(engine: engine, maxConcurrentDownloads: 2)

        let urls = (1...3).map { URL(string: "https://queue.example.com/pause_file\($0).bin")! }
        for url in urls {
            registerMockFile(url: url, size: 4096, delay: 0.08)
        }

        for (idx, url) in urls.enumerated() {
            let dest = tempDir.appendingPathComponent("pause_file\(idx + 1).bin")
            try await queueManager.addTask(url: url, destinationURL: dest, autoStart: true)
        }

        // Give them a moment to start
        try await Task.sleep(nanoseconds: 20_000_000)

        // Pause all
        await queueManager.pauseAll()

        let activeAfterPause = await queueManager.activeCount
        #expect(activeAfterPause == 0)

        let tasksAfterPause = await queueManager.tasks()
        for task in tasksAfterPause {
            #expect(task.status == .paused)
        }

        // Resume all
        try await queueManager.resumeAll()

        // Wait for completion
        var finished = false
        for _ in 0..<80 {
            try await Task.sleep(nanoseconds: 50_000_000)
            let currentTasks = await queueManager.tasks()
            if currentTasks.allSatisfy({ $0.status == .completed }) {
                finished = true
                break
            }
        }

        #expect(finished)
        let finalActive = await queueManager.activeCount
        #expect(finalActive == 0)
    }

    // MARK: - Test 3: Queue Reordering (moveTask)

    @Test("moveTask reorders the queue correctly with bounds clamping")
    func testQueueReordering() async throws {
        let queueManager = QueueManager(maxConcurrentDownloads: 1)

        let urlA = URL(string: "https://queue.example.com/a.bin")!
        let urlB = URL(string: "https://queue.example.com/b.bin")!
        let urlC = URL(string: "https://queue.example.com/c.bin")!
        let urlD = URL(string: "https://queue.example.com/d.bin")!

        let taskA = try await queueManager.addTask(url: urlA, filename: "A.bin", autoStart: false)
        let taskB = try await queueManager.addTask(url: urlB, filename: "B.bin", autoStart: false)
        let taskC = try await queueManager.addTask(url: urlC, filename: "C.bin", autoStart: false)
        let taskD = try await queueManager.addTask(url: urlD, filename: "D.bin", autoStart: false)

        var current = await queueManager.tasks().map(\.id)
        #expect(current == [taskA.id, taskB.id, taskC.id, taskD.id])

        // Move D to index 0 -> [D, A, B, C]
        await queueManager.moveTask(id: taskD.id, toIndex: 0)
        current = await queueManager.tasks().map(\.id)
        #expect(current == [taskD.id, taskA.id, taskB.id, taskC.id])

        // Move D to index 2 -> [A, B, D, C]
        await queueManager.moveTask(id: taskD.id, toIndex: 2)
        current = await queueManager.tasks().map(\.id)
        #expect(current == [taskA.id, taskB.id, taskD.id, taskC.id])

        // Move A to index 100 (clamp to end) -> [B, D, C, A]
        await queueManager.moveTask(id: taskA.id, toIndex: 100)
        current = await queueManager.tasks().map(\.id)
        #expect(current == [taskB.id, taskD.id, taskC.id, taskA.id])

        // Move non-existent ID is a no-op
        await queueManager.moveTask(id: UUID(), toIndex: 0)
        current = await queueManager.tasks().map(\.id)
        #expect(current == [taskB.id, taskD.id, taskC.id, taskA.id])
    }

    // MARK: - Test 4: Removing Task & Deleting File

    @Test("removeTask deletes from queue, and deleteFile flag controls disk removal")
    func testRemoveTaskAndFileDeletion() async throws {
        let tempDir = try createTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let stateStorageURL = tempDir.appendingPathComponent("tasks.json")
        let persister = JSONStatePersister(storageURL: stateStorageURL)
        let queueManager = QueueManager(statePersister: persister, maxConcurrentDownloads: 2)

        let file1URL = tempDir.appendingPathComponent("keep_file.bin")
        let file2URL = tempDir.appendingPathComponent("delete_file.bin")

        // Create actual files on disk
        try "payload1".data(using: .utf8)!.write(to: file1URL)
        try "payload2".data(using: .utf8)!.write(to: file2URL)

        #expect(FileManager.default.fileExists(atPath: file1URL.path))
        #expect(FileManager.default.fileExists(atPath: file2URL.path))

        let task1 = try await queueManager.addTask(
            url: URL(string: "https://queue.example.com/keep.bin")!,
            destinationURL: file1URL,
            autoStart: false
        )
        let task2 = try await queueManager.addTask(
            url: URL(string: "https://queue.example.com/delete.bin")!,
            destinationURL: file2URL,
            autoStart: false
        )

        #expect(await queueManager.tasks().count == 2)

        // Case A: Remove task1 with deleteFile: false
        try await queueManager.removeTask(id: task1.id, deleteFile: false)
        #expect(await queueManager.tasks().count == 1)
        #expect(await queueManager.task(for: task1.id) == nil)
        // File must still exist
        #expect(FileManager.default.fileExists(atPath: file1URL.path))

        // Case B: Remove task2 with deleteFile: true
        try await queueManager.removeTask(id: task2.id, deleteFile: true)
        #expect(await queueManager.tasks().isEmpty)
        #expect(await queueManager.task(for: task2.id) == nil)
        // File must be deleted from disk
        #expect(!FileManager.default.fileExists(atPath: file2URL.path))
    }

    // MARK: - Test 5: Dynamic Max Concurrent Downloads

    @Test("Dynamically updating maxConcurrentDownloads schedules pending tasks immediately")
    func testDynamicMaxConcurrentDownloads() async throws {
        QueueMockURLProtocol.reset()
        let session = makeSession()
        let tempDir = try createTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let engine = DownloadEngine(session: session)
        let queueManager = QueueManager(engine: engine, maxConcurrentDownloads: 1)

        let urls = (1...3).map { URL(string: "https://queue.example.com/dynamic\($0).bin")! }
        for url in urls {
            registerMockFile(url: url, size: 2048, delay: 0.05)
        }

        for (idx, url) in urls.enumerated() {
            let dest = tempDir.appendingPathComponent("dynamic\(idx + 1).bin")
            try await queueManager.addTask(url: url, destinationURL: dest, autoStart: true)
        }

        // With limit = 1, only 1 task should be active
        let activeInitial = await queueManager.activeCount
        #expect(activeInitial == 1)

        // Increase limit to 3
        await queueManager.setMaxConcurrentDownloads(3)

        // Give scheduler a brief moment to dispatch
        try await Task.sleep(nanoseconds: 20_000_000)

        // Now active count should be up to 3
        let activeAfterIncrease = await queueManager.activeCount
        #expect(activeAfterIncrease > 1)

        // Wait for all to complete
        var done = false
        for _ in 0..<80 {
            try await Task.sleep(nanoseconds: 50_000_000)
            let tasks = await queueManager.tasks()
            if tasks.allSatisfy({ $0.status == .completed }) {
                done = true
                break
            }
        }
        #expect(done)
    }

    // MARK: - Test 6: Speed Limit & Rate Limiter Passthrough

    @Test("QueueManager speed limit forwards to rate limiter")
    func testSpeedLimitPassthrough() async throws {
        let limiter = TokenBucketRateLimiter(bytesPerSecond: 10_000)
        let queueManager = QueueManager(rateLimiter: limiter)

        let initialSpeed = await queueManager.rateLimiter?.bytesPerSecond
        #expect(initialSpeed == 10_000)

        await queueManager.setSpeedLimit(50_000)
        let updatedSpeed = await queueManager.rateLimiter?.bytesPerSecond
        #expect(updatedSpeed == 50_000)
    }

    // MARK: - Test 7: QueueUpdates AsyncStream Observation

    @Test("queueUpdates AsyncStream yields updates when tasks are added and completed")
    func testQueueUpdatesStream() async throws {
        QueueMockURLProtocol.reset()
        let session = makeSession()
        let tempDir = try createTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let engine = DownloadEngine(session: session)
        let queueManager = QueueManager(engine: engine, maxConcurrentDownloads: 1)

        let testURL = URL(string: "https://queue.example.com/stream_test.bin")!
        registerMockFile(url: testURL, size: 1024, delay: 0.01)

        let updatesStream = await queueManager.queueUpdates

        let collectorTask = Task<Int, Never> {
            var receivedSnapshots = 0
            for await snapshot in updatesStream {
                receivedSnapshots += 1
                if let task = snapshot.first, task.status == .completed {
                    break
                }
            }
            return receivedSnapshots
        }

        let dest = tempDir.appendingPathComponent("stream_test.bin")
        try await queueManager.addTask(url: testURL, destinationURL: dest, autoStart: true)

        let totalSnapshots = await collectorTask.value
        #expect(totalSnapshots >= 2) // Initial empty/added + progress/completion
    }
}
