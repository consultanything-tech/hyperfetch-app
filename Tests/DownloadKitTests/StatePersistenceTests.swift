//
//  StatePersistenceTests.swift
//  DownloadKitTests
//

import Testing
import Foundation
@testable import DownloadKit

// MARK: - Isolated Mock URL Protocol for Persistence Tests

final class PersistenceMockURLProtocol: URLProtocol, @unchecked Sendable {
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

        let handler: Handler? = PersistenceMockURLProtocol.lock.withLock {
            PersistenceMockURLProtocol.handlers[url.absoluteString]
        }

        guard let handler else {
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

@Suite("StatePersistence Tests", .serialized)
struct StatePersistenceTests {

    private func createTempDir() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("HyperFetchPersistTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [PersistenceMockURLProtocol.self]
        return URLSession(configuration: config)
    }

    // MARK: - Test 1: Save and Load Collection of Tasks

    @Test("Save and load collection of tasks with chunks, statuses, categories, and timestamps")
    func testSaveAndLoadCollectionOfTasks() async throws {
        let tempDir = try createTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("tasks.json")
        let persister = JSONStatePersister(storageURL: fileURL)

        let date1 = Date(timeIntervalSince1970: 1700000000)
        let date2 = Date(timeIntervalSince1970: 1700003600)

        let task1 = DownloadTaskModel(
            id: UUID(),
            url: URL(string: "https://example.com/app.dmg")!,
            filename: "app.dmg",
            destinationURL: tempDir.appendingPathComponent("app.dmg"),
            totalBytes: 10_000_000,
            downloadedBytes: 5_000_000,
            status: .paused,
            chunks: [
                Chunk(index: 0, startOffset: 0, endOffset: 4_999_999, bytesDownloaded: 5_000_000, status: .completed),
                Chunk(index: 1, startOffset: 5_000_000, endOffset: 9_999_999, bytesDownloaded: 0, status: .pending)
            ],
            supportsRange: true,
            createdAt: date1,
            completedAt: nil,
            category: .applications
        )

        let task2 = DownloadTaskModel(
            id: UUID(),
            url: URL(string: "https://example.com/song.mp3")!,
            filename: "song.mp3",
            destinationURL: tempDir.appendingPathComponent("song.mp3"),
            totalBytes: 4_000_000,
            downloadedBytes: 4_000_000,
            status: .completed,
            chunks: [
                Chunk(index: 0, startOffset: 0, endOffset: 3_999_999, bytesDownloaded: 4_000_000, status: .completed)
            ],
            supportsRange: true,
            createdAt: date1,
            completedAt: date2,
            category: .music
        )

        let task3 = DownloadTaskModel(
            id: UUID(),
            url: URL(string: "https://example.com/archive.zip")!,
            filename: "archive.zip",
            destinationURL: tempDir.appendingPathComponent("archive.zip"),
            totalBytes: 20_000_000,
            downloadedBytes: 1_000_000,
            status: .failed(reason: "Server disconnected"),
            chunks: [],
            supportsRange: false,
            createdAt: date2,
            category: .archives
        )

        let originalTasks = [task1, task2, task3]
        try await persister.save(tasks: originalTasks)

        // Verify file exists on disk
        #expect(FileManager.default.fileExists(atPath: fileURL.path))

        let loadedTasks = try await persister.load()
        #expect(loadedTasks.count == 3)

        // Find corresponding tasks
        guard let loaded1 = loadedTasks.first(where: { $0.id == task1.id }),
              let loaded2 = loadedTasks.first(where: { $0.id == task2.id }),
              let loaded3 = loadedTasks.first(where: { $0.id == task3.id }) else {
            Issue.record("Failed to find all loaded tasks by ID")
            return
        }

        #expect(loaded1.filename == task1.filename)
        #expect(loaded1.destinationURL == task1.destinationURL)
        #expect(loaded1.totalBytes == task1.totalBytes)
        #expect(loaded1.downloadedBytes == task1.downloadedBytes)
        #expect(loaded1.status == .paused)
        #expect(loaded1.category == .applications)
        #expect(loaded1.chunks.count == 2)
        #expect(loaded1.chunks[0].status == .completed)
        #expect(loaded1.chunks[1].status == .pending)

        #expect(loaded2.status == .completed)
        #expect(loaded2.completedAt != nil)
        #expect(loaded2.category == .music)

        #expect(loaded3.status == .failed(reason: "Server disconnected"))
        #expect(loaded3.category == .archives)
    }

    // MARK: - Test 2: Atomic Write and Parent Directory Creation

    @Test("Atomic write creates nested parent directory if it does not exist")
    func testAtomicWriteAndDirectoryCreation() async throws {
        let tempDir = try createTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let nestedDir = tempDir.appendingPathComponent("a/b/c/nested")
        let storageURL = nestedDir.appendingPathComponent("state.json")

        #expect(!FileManager.default.fileExists(atPath: nestedDir.path))

        let persister = JSONStatePersister(storageURL: storageURL)
        let sampleTask = DownloadTaskModel(
            url: URL(string: "https://example.com/test.dat")!,
            filename: "test.dat"
        )

        try await persister.save(tasks: [sampleTask])

        #expect(FileManager.default.fileExists(atPath: nestedDir.path))
        #expect(FileManager.default.fileExists(atPath: storageURL.path))

        let loaded = try await persister.load()
        #expect(loaded.count == 1)
        #expect(loaded.first?.id == sampleTask.id)
    }

    // MARK: - Test 3: Auto-Recovery

    @Test("Auto-recovery converts downloading and probing tasks to paused and resets speed")
    func testAutoRecoveryRule() async throws {
        let tempDir = try createTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let storageURL = tempDir.appendingPathComponent("recovery_test.json")
        let persister = JSONStatePersister(storageURL: storageURL)

        // Task 1: Downloading state with active downloading chunk
        let downloadingTask = DownloadTaskModel(
            id: UUID(),
            url: URL(string: "https://example.com/downloading.bin")!,
            filename: "downloading.bin",
            totalBytes: 1000,
            downloadedBytes: 300,
            status: .downloading,
            chunks: [
                Chunk(index: 0, startOffset: 0, endOffset: 499, bytesDownloaded: 300, status: .downloading),
                Chunk(index: 1, startOffset: 500, endOffset: 999, bytesDownloaded: 0, status: .pending)
            ],
            supportsRange: true,
            bytesPerSecond: 102400.0
        )

        // Task 2: Probing state
        let probingTask = DownloadTaskModel(
            id: UUID(),
            url: URL(string: "https://example.com/probing.bin")!,
            filename: "probing.bin",
            status: .probing,
            bytesPerSecond: 5000.0
        )

        // Task 3: Completed state (should stay completed)
        let completedTask = DownloadTaskModel(
            id: UUID(),
            url: URL(string: "https://example.com/completed.bin")!,
            filename: "completed.bin",
            totalBytes: 500,
            downloadedBytes: 500,
            status: .completed
        )

        // Task 4: Idle state (should stay idle)
        let idleTask = DownloadTaskModel(
            id: UUID(),
            url: URL(string: "https://example.com/idle.bin")!,
            filename: "idle.bin",
            status: .idle
        )

        try await persister.save(tasks: [downloadingTask, probingTask, completedTask, idleTask])

        let recoveredTasks = try await persister.load()

        guard let recoveredDownload = recoveredTasks.first(where: { $0.id == downloadingTask.id }),
              let recoveredProbe = recoveredTasks.first(where: { $0.id == probingTask.id }),
              let recoveredComplete = recoveredTasks.first(where: { $0.id == completedTask.id }),
              let recoveredIdle = recoveredTasks.first(where: { $0.id == idleTask.id }) else {
            Issue.record("Failed to find all recovered tasks")
            return
        }

        // Downloading task recovered to paused
        #expect(recoveredDownload.status == .paused)
        #expect(recoveredDownload.bytesPerSecond == 0.0)
        #expect(recoveredDownload.downloadedBytes == 300)
        #expect(recoveredDownload.chunks[0].status == .pending) // Downloading chunk reset to pending
        #expect(recoveredDownload.chunks[0].bytesDownloaded == 300)

        // Probing task recovered to paused
        #expect(recoveredProbe.status == .paused)
        #expect(recoveredProbe.bytesPerSecond == 0.0)

        // Completed task preserved
        #expect(recoveredComplete.status == .completed)

        // Idle task preserved
        #expect(recoveredIdle.status == .idle)
    }

    // MARK: - Test 4: Corrupted JSON and Non-Existent File Handling

    @Test("Corrupted JSON data returns empty array without throwing")
    func testCorruptedJSONHandling() async throws {
        let tempDir = try createTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let storageURL = tempDir.appendingPathComponent("corrupted.json")
        let persister = JSONStatePersister(storageURL: storageURL)

        // Sub-case A: File does not exist
        let nonExistentResult = try await persister.load()
        #expect(nonExistentResult.isEmpty)

        // Sub-case B: Truncated JSON
        let truncatedJSON = "[{\"id\": \"1234\", \"filename\": \"truncated"
        try truncatedJSON.data(using: .utf8)!.write(to: storageURL)
        let truncatedResult = try await persister.load()
        #expect(truncatedResult.isEmpty)

        // Sub-case C: Random binary noise
        let randomBytes = Data((0..<500).map { UInt8(($0 * 13) & 0xFF) })
        try randomBytes.write(to: storageURL)
        let noiseResult = try await persister.load()
        #expect(noiseResult.isEmpty)

        // Sub-case D: Empty file (0 bytes)
        try Data().write(to: storageURL)
        let emptyResult = try await persister.load()
        #expect(emptyResult.isEmpty)

        // Sub-case E: JSON array with invalid object schema
        let invalidSchemaJSON = "[{\"randomKey\": 42, \"anotherKey\": true}]"
        try invalidSchemaJSON.data(using: .utf8)!.write(to: storageURL)
        let invalidSchemaResult = try await persister.load()
        #expect(invalidSchemaResult.isEmpty)
    }

    // MARK: - Test 5: Individual Task Save and Delete Operations

    @Test("saveTask and deleteTask handle individual task updates and removals")
    func testIndividualTaskUpdates() async throws {
        let tempDir = try createTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let storageURL = tempDir.appendingPathComponent("crud_test.json")
        let persister = JSONStatePersister(storageURL: storageURL)

        let taskA = DownloadTaskModel(
            url: URL(string: "https://example.com/taskA.zip")!,
            filename: "taskA.zip",
            totalBytes: 5000,
            downloadedBytes: 1000,
            status: .downloading
        )
        let taskB = DownloadTaskModel(
            url: URL(string: "https://example.com/taskB.tar")!,
            filename: "taskB.tar",
            totalBytes: 10000,
            downloadedBytes: 2000,
            status: .paused
        )

        // Save task A
        try await persister.saveTask(taskA)
        var loaded = try await persister.load()
        #expect(loaded.count == 1)
        #expect(loaded.first?.id == taskA.id)

        // Save task B
        try await persister.saveTask(taskB)
        loaded = try await persister.load()
        #expect(loaded.count == 2)

        // Update task A
        var updatedTaskA = taskA
        updatedTaskA.downloadedBytes = 3500
        updatedTaskA.status = .paused
        try await persister.saveTask(updatedTaskA)

        loaded = try await persister.load()
        #expect(loaded.count == 2)
        let fetchedA = loaded.first(where: { $0.id == taskA.id })
        #expect(fetchedA?.downloadedBytes == 3500)
        #expect(fetchedA?.status == .paused)

        // Delete task A
        try await persister.deleteTask(id: taskA.id)
        loaded = try await persister.load()
        #expect(loaded.count == 1)
        #expect(loaded.first?.id == taskB.id)

        // Deleting non-existent task is a safe no-op
        try await persister.deleteTask(id: UUID())
        loaded = try await persister.load()
        #expect(loaded.count == 1)

        // Delete task B
        try await persister.deleteTask(id: taskB.id)
        loaded = try await persister.load()
        #expect(loaded.isEmpty)
    }

    // MARK: - Test 6: End-to-End Download, Pause, Persist, Restore, Resume

    @Test("End-to-end: download with engine, pause, persist, restore in new engine, resume to completion")
    func testEndToEndDownloadPausePersistResume() async throws {
        PersistenceMockURLProtocol.reset()
        let session = makeSession()
        let tempDir = try createTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let testURL = URL(string: "https://engine.example.com/files/stateful-download.bin")!
        let totalSize = 512 * 1024 // 512 KB
        let expectedData = Data((0..<totalSize).map { UInt8(($0 * 43 + 19) & 0xFF) })

        PersistenceMockURLProtocol.register(url: testURL) { request in
            if request.httpMethod == "HEAD" {
                let response = HTTPURLResponse(
                    url: testURL,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: [
                        "Content-Length": "\(totalSize)",
                        "Accept-Ranges": "bytes",
                        "Content-Disposition": "attachment; filename=\"stateful-download.bin\""
                    ]
                )!
                return (response, nil)
            } else if request.httpMethod == "GET" {
                guard let rangeHeader = request.value(forHTTPHeaderField: "Range") else {
                    let resp = HTTPURLResponse(url: testURL, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
                    return (resp, expectedData)
                }
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
                        "Content-Length": "\(chunkData.count)",
                        "Content-Type": "application/octet-stream"
                    ]
                )!
                return (response, chunkData)
            }
            fatalError("Unexpected HTTP method \(request.httpMethod ?? "")")
        }

        let stateStorageURL = tempDir.appendingPathComponent("engine_state.json")
        let destinationURL = tempDir.appendingPathComponent("stateful-download.bin")

        let persister = JSONStatePersister(storageURL: stateStorageURL)
        let initialEngine = DownloadEngine(
            session: session,
            statePersister: persister,
            defaultChunkCount: 4,
            minChunkSize: 128 * 1024 // 4 chunks of 128 KB
        )

        let initialTask = DownloadTaskModel(
            url: testURL,
            destinationURL: destinationURL
        )

        let (startedStream, startedContinuation) = AsyncStream<Void>.makeStream()

        // Start download and cancel it midway once chunks are partitioned
        let downloadJob = Task {
            try await initialEngine.startDownload(task: initialTask) { snapshot in
                if snapshot.status == .downloading {
                    startedContinuation.yield()
                }
            }
        }

        // Wait until download enters downloading state, then cancel to simulate pause
        for await _ in startedStream {
            downloadJob.cancel()
            break
        }
        _ = try? await downloadJob.value

        // Allow any asynchronous state checkpointing to complete
        let persistedTasks = try await persister.load()
        #expect(!persistedTasks.isEmpty)
        guard let savedTask = persistedTasks.first(where: { $0.id == initialTask.id }) else {
            Issue.record("Persisted task was not found")
            return
        }

        #expect(savedTask.status == .paused)
        #expect(savedTask.supportsRange == true)
        #expect(savedTask.chunks.count == 4)

        // Simulate application restart: new engine instance, same storage
        let secondPersister = JSONStatePersister(storageURL: stateStorageURL)
        let newEngine = DownloadEngine(
            session: session,
            statePersister: secondPersister,
            defaultChunkCount: 4,
            minChunkSize: 128 * 1024
        )

        let restoredTasks = try await newEngine.restoreTasks()
        #expect(restoredTasks.count == 1)
        let taskToResume = restoredTasks[0]
        #expect(taskToResume.status == .paused)

        // Resume download to completion
        let finishedTask = try await newEngine.startDownload(task: taskToResume)

        #expect(finishedTask.status == .completed)
        #expect(finishedTask.progress == 1.0)
        #expect(finishedTask.downloadedBytes == Int64(totalSize))
        #expect(finishedTask.completedAt != nil)

        // Verify disk file integrity
        let fileData = try Data(contentsOf: destinationURL)
        #expect(fileData.count == totalSize)
        #expect(fileData == expectedData)

        // Verify that the final persisted state in storage reflects .completed
        let finalPersistedTasks = try await secondPersister.load()
        let finalTask = finalPersistedTasks.first(where: { $0.id == initialTask.id })
        #expect(finalTask?.status == .completed)
        #expect(finalTask?.downloadedBytes == Int64(totalSize))
    }

    // MARK: - Test 7: State File Permissions Are Restricted

    @Test("State file permissions are restricted to owner read/write (0o600)")
    func testStateFilePermissionsAreRestricted() async throws {
        let tempDir = try createTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let storageURL = tempDir.appendingPathComponent("secure_state.json")
        let persister = JSONStatePersister(storageURL: storageURL)

        let task = DownloadTaskModel(
            url: URL(string: "https://example.com/secure.zip")!,
            filename: "secure.zip"
        )
        try await persister.save(tasks: [task])

        #expect(FileManager.default.fileExists(atPath: storageURL.path))

        let attributes = try FileManager.default.attributesOfItem(atPath: storageURL.path)
        guard let permissions = attributes[.posixPermissions] as? NSNumber else {
            Issue.record("POSIX permissions attribute missing on state file")
            return
        }

        #expect((permissions.intValue & 0o777) == 0o600)
    }
}
