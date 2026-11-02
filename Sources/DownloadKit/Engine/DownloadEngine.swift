import Foundation

/// High-performance multi-chunk concurrent download engine with speed calculation and progress tracking.
public actor DownloadEngine {
    private let session: URLSession
    private let probe: any HTTPProbing
    private let downloader: any ChunkDownloading
    private let fileWriterFactory: @Sendable (URL) -> any FileWriting
    private let defaultChunkCount: Int
    private let minChunkSize: Int64

    private var taskStore: [UUID: DownloadTaskModel] = [:]
    private var speedTrackers: [UUID: SpeedTracker] = [:]

    public init(
        session: URLSession = .shared,
        probe: (any HTTPProbing)? = nil,
        downloader: (any ChunkDownloading)? = nil,
        fileWriterFactory: (@Sendable (URL) -> any FileWriting)? = nil,
        defaultChunkCount: Int = 4,
        minChunkSize: Int64 = 256 * 1024
    ) {
        self.session = session
        self.probe = probe ?? HTTPRangeProbe(session: session)
        self.downloader = downloader ?? ChunkDownloader(session: session)
        self.fileWriterFactory = fileWriterFactory ?? { FileWriter(destinationURL: $0) }
        self.defaultChunkCount = defaultChunkCount
        self.minChunkSize = minChunkSize
    }

    /// Retrieves the current recorded state of a download task.
    public func task(for id: UUID) -> DownloadTaskModel? {
        taskStore[id]
    }

    /// Pauses an active download task.
    public func pauseDownload(id: UUID) {
        taskStore[id]?.status = .paused
    }

    /// Starts or resumes a download task.
    public func startDownload(
        task: DownloadTaskModel,
        progressHandler: (@Sendable (DownloadTaskModel) -> Void)? = nil
    ) async throws -> DownloadTaskModel {
        var currentTask = taskStore[task.id] ?? task
        taskStore[currentTask.id] = currentTask

        if Task.isCancelled {
            currentTask.status = .paused
            taskStore[currentTask.id] = currentTask
            progressHandler?(currentTask)
            throw CancellationError()
        }

        // Step 1: Probe remote resource if idle or size unknown
        if currentTask.status == .idle || currentTask.totalBytes < 0 {
            currentTask.status = .probing
            taskStore[currentTask.id] = currentTask
            progressHandler?(currentTask)

            let probeResult: ProbeResult
            do {
                probeResult = try await probe.probe(url: currentTask.url)
            } catch is CancellationError {
                currentTask.status = .paused
                taskStore[currentTask.id] = currentTask
                progressHandler?(currentTask)
                throw CancellationError()
            } catch {
                currentTask.status = .failed(reason: error.localizedDescription)
                taskStore[currentTask.id] = currentTask
                progressHandler?(currentTask)
                throw error
            }

            currentTask.totalBytes = probeResult.totalBytes
            currentTask.supportsRange = probeResult.supportsRange
            if !probeResult.filename.isEmpty {
                currentTask.filename = probeResult.filename
                currentTask.category = DownloadCategory.category(for: probeResult.filename)
                let parentDir = currentTask.destinationURL.deletingLastPathComponent()
                currentTask.destinationURL = parentDir.appendingPathComponent(probeResult.filename)
            }
        }

        // Step 2: Chunk setup and partitioning
        if currentTask.chunks.isEmpty {
            if currentTask.supportsRange && currentTask.totalBytes > minChunkSize {
                let chunkCount = min(defaultChunkCount, max(1, Int(currentTask.totalBytes / minChunkSize)))
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
        }

        // Pre-allocate destination file if range supported and totalBytes > 0
        let writer = fileWriterFactory(currentTask.destinationURL)
        if currentTask.supportsRange && currentTask.totalBytes > 0 {
            do {
                try await writer.allocate(totalBytes: currentTask.totalBytes)
            } catch {
                currentTask.status = .failed(reason: error.localizedDescription)
                taskStore[currentTask.id] = currentTask
                progressHandler?(currentTask)
                throw error
            }
        }

        currentTask.status = .downloading
        taskStore[currentTask.id] = currentTask
        progressHandler?(currentTask)

        speedTrackers[currentTask.id] = SpeedTracker()

        let (progressStream, progressContinuation) = AsyncStream<(Int, Int64)>.makeStream()

        let progressTask = Task { [weak self] in
            for await (chunkIndex, delta) in progressStream {
                await self?.recordChunkProgress(
                    taskId: currentTask.id,
                    chunkIndex: chunkIndex,
                    delta: delta,
                    progressHandler: progressHandler
                )
            }
        }

        let downloadURL = currentTask.url
        let downloader = self.downloader
        let chunksToDownload = currentTask.chunks

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
                            to: writer
                        ) { delta in
                            progressContinuation.yield((chunkIndex, delta))
                        }
                        return localChunk
                    }
                }

                for try await completedChunk in group {
                    if let idx = currentTask.chunks.firstIndex(where: { $0.index == completedChunk.index }) {
                        currentTask.chunks[idx] = completedChunk
                    }
                }
            }

            progressContinuation.finish()
            _ = await progressTask.value

            try await writer.sync()
            await writer.close()

            // Ensure all chunks that reached expected length are marked completed
            for i in 0..<currentTask.chunks.count {
                if currentTask.chunks[i].expectedLength > 0 && currentTask.chunks[i].bytesDownloaded >= currentTask.chunks[i].expectedLength {
                    currentTask.chunks[i].status = .completed
                } else if currentTask.chunks[i].endOffset == -1 {
                    currentTask.chunks[i].status = .completed
                }
            }

            if currentTask.totalBytes > 0 {
                currentTask.downloadedBytes = currentTask.totalBytes
            }
            currentTask.status = .completed
            currentTask.completedAt = Date()
            currentTask.bytesPerSecond = 0.0

            taskStore[currentTask.id] = currentTask
            progressHandler?(currentTask)
            return currentTask

        } catch is CancellationError {
            progressContinuation.finish()
            progressTask.cancel()
            try? await writer.sync()
            await writer.close()

            if let latest = taskStore[currentTask.id] {
                currentTask = latest
            }
            currentTask.status = .paused
            currentTask.bytesPerSecond = 0.0
            taskStore[currentTask.id] = currentTask
            progressHandler?(currentTask)
            throw CancellationError()
        } catch {
            progressContinuation.finish()
            progressTask.cancel()
            try? await writer.sync()
            await writer.close()

            currentTask.status = .failed(reason: error.localizedDescription)
            currentTask.bytesPerSecond = 0.0
            taskStore[currentTask.id] = currentTask
            progressHandler?(currentTask)
            throw error
        }
    }

    private func recordChunkProgress(
        taskId: UUID,
        chunkIndex: Int,
        delta: Int64,
        progressHandler: (@Sendable (DownloadTaskModel) -> Void)?
    ) {
        guard var task = taskStore[taskId] else { return }

        if let idx = task.chunks.firstIndex(where: { $0.index == chunkIndex }) {
            task.chunks[idx].bytesDownloaded += delta
            if task.chunks[idx].expectedLength > 0 && task.chunks[idx].bytesDownloaded >= task.chunks[idx].expectedLength {
                task.chunks[idx].status = .completed
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
        progressHandler?(task)
    }
}

// MARK: - Speed Tracker

/// Rolling window speed calculator measuring bytes per second.
public struct SpeedTracker: Sendable {
    private var window: [(time: CFAbsoluteTime, bytes: Int64)] = []
    private let windowDuration: CFTimeInterval

    public init(windowDuration: CFTimeInterval = 1.0) {
        self.windowDuration = windowDuration
    }

    public mutating func record(bytes: Int64) {
        guard bytes > 0 else { return }
        let now = CFAbsoluteTimeGetCurrent()
        window.append((time: now, bytes: bytes))
        prune(now: now)
    }

    public mutating func currentSpeed() -> Double {
        let now = CFAbsoluteTimeGetCurrent()
        prune(now: now)
        guard let first = window.first, let last = window.last else {
            return 0.0
        }
        let totalBytes = window.reduce(Int64(0)) { $0 + $1.bytes }
        let elapsed = last.time - first.time
        if elapsed > 0.001 {
            return Double(totalBytes) / elapsed
        } else {
            return Double(totalBytes)
        }
    }

    private mutating func prune(now: CFAbsoluteTime) {
        let cutoff = now - windowDuration
        window.removeAll { $0.time < cutoff }
    }
}
