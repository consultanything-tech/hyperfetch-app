//
//  StatePersister.swift
//  DownloadKit
//

import Foundation
import OSLog

/// Protocol defining operations for persisting and recovering download task state across app sessions and restarts.
public protocol StatePersisting: Sendable {
    func save(tasks: [DownloadTaskModel]) async throws
    func load() async throws -> [DownloadTaskModel]
    func saveTask(_ task: DownloadTaskModel, immediate: Bool) async throws
    func deleteTask(id: UUID) async throws
    func flush() async throws
    func flushSync()
}

extension StatePersisting {
    public func saveTask(_ task: DownloadTaskModel) async throws {
        try await saveTask(task, immediate: true)
    }
    public func flush() async throws {}
    public func flushSync() {}
}

private final class SyncStateBox: @unchecked Sendable {
    private let lock = NSLock()
    private var tasks: [DownloadTaskModel] = []

    func set(_ newTasks: [DownloadTaskModel]) {
        lock.withLock {
            tasks = newTasks
        }
    }

    func get() -> [DownloadTaskModel] {
        lock.withLock {
            tasks
        }
    }
}

/// Thread-safe actor persisting download tasks to disk using atomic JSON file operations.
public actor JSONStatePersister: StatePersisting {
    public let storageURL: URL
    private let fileManager: FileManager
    private let logger = Logger(subsystem: "com.hyperfetch.downloadkit", category: "JSONStatePersister")
    private var cachedTasks: [DownloadTaskModel]?
    private var pendingDebounceTask: Task<Void, Never>?
    private let debounceInterval: Duration
    private let syncBox = SyncStateBox()

    /// Default storage location inside the application support directory.
    public static var defaultStorageURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return appSupport
            .appendingPathComponent("HyperFetch", isDirectory: true)
            .appendingPathComponent("downloads_state.json")
    }

    public init(
        storageURL: URL = JSONStatePersister.defaultStorageURL,
        fileManager: FileManager = .default,
        debounceInterval: Duration = .milliseconds(500)
    ) {
        self.storageURL = storageURL
        self.fileManager = fileManager
        self.debounceInterval = debounceInterval
    }

    deinit {
        pendingDebounceTask?.cancel()
    }

    // MARK: - StatePersisting Implementation

    /// Persists the collection of tasks atomically to disk.
    public func save(tasks: [DownloadTaskModel]) async throws {
        pendingDebounceTask?.cancel()
        pendingDebounceTask = nil
        cachedTasks = tasks
        syncBox.set(tasks)
        let parentDir = storageURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parentDir.path) {
            try fileManager.createDirectory(
                at: parentDir,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }

        let data = try makeEncoder().encode(tasks)
        do {
            try data.write(to: storageURL, options: [.atomic, .completeFileProtection])
        } catch {
            try data.write(to: storageURL, options: [.atomic])
        }
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: storageURL.path)
    }

    /// Loads tasks from disk, automatically converting interrupted downloads to paused state.
    public func load() async throws -> [DownloadTaskModel] {
        let rawTasks = loadRawTasks()
        cachedTasks = rawTasks
        syncBox.set(rawTasks)
        return rawTasks.map { autoRecover(task: $0) }
    }

    /// Updates or inserts a single download task and persists the updated task list atomically.
    public func saveTask(_ task: DownloadTaskModel, immediate: Bool = false) async throws {
        var currentTasks = cachedTasks ?? loadRawTasks()
        if let index = currentTasks.firstIndex(where: { $0.id == task.id }) {
            currentTasks[index] = task
        } else {
            currentTasks.append(task)
        }
        cachedTasks = currentTasks
        syncBox.set(currentTasks)

        if immediate {
            pendingDebounceTask?.cancel()
            pendingDebounceTask = nil
            try await save(tasks: currentTasks)
        } else {
            pendingDebounceTask?.cancel()
            let tasks = currentTasks
            let interval = debounceInterval
            pendingDebounceTask = Task { [weak self] in
                do {
                    try await Task.sleep(for: interval)
                    guard !Task.isCancelled else { return }
                    try await self?.save(tasks: tasks)
                } catch {
                    // Cancelled or error
                }
            }
        }
    }

    /// Flushes any pending debounced save immediately to disk.
    public func flush() async throws {
        pendingDebounceTask?.cancel()
        pendingDebounceTask = nil
        if let tasks = cachedTasks {
            try await save(tasks: tasks)
        }
    }

    /// Synchronously flushes in-memory tasks to disk atomically without awaiting or debouncing.
    nonisolated public func flushSync() {
        let tasks = syncBox.get()
        guard !tasks.isEmpty else { return }

        let fm = FileManager.default
        let parentDir = storageURL.deletingLastPathComponent()
        if !fm.fileExists(atPath: parentDir.path) {
            try? fm.createDirectory(
                at: parentDir,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(tasks) else { return }

        do {
            try data.write(to: storageURL, options: [.atomic, .completeFileProtection])
        } catch {
            try? data.write(to: storageURL, options: [.atomic])
        }
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: storageURL.path)
    }

    /// Removes a download task with the given identifier and persists changes atomically.
    public func deleteTask(id: UUID) async throws {
        pendingDebounceTask?.cancel()
        pendingDebounceTask = nil
        var currentTasks = cachedTasks ?? loadRawTasks()
        guard currentTasks.contains(where: { $0.id == id }) else { return }
        currentTasks.removeAll(where: { $0.id == id })
        cachedTasks = currentTasks
        syncBox.set(currentTasks)
        try await save(tasks: currentTasks)
    }

    // MARK: - Private Helpers

    /// Reads tasks directly from disk without mutating status, safely handling missing or corrupted files.
    private func loadRawTasks() -> [DownloadTaskModel] {
        guard fileManager.fileExists(atPath: storageURL.path) else {
            return []
        }

        let data: Data
        do {
            data = try Data(contentsOf: storageURL)
        } catch {
            logger.error("Failed to read state file at \(self.storageURL.path): \(error.localizedDescription)")
            return []
        }

        guard !data.isEmpty else {
            return []
        }

        do {
            return try makeDecoder().decode([DownloadTaskModel].self, from: data)
        } catch {
            logger.error("Failed to decode tasks from \(self.storageURL.path): \(error.localizedDescription)")
            return []
        }
    }

    /// Converts active or in-flight download tasks to paused upon recovery.
    private func autoRecover(task: DownloadTaskModel) -> DownloadTaskModel {
        var recovered = task
        switch recovered.status {
        case .downloading, .probing:
            recovered.status = .paused
            recovered.bytesPerSecond = 0.0
        case .idle, .paused, .completed, .failed:
            break
        }

        recovered.chunks = recovered.chunks.map { chunk in
            var c = chunk
            if c.status == .downloading {
                c.status = .pending
            }
            return c
        }
        return recovered
    }

    private func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        return encoder
    }

    nonisolated(unsafe) private static let isoWithFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    nonisolated(unsafe) private static let isoStandard: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let timeInterval = try? container.decode(Double.self) {
                return Date(timeIntervalSinceReferenceDate: timeInterval)
            }
            let string = try container.decode(String.self)
            if let date = Self.isoWithFraction.date(from: string) {
                return date
            }
            if let date = Self.isoStandard.date(from: string) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid date format string: \(string)"
            )
        }
        return decoder
    }
}
