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
    func saveTask(_ task: DownloadTaskModel) async throws
    func deleteTask(id: UUID) async throws
}

/// Thread-safe actor persisting download tasks to disk using atomic JSON file operations.
public actor JSONStatePersister: StatePersisting {
    public let storageURL: URL
    private let fileManager: FileManager
    private let logger = Logger(subsystem: "com.hyperfetch.downloadkit", category: "JSONStatePersister")
    private var cachedTasks: [DownloadTaskModel]?

    /// Default storage location inside the application support directory.
    public static var defaultStorageURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return appSupport
            .appendingPathComponent("HyperFetch", isDirectory: true)
            .appendingPathComponent("downloads_state.json")
    }

    public init(storageURL: URL = JSONStatePersister.defaultStorageURL, fileManager: FileManager = .default) {
        self.storageURL = storageURL
        self.fileManager = fileManager
    }

    // MARK: - StatePersisting Implementation

    /// Persists the collection of tasks atomically to disk.
    public func save(tasks: [DownloadTaskModel]) async throws {
        cachedTasks = tasks
        let parentDir = storageURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parentDir.path) {
            try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }

        let data = try makeEncoder().encode(tasks)
        try data.write(to: storageURL, options: [.atomic])
    }

    /// Loads tasks from disk, automatically converting interrupted downloads to paused state.
    public func load() async throws -> [DownloadTaskModel] {
        let rawTasks = loadRawTasks()
        cachedTasks = rawTasks
        return rawTasks.map { autoRecover(task: $0) }
    }

    /// Updates or inserts a single download task and persists the updated task list atomically.
    public func saveTask(_ task: DownloadTaskModel) async throws {
        var currentTasks = cachedTasks ?? loadRawTasks()
        if let index = currentTasks.firstIndex(where: { $0.id == task.id }) {
            currentTasks[index] = task
        } else {
            currentTasks.append(task)
        }
        cachedTasks = currentTasks
        try await save(tasks: currentTasks)
    }

    /// Removes a download task with the given identifier and persists changes atomically.
    public func deleteTask(id: UUID) async throws {
        var currentTasks = cachedTasks ?? loadRawTasks()
        guard currentTasks.contains(where: { $0.id == id }) else { return }
        currentTasks.removeAll(where: { $0.id == id })
        cachedTasks = currentTasks
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
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let timeInterval = try? container.decode(Double.self) {
                return Date(timeIntervalSinceReferenceDate: timeInterval)
            }
            let string = try container.decode(String.self)
            let isoWithFraction = ISO8601DateFormatter()
            isoWithFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = isoWithFraction.date(from: string) {
                return date
            }
            let isoStandard = ISO8601DateFormatter()
            isoStandard.formatOptions = [.withInternetDateTime]
            if let date = isoStandard.date(from: string) {
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
