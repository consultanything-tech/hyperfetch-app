//
//  QueueManager.swift
//  DownloadKit
//

import Foundation

/// Coordinates multi-task download scheduling, bandwidth limits, state persistence, and concurrency bounds.
public actor QueueManager {
    public let engine: DownloadEngine
    public let statePersister: (any StatePersisting)?
    public let rateLimiter: (any RateLimiting)?
    public private(set) var maxConcurrentDownloads: Int

    private var taskQueue: [DownloadTaskModel] = []
    private var taskIndexMap: [UUID: Int] = [:]
    private var activeTasks: [UUID: Task<Void, Never>] = [:]
    private var taskExecutionTokens: [UUID: UUID] = [:]
    private var resumedTaskIDs: Set<UUID> = []
    private var continuations: [UUID: AsyncStream<[DownloadTaskModel]>.Continuation] = [:]

    private func rebuildIndex() {
        taskIndexMap.removeAll(keepingCapacity: true)
        taskIndexMap.reserveCapacity(taskQueue.count)
        for (i, task) in taskQueue.enumerated() {
            taskIndexMap[task.id] = i
        }
    }

    private func isFailedStatus(_ status: DownloadStatus) -> Bool {
        if case .failed = status { return true }
        return false
    }

    /// Number of downloads currently executing in the engine.
    public var activeCount: Int {
        activeTasks.count
    }

    /// Real-time stream of task queue snapshots for UI observers.
    public var queueUpdates: AsyncStream<[DownloadTaskModel]> {
        let (stream, continuation) = AsyncStream<[DownloadTaskModel]>.makeStream()
        let id = UUID()
        continuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { [weak self] in
                await self?.removeContinuation(id: id)
            }
        }
        continuation.yield(taskQueue)
        return stream
    }

    public init(
        engine: DownloadEngine? = nil,
        statePersister: (any StatePersisting)? = nil,
        rateLimiter: (any RateLimiting)? = nil,
        maxConcurrentDownloads: Int = 3
    ) {
        let limiter = rateLimiter ?? engine?.rateLimiter ?? TokenBucketRateLimiter(bytesPerSecond: 0)
        self.rateLimiter = limiter
        self.statePersister = statePersister
        self.maxConcurrentDownloads = max(1, maxConcurrentDownloads)
        self.engine = engine ?? DownloadEngine(
            statePersister: statePersister,
            rateLimiter: limiter
        )
    }

    /// Restores persisted tasks from the state persister into the queue.
    @discardableResult
    public func restoreTasks() async throws -> [DownloadTaskModel] {
        guard let statePersister else { return [] }
        let restored = try await statePersister.load()
        self.taskQueue = restored
        rebuildIndex()
        _ = try? await engine.restoreTasks()
        broadcastUpdate()
        return restored
    }

    /// Returns a snapshot of all tasks in queue order.
    public func tasks() -> [DownloadTaskModel] {
        taskQueue
    }

    /// Retrieves a specific task from the queue by ID.
    public func task(for id: UUID) -> DownloadTaskModel? {
        guard let idx = taskIndexMap[id], idx < taskQueue.count else { return nil }
        return taskQueue[idx]
    }

    /// Adds a new download task to the queue.
    @discardableResult
    public func addTask(
        url: URL,
        destinationURL: URL? = nil,
        filename: String? = nil,
        headers: [String: String] = [:],
        preferredChunkCount: Int? = nil,
        autoStart: Bool = true
    ) async throws -> DownloadTaskModel {
        let task = DownloadTaskModel(
            url: url,
            filename: filename,
            destinationURL: destinationURL,
            status: autoStart ? .idle : .paused,
            headers: headers,
            preferredChunkCount: preferredChunkCount
        )
        return try await addTask(task, autoStart: autoStart)
    }

    /// Adds an existing task model to the queue.
    @discardableResult
    public func addTask(
        _ task: DownloadTaskModel,
        autoStart: Bool = true
    ) async throws -> DownloadTaskModel {
        if let existingIdx = taskQueue.firstIndex(where: {
            $0.url == task.url && $0.status != .completed && !isFailedStatus($0.status)
        }) {
            let existing = taskQueue[existingIdx]
            if autoStart && existing.status == .paused {
                try await resumeTask(id: existing.id)
            }
            return existing
        }

        var newTask = task
        newTask.status = autoStart ? .idle : .paused
        taskQueue.append(newTask)
        taskIndexMap[newTask.id] = taskQueue.count - 1
        try await statePersister?.saveTask(newTask)
        broadcastUpdate()

        if autoStart {
            scheduleNextTasks()
        }

        if let idx = taskIndexMap[newTask.id], idx < taskQueue.count {
            return taskQueue[idx]
        }
        return newTask
    }

    /// Pauses an active or queued download task.
    public func pauseTask(id: UUID) async {
        resumedTaskIDs.remove(id)
        taskExecutionTokens.removeValue(forKey: id)
        if let idx = taskIndexMap[id], idx < taskQueue.count {
            taskQueue[idx].status = .paused
            taskQueue[idx].bytesPerSecond = 0.0
            try? await statePersister?.saveTask(taskQueue[idx])
        }
        broadcastUpdate()

        if let running = activeTasks.removeValue(forKey: id) {
            running.cancel()
            await engine.pauseDownload(id: id)
        }
        scheduleNextTasks()
    }

    /// Resumes a paused or failed download task.
    public func resumeTask(id: UUID) async throws {
        guard let idx = taskIndexMap[id], idx < taskQueue.count else { return }
        guard taskQueue[idx].status != .completed else { return }

        if case .failed(let reason) = taskQueue[idx].status {
            taskQueue[idx].status = .idle
            if reason.contains("206") || reason.contains("range") || reason.contains("Range") ||
               reason.contains("429") || reason.contains("403") || reason.contains("503") ||
               reason.localizedCaseInsensitiveContains("too many requests") ||
               !taskQueue[idx].supportsRange {
                taskQueue[idx].supportsRange = false
                taskQueue[idx].chunks = []
                taskQueue[idx].downloadedBytes = 0
            }
            try? await statePersister?.saveTask(taskQueue[idx])
        }

        resumedTaskIDs.insert(id)
        scheduleNextTasks()
        broadcastUpdate()
    }

    /// Cancels a task, stopping it and marking it as paused.
    public func cancelTask(id: UUID) async {
        await pauseTask(id: id)
    }

    /// Removes a task from the queue, optionally deleting the downloaded file from disk.
    public func removeTask(id: UUID, deleteFile: Bool = false) async throws {
        resumedTaskIDs.remove(id)
        taskExecutionTokens.removeValue(forKey: id)
        if let running = activeTasks.removeValue(forKey: id) {
            running.cancel()
            await engine.pauseDownload(id: id)
        }

        guard let idx = taskIndexMap[id], idx < taskQueue.count else { return }
        let task = taskQueue.remove(at: idx)
        rebuildIndex()

        if deleteFile {
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: task.destinationURL.path) {
                try fileManager.removeItem(at: task.destinationURL)
            }
        }

        try await statePersister?.deleteTask(id: id)
        broadcastUpdate()
        scheduleNextTasks()
    }

    /// Pauses all active and queued downloads.
    public func pauseAll() async {
        resumedTaskIDs.removeAll()
        taskExecutionTokens.removeAll()
        for i in 0..<taskQueue.count {
            if taskQueue[i].status == .downloading || taskQueue[i].status == .probing || taskQueue[i].status == .idle {
                taskQueue[i].status = .paused
                taskQueue[i].bytesPerSecond = 0.0
            }
        }

        try? await statePersister?.save(tasks: taskQueue)
        broadcastUpdate()

        for (id, running) in activeTasks {
            running.cancel()
            await engine.pauseDownload(id: id)
        }
        activeTasks.removeAll()
    }

    /// Resumes all paused and idle tasks in queue order.
    public func resumeAll() async throws {
        for task in taskQueue {
            if task.status == .paused || task.status == .idle {
                resumedTaskIDs.insert(task.id)
            }
        }
        scheduleNextTasks()
        broadcastUpdate()
    }

    /// Moves a task to a new index in the queue.
    public func moveTask(id: UUID, toIndex: Int) async {
        guard let currentIndex = taskIndexMap[id], currentIndex < taskQueue.count else { return }
        let task = taskQueue.remove(at: currentIndex)
        let targetIndex = max(0, min(toIndex, taskQueue.count))
        taskQueue.insert(task, at: targetIndex)
        rebuildIndex()

        try? await statePersister?.save(tasks: taskQueue)
        broadcastUpdate()
        scheduleNextTasks()
    }

    /// Updates the maximum number of concurrent downloads.
    public func setMaxConcurrentDownloads(_ count: Int) async {
        self.maxConcurrentDownloads = max(1, count)

        // If decreasing concurrency below active count, pause excess active tasks
        while activeTasks.count > maxConcurrentDownloads {
            if let taskToPause = taskQueue.last(where: { activeTasks[$0.id] != nil }) {
                resumedTaskIDs.insert(taskToPause.id)
                taskExecutionTokens.removeValue(forKey: taskToPause.id)
                if let running = activeTasks.removeValue(forKey: taskToPause.id) {
                    running.cancel()
                    await engine.pauseDownload(id: taskToPause.id)
                }
                if let idx = taskIndexMap[taskToPause.id], idx < taskQueue.count {
                    taskQueue[idx].status = .paused
                    taskQueue[idx].bytesPerSecond = 0.0
                }
            } else {
                break
            }
        }

        scheduleNextTasks()
        broadcastUpdate()
    }

    /// Sets or updates the bandwidth speed limit across all downloads.
    public func setSpeedLimit(_ bytesPerSecond: Int64) async {
        await rateLimiter?.updateLimit(bytesPerSecond: bytesPerSecond)
    }

    // MARK: - Private Scheduling Logic

    private func scheduleNextTasks() {
        guard activeTasks.count < maxConcurrentDownloads else { return }

        for index in 0..<taskQueue.count {
            guard activeTasks.count < maxConcurrentDownloads else { break }

            let task = taskQueue[index]
            guard activeTasks[task.id] == nil else { continue }

            let isEligible: Bool
            if task.status == .idle {
                isEligible = true
            } else if resumedTaskIDs.contains(task.id) {
                switch task.status {
                case .paused, .idle, .failed:
                    isEligible = true
                default:
                    isEligible = false
                }
            } else {
                isEligible = false
            }

            if isEligible {
                resumedTaskIDs.remove(task.id)
                startTaskInternal(task: task)
            }
        }
    }

    private func startTaskInternal(task: DownloadTaskModel) {
        let taskId = task.id
        let token = UUID()
        taskExecutionTokens[taskId] = token

        if let idx = taskIndexMap[taskId], idx < taskQueue.count {
            taskQueue[idx].status = task.totalBytes > 0 ? .downloading : .probing
        }
        broadcastUpdate()

        let runningTask = Task { [weak self, engine] in
            do {
                let completedTask = try await engine.startDownload(task: task) { [weak self] progressTask in
                    Task { [weak self] in
                        await self?.updateTaskProgress(progressTask, token: token)
                    }
                }
                await self?.handleTaskCompletion(id: taskId, token: token, completedTask: completedTask)
            } catch is CancellationError {
                await self?.handleTaskCancellation(id: taskId, token: token)
            } catch {
                if Task.isCancelled {
                    await self?.handleTaskCancellation(id: taskId, token: token)
                } else {
                    await self?.handleTaskFailure(id: taskId, token: token, error: error)
                }
            }
        }

        activeTasks[taskId] = runningTask
    }

    private func updateTaskProgress(_ updatedTask: DownloadTaskModel, token: UUID) {
        guard taskExecutionTokens[updatedTask.id] == token else { return }
        guard let idx = taskIndexMap[updatedTask.id], idx < taskQueue.count else { return }
        if taskQueue[idx].status == .completed { return }
        if case .failed = taskQueue[idx].status { return }
        if taskQueue[idx].status == .paused { return }

        taskQueue[idx] = updatedTask
        broadcastUpdate()
    }

    private func handleTaskCompletion(id: UUID, token: UUID, completedTask: DownloadTaskModel) async {
        guard taskExecutionTokens[id] == token else { return }
        taskExecutionTokens.removeValue(forKey: id)
        activeTasks.removeValue(forKey: id)
        if let idx = taskIndexMap[id], idx < taskQueue.count {
            taskQueue[idx] = completedTask
            try? await statePersister?.saveTask(completedTask)
        }
        broadcastUpdate()
        scheduleNextTasks()
    }

    private func handleTaskCancellation(id: UUID, token: UUID) async {
        guard taskExecutionTokens[id] == token else { return }
        taskExecutionTokens.removeValue(forKey: id)
        activeTasks.removeValue(forKey: id)
        if let idx = taskIndexMap[id], idx < taskQueue.count {
            if var engineTask = await engine.task(for: id) {
                engineTask.status = .paused
                engineTask.bytesPerSecond = 0.0
                taskQueue[idx] = engineTask
            } else {
                taskQueue[idx].status = .paused
                taskQueue[idx].bytesPerSecond = 0.0
            }
            try? await statePersister?.saveTask(taskQueue[idx])
        }
        broadcastUpdate()
        scheduleNextTasks()
    }

    private func handleTaskFailure(id: UUID, token: UUID, error: Error) async {
        guard taskExecutionTokens[id] == token else { return }
        taskExecutionTokens.removeValue(forKey: id)
        activeTasks.removeValue(forKey: id)
        if let idx = taskIndexMap[id], idx < taskQueue.count {
            if taskQueue[idx].status == .paused { return }
            if let engineTask = await engine.task(for: id) {
                taskQueue[idx] = engineTask
            } else {
                taskQueue[idx].status = .failed(reason: error.localizedDescription)
                taskQueue[idx].bytesPerSecond = 0.0
            }
            try? await statePersister?.saveTask(taskQueue[idx])
        }
        broadcastUpdate()
        scheduleNextTasks()
    }

    private func removeContinuation(id: UUID) {
        continuations.removeValue(forKey: id)
    }

    private func broadcastUpdate() {
        for continuation in continuations.values {
            continuation.yield(taskQueue)
        }
    }
}
