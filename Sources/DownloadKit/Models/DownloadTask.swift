import Foundation

/// Lifecycle status of a download task.
public enum DownloadStatus: Codable, Equatable, Sendable {
    case idle
    case probing
    case downloading
    case paused
    case completed
    case failed(reason: String)
}

/// Core domain model representing a file download task and its state.
public struct DownloadTaskModel: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let url: URL
    public var filename: String
    public var destinationURL: URL
    public var totalBytes: Int64
    public var downloadedBytes: Int64
    public var status: DownloadStatus
    public var chunks: [Chunk]
    public var supportsRange: Bool
    public var createdAt: Date
    public var completedAt: Date?
    public var category: DownloadCategory
    public var bytesPerSecond: Double

    /// Overall progress of the download, ranging from 0.0 to 1.0.
    public var progress: Double {
        if totalBytes > 0 {
            return min(1.0, max(0.0, Double(downloadedBytes) / Double(totalBytes)))
        }
        return status == .completed ? 1.0 : 0.0
    }

    public init(
        id: UUID = UUID(),
        url: URL,
        filename: String? = nil,
        destinationURL: URL? = nil,
        totalBytes: Int64 = -1,
        downloadedBytes: Int64 = 0,
        status: DownloadStatus = .idle,
        chunks: [Chunk] = [],
        supportsRange: Bool = false,
        createdAt: Date = Date(),
        completedAt: Date? = nil,
        category: DownloadCategory? = nil,
        bytesPerSecond: Double = 0.0
    ) {
        self.id = id
        self.url = url
        let fallbackName = url.lastPathComponent.isEmpty ? "download" : url.lastPathComponent
        let resolvedFilename = filename ?? fallbackName
        self.filename = resolvedFilename
        self.destinationURL = destinationURL ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.appendingPathComponent(resolvedFilename) ?? URL(fileURLWithPath: resolvedFilename)
        self.totalBytes = totalBytes
        self.downloadedBytes = downloadedBytes
        self.status = status
        self.chunks = chunks
        self.supportsRange = supportsRange
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.category = category ?? DownloadCategory.category(for: resolvedFilename)
        self.bytesPerSecond = bytesPerSecond
    }
}
