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
    public var headers: [String: String]
    public var preferredChunkCount: Int?
    public var etag: String?
    public var lastModified: String?

    /// Overall progress of the download, ranging from 0.0 to 1.0.
    public var progress: Double {
        if totalBytes > 0 {
            return min(1.0, max(0.0, Double(downloadedBytes) / Double(totalBytes)))
        }
        return status == .completed ? 1.0 : 0.0
    }

    /// Base directory for HyperFetch downloads under the user's Downloads directory (~/Downloads/HyperFetch/).
    public static var defaultBaseDirectory: URL {
        let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads", isDirectory: true)
        return downloadsDir.appendingPathComponent("HyperFetch", isDirectory: true)
    }

    /// Computes the default destination URL under ~/Downloads/HyperFetch/<Category>/<Filename>.
    public static func defaultDestinationURL(for filename: String, category: DownloadCategory? = nil) -> URL {
        let cat = category ?? DownloadCategory.category(for: filename)
        let folderName = cat.folderName
        return defaultBaseDirectory
            .appendingPathComponent(folderName, isDirectory: true)
            .appendingPathComponent(filename)
            .standardizedFileURL
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
        bytesPerSecond: Double = 0.0,
        headers: [String: String] = [:],
        preferredChunkCount: Int? = nil,
        etag: String? = nil,
        lastModified: String? = nil
    ) {
        self.id = id
        self.url = url
        let fallbackName = url.lastPathComponent.isEmpty ? "download" : url.lastPathComponent
        let rawName = filename ?? fallbackName
        let sanitized = FilenameResolver.sanitize(rawName)
        let resolvedFilename = sanitized.isEmpty ? "download" : sanitized
        self.filename = resolvedFilename

        let resolvedCategory = category ?? DownloadCategory.category(for: resolvedFilename)
        self.category = resolvedCategory

        if let explicitURL = destinationURL {
            self.destinationURL = explicitURL.standardizedFileURL
        } else {
            self.destinationURL = DownloadTaskModel.defaultDestinationURL(for: resolvedFilename, category: resolvedCategory)
        }
        self.totalBytes = totalBytes
        self.downloadedBytes = downloadedBytes
        self.status = status
        self.chunks = chunks
        self.supportsRange = supportsRange
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.bytesPerSecond = bytesPerSecond
        self.headers = headers
        self.preferredChunkCount = preferredChunkCount
        self.etag = etag
        self.lastModified = lastModified
    }

    enum CodingKeys: String, CodingKey {
        case id, url, filename, destinationURL, totalBytes, downloadedBytes
        case status, chunks, supportsRange, createdAt, completedAt, category, bytesPerSecond, headers
        case preferredChunkCount, etag, lastModified
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.url = try container.decode(URL.self, forKey: .url)
        self.filename = try container.decode(String.self, forKey: .filename)
        self.destinationURL = try container.decode(URL.self, forKey: .destinationURL)
        self.totalBytes = try container.decode(Int64.self, forKey: .totalBytes)
        self.downloadedBytes = try container.decode(Int64.self, forKey: .downloadedBytes)
        self.status = try container.decode(DownloadStatus.self, forKey: .status)
        self.chunks = try container.decode([Chunk].self, forKey: .chunks)
        self.supportsRange = try container.decode(Bool.self, forKey: .supportsRange)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        self.category = try container.decode(DownloadCategory.self, forKey: .category)
        self.bytesPerSecond = try container.decode(Double.self, forKey: .bytesPerSecond)
        self.headers = try container.decodeIfPresent([String: String].self, forKey: .headers) ?? [:]
        self.preferredChunkCount = try container.decodeIfPresent(Int.self, forKey: .preferredChunkCount)
        self.etag = try container.decodeIfPresent(String.self, forKey: .etag)
        self.lastModified = try container.decodeIfPresent(String.self, forKey: .lastModified)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(url, forKey: .url)
        try container.encode(filename, forKey: .filename)
        try container.encode(destinationURL, forKey: .destinationURL)
        try container.encode(totalBytes, forKey: .totalBytes)
        try container.encode(downloadedBytes, forKey: .downloadedBytes)
        try container.encode(status, forKey: .status)
        try container.encode(chunks, forKey: .chunks)
        try container.encode(supportsRange, forKey: .supportsRange)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(completedAt, forKey: .completedAt)
        try container.encode(category, forKey: .category)
        try container.encode(bytesPerSecond, forKey: .bytesPerSecond)
        try container.encode(headers, forKey: .headers)
        try container.encodeIfPresent(preferredChunkCount, forKey: .preferredChunkCount)
        try container.encodeIfPresent(etag, forKey: .etag)
        try container.encodeIfPresent(lastModified, forKey: .lastModified)
    }
}
