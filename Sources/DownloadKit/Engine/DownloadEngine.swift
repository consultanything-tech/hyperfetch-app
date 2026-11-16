import Foundation

/// High-performance multi-chunk concurrent download engine with speed calculation and progress tracking.
public actor DownloadEngine {
    private let session: URLSession
    private let probe: any HTTPProbing
    private let downloader: any ChunkDownloading
    private let fileWriterFactory: @Sendable (URL) -> any FileWriting
    private let statePersister: (any StatePersisting)?
    public let rateLimiter: (any RateLimiting)?
    private let defaultChunkCount: Int
    private let minChunkSize: Int64
    private let rateLimitBackoffDuration: Duration

    private var taskStore: [UUID: DownloadTaskModel] = [:]
    private var speedTrackers: [UUID: SpeedTracker] = [:]
    private var lastProgressEmitTime: [UUID: ContinuousClock.Instant] = [:]
    private let progressClock = ContinuousClock()

    public init(
        session: URLSession = DownloadURLSession.shared,
        probe: (any HTTPProbing)? = nil,
        downloader: (any ChunkDownloading)? = nil,
        fileWriterFactory: (@Sendable (URL) -> any FileWriting)? = nil,
        statePersister: (any StatePersisting)? = nil,
        rateLimiter: (any RateLimiting)? = nil,
        defaultChunkCount: Int = 4,
        minChunkSize: Int64 = 256 * 1024,
        rateLimitBackoffDuration: Duration = .milliseconds(1500)
    ) {
        self.session = session
        self.probe = probe ?? HTTPRangeProbe(session: session)
        self.downloader = downloader ?? ChunkDownloader(session: session, rateLimiter: rateLimiter)
        self.fileWriterFactory = fileWriterFactory ?? { FileWriter(destinationURL: $0) }
        self.statePersister = statePersister
        self.rateLimiter = rateLimiter
        self.defaultChunkCount = defaultChunkCount
        self.minChunkSize = minChunkSize
        self.rateLimitBackoffDuration = rateLimitBackoffDuration
    }

    /// Sets or updates the bandwidth limit for downloads.
    public func setSpeedLimit(_ bytesPerSecond: Int64) async {
        await rateLimiter?.updateLimit(bytesPerSecond: bytesPerSecond)
    }

    /// Retrieves the current recorded state of a download task.
    public func task(for id: UUID) -> DownloadTaskModel? {
        taskStore[id]
    }

    /// Returns all tasks currently tracked by the engine.
    public func allTasks() -> [DownloadTaskModel] {
        Array(taskStore.values)
    }

    /// Restores previously persisted tasks into the engine's memory store.
    @discardableResult
    public func restoreTasks() async throws -> [DownloadTaskModel] {
        guard let statePersister else { return [] }
        let restoredTasks = try await statePersister.load()
        for task in restoredTasks {
            taskStore[task.id] = task
        }
        return restoredTasks
    }

    /// Pauses an active download task and persists its updated state.
    public func pauseDownload(id: UUID) async {
        taskStore[id]?.status = .paused
        taskStore[id]?.bytesPerSecond = 0.0
        if let task = taskStore[id] {
            try? await statePersister?.saveTask(task, immediate: true)
        }
    }

    private func cancelAndPause(
        task: inout DownloadTaskModel,
        writer: (any FileWriting)? = nil,
        progressHandler: (@Sendable (DownloadTaskModel) -> Void)?
    ) async throws -> Never {
        if let writer = writer {
            try? await writer.sync()
            await writer.close()
        }
        if let latest = taskStore[task.id] {
            task = latest
        }
        task.status = .paused
        task.bytesPerSecond = 0.0
        taskStore[task.id] = task
        try? await statePersister?.saveTask(task, immediate: true)
        progressHandler?(task)
        throw CancellationError()
    }

    /// Starts or resumes a download task.
    public func startDownload(
        task: DownloadTaskModel,
        progressHandler: (@Sendable (DownloadTaskModel) -> Void)? = nil
    ) async throws -> DownloadTaskModel {
        var currentTask = taskStore[task.id] ?? task
        if let existing = taskStore[task.id] {
            switch existing.status {
            case .paused, .idle, .failed:
                currentTask = task
            case .downloading, .probing, .completed:
                break
            }
        }

        switch currentTask.status {
        case .paused, .idle, .failed:
            currentTask.status = (currentTask.totalBytes > 0 && currentTask.status != .idle) ? .downloading : .probing
        case .downloading, .probing, .completed:
            break
        }
        taskStore[currentTask.id] = currentTask

        if Task.isCancelled {
            try await cancelAndPause(task: &currentTask, writer: nil, progressHandler: progressHandler)
        }

        // Step 1: Probe remote resource if idle or size unknown
        if currentTask.status == .probing || currentTask.status == .idle || currentTask.totalBytes < 0 {
            currentTask.status = .probing
            taskStore[currentTask.id] = currentTask
            progressHandler?(currentTask)
            try? await statePersister?.saveTask(currentTask, immediate: true)

            do {
                let probeResult = try await probe.probe(url: currentTask.url, headers: currentTask.headers)
                currentTask.totalBytes = probeResult.totalBytes
                currentTask.supportsRange = probeResult.supportsRange
                if !probeResult.filename.isEmpty {
                    currentTask.filename = probeResult.filename
                    let newCategory = DownloadCategory.category(for: probeResult.filename)
                    currentTask.category = newCategory

                    let oldDest = currentTask.destinationURL
                    let base = DownloadTaskModel.defaultBaseDirectory.standardizedFileURL
                    if oldDest.path.hasPrefix(base.path) {
                        currentTask.destinationURL = DownloadTaskModel.defaultDestinationURL(for: probeResult.filename, category: newCategory)
                    } else {
                        let parentDir = oldDest.deletingLastPathComponent()
                        currentTask.destinationURL = parentDir.appendingPathComponent(probeResult.filename)
                    }
                }
            } catch is CancellationError {
                try await cancelAndPause(task: &currentTask, writer: nil, progressHandler: progressHandler)
            } catch ProbeError.cancelled {
                try await cancelAndPause(task: &currentTask, writer: nil, progressHandler: progressHandler)
            } catch {
                print("[DownloadEngine] Warning: probe failed for \(currentTask.url): \(error). Falling back to direct single-stream download.")
                currentTask.supportsRange = false
                currentTask.totalBytes = -1
            }
            taskStore[currentTask.id] = currentTask
            try? await statePersister?.saveTask(currentTask, immediate: true)
        }

        // Step 2: Chunk setup and partitioning
        if currentTask.chunks.isEmpty {
            if currentTask.supportsRange && currentTask.totalBytes > minChunkSize {
                let targetCount = currentTask.preferredChunkCount ?? defaultChunkCount
                let chunkCount = min(targetCount, max(1, Int(currentTask.totalBytes / minChunkSize)))
                let baseChunkSize = currentTask.totalBytes / Int64(chunkCount)
                var chunks: [Chunk] = []
                var startOffset: Int64 = 0

                for i in 0..<chunkCount {
                    let isLast = (i == chunkCount - 1)
                    let endOffset = isLast ? (currentTask.totalBytes - 1) : (startOffset + baseChunkSize - 1)
                    chunks.append(Chunk(index: i, startOffset: startOffset, endOffset: endOffset))
                    startOffset = endOffset + 1
                }
                currentTask.chunks = chunks
            } else if currentTask.supportsRange && currentTask.totalBytes > 0 {
                // Single chunk with range
                currentTask.chunks = [Chunk(index: 0, startOffset: 0, endOffset: currentTask.totalBytes - 1)]
            } else {
                // Non-range or indeterminate stream
                currentTask.chunks = [Chunk(index: 0, startOffset: 0, endOffset: -1)]
            }
            taskStore[currentTask.id] = currentTask
            try? await statePersister?.saveTask(currentTask, immediate: true)
        }

        // Pre-allocate destination file if range supported and totalBytes > 0
        let writer = fileWriterFactory(currentTask.destinationURL)
        if currentTask.supportsRange && currentTask.totalBytes > 0 {
            do {
                try await writer.allocate(totalBytes: currentTask.totalBytes)
            } catch {
                currentTask.status = .failed(reason: error.localizedDescription)
                taskStore[currentTask.id] = currentTask
                try? await statePersister?.saveTask(currentTask, immediate: true)
                progressHandler?(currentTask)
                throw error
            }
        }

        if Task.isCancelled || taskStore[currentTask.id]?.status == .paused {
            try await cancelAndPause(task: &currentTask, writer: writer, progressHandler: progressHandler)
        }

        currentTask.status = .downloading
        taskStore[currentTask.id] = currentTask
        progressHandler?(currentTask)
        try? await statePersister?.saveTask(currentTask, immediate: true)

        do {
            try await executeChunks(for: currentTask.id, writer: writer, progressHandler: progressHandler)
        } catch is CancellationError {
            try await cancelAndPause(task: &currentTask, writer: writer, progressHandler: progressHandler)
        } catch {
            if Task.isCancelled || taskStore[currentTask.id]?.status == .paused {
                try await cancelAndPause(task: &currentTask, writer: writer, progressHandler: progressHandler)
            }

            if (isRangeNotSupportedError(error) || isRateLimitError(error)) && (currentTask.supportsRange || currentTask.chunks.count > 1) {
                print("[DownloadEngine] Server does not support range requests or rate-limited concurrent connections for task \(currentTask.id) (\(error)). Seamlessly falling back to direct single-stream download.")
                if isRateLimitError(error) {
                    try? await Task.sleep(for: rateLimitBackoffDuration)
                }

                if Task.isCancelled || taskStore[currentTask.id]?.status == .paused {
                    try await cancelAndPause(task: &currentTask, writer: writer, progressHandler: progressHandler)
                }

                currentTask.supportsRange = false
                currentTask.downloadedBytes = 0
                currentTask.chunks = [Chunk(index: 0, startOffset: 0, endOffset: -1)]
                taskStore[currentTask.id] = currentTask
                try? await writer.allocate(totalBytes: 0)
                try? await statePersister?.saveTask(currentTask, immediate: true)
                progressHandler?(currentTask)

                if Task.isCancelled || taskStore[currentTask.id]?.status == .paused {
                    try await cancelAndPause(task: &currentTask, writer: writer, progressHandler: progressHandler)
                }

                do {
                    try await executeChunks(for: currentTask.id, writer: writer, progressHandler: progressHandler)
                } catch is CancellationError {
                    try await cancelAndPause(task: &currentTask, writer: writer, progressHandler: progressHandler)
                } catch {
                    if Task.isCancelled || taskStore[currentTask.id]?.status == .paused {
                        try await cancelAndPause(task: &currentTask, writer: writer, progressHandler: progressHandler)
                    }

                    try? await writer.sync()
                    await writer.close()

                    currentTask.status = .failed(reason: error.localizedDescription)
                    currentTask.bytesPerSecond = 0.0
                    taskStore[currentTask.id] = currentTask
                    try? await statePersister?.saveTask(currentTask, immediate: true)
                    progressHandler?(currentTask)
                    throw error
                }
            } else {
                try? await writer.sync()
                await writer.close()

                currentTask.status = .failed(reason: error.localizedDescription)
                currentTask.bytesPerSecond = 0.0
                taskStore[currentTask.id] = currentTask
                try? await statePersister?.saveTask(currentTask, immediate: true)
                progressHandler?(currentTask)
                throw error
            }
        }

        if let latestTask = taskStore[currentTask.id] {
            currentTask = latestTask
        }

        try await writer.sync()
        await writer.close()

        // Ensure all chunks that reached expected length are clamped and marked completed
        for i in 0..<currentTask.chunks.count {
            if currentTask.chunks[i].expectedLength > 0 && currentTask.chunks[i].bytesDownloaded >= currentTask.chunks[i].expectedLength {
                currentTask.chunks[i].bytesDownloaded = currentTask.chunks[i].expectedLength
                currentTask.chunks[i].status = .completed
            } else if currentTask.chunks[i].endOffset == -1 {
                currentTask.chunks[i].status = .completed
            }
        }

        if currentTask.totalBytes > 0 {
            currentTask.downloadedBytes = currentTask.totalBytes
        } else if currentTask.downloadedBytes > 0 {
            currentTask.totalBytes = currentTask.downloadedBytes
        }
        currentTask.status = .completed
        currentTask.completedAt = Date()
        currentTask.bytesPerSecond = 0.0

        // Scrub sensitive session credentials and authentication tokens upon download completion (CWE-312)
        currentTask.headers.removeValue(forKey: "Cookie")
        currentTask.headers.removeValue(forKey: "cookie")
        currentTask.headers.removeValue(forKey: "Authorization")
        currentTask.headers.removeValue(forKey: "authorization")

        taskStore[currentTask.id] = currentTask
        try? await statePersister?.saveTask(currentTask, immediate: true)
        progressHandler?(currentTask)
        return currentTask
    }

    private func executeChunks(
        for taskId: UUID,
        writer: any FileWriting,
        progressHandler: (@Sendable (DownloadTaskModel) -> Void)?
    ) async throws {
        guard let task = taskStore[taskId] else { return }
        speedTrackers[taskId] = SpeedTracker()

        let (progressStream, progressContinuation) = AsyncStream<(Int, Int64)>.makeStream()

        let progressTask = Task { [weak self] in
            for await (chunkIndex, delta) in progressStream {
                await self?.recordChunkProgress(
                    taskId: taskId,
                    chunkIndex: chunkIndex,
                    delta: delta,
                    progressHandler: progressHandler
                )
            }
        }

        let downloadURL = task.url
        let taskHeaders = task.headers
        let downloader = self.downloader
        let chunksToDownload = task.chunks

        do {
            try await withThrowingTaskGroup(of: Chunk.self) { group in
                for chunk in chunksToDownload {
                    if chunk.status == .completed || (chunk.expectedLength > 0 && chunk.bytesDownloaded >= chunk.expectedLength) {
                        continue
                    }

                    let chunkIndex = chunk.index
                    group.addTask {
                        var localChunk = chunk
                        try await downloader.download(
                            chunk: &localChunk,
                            from: downloadURL,
                            to: writer,
                            headers: taskHeaders
                        ) { delta in
                            progressContinuation.yield((chunkIndex, delta))
                        }
                        return localChunk
                    }
                }

                for try await completedChunk in group {
                    if var storedTask = taskStore[taskId] {
                        if let idx = storedTask.chunks.firstIndex(where: { $0.index == completedChunk.index }) {
                            storedTask.chunks[idx] = completedChunk
                            taskStore[storedTask.id] = storedTask
                            try? await statePersister?.saveTask(storedTask, immediate: false)
                        }
                    }
                }
            }

            progressContinuation.finish()
            _ = await progressTask.value
        } catch {
            progressContinuation.finish()
            progressTask.cancel()
            throw error
        }
    }

    private func isRangeNotSupportedError(_ error: Error) -> Bool {
        if let chunkError = error as? ChunkDownloadError {
            switch chunkError {
            case .serverDoesNotSupportRange:
                return true
            case .httpError(let statusCode):
                return statusCode == 416 || statusCode == 501
            default:
                break
            }
        }
        let desc = error.localizedDescription
        return desc.contains("206") || desc.contains("range") || desc.contains("Range")
    }

    func exposedIsRangeNotSupportedError(_ error: Error) -> Bool {
        isRangeNotSupportedError(error)
    }

    func exposedIsRateLimitError(_ error: Error) -> Bool {
        isRateLimitError(error)
    }

    private func isRateLimitError(_ error: Error) -> Bool {
        if let chunkError = error as? ChunkDownloadError {
            if case .httpError(let statusCode) = chunkError {
                return statusCode == 429 || statusCode == 503
            }
        }
        let desc = error.localizedDescription
        return desc.contains("429") || desc.contains("503") || desc.localizedCaseInsensitiveContains("too many requests")
    }

    private func recordChunkProgress(
        taskId: UUID,
        chunkIndex: Int,
        delta: Int64,
        progressHandler: (@Sendable (DownloadTaskModel) -> Void)?
    ) {
        guard var task = taskStore[taskId] else { return }
        guard task.status != .paused, !Task.isCancelled else { return }

        var chunkFinished = false
        if let idx = task.chunks.firstIndex(where: { $0.index == chunkIndex }) {
            task.chunks[idx].bytesDownloaded += delta
            if task.chunks[idx].expectedLength > 0 && task.chunks[idx].bytesDownloaded >= task.chunks[idx].expectedLength {
                task.chunks[idx].bytesDownloaded = task.chunks[idx].expectedLength
                task.chunks[idx].status = .completed
                chunkFinished = true
            } else {
                task.chunks[idx].status = .downloading
            }
        }

        task.downloadedBytes += delta
        if task.totalBytes > 0 && task.downloadedBytes > task.totalBytes {
            task.downloadedBytes = task.totalBytes
        }

        speedTrackers[taskId]?.record(bytes: delta)
        task.bytesPerSecond = speedTrackers[taskId]?.currentSpeed() ?? 0.0

        taskStore[taskId] = task

        let taskFinished = (task.totalBytes > 0 && task.downloadedBytes >= task.totalBytes)
        let now = progressClock.now
        let shouldEmit: Bool
        if chunkFinished || taskFinished {
            shouldEmit = true
        } else if let last = lastProgressEmitTime[taskId] {
            shouldEmit = (now - last) >= .milliseconds(100)
        } else {
            shouldEmit = true
        }

        if shouldEmit {
            lastProgressEmitTime[taskId] = now
            progressHandler?(task)
        }
    }
}

// MARK: - Speed Tracker

extension DownloadEngine {
    public typealias SpeedTracker = DownloadKit.SpeedTracker
}

/// Rolling window speed calculator measuring bytes per second using a monotonic ContinuousClock.
public struct SpeedTracker: Sendable {
    private var window: [(time: ContinuousClock.Instant, bytes: Int64)] = []
    private let clock: ContinuousClock
    private let windowDuration: Duration

    var windowCount: Int {
        window.count
    }

    public init(windowDuration: Duration = .seconds(1), clock: ContinuousClock = ContinuousClock()) {
        self.windowDuration = windowDuration
        self.clock = clock
    }

    public mutating func record(bytes: Int64) {
        guard bytes > 0 else { return }
        let now = clock.now
        window.append((time: now, bytes: bytes))
        prune(now: now)
        if window.count > 500 {
            window.removeFirst(window.count - 500)
        }
    }

    public mutating func currentSpeed() -> Double {
        let now = clock.now
        prune(now: now)
        guard let first = window.first, let last = window.last else {
            return 0.0
        }
        let totalBytes = window.reduce(Int64(0)) { $0 + $1.bytes }
        let elapsed = first.time.duration(to: last.time)
        let elapsedSeconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        if elapsedSeconds > 0.001 {
            return Double(totalBytes) / elapsedSeconds
        } else {
            return Double(totalBytes)
        }
    }

    private mutating func prune(now: ContinuousClock.Instant) {
        let maxAge = windowDuration
        window.removeAll { entry in
            now - entry.time > maxAge
        }
    }
}
